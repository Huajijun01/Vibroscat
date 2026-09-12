#ifndef LIB_CLOUD_TEMPORAL_GLSL
#define LIB_CLOUD_TEMPORAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/filters.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/cloud/volumetric.glsl"

// Previous-frame camera transforms, shared with TAA and the GTAO temporal
// accumulation (temporal_ao.glsl); declared in uniforms.glsl so both
// include cleanly.
#include "/lib/contract/uniforms.glsl"

struct CloudFrame {
    vec3 radiance;   // x = sun, y = moon, z = transmittance
    float surface_distance;  // km; hit distance, or cloud-top distance when clear (T = 1)
};

// Return the full-resolution pixel's coordinate on the moving low-res lattice.
// The low-res texel centers are at (id + r2_offset) * cell_size in full-res
// pixel coordinates, so integer lattice coordinates are valid sample centers.
vec2 CloudCurrentGridPosition(ivec2 full_res_texel) {
    vec2 full_size = vec2(textureSize(depthtex0, 0));
    vec2 low_size = vec2(textureSize(usam_clouds_current, 0));
    vec2 cell_size = full_size / low_size;
#if CLOUD_TEMPORAL_UPSCALING == 1
    vec2 r2_offset = vec2(0.5);
#else
    vec2 r2_offset = R2Offset(frameCounter);
#endif
    return (vec2(full_res_texel) + 0.5) / cell_size - r2_offset;
}

// Reconstruct the current low-res cloud frame for every full-res sky pixel.
// Radiance uses the filtered current neighborhood. The reprojection anchor
// must come from a lattice texel that actually traced the cloud shell
// (alpha > 0): terrain and ground-blocked texels store 0, and picking one
// would anchor the history lookup at the ground's parallax instead of the
// cloud's. When no traced texel borders the pixel, the caller's own shell
// geometry (no_hit_distance_km) stands in; 0 then reseeds via
// CloudHistoryInvalid, which rejects a zero distance by contract.
CloudFrame CloudSampleCurrentBilinear(ivec2 full_res_texel, float no_hit_distance_km) {
    vec2 low_size = vec2(textureSize(usam_clouds_current, 0));
    vec2 grid_position = CloudCurrentGridPosition(full_res_texel);
    ivec2 base_texel = clamp(ivec2(floor(grid_position)), ivec2(0), ivec2(low_size) - ivec2(1));
    ivec2 grid_max = ivec2(low_size) - ivec2(1);
    vec2 fraction = fract(grid_position);

    // Hardware bilinear would blend untraced texels (terrain, ground-blocked
    // sky: rgb = clear sky, alpha = 0) into the upsample, painting a
    // see-through band around every silhouette. Weight only texels that
    // actually traced the shell; the distance anchor additionally takes the
    // nearest traced texel so reprojection follows the cloud, not the ground.
    vec3 radiance = vec3(0.0);
    float radiance_weight = 0.0;
    float surface_distance = no_hit_distance_km;
    float best_rank = 1.0e30;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 texel = min(base_texel + ivec2(x, y), grid_max);
            float weight = (x == 0 ? 1.0 - fraction.x : fraction.x)
                * (y == 0 ? 1.0 - fraction.y : fraction.y);
            vec4 sample_value = texelFetch(usam_clouds_current, texel, 0);
            if (sample_value.a > 0.0) {
                radiance += sample_value.rgb * weight;
                radiance_weight += weight;
                vec2 offset = vec2(texel) - grid_position;
                float rank = dot(offset, offset);
                if (rank < best_rank) {
                    best_rank = rank;
                    surface_distance = sample_value.a;
                }
            }
        }
    }
    CloudFrame frame;
    frame.radiance = radiance_weight > 0.0 ? radiance / radiance_weight : vec3(0.0, 0.0, 1.0);
    frame.surface_distance = surface_distance;
    return frame;
}

// True when this history slot has no usable data (never written / cleared).
// NaN in surface_distance is covered by the > 0 comparison; NaN in radiance
// is the HISTORY_NO_CLOUD_DATA marker carried by invalid frames.
bool CloudHistoryInvalid(CloudFrame history) {
    return any(isnan(history.radiance)) || !(history.surface_distance > 0.0);
}

// Sample history at a fractional previous-frame UV with the fast Catmull-Rom
// bicubic. The reprojected center texel gates first: CR taps crossing the
// sky/geometry boundary would propagate the AO-side NaN marker (A = 0 would
// blend in as a small positive distance), so the gate rejects exactly at the
// reprojected position. Caller falls back to the fresh trace on a NaN frame.
CloudFrame CloudHistorySample(vec2 previous_uv) {
    vec2 history_size = vec2(textureSize(colortex8, 0));
    vec2 texel = 1.0 / history_size;
    vec2 clamped_uv = clamp(previous_uv, 2.0 * texel, 1.0 - 2.0 * texel);

    ivec2 center_texel = ivec2(clamped_uv * history_size);
    if (!(texelFetch(colortex8, center_texel, 0).a > 0.0)) {
        CloudFrame invalid;
        invalid.radiance = vec3(HISTORY_NO_CLOUD_DATA);
        invalid.surface_distance = HISTORY_NO_CLOUD_DATA;
        return invalid;
    }

    vec4 col = FastCatmullRom5Tap(colortex8, clamped_uv, texel, 0.5);
    CloudFrame frame;
    frame.radiance = col.rgb;
    frame.surface_distance = col.a;
    return frame;
}

// Age-based history blending: the accepted-frame age is also the accumulated
// history weight. The current frame keeps a 1/CLOUD_AGE_LIMIT contribution
// after the cap. Radiance is mixed, distance is never EMA-mixed. Callers
// validate history through CloudHistoryInvalid; no re-check here.
CloudFrame CloudAccumulate(CloudFrame current, CloudFrame history, int pixel_age
) {
    // Age counts accepted frames and doubles as the bounded accumulated
    // sample weight, matching the Alpha-style history cap.
    float alpha = 1.0 / float(min(pixel_age + 1, CLOUD_AGE_LIMIT));
    CloudFrame result;
    // Radiance mixes linearly; transmittance is nonlinear (T = exp(-OD)),
    // so it mixes in log space (unbiased). Distance is a hit location, keeps
    // the last fresh sample.
    result.radiance = vec3(mix(history.radiance.x, current.radiance.x, alpha),
        mix(history.radiance.y, current.radiance.y, alpha), exp(mix(log(max(history.radiance.z, 1.0e-4)),
            log(max(current.radiance.z, 1.0e-4)), alpha)));
    result.surface_distance = current.surface_distance;
    return result;
}

#endif
