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
            // Explicit non-finite filter on both colortex9 readers:
            // comparison-based rejection is not trusted on this driver
            // (docs/defensive-code-audit.md items 9/10).
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
    float blended_age = min(floor(age_sum / weight_sum) + 1.0,
        float(GI_HISTORY_FRAMES));
    float blend_weight = 1.0 / blended_age;
    // Clip around the blended estimate, not the raw current sample: a
    // current-frame outlier then moves the anchor by 1/age instead of
    // dragging the whole window, so low-sigma miss frames cannot crush
    // accumulated history and single fireflies cannot lift it.
    float anchor_luminance = mix(history_luminance, current_luminance, blend_weight);
    float clip_extent = 3.0 * sample_sigma + 0.03 + 0.1 * anchor_luminance;
    float clipped_luminance = clamp(history_luminance,
        max(anchor_luminance - clip_extent, 0.0), anchor_luminance + clip_extent);
    bool history_clipped = clipped_luminance != history_luminance;
    history *= clipped_luminance / max(history_luminance, 1.0e-6);
    // A clip hit means current contradicts history beyond its noise scale:
    // shorten the blend so persistent lighting changes still converge fast.
    // Transient noise stays inside the window and keeps the full history.
    history_age = history_clipped ? min(blended_age, 4.0) : blended_age;
    return mix(history, current_irradiance, 1.0 / history_age);
}

// Disocclusion repair for the deferred4 consumer: a pixel whose temporal
// history was rejected (metadata age 1) would otherwise light from the raw
// 1-spp estimate. Borrow the temporally filtered neighborhood instead, with
// the same metadata contracts as the temporal filter: source-matched age,
// world normal, and view-plane distance. Neighbors are current-frame
// colortex9 entries, so receiver and samples share one projection and one
// TAA jitter; the residual per-texel jitter offset is far below the plane
// tolerance. Returns false when no neighbor passes, leaving the raw value.
bool RepairGIDisocclusion(ivec2 center_texel, vec3 receiver_view, vec3 normal_view,
        vec3 normal_world, out vec3 repaired_irradiance) {
    repaired_irradiance = vec3(0.0);
    ivec2 history_size = textureSize(colortex9, 0);
    vec2 history_size_f = vec2(history_size);
    float plane_tolerance_m = 0.04 + abs(receiver_view.z) * 0.002;
    vec3 repair_sum = vec3(0.0);
    float weight_sum = 0.0;
    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            if (x == 0 && y == 0) continue;
            ivec2 sample_texel = center_texel + ivec2(x, y);
            if (any(lessThan(sample_texel, ivec2(0)))
                    || any(greaterThanEqual(sample_texel, history_size))) continue;
            uint metadata = texelFetch(colortex10, sample_texel, 0).r;
            float age = GIHistoryAge(metadata);
            float depth_view = GIHistoryDepth(metadata);
            if (age < 1.0 || depth_view <= 0.0 || isinf(depth_view) || isnan(depth_view)) continue;
            if (dot(normal_world, GIHistoryNormal(metadata)) < 0.94) continue;
            vec2 sample_ndc = (vec2(sample_texel) + 0.5) / history_size_f * 2.0 - 1.0;
            vec2 sample_ray = (sample_ndc + gbufferProjection[2].xy)
                / vec2(gbufferProjection[0].x, gbufferProjection[1].y);
            vec3 sample_view = vec3(sample_ray, -1.0) * depth_view;
            float plane_distance = abs(dot(sample_view - receiver_view, normal_view));
            if (plane_distance > plane_tolerance_m) continue;
            // Older neighbors carry more converged history; fresh (age 1)
            // entries still help as raw spatial averages.
            float weight = min(age, 4.0) * (1.0 - plane_distance / plane_tolerance_m);
            vec3 history = texelFetch(colortex9, sample_texel, 0).rgb;
            if (any(isnan(history)) || any(isinf(history))) continue;
            repair_sum += history * weight;
            weight_sum += weight;
        }
    }
    if (weight_sum < 0.05) return false;
    repaired_irradiance = repair_sum / weight_sum;
    return true;
}

#endif // LIB_LIGHTING_GI_DENOISE_GLSL
