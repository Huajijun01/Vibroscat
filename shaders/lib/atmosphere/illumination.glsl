#ifndef LIB_ATMOSPHERE_ILLUMINATION_GLSL
#define LIB_ATMOSPHERE_ILLUMINATION_GLSL

#include "/lib/contract/uniforms.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/atmosphere/transmittance.glsl"

// -- Solar irradiance (W/m2/nm at TOA) --
const vec4 ATM_SOLAR = vec4(2.01085377, 1.92558253, 1.85678685, 1.56775546);

// -- Moonlight irradiance (W/m2/nm) --
const vec4 ATM_MOON_IRR = vec4(3.0, 2.0, 1.0, 1.0) * 0.002;

// Shared linear radiance calibration for sky, direct light and ambient.
// It precedes the separate display exposure and tonemap.
const float ATM_EXPOSURE = 0.05;

// Direct irradiance at a planet-centered radius in km. Horizon visibility
// and any artistic sun/moon handover remain the caller's policy.
vec3 AtmosphereDirectIrradianceAt(float radius_km, float radius_squared_km, float light_mu,
    vec4 irradiance
) {
    vec4 transmittance = SampleTransmittance(utex_tslut, radius_km, radius_squared_km, light_mu);
    return SpectralToLinearSRGBWhiteBalanced(transmittance * irradiance) * ATM_EXPOSURE;
}

// Local solar multiple-scattering source used for volumetric-cloud fill.
// This is distinct from the clear directional sky color used by cirrus.
vec3 AtmosphereAmbientRadianceAt(float radius_km, float sun_mu) {
    AtmosphereMedia medium = AtmosphereMediaAt(radius_km);
    vec4 multiple_scattering = SampleMultiScatter(utex_mslut, radius_km, sun_mu);
    return SpectralToLinearSRGBWhiteBalanced(
        medium.sigma_s * multiple_scattering * ATM_SOLAR) * ATM_EXPOSURE;
}

#endif // LIB_ATMOSPHERE_ILLUMINATION_GLSL
