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
// the SH term takes the strength, because the floor is an absolute minimum
// outside the sky's control. Keeping the scale here makes this function its
// single owner, so the no-GI ambient and the SH fallback both GI sources leave
// in their uncovered directions cannot drift apart. ao:
// screen-space AO (1.0 where unavailable, e.g. gbuffer translucent). Shared by
// the deferred shading pass and the forward translucent passes; the
// Lambert/diffuse BRDF multiplies the result.
vec3 AmbientLight(vec3 normal_world, vec3 ao, float lm_sky) {
    return SkyAmbientColor(normal_world, ao) * SkyLightFromLm(lm_sky)
        * SKY_AMBIENT_STRENGTH + vec3(AMBIENT_FLOOR);
}

#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
// Blocked fractions below this are treated as unoccluded for the directional
// remap: dividing by a near-zero blocked fraction would amplify SH-truncation
// noise, while the skipped correction is at most the same tiny fraction of
// the open-to-visible gap.
const float SKY_VISIBILITY_GAIN_EPSILON = 1.0e-4;

// RSM ambient fallback with directional sky visibility (gtao.glsl supplies
// the arc integral). raw_ao is the geometric GTAO visibility before artistic
// response; surface_ao is the same value after ApplySurfaceAO strength and
// multibounce. The remap scales the directional occlusion
// (open_sky - visible_sky) by how much artistic surface AO actually darkens,
// so GTAO_STRENGTH and GTAO_MULTIBOUNCE keep their existing control: at
// strength 1 with multibounce off, surface_ao equals raw_ao, the gain is 1,
// and the sky term is exactly the physical visible_sky. The returned
// fallback already carries sky occlusion and the AO-scaled ambient floor;
// GatherRSM must not multiply it by ambient_ao again.
vec3 AmbientLightWithSkyVisibility(vec3 open_sky, vec3 visible_sky,
        float raw_ao, vec3 surface_ao, float lm_sky) {
    float blocked_fraction = 1.0 - clamp(raw_ao, 0.0, 1.0);
    vec3 occlusion_gain = vec3(1.0);
    if (blocked_fraction > SKY_VISIBILITY_GAIN_EPSILON) {
        occlusion_gain = max(vec3(1.0) - surface_ao, vec3(0.0)) / blocked_fraction;
    }
    vec3 adjusted_sky = clamp(open_sky - (open_sky - visible_sky) * occlusion_gain,
        vec3(0.0), open_sky);
    return adjusted_sky * SkyLightFromLm(lm_sky) * SKY_AMBIENT_STRENGTH
        + vec3(AMBIENT_FLOOR) * surface_ao;
}
#endif

#endif // LIB_LIGHTING_AMBIENT_LIGHT_GLSL
