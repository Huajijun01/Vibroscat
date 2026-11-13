#ifndef LIB_LIGHTING_AMBIENT_LIGHT_GLSL
#define LIB_LIGHTING_AMBIENT_LIGHT_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/lighting/lightmap.glsl"

// ao = 1 where no screen-space AO exists (translucent).
vec3 SkyAmbientColor(vec3 normal_world, vec3 ao) {
    return mix(EvalSkyLightAverage() * 0.3, EvalSkyLight(normal_world), ao);
}

// Only the SH term takes SKY_AMBIENT_STRENGTH; AMBIENT_FLOOR is an absolute
// minimum outside the sky's control. Keeping both here prevents the no-GI
// ambient and the GI sky fallback from drifting apart.
vec3 AmbientLight(vec3 normal_world, vec3 ao, float lm_sky) {
    return SkyAmbientColor(normal_world, ao) * SkyLightFromLm(lm_sky)
        * SKY_AMBIENT_STRENGTH + vec3(AMBIENT_FLOOR);
}

#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
// The directional integral already contains geometric sky occlusion. GI does
// not apply artistic AO strength or multibounce; raw AO attenuates only the
// ambient floor here. GatherRSM must not multiply this fallback by AO again.
vec3 AmbientLightWithSkyVisibility(vec3 visible_sky, float raw_ao, float lm_sky) {
    return visible_sky * SkyLightFromLm(lm_sky) * SKY_AMBIENT_STRENGTH
        + vec3(AMBIENT_FLOOR * raw_ao);
}
#endif

#endif // LIB_LIGHTING_AMBIENT_LIGHT_GLSL
