#ifndef LIB_LIGHTING_OPAQUE_REFLECTION_FILTER_GLSL
#define LIB_LIGHTING_OPAQUE_REFLECTION_FILTER_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"

float OpaqueSpatialRadius(float roughness, float path_distance) {
    float support = max(roughness, 0.0) * max(roughness, 0.0)
        * (1.0 + 0.5 * sqrt(max(path_distance, 0.0)));
    // Keep a one-ring footprint for valid SSR, even on polished materials.
    // Without this floor, roughness=0 quantizes every stage to the center tap.
    return min(float(OPAQUE_SSR_FILTER_RADIUS), max(0.5, support));
}

int OpaqueSpatialStride(float radius, int stage) {
    if (stage == 0) return 2;
    return radius >= 0.5 ? 1 : 0;
}

float OpaqueSpatialKernelWeight(ivec2 tap, int radius) {
    ivec2 tap_abs = abs(tap);
    if (any(greaterThan(tap_abs, ivec2(radius)))) return 0.0;
    if (radius <= 0) return 1.0;

    float center_weight = radius == 1 ? 2.0 : 6.0;
    float adjacent_weight = radius == 1 ? 1.0 : 4.0;
    float weight_x = tap_abs.x == 0 ? center_weight
        : tap_abs.x == 1 ? adjacent_weight : 1.0;
    float weight_y = tap_abs.y == 0 ? center_weight
        : tap_abs.y == 1 ? adjacent_weight : 1.0;
    return weight_x * weight_y / (center_weight * center_weight);
}

float OpaqueSpatialWeight(float kernel_weight,
        float center_depth, float sample_depth,
        vec3 center_geo_normal, vec3 sample_geo_normal,
        vec3 center_shading_normal, vec3 sample_shading_normal,
        float center_roughness, float sample_roughness,
        float center_distance, float sample_distance) {
    float spatial_weight = max(kernel_weight, 0.0);
    float depth_scale = max(0.05, 0.02 * max(center_depth, 1.0));
    float depth_weight = exp(-abs(sample_depth - center_depth) / depth_scale);
    float geo_similarity = max(dot(center_geo_normal, sample_geo_normal), 0.0);
    float shading_similarity = max(
        dot(center_shading_normal, sample_shading_normal), 0.0);
    float normal_weight = pow(geo_similarity, 32.0)
        * pow(shading_similarity, 8.0);
    float roughness_weight = exp(
        -16.0 * abs(sample_roughness - center_roughness));
    float distance_scale = max(0.5, 0.25 * max(abs(center_distance), 0.0));
    // A miss has no path length. Let valid neighbors fill that hole instead
    // of comparing their distance against the zero sentinel.
    float distance_weight = center_distance <= 0.0 || sample_distance <= 0.0
        ? 1.0
        : exp(-abs(abs(sample_distance) - abs(center_distance))
            / distance_scale);
    return clamp(spatial_weight * depth_weight
        * normal_weight * roughness_weight * distance_weight, 0.0, 1.0);
}

#endif
