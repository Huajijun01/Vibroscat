#ifndef LIB_RAYTRACE_OPAQUE_REFLECTION_RECONSTRUCTION_GLSL
#define LIB_RAYTRACE_OPAQUE_REFLECTION_RECONSTRUCTION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/color/spaces.glsl"
#include "/lib/raytrace/opaque_reflection_history.glsl"

#if defined(OPAQUE_SSR) && OPAQUE_SSR_FILTER == 2
struct OpaqueReflectionFilterGuide {
    vec3 normal_world;
    vec2 plane_step;
    float ray_plane;
    float receiver_plane;
    float receiver_depth;
    float roughness;
    float age;
    float normal_floor;
    float support_floor;
    uint selector;
};

struct OpaqueReflectionFilterState {
    vec3 sum_z;
    float sum_weight;
    vec3 brightest_z;
    float brightest_y;
    float brightest_weight;
    uint brightest_variance;
    float brightest_age;
    float support_sum_weight;
    int support_taps;
};

// Inner taps call this with constant offsets and support=true; outer taps
// use support=false. Neither path needs indexed private sample storage.
float AccumulateOpaqueReflectionTap(ivec2 texel, ivec2 offset, float spatial_weight, bool use_support,
        OpaqueReflectionFilterGuide guide, inout OpaqueReflectionFilterState state) {
    ivec2 tap = texel + offset;
    if (any(lessThan(tap, ivec2(0))) || any(greaterThanEqual(tap, ivec2(u_render_res)))) return 1e30;
    uvec4 data = texelFetch(colortex6, tap, 0);
    float tap_age = OpaqueHistoryAge(data);
    if (tap_age < 1.0) return 1e30;
    float roughness_difference = abs(OpaqueHistoryRoughness(data) - guide.roughness);
    if (roughness_difference > 0.04) return 1e30;
    float depth_view = OpaqueHistoryDepth(data);
    float ray_plane = guide.ray_plane + dot(vec2(offset), guide.plane_step);
    float plane_error = abs(depth_view * ray_plane - guide.receiver_plane);
    float plane_limit = 0.015 + 0.0012 * max(depth_view, guide.receiver_depth);
    if (plane_error > plane_limit) return 1e30;
    vec3 tap_normal = DecodeOctahedralNormal(texelFetch(colortex12, tap, 0).rg);
    float normal_dot = dot(guide.normal_world, tap_normal);
    float selector_difference = abs(float(data.g >> 8) - float(guide.selector)) / 255.0;
    float weight = 1.0 / (1.0 + 2.0 * selector_difference);
    weight *= 1.0 - roughness_difference / 0.04;
    weight *= 1.0 - smoothstep(plane_limit * 0.5, plane_limit, plane_error);
    // The receiver already folded the local angular-lobe factor into the
    // spatial weight. No tap position or normalized eye vector is needed.
    weight *= min(tap_age / guide.age, 1.0) * spatial_weight;
    float support_weight = use_support ? weight * smoothstep(guide.support_floor, 1.0, normal_dot) : 0.0;
    weight *= smoothstep(guide.normal_floor, 1.0, normal_dot);
    if (max(weight, support_weight) <= 1e-4) return 1e30;
    vec3 tap_z = OpaqueHistoryMean(tap, data);
    if (!IsFinite(tap_z)) return 1e30;
    float tap_y = Luminance(tap_z);
    float support_y = 1e30;
    if (support_weight > 1e-4) {
        state.support_sum_weight += support_weight;
        ++state.support_taps;
        support_y = tap_y;
    }
    if (weight <= 1e-4) return support_y;
    state.sum_z += weight * tap_z;
    state.sum_weight += weight;
    if (tap_y > state.brightest_y) {
        state.brightest_z = tap_z;
        state.brightest_y = tap_y;
        state.brightest_weight = weight;
        state.brightest_variance = data.a;
        state.brightest_age = tap_age;
    }
    return support_y;
}

void OrderOpaqueReflectionSupport(inout float a, inout float b) {
    float low = min(a, b);
    b = max(a, b);
    a = low;
}

float OpaqueReflectionSupportMedian(vec4 low, vec4 high, int count) {
    // Fixed eight-value sorting network. Missing taps sort after valid ones;
    // the upper median preserves a bright edge with half-neighborhood support.
    OrderOpaqueReflectionSupport(low.x, low.y);
    OrderOpaqueReflectionSupport(low.z, low.w);
    OrderOpaqueReflectionSupport(high.x, high.y);
    OrderOpaqueReflectionSupport(high.z, high.w);
    OrderOpaqueReflectionSupport(low.x, low.z);
    OrderOpaqueReflectionSupport(low.y, low.w);
    OrderOpaqueReflectionSupport(high.x, high.z);
    OrderOpaqueReflectionSupport(high.y, high.w);
    OrderOpaqueReflectionSupport(low.y, low.z);
    OrderOpaqueReflectionSupport(high.y, high.z);
    OrderOpaqueReflectionSupport(low.x, high.x);
    OrderOpaqueReflectionSupport(low.w, high.w);
    OrderOpaqueReflectionSupport(low.y, high.y);
    OrderOpaqueReflectionSupport(low.z, high.z);
    OrderOpaqueReflectionSupport(low.y, high.x);
    OrderOpaqueReflectionSupport(low.w, high.z);
    OrderOpaqueReflectionSupport(low.z, high.x);
    OrderOpaqueReflectionSupport(low.w, high.y);
    OrderOpaqueReflectionSupport(low.w, high.x);
    // The caller has 4..8 valid taps, so only sorted elements 2, 3, 4
    // can be selected. Keep every component statically addressable.
    return count < 6 ? low.z : count < 8 ? low.w : high.x;
}
#endif

