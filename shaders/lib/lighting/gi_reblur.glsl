#ifndef LIB_LIGHTING_GI_REBLUR_GLSL
#define LIB_LIGHTING_GI_REBLUR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/color/spaces.glsl"
#include "/lib/lighting/gi_history.glsl"

// Independent diffuse adaptation of the published ReBLUR architecture:
// long/fast histories, history reconstruction, adaptive blur, spatial feedback,
// and separate temporal stabilization. This is not an NRD SDK source port.
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

vec4 StabilizeGIReblur(ivec2 texel, vec4 filtered) {
    float age = GIHistoryAge(texelFetch(colortex10, texel, 0).r);
    if (age < 1.0) return vec4(filtered.rgb, 0.0);
    vec4 previous = texelFetch(colortex7, texel, 0);
    if (previous.a < 1.0) return vec4(filtered.rgb, 1.0);

    // The neighborhood bounds keep moving light/occlusion responsive. Main
    // feedback remains the post-blur value, not this extra-stabilized output.
    vec3 lower = filtered.rgb;
    vec3 upper = filtered.rgb;
    ivec2 size_texel = textureSize(colortex10, 0);
    uint metadata = texelFetch(colortex10, texel, 0).r;
    vec3 center_view = GIReblurViewPosition(texel, GIHistoryDepth(metadata));
    vec3 normal_world = GIHistoryNormal(metadata);
    vec3 normal_view = normalize(mat3(gbufferModelView) * normal_world);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            ivec2 sample_texel = texel + ivec2(x, y);
            if (GIReblurGeometryWeight(sample_texel, size_texel, center_view,
                    normal_world, normal_view) <= 0.0) continue;
            vec3 neighbor = texelFetch(usam_gi_reblur_a, sample_texel, 0).rgb;
            lower = min(lower, neighbor);
            upper = max(upper, neighbor);
        }
    }
    float sigma = filtered.a;
    vec3 extent = vec3(2.0 * sigma + 0.005) + 0.03 * filtered.rgb;
    lower = max(lower, filtered.rgb - extent);
    upper = min(upper, filtered.rgb + extent);
    vec3 clipped = clamp(previous.rgb, lower, upper);
    float stabilization_age = min(min(previous.a + 1.0, age), 8.0);
    float previous_luminance = Luminance(previous.rgb);
    float clamp_delta = abs(Luminance(clipped) - previous_luminance);
    float response = clamp(clamp_delta / (sigma + 0.05 * previous_luminance + 0.01), 0.0, 1.0);
    stabilization_age = mix(stabilization_age, 1.0, response);
    return vec4(GIReblurFinite(mix(clipped, filtered.rgb, 1.0 / stabilization_age)), stabilization_age);
}
#endif

#endif // LIB_LIGHTING_GI_REBLUR_GLSL
