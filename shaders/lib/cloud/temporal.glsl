#ifndef CLOUD_TEMPORAL_GLSL
#define CLOUD_TEMPORAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/filters.glsl"
#include "/lib/cloud/volumetric.glsl"
#include "/lib/cloud/checkerboard.glsl"

// Previous-frame camera transforms, shared with TAA and the GTAO temporal
// accumulation (temporal_ao.glsl); declared in uniforms.glsl so both
// include cleanly.
#include "/lib/contract/uniforms.glsl"

struct CloudFrame {
    vec3 radiance;   // x = sun, y = moon, z = transmittance
    float surface_distance;  // km; hit distance, or cloud-top distance when clear (T = 1)
};

// True only for the one full-res pixel per cell that this frame's low-res
// render sampled.
bool CloudHasFreshSample(ivec2 full_res_texel) {
    ivec2 local = full_res_texel % CLOUD_TEMPORAL_UPSCALING;
    ivec2 offset = CloudCheckerboardOffset(uint(frameCounter) % uint(CLOUD_CHECKERBOARD_AREA));
    return all(equal(local, offset));
}

// Raw sample for this pixel's low-res cell (downscaled render). No
// interpolation, no snapping.
CloudFrame CloudSampleFresh(ivec2 full_res_texel) {
    // Low-res march samples cell·n + currentOffset; history-less seeds snap
    // to the nearest marched sample (aligned with the checkerboard grid, not
    // shifted by up to n-1 px).
    ivec2 offset = CloudCheckerboardOffset(uint(frameCounter) % uint(CLOUD_CHECKERBOARD_AREA));
    ivec2 nearest_sample_pos = full_res_texel - offset + CLOUD_TEMPORAL_UPSCALING / 2;
    ivec2 low_res_texel = ivec2(floor(vec2(nearest_sample_pos) / float(CLOUD_TEMPORAL_UPSCALING)));
    // Clamp partial edge cells to the last valid low-res texel.
    low_res_texel = clamp(low_res_texel, ivec2(0), textureSize(usam_clouds_current, 0) - 1);
    vec4 value = texelFetch(usam_clouds_current, low_res_texel, 0);
    CloudFrame frame;
    frame.radiance = value.rgb;
    frame.surface_distance = value.a;
    return frame;
}

// Bilinear reconstruction of the low-res frame for empty history slots:
// radiance filtered by hardware bilinear (usam_clouds_current declared
// linear); distance is a location, keeps the nearest marched sample. UV maps
// the texelFetch lattice to (i + 0.5)/size.
CloudFrame CloudSampleCurrentBilinear(ivec2 full_res_texel) {
    ivec2 offset = CloudCheckerboardOffset(uint(frameCounter) % uint(CLOUD_CHECKERBOARD_AREA));
    // Continuous lattice coordinate; the low-res grid sits at id·n + offset.
    vec2 coord = (vec2(full_res_texel) - vec2(offset)) / float(CLOUD_TEMPORAL_UPSCALING);
    vec2 uv = (coord + 0.5) / vec2(textureSize(usam_clouds_current, 0));
    vec4 value = texture(usam_clouds_current, uv);

    CloudFrame nearest = CloudSampleFresh(full_res_texel);
    CloudFrame frame;
    frame.radiance = value.rgb;
    frame.surface_distance = nearest.surface_distance;
    return frame;
}

// Same-pixel history load. No reprojection.
CloudFrame CloudHistoryLoad(ivec2 texel) {
    vec4 history = texelFetch(colortex8, texel, 0);
    CloudFrame frame;
    frame.radiance = history.rgb;
    frame.surface_distance = history.a;
    return frame;
}

// True when this history slot has no usable data (never written / cleared).
bool CloudHistoryInvalid(CloudFrame history) {
    return any(isnan(history.radiance)) || isnan(history.surface_distance) || !(history.surface_distance > 0.0);
}

// Reproject the cloud point at distanceKm along viewDirWorld to the previous
// UV (false = behind the previous camera / off-screen).
bool CloudReprojectToPrevious(vec3 view_dir_world, float distance_km, out vec2 previous_uv) {
    return CloudProjectToPrevious(view_dir_world, distance_km, previous_uv);
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
        invalid.radiance = vec3(CLOUD_HISTORY_NO_DATA);
        invalid.surface_distance = CLOUD_HISTORY_NO_DATA;
        return invalid;
    }

    vec4 col = FastCatmullRom5Tap(colortex8, clamped_uv, texel, 0.5);
    CloudFrame frame;
    frame.radiance = col.rgb;
    frame.surface_distance = col.a;
    return frame;
}

// Age-based history blending: the first samples after seeding are box-
// averaged with equal weight, then the weight switches to the steady-state
// EMA alpha. Radiance is mixed, distance is never EMA-mixed.
CloudFrame CloudAccumulate(CloudFrame current, CloudFrame history, int pixel_age
) {
    // Single NaN guard so a never-initialized history cannot poison the EMA.
    if (any(isnan(history.radiance)) || isnan(history.surface_distance)) {
        return current;
    }
    // Sample count since seeding: floor(age / CLOUD_CHECKERBOARD_AREA) + 1
    // (one phase-matched blend per cycle, phase-alignment independent).
    // Box-average 1/(n+1) while n < box samples, then steady-state EMA.
    float fresh_samples = floor(float(pixel_age) / float(CLOUD_CHECKERBOARD_AREA)) + 1.0;
    float alpha = fresh_samples < CLOUD_ACCUMULATION_BOX_SAMPLES ? 1.0 / max(fresh_samples + 1.0, 1.0) : CLOUD_ACCUMULATION_ALPHA;
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
