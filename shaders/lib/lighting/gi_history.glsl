#ifndef LIB_LIGHTING_GI_HISTORY_GLSL
#define LIB_LIGHTING_GI_HISTORY_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/packing.glsl"

// R32UI: half linear view depth [0:15], oct5 world normal [16:25],
// age [26:30], source [31] (0=SSGI, 1=RSM). Age zero is invalid.
uint EncodeGIHistory(float depth_view, vec3 normal_world, float age) {
    uvec2 normal_bits = uvec2(round(EncodeOctahedralNormal(normal_world) * 31.0));
    uint depth_bits = packHalf2x16(vec2(min(depth_view, 65000.0), 0.0)) & 65535u;
    uint source_bit = uint(GI_MODE == 2) << 31u;
    return source_bit | (uint(clamp(age, 1.0, 31.0)) << 26u)
        | (normal_bits.y << 21u) | (normal_bits.x << 16u) | depth_bits;
}

float GIHistoryAge(uint metadata) {
    return (metadata >> 31u) == uint(GI_MODE == 2) ? float((metadata >> 26u) & 31u) : 0.0;
}

float GIHistoryDepth(uint metadata) {
    return unpackHalf2x16(metadata & 65535u).x;
}

vec3 GIHistoryNormal(uint metadata) {
    return DecodeOctahedralNormal(vec2((metadata >> 16u) & 31u, (metadata >> 21u) & 31u) / 31.0);
}

// Shared reprojection for both denoisers. Validate taps in their previous
// view space before sampling long or fast history.
struct GIReprojectedHistory {
    vec3 irradiance;
    float age;
    float weight;
#ifdef GI_REBLUR_ACTIVE
    vec4 fast;
#endif
};

GIReprojectedHistory ReprojectGIHistory(vec3 receiver_world, vec3 normal_world) {
    GIReprojectedHistory result;
    result.irradiance = vec3(0.0);
    result.age = 0.0;
    result.weight = 0.0;
#ifdef GI_REBLUR_ACTIVE
    result.fast = vec4(0.0);
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
    if (reset) return result;

    vec3 previous_view = (gbufferPreviousModelView * vec4(receiver_world + camera_delta, 1.0)).xyz;
    vec4 previous_clip = gbufferPreviousProjection * vec4(previous_view, 1.0);
    if (previous_clip.w <= 0.0) return result;
    vec2 previous_uv = previous_clip.xy / previous_clip.w * 0.5 + 0.5;
#ifdef TAA
    previous_uv += u_taa_offset_previous * 0.5;
#endif
    if (any(lessThan(previous_uv, vec2(0.0))) || any(greaterThanEqual(previous_uv, vec2(1.0)))) {
        return result;
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
#ifdef GI_REBLUR_ACTIVE
    vec4 fast_sum = vec4(0.0);
#endif
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
            // comparison-based rejection is not trusted on this driver.
            if (any(isnan(history)) || any(isinf(history))) continue;
#ifdef GI_REBLUR_ACTIVE
            vec4 fast_sample = texelFetch(colortex6, sample_texel, 0);
            if (any(isnan(fast_sample)) || any(isinf(fast_sample))) continue;
            fast_sum += fast_sample * weight;
#endif
            history_sum += history * weight;
            age_sum += age * weight;
            weight_sum += weight;
        }
    }
    if (weight_sum < 0.05) return result;
    result.irradiance = history_sum / weight_sum;
    result.age = age_sum / weight_sum;
    result.weight = weight_sum;
#ifdef GI_REBLUR_ACTIVE
    result.fast = fast_sum / weight_sum;
#endif
    return result;
}

#endif // LIB_LIGHTING_GI_HISTORY_GLSL
