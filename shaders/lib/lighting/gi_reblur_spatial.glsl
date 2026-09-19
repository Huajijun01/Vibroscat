#ifndef LIB_LIGHTING_GI_REBLUR_SPATIAL_GLSL
#define LIB_LIGHTING_GI_REBLUR_SPATIAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/color/spaces.glsl"
#include "/lib/lighting/gi_history.glsl"
#include "/lib/lighting/gi_reblur.glsl"

#ifdef GI_REBLUR_ACTIVE
vec4 RepairGIReblurHistory(ivec2 texel) {
    vec3 center = GIReblurFinite(texelFetch(colortex9, texel, 0).rgb);
    uint metadata = texelFetch(colortex10, texel, 0).r;
    float age = GIHistoryAge(metadata);
    if (age < 1.0) return vec4(center, 0.0);
    ivec2 size_texel = textureSize(colortex9, 0);
    vec3 center_view = GIReblurViewPosition(texel, GIHistoryDepth(metadata));
    vec3 normal_world = GIHistoryNormal(metadata);
    vec3 normal_view = normalize(mat3(gbufferModelView) * normal_world);
    vec3 fast_center = GIReblurFinite(texelFetch(colortex6, texel, 0).rgb);
    vec3 fast_sum = fast_center;
    vec3 fast_squared_sum = fast_center * fast_center;
    float fast_weight = 1.0;
    vec3 repair_sum = center;
    float repair_weight = 1.0;
    // A wider footprint reconstructs a newly exposed receiver; mature pixels
    // only need the local fast-history statistics used for history clamping.
    int stride_texel = age < 4.0 ? 2 : 1;
    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            if (x == 0 && y == 0) continue;
            ivec2 sample_texel = texel + ivec2(x, y) * stride_texel;
            float weight = GIReblurGeometryWeight(sample_texel, size_texel,
                center_view, normal_world, normal_view);
            if (weight <= 0.0) continue;
            weight *= exp2(-0.25 * float(x * x + y * y));
            vec3 fast_sample = GIReblurFinite(texelFetch(colortex6, sample_texel, 0).rgb);
            fast_sum += fast_sample * weight;
            fast_squared_sum += fast_sample * fast_sample * weight;
            fast_weight += weight;
            if (age < 4.0) {
                float sample_age = GIHistoryAge(texelFetch(colortex10, sample_texel, 0).r);
                float reconstruction_weight = weight * min(sample_age, 8.0);
                repair_sum += GIReblurFinite(texelFetch(colortex9, sample_texel, 0).rgb)
                    * reconstruction_weight;
                repair_weight += reconstruction_weight;
            }
        }
    }
    vec3 fast_mean = fast_sum / fast_weight;
    vec3 fast_sigma = sqrt(max(fast_squared_sum / fast_weight - fast_mean * fast_mean, vec3(0.0)));
    vec3 extent = 2.5 * fast_sigma + 0.03 * fast_mean + vec3(0.005);
    // Preserve the center fast estimate so a sharp, valid lighting boundary
    // does not get forced to its neighbors' average.
    vec3 lower = max(min(fast_mean - extent, fast_center), vec3(0.0));
    vec3 upper = max(fast_mean + extent, fast_center);
    vec3 reconstructed = mix(center, repair_sum / repair_weight, clamp((4.0 - age) / 3.0, 0.0, 1.0));
    vec3 repaired = clamp(reconstructed, lower, upper);
    // Store sigma, not squared variance, to keep HDR statistics finite in FP16.
    float sigma = Luminance(fast_sigma);
    return vec4(GIReblurFinite(repaired), min(sigma, 65000.0));
}

vec3 FilterGIReblur(ivec2 texel) {
    vec4 center = texelFetch(usam_gi_reblur_a, texel, 0);
    uint metadata = texelFetch(colortex10, texel, 0).r;
    float age = GIHistoryAge(metadata);
    if (age < 1.0) return center.rgb;
    ivec2 size_texel = textureSize(colortex10, 0);
    float depth_view = GIHistoryDepth(metadata);
    vec3 center_view = GIReblurViewPosition(texel, depth_view);
    vec3 normal_world = GIHistoryNormal(metadata);
    vec3 normal_view = normalize(mat3(gbufferModelView) * normal_world);
    float hit_distance = clamp(texelFetch(colortex6, texel, 0).a, 0.0, 1.0);
    float convergence = clamp((age - 1.0) / max(float(GI_HISTORY_FRAMES) - 1.0, 1.0), 0.0, 1.0);
    float max_radius = float(GI_REBLUR_RADIUS) * mix(1.0, 0.25, sqrt(convergence));
    // A secondary hit close to the receiver limits the physical filter size.
    // The far sentinel allows a broad footprint for the smooth SH fallback.
    float hit_distance_m = (3.0 + 0.1 * depth_view) * hit_distance / max(1.0 - hit_distance, 0.001);
    float pixel_size_m = 2.0 * depth_view / (abs(gbufferProjection[1].y) * float(size_texel.y));
    float radius = clamp(0.15 * hit_distance_m / max(pixel_size_m, 1.0e-5), 1.0, max_radius);
    float center_luminance = Luminance(center.rgb);
    float luminance_scale = 3.0 * center.a + 0.1 * center_luminance + 0.01;
    vec3 irradiance_sum = center.rgb;
    float weight_sum = 1.0;
    // A rotated disk avoids axis-aligned banding without an a-trous stride
    // ladder. Radius shrinks with convergence and the center tap is retained.
    float rotation = 2.39996323 * float(frameCounter & 31);
    for (int i = 0; i < 16; ++i) {
        float disk_radius = sqrt((float(i) + 0.5) / 16.0);
        float angle = float(i) * 2.39996323 + rotation;
        ivec2 offset_texel = ivec2(round(vec2(cos(angle), sin(angle)) * (radius * disk_radius)));
        if (all(equal(offset_texel, ivec2(0)))) continue;
        ivec2 sample_texel = texel + offset_texel;
        float weight = GIReblurGeometryWeight(sample_texel, size_texel,
            center_view, normal_world, normal_view);
        if (weight <= 0.0) continue;
        vec4 sample_value = texelFetch(usam_gi_reblur_a, sample_texel, 0);
        float sample_hit = texelFetch(colortex6, sample_texel, 0).a;
        float hit_weight = exp2(-abs(sample_hit - hit_distance) / (0.1 + 0.25 * hit_distance));
        float luminance_delta = abs(Luminance(sample_value.rgb) - center_luminance);
        // Young history has unreliable radiance; trust geometry more there.
        float luminance_weight = exp2(-luminance_delta / (luminance_scale + 2.0 * sample_value.a));
        weight *= exp2(-2.0 * disk_radius * disk_radius) * hit_weight
            * mix(1.0, luminance_weight, min(age / 8.0, 1.0));
        irradiance_sum += sample_value.rgb * weight;
        weight_sum += weight;
    }
    return GIReblurFinite(irradiance_sum / weight_sum);
}
#endif

#endif // LIB_LIGHTING_GI_REBLUR_SPATIAL_GLSL
