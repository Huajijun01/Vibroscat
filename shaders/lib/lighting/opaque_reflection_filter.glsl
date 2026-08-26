#ifndef LIB_LIGHTING_OPAQUE_REFLECTION_FILTER_GLSL
#define LIB_LIGHTING_OPAQUE_REFLECTION_FILTER_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"

float OpaqueSpatialRadius(float roughness, float path_distance) {
    float support = max(roughness, 0.0) * max(roughness, 0.0)
        * (1.0 + 0.5 * sqrt(max(path_distance, 0.0)));
    return min(float(OPAQUE_SSR_FILTER_RADIUS), support);
}

int OpaqueSpatialStride(float radius, int stage) {
    if (stage == 0) return 2;
    return radius >= 0.5 ? 1 : 0;
}

float OpaqueSpatialWeight(vec2 tap_offset,
        float center_depth, float sample_depth,
        vec3 center_geo_normal, vec3 sample_geo_normal,
        vec3 center_shading_normal, vec3 sample_shading_normal,
        float center_roughness, float sample_roughness,
        float center_distance, float sample_distance,
        bool center_environment, bool sample_environment) {
    float source_weight = center_environment == sample_environment ? 1.0 : 0.0;
    if (source_weight <= 0.0) return 0.0;

    float spatial_weight = exp(-0.75 * dot(tap_offset, tap_offset));
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
    float distance_weight = exp(
        -abs(abs(sample_distance) - abs(center_distance)) / distance_scale);
    return clamp(source_weight * spatial_weight * depth_weight
        * normal_weight * roughness_weight * distance_weight, 0.0, 1.0);
}

#endif
