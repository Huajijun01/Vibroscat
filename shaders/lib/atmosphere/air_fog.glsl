#ifndef LIB_ATMOSPHERE_AIR_FOG_GLSL
#define LIB_ATMOSPHERE_AIR_FOG_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/scattering/phase.glsl"

// km^-1 -> m^-1; the density profile below is authored in km^-1.
const float AIR_FOG_KM_TO_M = 1.0 / 1000.0;

// Haze density for the current sun elevation (10.0 = thin haze, see the
// AIR_FOG_DENSITY_* options). The elevation is folded about the horizon with
// abs(), so the twilight band thickens the haze at sunrise and sunset alike,
// while the day value carries noon, night, and anything past the band.
float AirFogDensity() {
    float sun_elevation = abs(u_world_sun_dir.y);
    float dusk_weight = 1.0 - smoothstep(AIR_FOG_DUSK_FADE_START, AIR_FOG_DUSK_FADE_END, sun_elevation);
    return mix(AIR_FOG_DENSITY_DAY, AIR_FOG_DENSITY_DUSK, dusk_weight);
}

// Per-metre medium scale at the current density, shared by the analytic fog
// composite and the epipolar air column so both see the same haze.
float AirFogMediumScale() {
    return AirFogDensity() * AIR_FOG_KM_TO_M;
}

// Air density is approximated constant at the camera altitude. The existing
// atmosphere model returns km^-1 spectral coefficients; convert to m^-1.
struct AirFogMedium {
    vec4 extinction;      // Rayleigh + aerosol (scattering and absorption) + ozone + wetness
    vec4 scattering_ray;
    vec4 scattering_mie;  // includes the wetness increment: rain haze scatters too
};

AirFogMedium AirFogMediumAtCamera() {
    float scale = AirFogMediumScale();
    // One extinction owns the whole fog, so the epipolar air column weights its
    // march by exactly the transmittance this composite integrates.
    vec4 extinction = GetExtinction(u_cam_altitude) * scale + wetness * 0.01;
    vec4 ray = GetSigmaSRay(u_cam_altitude) * scale;
    vec4 mie = GetSigmaSMie(u_cam_altitude) * scale + wetness * 0.01;
    return AirFogMedium(extinction, ray, mie);
}

// Closed form of integral0^S sigmas*exp(-sigmat*t) dt; no light-direction OD
// (groundLight approximates the active light reaching the scene).
vec4 AirScatteringIntegral(float segment_length, vec4 sigma_s, vec4 sigma_t) {
    return sigma_s * (vec4(1.0) - exp(-sigma_t * segment_length)) / sigma_t;
}

// View-ray length clamped to `far` (sphere approx of the loaded area;
// shared by air_fog.fragment and epipolar_integrate_air.compute).
float AirFogSegmentLength(float depth_dist, float radius) {
    return min(depth_dist, radius);
}

// Per-metre extinction of the composite's own medium, max spectral channel
// (the shadow map is scalar, so one weight suffices; max keeps the IS optical
// depth aligned with the slowest channel). Reading it from the medium instead
// of rebuilding it keeps the epipolar visibility weighted by the same
// transmittance the fog applies: a thinner sigma would stretch the averaging
// span, which the rain wetness increment scales by two orders of magnitude.
float AirExtinction() {
    vec4 ext = AirFogMediumAtCamera().extinction;
    return max(max(ext.r, ext.g), ext.b);
}

struct AirFogResult {
    vec3 transmittance;
    vec3 in_scattering;
};

AirFogResult AirFogRender(vec3 world_dir, float depth_dist, float radius,
                          AirFogMedium medium,
                          vec3 epipolar_light, float shadow_fallback) {
    AirFogResult result;
    result.transmittance = vec3(1.0);
    result.in_scattering = vec3(0.0);

    float segment_length = AirFogSegmentLength(depth_dist, radius);

    vec4 trans_spectral = exp(-medium.extinction * segment_length);

    // Full analytic single scattering: Rayleigh and Mie integrated separately
    // against the shared extinction, each with its own phase.
    vec4 ray_int = AirScatteringIntegral(segment_length, medium.scattering_ray, medium.extinction);
    vec4 mie_int = AirScatteringIntegral(segment_length, medium.scattering_mie, medium.extinction);
    vec3 ray_rgb = SpectralFractionToLinearSRGB(ray_int) * AIR_FOG_INTENSITY;
    vec3 mie_rgb = SpectralFractionToLinearSRGB(mie_int) * AIR_FOG_INTENSITY;
    vec3 sca_rgb = ray_rgb + mie_rgb;
    vec3 trans_rgb = TransmittanceToLinearSRGB(trans_spectral, vec4(1.0));

    float cos_theta = dot(world_dir, u_world_light_dir);

    // Direct sun scattering shadowed by the epipolar air term (a
    // transmittance-weighted average visibility: light shafts without
    // full-res marching).
#ifdef EPIPOLAR_VOLUMETRICS
    vec3 sun_visibility = epipolar_light;
#else
    vec3 sun_visibility = vec3(shadow_fallback);
#endif
    result.in_scattering += (ray_rgb * PhaseRayleigh(cos_theta)
                          + mie_rgb * PhaseHenyeyGreensteinTripleLobe(cos_theta, ATM_MIE_PHASE))
        * ground_light.rgb * sun_visibility;

    // Multiple scattering
    result.in_scattering += sca_rgb * PHASE_ISOTROPIC
        * EvalSkyLight(world_dir)
        * AIR_FOG_SKY_STRENGTH;

    result.transmittance = trans_rgb;
    return result;
}

#endif // LIB_ATMOSPHERE_AIR_FOG_GLSL
