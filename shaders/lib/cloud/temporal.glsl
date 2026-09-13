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
// Radiance uses the filtered current neighborhood; distance remains the
// nearest sample location so reprojection does not invent a surface depth.
CloudFrame CloudSampleCurrentBilinear(ivec2 full_res_texel) {
    vec2 low_size = vec2(textureSize(usam_clouds_current, 0));
    vec2 low_texel_size = 1.0 / low_size;
    vec2 grid_position = CloudCurrentGridPosition(full_res_texel);
    vec2 current_uv = (grid_position + 0.5) * low_texel_size;
    current_uv = clamp(current_uv, 0.5 * low_texel_size, vec2(1.0) - 0.5 * low_texel_size);
    vec4 value = texture(usam_clouds_current, current_uv);

    ivec2 nearest_texel = clamp(
        ivec2(floor(grid_position + 0.5)),
        ivec2(0),
        ivec2(low_size) - ivec2(1)
    );
    CloudFrame frame;
    frame.radiance = value.rgb;
    frame.surface_distance = texelFetch(usam_clouds_current, nearest_texel, 0).a;
    return frame;
}

// True when this history slot has no usable data (never written / cleared).
bool CloudHistoryInvalid(CloudFrame history) {
    return any(isnan(history.radiance)) || isnan(history.surface_distance) || !(history.surface_distance > 0.0);
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
// history weight. The current frame keeps a 1/CLOUD_HISTORY_FRAMES contribution
// after the cap. Radiance is mixed, distance is never EMA-mixed.
CloudFrame CloudAccumulate(CloudFrame current, CloudFrame history, int pixel_age
) {
    // Single NaN guard so a never-initialized history cannot poison the blend.
    if (any(isnan(history.radiance)) || isnan(history.surface_distance)) {
        return current;
    }
    // Age counts accepted frames and doubles as the bounded accumulated
    // sample weight, matching the Alpha-style history cap.
    float alpha = 1.0 / float(min(pixel_age + 1, CLOUD_HISTORY_FRAMES));
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
