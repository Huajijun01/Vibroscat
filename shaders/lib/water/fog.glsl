#ifndef LIB_WATER_FOG_GLSL
#define LIB_WATER_FOG_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/scattering/phase.glsl"


const vec3 FAST_WATERFOG_SCATTERING = vec3(0.1, 0.4, 0.4) * 0.05;
const vec3 FAST_WATERFOG_EXTINCTION = vec3(0.4, 0.19, 0.15) * 0.6;
// Lighting approximations, not measured optical properties. The uniform,
// unshadowed source needs a neutral gain; do not dim the scattering here.
const float FAST_WATERFOG_PHASE_G = 0.15;

// In-water sunlight path per metre of vertical drop (flat-surface
// refraction, air->water IOR 1.333 inlined - no IOR config needed).
float WaterLightPathPerMetre() {
    // Frame-uniform refraction path (CPU): identical geometry, one sqrt.
    return u_water_light_path;
}

// Uniform source approximation at a representative water-column depth.
// The lightmap proxy matches caustics; 1 m represents near-surface lighting.
// Shared with the underwater reflection fallback.
vec3 FastWaterFogRadiance(vec3 light_color, vec3 ambient_color, float light_view_cosine) {
    float skylight = u_water_skylight;
    // A collimated beam loses both absorption and out-scattering. Diffuse
    // sky light uses an absorption-only approximation for angular redistribution.
    vec3 direct_transmittance = u_water_direct_transmittance;
    vec3 ambient_transmittance = u_water_ambient_transmittance;
    float phase = PhaseCornetteShanks(light_view_cosine, FAST_WATERFOG_PHASE_G);
    vec3 illumination = ambient_color * ambient_transmittance * (PHASE_ISOTROPIC * skylight)
        + light_color * direct_transmittance * (phase * skylight * skylight);
    return FAST_WATERFOG_SCATTERING / FAST_WATERFOG_EXTINCTION
        * illumination * u_water_wetness_gain;
}

// Closed-form Beer-Lambert integration of the uniform source: no shadow
// march or multiple-scattering solve. Zero length preserves the input.
void FastWaterFogRender(inout vec3 color, float segment_length_m, vec3 fog_radiance) {
    vec3 transmittance = exp(-FAST_WATERFOG_EXTINCTION * max(segment_length_m, 0.0));
    color = color * transmittance + fog_radiance * (1.0 - transmittance);
}

// Caustics and fog use the same medium.
vec3 WaterAbsorptionTransmittance(float dist) {
    return exp(-FAST_WATERFOG_EXTINCTION * dist);
}

#endif // LIB_WATER_FOG_GLSL
