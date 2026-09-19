#ifndef LIB_LIGHTING_GI_REBLUR_GLSL
#define LIB_LIGHTING_GI_REBLUR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/lighting/gi_history.glsl"

// Reduced diffuse adaptation of the published ReBLUR architecture:
// long/fast temporal histories, history reconstruction and one adaptive blur
// with spatial feedback. This is not an NRD SDK source port.
// https://developer.nvidia.com/rtx/ray-tracing/rt-denoisers
// Distances describe the secondary transport segment, never camera depth.
float GIReblurHitDistance(float hit_distance_m, float view_depth_m) {
    // Bounded rational encoding; 1 is reserved for uncovered sky directions.
    // Unlike NRD's ray input, this pack integrates several visibility sectors.
    float scale_m = 3.0 + 0.1 * view_depth_m;
    return hit_distance_m / (hit_distance_m + scale_m);
}

vec3 GIReblurFinite(vec3 irradiance) {
    if (any(isnan(irradiance)) || any(isinf(irradiance))) return vec3(0.0);
    // Keep RGB and its standard deviation representable in RGBA16F.
    return clamp(irradiance, vec3(0.0), vec3(65000.0));
}

#ifdef GI_REBLUR_ACTIVE
vec3 GIReblurViewPosition(ivec2 texel, float depth_view) {
    vec2 ndc = (vec2(texel) + 0.5) * u_view_pixel_size * 2.0 - 1.0;
#ifdef TAA
    ndc -= u_taa_offset;
#endif
    vec2 ray = (ndc + gbufferProjection[2].xy)
        / vec2(gbufferProjection[0].x, gbufferProjection[1].y);
    return vec3(ray, -1.0) * depth_view;
}

// All spatial stages use the same current-frame receiver plane and source tag.
// Bilateral plane rejection prevents filtering through silhouettes and steps.
float GIReblurGeometryWeight(ivec2 sample_texel, ivec2 size_texel,
        vec3 center_view, vec3 normal_world, vec3 normal_view) {
    if (any(lessThan(sample_texel, ivec2(0)))
            || any(greaterThanEqual(sample_texel, size_texel))) return 0.0;
    uint metadata = texelFetch(colortex10, sample_texel, 0).r;
    float depth_view = GIHistoryDepth(metadata);
    if (GIHistoryAge(metadata) < 1.0 || depth_view <= 0.0
            || isnan(depth_view) || isinf(depth_view)) return 0.0;
    float normal_dot = dot(normal_world, GIHistoryNormal(metadata));
    if (normal_dot < 0.94) return 0.0;
    vec3 delta_view = GIReblurViewPosition(sample_texel, depth_view) - center_view;
    float tolerance_m = 0.025 + abs(center_view.z) * 0.002;
    float plane_distance_m = abs(dot(delta_view, normal_view));
    return max(1.0 - plane_distance_m / tolerance_m, 0.0)
        * clamp((normal_dot - 0.94) / 0.06, 0.0, 1.0);
}

#endif

#endif // LIB_LIGHTING_GI_REBLUR_GLSL
