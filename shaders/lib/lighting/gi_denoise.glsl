#ifndef LIB_LIGHTING_GI_DENOISE_GLSL
#define LIB_LIGHTING_GI_DENOISE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/color/color.glsl"
#include "/lib/lighting/gi_history.glsl"

// Half-depth quantization and oct5 normals share the existing R32UI history.
// Validate each bilinear tap in its OWN previous view space, against the
// reprojected receiver plane. No current-frame normal masquerades as history.
vec3 AccumulateGI(vec3 current_irradiance, float sample_sigma, vec3 receiver_world,
        vec3 normal_world, out float history_age) {
    history_age = 1.0;
#ifndef GI_DENOISE
    return current_irradiance;
#endif
#if GI_MODE == 2 && RSM_DEBUG == 1
    return current_irradiance;
#endif
    vec3 camera_delta = cameraPosition - previousCameraPosition;
#if GI_MODE == 2
    float camera_jump_m = RSM_RADIUS;
#else
    float camera_jump_m = 8.0;
#endif
    bool reset = frameCounter < 2 || length(camera_delta) > camera_jump_m;
    reset = reset || abs(gbufferProjection[0].x / gbufferPreviousProjection[0].x - 1.0) > 0.05;
    reset = reset || abs(gbufferProjection[1].y / gbufferPreviousProjection[1].y - 1.0) > 0.05;
    if (reset) return current_irradiance;

    vec3 previous_view = (gbufferPreviousModelView * vec4(receiver_world + camera_delta, 1.0)).xyz;
    vec4 previous_clip = gbufferPreviousProjection * vec4(previous_view, 1.0);
    if (previous_clip.w <= 0.0) return current_irradiance;
    vec2 previous_uv = previous_clip.xy / previous_clip.w * 0.5 + 0.5;
#ifdef TAA
    previous_uv += u_taa_offset_previous * 0.5;
#endif
    if (any(lessThan(previous_uv, vec2(0.0))) || any(greaterThanEqual(previous_uv, vec2(1.0)))) {
        return current_irradiance;
    }

    ivec2 history_size = textureSize(colortex9, 0);
    vec2 history_size_f = vec2(history_size);
    vec2 previous_ray_scale = vec2(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y);
    vec2 previous_ray_bias = gbufferPreviousProjection[2].xy;
    float footprint_m = abs(previous_view.z) * 4.0
        / (abs(gbufferPreviousProjection[1].y) * float(history_size.y));
    vec2 previous_texel = previous_uv * history_size_f - 0.5;
    ivec2 base_texel = ivec2(floor(previous_texel));
    vec2 fraction = fract(previous_texel);
    vec3 previous_normal = normalize(mat3(gbufferPreviousModelView) * normal_world);
    float plane_tolerance_m = 0.04 + abs(previous_view.z) * 0.002;
    vec3 history_sum = vec3(0.0);
    float weight_sum = 0.0;
    float age_sum = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 sample_texel = base_texel + ivec2(x, y);
            if (any(lessThan(sample_texel, ivec2(0))) || any(greaterThanEqual(sample_texel, history_size))) continue;
            uint metadata = texelFetch(colortex10, sample_texel, 0).r;
            float age = GIHistoryAge(metadata);
            float depth_view = GIHistoryDepth(metadata);
            if (age < 1.0 || depth_view <= 0.0 || isinf(depth_view) || isnan(depth_view)) continue;
            float normal_dot = dot(normal_world, GIHistoryNormal(metadata));
            if (normal_dot < 0.94) continue;
            vec2 sample_ndc = (vec2(sample_texel) + 0.5) / history_size_f * 2.0 - 1.0;
#ifdef TAA
            sample_ndc -= u_taa_offset_previous;
#endif
            vec2 previous_ray = (sample_ndc + previous_ray_bias) / previous_ray_scale;
            vec3 sample_view = vec3(previous_ray, -1.0) * depth_view;
            vec3 delta_view = sample_view - previous_view;
            float plane_distance = abs(dot(delta_view, previous_normal));
            if (plane_distance > plane_tolerance_m || length(delta_view) > 0.25 + footprint_m) continue;
            vec2 bilinear = mix(vec2(1.0) - fraction, fraction, vec2(x, y));
            float weight = bilinear.x * bilinear.y * (1.0 - plane_distance / plane_tolerance_m);
            vec3 history = texelFetch(colortex9, sample_texel, 0).rgb;
            if (any(isnan(history)) || any(isinf(history))) continue;
            history_sum += history * weight;
            age_sum += age * weight;
            weight_sum += weight;
        }
    }
    if (weight_sum < 0.05) return current_irradiance;

    vec3 history = history_sum / weight_sum;
    // Filter irradiance before receiver albedo (SVGF, Schied et al. 2017).
    // Source moments include the SH fallback, without a moments buffer.
    float current_luminance = Luminance(current_irradiance);
    float history_luminance = Luminance(history);
    float clip_extent = 3.0 * sample_sigma + 0.03 + 0.5 * current_luminance;
    float clipped_luminance = clamp(history_luminance,
        max(current_luminance - clip_extent, 0.0), current_luminance + clip_extent);
    history *= clipped_luminance / max(history_luminance, 1.0e-6);
    float age_limit = min(float(GI_HISTORY_FRAMES), max(4.0, 0.25 / max(frameTime, 0.001)));
    history_age = min(floor(age_sum / weight_sum) + 1.0, age_limit);
    return mix(history, current_irradiance, 1.0 / history_age);
}

#endif // LIB_LIGHTING_GI_DENOISE_GLSL
