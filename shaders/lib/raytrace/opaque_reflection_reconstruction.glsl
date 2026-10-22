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
void OrderOpaqueReflectionSupport(inout float a, inout float b) {
    float low = min(a, b);
    b = max(a, b);
    a = low;
}

float OpaqueReflectionSupportMedian(float values[8], int count) {
    // Fixed eight-value sorting network. Missing taps sort after valid ones;
    // the upper median preserves a bright edge with half-neighborhood support.
    OrderOpaqueReflectionSupport(values[0], values[1]);
    OrderOpaqueReflectionSupport(values[2], values[3]);
    OrderOpaqueReflectionSupport(values[4], values[5]);
    OrderOpaqueReflectionSupport(values[6], values[7]);
    OrderOpaqueReflectionSupport(values[0], values[2]);
    OrderOpaqueReflectionSupport(values[1], values[3]);
    OrderOpaqueReflectionSupport(values[4], values[6]);
    OrderOpaqueReflectionSupport(values[5], values[7]);
    OrderOpaqueReflectionSupport(values[1], values[2]);
    OrderOpaqueReflectionSupport(values[5], values[6]);
    OrderOpaqueReflectionSupport(values[0], values[4]);
    OrderOpaqueReflectionSupport(values[3], values[7]);
    OrderOpaqueReflectionSupport(values[1], values[5]);
    OrderOpaqueReflectionSupport(values[2], values[6]);
    OrderOpaqueReflectionSupport(values[1], values[4]);
    OrderOpaqueReflectionSupport(values[3], values[6]);
    OrderOpaqueReflectionSupport(values[2], values[4]);
    OrderOpaqueReflectionSupport(values[3], values[5]);
    OrderOpaqueReflectionSupport(values[3], values[4]);
    return values[count / 2];
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
    vec3 sum_z = center_z;
    float sum_weight = 1.0;
    vec3 brightest_z = vec3(0.0);
    float brightest_y = 0.0;
    float brightest_weight = 0.0;
    float brightest_noise = 0.0;
    float support_sum_weight = 0.0;
    int support_taps = 0;
    float support_values[8] = float[8](1e30, 1e30, 1e30, 1e30, 1e30, 1e30, 1e30, 1e30);
    vec3 geo_view = mat3(gbufferModelView) * geo_normal_world;
    const ivec2 OFFSETS[20] = ivec2[20](ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1),
        ivec2(-1, -1), ivec2(1, -1), ivec2(-1, 1), ivec2(1, 1),
        ivec2(-2, 0), ivec2(2, 0), ivec2(0, -2), ivec2(0, 2),
        ivec2(-2, -1), ivec2(-2, 1), ivec2(2, -1), ivec2(2, 1),
        ivec2(-1, -2), ivec2(1, -2), ivec2(-1, 2), ivec2(1, 2));
    for (int i = 0; i < 20; ++i) {
        if (i >= 4 && diagonal_weight < 0.01) break;
        if (i >= 8 && outer_weight < 0.01) break;
        ivec2 tap = texel + OFFSETS[i];
        if (any(lessThan(tap, ivec2(0))) || any(greaterThanEqual(tap, ivec2(u_render_res)))) continue;
        uvec4 data = texelFetch(colortex6, tap, 0);
        float tap_age = OpaqueHistoryAge(data);
        if (tap_age < 1.0) continue;
        float roughness_difference = abs(OpaqueHistoryRoughness(data) - roughness);
        if (roughness_difference > 0.04) continue;
        vec2 uv = (vec2(tap) + 0.5) * u_render_pixel_size;
#ifdef TAA
        uv -= u_taa_offset * 0.5;
#endif
        vec2 ray = (uv * 2.0 - 1.0) / vec2(gbufferProjection[0][0], gbufferProjection[1][1]);
        vec3 tap_view = vec3(ray, -1.0) * OpaqueHistoryDepth(data);
        float plane_error = abs(dot(tap_view - receiver_view, geo_view));
        float plane_limit = 0.015 + 0.0012 * max(-tap_view.z, -receiver_view.z);
        if (plane_error > plane_limit) continue;
        vec3 tap_normal = DecodeOctahedralNormal(texelFetch(colortex12, tap, 0).rg);
        float normal_floor = mix(0.9995, 0.95, roughness * roughness);
        float normal_dot = dot(normal_world, tap_normal);
        float weight = 1.0;
        // Same GGX model permits color/F0 edges; selector changes are soft.
        float selector_difference = abs(float(data.g >> 8) - float(center_data.g >> 8)) / 255.0;
        weight *= 1.0 / (1.0 + 2.0 * selector_difference);
        weight *= 1.0 - roughness_difference / 0.04;
        weight *= 1.0 - smoothstep(plane_limit * 0.5, plane_limit, plane_error);
        float view_difference = length(normalize(-tap_view) - normalize(-receiver_view));
        weight *= 1.0 / (1.0 + view_difference / max(roughness * roughness, 0.002));
        float spatial_weight = i < 4 ? 0.7 : i < 8 ? 0.4 * diagonal_weight
            : (i < 12 ? 0.35 : 0.25) * outer_weight;
        weight *= min(tap_age / max(age, 1.0), 1.0) * spatial_weight;
        // Normal-map detail must not leave a rough outlier with no statistical
        // support. Use a broader normal guide for its luminance limit only;
        // the color average below retains the strict lobe/normal boundary.
        float support_floor = mix(0.9995, 0.65, smoothstep(0.08, 0.25, roughness));
        float support_weight = i < 8 ? weight * smoothstep(support_floor, 1.0, normal_dot) : 0.0;
        weight *= smoothstep(normal_floor, 1.0, normal_dot);
        if (max(weight, support_weight) <= 1e-4) continue;
        vec3 tap_z = OpaqueHistoryMean(tap, data);
        if (!IsFinite(tap_z)) continue;
        float tap_y = Luminance(tap_z);
        if (support_weight > 1e-4) {
            support_sum_weight += support_weight;
            support_values[support_taps] = tap_y;
            ++support_taps;
        }
        if (weight <= 1e-4) continue;
        sum_z += weight * tap_z;
        sum_weight += weight;
        if (tap_y > brightest_y) {
            brightest_z = tap_z;
            brightest_y = tap_y;
            brightest_weight = weight;
            brightest_noise = max(sqrt(max(OpaqueHistoryVariance(data), 0.0)) / max(tap_y, 0.05),
                rough_outlier * (1.0 - smoothstep(1.0, 4.0, tap_age)));
        }
    }
    // Estimate local support without the center. The median also rejects a
    // small cluster whose brightest neighbors would contaminate a mean. Only
    // isolated, noisy outliers are limited; a stable highlight or a reflected
    // edge supported by several bright taps keeps its energy. This display
    // estimator is intentionally biased; the temporal mean stays unmodified.
    if (support_taps >= 4 && support_sum_weight > 1.0) {
        float supported_y = OpaqueReflectionSupportMedian(support_values, support_taps);
        // A broad rough lobe needs stronger local support than a sharp lobe.
        // Newly reset histories have no useful variance yet, so their age
        // supplies uncertainty only for rough surfaces. Keep this out of the
        // recursive mean to avoid hiding a persistent small light source.
        float limit = mix(6.0, 2.5, rough_outlier) * supported_y + 0.05;
        float noise_start = mix(0.75, 0.25, rough_outlier);
        float noise_full = mix(1.5, 0.75, rough_outlier);
        float center_scale = mix(1.0, min(limit / max(Luminance(center_z), 0.05), 1.0),
            smoothstep(noise_start, noise_full, center_instability));
        float brightest_scale = mix(1.0, min(limit / max(brightest_y, 0.05), 1.0),
            smoothstep(noise_start, noise_full, brightest_noise));
        sum_z += center_z * (center_scale - 1.0)
            + brightest_z * (brightest_weight * (brightest_scale - 1.0));
    }
    return sum_z / sum_weight;
#elif defined(OPAQUE_SSR) && OPAQUE_SSR_FILTER > 0
    return OpaqueHistoryMean(texel, texelFetch(colortex6, texel, 0));
#else
    return texelFetch(colortex3, texel, 0).rgb;
#endif
}

#endif // LIB_RAYTRACE_OPAQUE_REFLECTION_RECONSTRUCTION_GLSL
