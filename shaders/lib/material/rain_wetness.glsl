#ifndef LIB_MATERIAL_RAIN_WETNESS_GLSL
#define LIB_MATERIAL_RAIN_WETNESS_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/material/model.glsl"
#include "/lib/water/rain_ripples.glsl"
#include "/lib/geometry/fragment_position.glsl"

// surface_view_pos: reuse the caller's derivative-basis position when available; otherwise
// this library reconstructs it after the cheap rejections, so dry surfaces never pay for it.
// Returns whether the wet layer was applied.
bool ApplyRainWetness(
#if defined(TERRAIN_DERIVATIVE_TBN_ACTIVE) && defined(RAIN_WETNESS_POSITION_ACTIVE)
        vec3 surface_view_pos,
#endif
        float geo_normal_y, float sky_light, int material_id,
        inout OpaqueMaterial material, inout vec3 normal_world,
        inout vec3 albedo_srgb) {
    if (u_wetness_weight <= 0.001 || isEyeInWater != 0 ||
        geo_normal_y <= 0.95 || sky_light <= 15.0 / 16.0 ||
        material_id >= 112 || (material_id >= 80 && material_id < 96)) return false;
#ifdef RAIN_PUDDLES
    if (RAIN_PUDDLE_COVERAGE <= 0.0) return false;
#endif

    float rain_exposure = smoothstep(15.0 / 16.0, 1.0, sky_light);
    float wet_surface = u_wetness_weight * rain_exposure * smoothstep(0.95, 1.0, geo_normal_y);
    if (wet_surface <= 0.001) return false;

#if defined(RAIN_WETNESS_POSITION_ACTIVE)
#if !defined(TERRAIN_DERIVATIVE_TBN_ACTIVE)
    vec3 surface_view_pos = ReconstructGbufferViewPosition(gl_FragCoord);
#endif
    vec2 world_xz = ViewToWorldSpace(surface_view_pos).xz;
#endif

    float puddle;
#ifdef RAIN_PUDDLES
    vec2 camera_xz = vec2(cameraPositionInt.xz & ivec2(RAIN_PUDDLE_SCALE_M - 1))
        + cameraPositionFract.xz;
    vec2 uv = (world_xz + camera_xz) / float(RAIN_PUDDLE_SCALE_M);
    // Fixed LOD: implicit derivatives are invalid after non-uniform early-outs; puddles stay
    // independent of cloud wind, coverage and cloud toggles.
    float distribution = textureLod(utex_cloud_distribution_tex, uv, 0.0).r;
    float threshold = 1.0 - RAIN_PUDDLE_COVERAGE;
    puddle = smoothstep(threshold - 0.08, threshold + 0.08, distribution) * wet_surface;
    if (puddle <= 0.001) return false;
#else
    puddle = wet_surface;
#endif

    material.perceptual_roughness = mix(material.perceptual_roughness,
        min(material.perceptual_roughness, 0.04), puddle);
    albedo_srgb *= 1.0 - 0.15 * puddle;
    // Selector/emission/AO and the geometric normal stay intact: deferred lighting and its SSR gate consume this single layer.
    vec3 puddle_normal = vec3(0.0, 1.0, 0.0);
#ifdef RAIN_RIPPLES
    float ripple_weight = u_rain_weight * RAIN_RIPPLE_STRENGTH * rain_exposure;
    if (ripple_weight > 0.001) {
        vec2 slope = SampleRainRippleSlope(world_xz) * ripple_weight;
        puddle_normal = vec3(slope.x, 1.0, slope.y);
    }
#endif
    normal_world = normalize(mix(normal_world, puddle_normal, puddle));
    return true;
}

#endif // LIB_MATERIAL_RAIN_WETNESS_GLSL
