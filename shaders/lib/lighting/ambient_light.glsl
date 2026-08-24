#ifndef LIB_LIGHTING_AMBIENT_LIGHT_GLSL
#define LIB_LIGHTING_AMBIENT_LIGHT_GLSL

// lmcoord → lighting helpers shared by deferred2 and the translucent passes
// (same remap curves + sky ambient). Vanilla lightmap = (blockLight,
// skyLight) in 0..1: deferred2 from colortex4.zw, translucent from
// v_texcoord.zw.

#include "/lib/contract/settings.glsl"
#include "/lib/atmosphere/sky_light.glsl"

// Block light: steep power curve for high dynamic range (torches are bright).
float BlockLightFalloff(float lm_block) {
    float d = (1.0 - lm_block) * 15.0 + 1.5;
    return 1.0 / (d * d);
}

float BlockLightFromLm(float lm_block) {
    float light = BlockLightFalloff(lm_block);
    float light_zero = BlockLightFalloff(0.0);
    return (light - light_zero) / (1.0 - light_zero);
}

// Sky light: quadratic falloff — outdoor areas ramp quickly with sky access.
float SkyLightFromLm(float lm_sky) {
    return lm_sky * lm_sky;
}

// Sky ambient: at full visibility the directional SH irradiance at the
// normal applies; as AO drops (normal into a corner) it blends toward the
// direction-independent sky average (~1/8 sphere). Pass ao = vec3(1.0) where
// no screen-space AO exists (translucent); caller multiplies by the remapped
// sky light.
vec3 SkyAmbientColor(vec3 normal, vec3 ao) {
    return mix(EvalSkyLightAverage() * 0.3, EvalSkyLight(normal), ao);
}

// Final ambient light for a surface: the AO-blended sky irradiance scaled by
// the remapped sky light, plus the global AMBIENT_BASE floor so caves and
// deep shadows never render fully black. ao: screen-space AO (1.0 where
// unavailable, e.g. gbuffer translucent). Shared by deferred2 and the
// translucent passes; the Lambert/diffuse BRDF multiplies the result.
vec3 AmbientLight(vec3 normal, vec3 ao, float lm_sky) {
    return SkyAmbientColor(normal, ao) * SkyLightFromLm(lm_sky) + vec3(AMBIENT_BASE);
}

#endif