// Display-only filtering: never write the spatial result into colortex3.
vec3 ReconstructOpaqueReflection(ivec2 texel, vec3 receiver_view,
        vec3 normal_world, vec3 geo_normal_world, float roughness, bool is_hand) {
#if defined(OPAQUE_SSR) && OPAQUE_SSR_FILTER == 2
    uvec4 center_data = texelFetch(colortex6, texel, 0);
    vec3 center_z = OpaqueHistoryMean(texel, center_data);
    if (is_hand || roughness < 0.06) return center_z;
    float age = OpaqueHistoryAge(center_data);
    if (age < 1.0) return center_z;
    float variance = OpaqueHistoryVariance(center_data);
    float relative_noise = sqrt(max(variance, 0.0)) / max(Luminance(center_z), 0.05);
    float rough_outlier = smoothstep(0.08, 0.25, roughness);
    float center_instability = max(relative_noise,
        rough_outlier * (1.0 - smoothstep(1.0, 4.0, age)));
    // Contiguous support avoids separate pixel lattices and frame-varying
    // integer strides driven by a single random reflection hit distance.
    // Diagonals enter continuously as estimator variance rises.
    float diagonal_weight = smoothstep(0.12, 0.24, roughness)
        * max(1.0 - smoothstep(2.0, 8.0, age), smoothstep(0.15, 0.65, relative_noise));
    // Short histories during motion need additional spatial samples instead
    // of a longer temporal trail. Add a connected radius-two ring only for
    // rough, noisy histories; established stationary means keep the small kernel.
    float outer_weight = smoothstep(0.12, 0.25, roughness)
        * smoothstep(0.2, 0.8, relative_noise) * (1.0 - smoothstep(6.0, 12.0, age));
    OpaqueReflectionFilterGuide guide;
    guide.normal_world = normal_world;
    vec3 geo_view = mat3(gbufferModelView) * geo_normal_world;
    vec2 uv = (vec2(texel) + 0.5) * u_render_pixel_size;
#ifdef TAA
    uv -= u_taa_offset * 0.5;
#endif
    vec2 projection_inverse = 1.0 / vec2(gbufferProjection[0][0], gbufferProjection[1][1]);
    vec2 ray = (uv * 2.0 - 1.0) * projection_inverse;
    vec2 ray_step = 2.0 * u_render_pixel_size * projection_inverse;
    guide.plane_step = ray_step * geo_view.xy;
    guide.ray_plane = dot(vec3(ray, -1.0), geo_view);
    guide.receiver_plane = dot(receiver_view, geo_view);
    guide.receiver_depth = -receiver_view.z;
    guide.roughness = roughness;
    guide.age = age;
    guide.normal_floor = mix(0.9995, 0.95, roughness * roughness);
    // Broader normals provide statistical support on normal-mapped surfaces;
    // the color average retains the strict normal boundary above.
    guide.support_floor = mix(0.9995, 0.65, rough_outlier);
    guide.selector = center_data.g >> 8;
    // Differential of normalize(vec3(ray,-1)): squared angular distance is
    // dx^2*M.x + 2*dx*dy*M.y + dy^2*M.z. The <=2-pixel kernel needs only
    // this local metric, not a normalized 3D eye vector for every sample.
    float ray_length_sq = dot(ray, ray) + 1.0;
    vec3 view_metric = vec3(ray_step.x * ray_step.x * (1.0 + ray.y * ray.y),
        -ray_step.x * ray_step.y * ray.x * ray.y,
        ray_step.y * ray_step.y * (1.0 + ray.x * ray.x)) / (ray_length_sq * ray_length_sq);
    float inverse_lobe = 1.0 / max(roughness * roughness, 0.002);
    vec2 axial_weight = vec2(0.7) / (vec2(1.0) + sqrt(view_metric.xz) * inverse_lobe);
    vec2 diagonal_lobe = vec2(1.0) / (vec2(1.0)
        + sqrt(max(vec2(view_metric.x + view_metric.z) + vec2(2.0, -2.0) * view_metric.y,
            vec2(0.0))) * inverse_lobe);
    OpaqueReflectionFilterState state;
    state.sum_z = center_z;
    state.sum_weight = 1.0;
    state.brightest_z = vec3(0.0);
    state.brightest_y = 0.0;
    state.brightest_weight = 0.0;
    state.brightest_variance = 0u;
    state.brightest_age = 1.0;
    state.support_sum_weight = 0.0;
    state.support_taps = 0;
    vec4 support_low;
    support_low.x = AccumulateOpaqueReflectionTap(texel, ivec2(-1, 0), axial_weight.x, true, guide, state);
    support_low.y = AccumulateOpaqueReflectionTap(texel, ivec2(1, 0), axial_weight.x, true, guide, state);
    support_low.z = AccumulateOpaqueReflectionTap(texel, ivec2(0, -1), axial_weight.y, true, guide, state);
    support_low.w = AccumulateOpaqueReflectionTap(texel, ivec2(0, 1), axial_weight.y, true, guide, state);
    vec4 support_high = vec4(1e30);
    if (diagonal_weight >= 0.01) {
        vec2 diagonal = 0.4 * diagonal_weight * diagonal_lobe;
        support_high.x = AccumulateOpaqueReflectionTap(texel, ivec2(-1, -1), diagonal.x, true, guide, state);
        support_high.y = AccumulateOpaqueReflectionTap(texel, ivec2(1, -1), diagonal.y, true, guide, state);
        support_high.z = AccumulateOpaqueReflectionTap(texel, ivec2(-1, 1), diagonal.y, true, guide, state);
        support_high.w = AccumulateOpaqueReflectionTap(texel, ivec2(1, 1), diagonal.x, true, guide, state);
        if (outer_weight >= 0.01) {
            for (int i = 0; i < 12; ++i) {
                ivec2 offset;
                if (i < 4) {
                    offset = 2 * ivec2(i < 2 ? i * 2 - 1 : 0, i >= 2 ? i * 2 - 5 : 0);
                } else if (i < 8) {
                    offset = ivec2(((i >> 1) & 1) * 4 - 2, (i & 1) * 2 - 1);
                } else {
                    offset = ivec2((i & 1) * 2 - 1, ((i >> 1) & 1) * 4 - 2);
                }
                vec2 offset_float = vec2(offset);
                float view_difference = sqrt(max(dot(view_metric,
                    vec3(offset_float.x * offset_float.x, 2.0 * offset_float.x * offset_float.y,
                        offset_float.y * offset_float.y)), 0.0));
                float spatial_weight = (i < 4 ? 0.35 : 0.25) * outer_weight
                    / (1.0 + view_difference * inverse_lobe);
                AccumulateOpaqueReflectionTap(texel, offset, spatial_weight, false, guide, state);
            }
        }
    }
    // Estimate local support without the center. The median also rejects a
    // small cluster whose brightest neighbors would contaminate a mean. Only
    // isolated, noisy outliers are limited; a stable highlight or a reflected
    // edge supported by several bright taps keeps its energy. This display
    // estimator is intentionally biased; the temporal mean stays unmodified.
    if (state.support_taps >= 4 && state.support_sum_weight > 1.0) {
        float brightest_noise = max(sqrt(max(OpaqueHistoryVariance(
            uvec4(0u, 0u, 0u, state.brightest_variance)), 0.0)) / max(state.brightest_y, 0.05),
            rough_outlier * (1.0 - smoothstep(1.0, 4.0, state.brightest_age)));
        float supported_y = OpaqueReflectionSupportMedian(support_low, support_high, state.support_taps);
        // A broad rough lobe needs stronger local support than a sharp lobe.
        // Newly reset histories have no useful variance yet, so their age
        // supplies uncertainty only for rough surfaces. Keep this out of the
        // recursive mean to avoid hiding a persistent small light source.
        float limit = mix(6.0, 2.5, rough_outlier) * supported_y + 0.05;
        float noise_start = mix(0.75, 0.25, rough_outlier);
        float noise_full = mix(1.5, 0.75, rough_outlier);
        float center_scale = mix(1.0, min(limit / max(Luminance(center_z), 0.05), 1.0),
            smoothstep(noise_start, noise_full, center_instability));
        float brightest_scale = mix(1.0, min(limit / max(state.brightest_y, 0.05), 1.0),
            smoothstep(noise_start, noise_full, brightest_noise));
        state.sum_z += center_z * (center_scale - 1.0)
            + state.brightest_z * (state.brightest_weight * (brightest_scale - 1.0));
    }
    return state.sum_z / state.sum_weight;
#elif defined(OPAQUE_SSR) && OPAQUE_SSR_FILTER > 0
    return OpaqueHistoryMean(texel, texelFetch(colortex6, texel, 0));
#else
    return texelFetch(colortex3, texel, 0).rgb;
#endif
}

#endif // LIB_RAYTRACE_OPAQUE_REFLECTION_RECONSTRUCTION_GLSL
