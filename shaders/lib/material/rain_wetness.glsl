#ifndef LIB_MATERIAL_RAIN_WETNESS_GLSL
#define LIB_MATERIAL_RAIN_WETNESS_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/material/model.glsl"
#include "/lib/water/rain_ripples.glsl"

void ApplyRainWetness(vec2 world_xz, float geo_normal_y, float sky_light,
        int material_id, inout OpaqueMaterial material,
        inout vec3 normal_world, inout vec3 albedo_srgb) {
    // Reject before either lookup. Plants, emissive blocks and translucent
    // classes cannot hold a puddle; geometry, rather than the normal map,
    // decides which faces are upward-facing.
    if (u_wetness_weight <= 0.001 || isEyeInWater != 0 ||
        geo_normal_y <= 0.95 || sky_light <= 15.0 / 16.0 ||
        material_id >= 112 || (material_id >= 80 && material_id < 96)) return;
#ifdef RAIN_PUDDLES
    if (RAIN_PUDDLE_COVERAGE <= 0.0) return;
#endif

    float rain_exposure = smoothstep(15.0 / 16.0, 1.0, sky_light);
    float wet_surface = u_wetness_weight * rain_exposure * smoothstep(0.95, 1.0, geo_normal_y);
    if (wet_surface <= 0.001) return;

    float puddle;
#ifdef RAIN_PUDDLES
    vec2 camera_xz = vec2(cameraPositionInt.xz & ivec2(RAIN_PUDDLE_SCALE_M - 1))
        + cameraPositionFract.xz;
    vec2 uv = (world_xz + camera_xz) / float(RAIN_PUDDLE_SCALE_M);
    // Fixed LOD is valid after non-uniform early-outs. Puddle shapes stay
    // stationary and independent of cloud wind, coverage and cloud toggles.
    float distribution = textureLod(utex_cloud_distribution_tex, uv, 0.0).r;
    float threshold = 1.0 - RAIN_PUDDLE_COVERAGE;
    puddle = smoothstep(threshold - 0.08, threshold + 0.08, distribution) * wet_surface;
    if (puddle <= 0.001) return;
#else
    puddle = wet_surface;
#endif

    material.perceptual_roughness = mix(material.perceptual_roughness,
        min(material.perceptual_roughness, 0.04), puddle);
    albedo_srgb *= 1.0 - 0.15 * puddle;
    // Keep selector/emission/AO and the separate geometric normal intact:
    // deferred lighting and its existing SSR gate consume this single layer.
    vec3 puddle_normal = vec3(0.0, 1.0, 0.0);
#ifdef RAIN_RIPPLES
    float ripple_weight = u_rain_weight * RAIN_RIPPLE_STRENGTH * rain_exposure;
    if (ripple_weight > 0.001) {
        vec2 slope = SampleRainRippleSlope(world_xz) * ripple_weight;
        puddle_normal = vec3(slope.x, 1.0, slope.y);
    }
#endif
    normal_world = normalize(mix(normal_world, puddle_normal, puddle));
}

#endif // LIB_MATERIAL_RAIN_WETNESS_GLSL
