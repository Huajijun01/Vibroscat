#ifndef LIB_LIGHTING_AMBIENT_LIGHT_GLSL
#define LIB_LIGHTING_AMBIENT_LIGHT_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/lighting/lightmap.glsl"

// Sky ambient: at full visibility the directional SH irradiance at the
// normal applies; as AO drops (normal into a corner) it blends toward the
// direction-independent sky average (~1/8 sphere). Pass ao = vec3(1.0) where
// no screen-space AO exists (translucent); caller multiplies by the remapped
// sky light.
vec3 SkyAmbientColor(vec3 normal_world, vec3 ao) {
    return mix(EvalSkyLightAverage() * 0.3, EvalSkyLight(normal_world), ao);
}

// Final ambient light for a surface: the AO-blended sky irradiance scaled by
// the remapped sky light and the global SKY_AMBIENT_STRENGTH, plus the global
// AMBIENT_FLOOR floor so caves and deep shadows never render fully black. Only
// the SH term takes the strength, because the floor is an absolute minimum and
// RSMOccludedSky splits the two the same way. Keeping the scale here makes this
// function its single owner, so the no-GI ambient and the SH fallback both GI
// sources leave in their uncovered directions cannot drift apart. ao:
// screen-space AO (1.0 where unavailable, e.g. gbuffer translucent). Shared by
// the deferred shading pass and the forward translucent passes; the
// Lambert/diffuse BRDF multiplies the result.
vec3 AmbientLight(vec3 normal_world, vec3 ao, float lm_sky) {
    return SkyAmbientColor(normal_world, ao) * SkyLightFromLm(lm_sky)
        * SKY_AMBIENT_STRENGTH + vec3(AMBIENT_FLOOR);
}

#endif // LIB_LIGHTING_AMBIENT_LIGHT_GLSL
