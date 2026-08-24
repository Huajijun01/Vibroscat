#ifndef LIB_ATMOSPHERE_AIR_FOG_GLSL
#define LIB_ATMOSPHERE_AIR_FOG_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/core.glsl"
#include "/lib/atmosphere/sky_light.glsl"

const float AIR_FOG_KM_TO_M = AIR_FOG_DENSITY / 1000.0;

// Air density is approximated constant at the camera altitude. The existing
// atmosphere model returns km^-1 spectral coefficients; convert to m^-1.
struct AirFogMedium {
    vec4 extinction;      // Rayleigh + Mie
    vec4 scattering_ray;
    vec4 scattering_mie;
};

AirFogMedium AirFogMediumAtCamera() {
    float scale = AIR_FOG_KM_TO_M;
    vec4 ray = GetSigmaSRay(u_cam_altitude) * scale;
    vec4 mie = GetSigmaSMie(u_cam_altitude) * scale;
    return AirFogMedium(ray + mie, ray, mie);
}

// Closed form of ∫₀^S σs·exp(-σt·t) dt; no light-direction OD
// (groundLight approximates the active light reaching the scene).
vec4 AirScatteringIntegral(float S, vec4 sigma_s, vec4 sigma_t) {
    return sigma_s * (vec4(1.0) - exp(-sigma_t * S)) / sigma_t;
}

// View-ray length clamped to `far` (sphere approx of the loaded area;
// shared by air_fog.fragment and epipolar_integrate_air.compute).
bool AirFogSegment(float depth_dist, float radius, out float S) {
    S = min(depth_dist, radius);
    return true;
}

// Unitless spectral fraction -> linear sRGB, normalized so a neutral
// spectrum maps to white (same convention as TransmittanceToLinearSRGB).
vec3 SpectralFractionToLinearSRGB(vec4 x) {
    vec3 white = SpectralToLinearSRGB(vec4(1.0));
    return SpectralToLinearSRGB(clamp(x, vec4(0.0), vec4(1.0))) / white;
}

// Per-metre extinction, max spectral channel (the shadow map is scalar, so
// one weight suffices; max keeps the IS optical depth aligned with the
// slowest channel).
float AirExtinction() {
    vec4 ext = GetScattering(u_cam_altitude) * AIR_FOG_KM_TO_M;
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

    float S;
    if (!AirFogSegment(depth_dist, radius, S)) {
        return result;
    }

    vec4 trans_spectral = exp(-medium.extinction * S);

    // Full analytic single scattering: Rayleigh and Mie integrated separately
    // against the shared extinction, each with its own phase.
    vec4 ray_int = AirScatteringIntegral(S, medium.scattering_ray, medium.extinction);
    vec4 mie_int = AirScatteringIntegral(S, medium.scattering_mie, medium.extinction);
    vec3 ray_rgb = SpectralFractionToLinearSRGB(ray_int) * AIR_FOG_INTENSITY;
    vec3 mie_rgb = SpectralFractionToLinearSRGB(mie_int) * AIR_FOG_INTENSITY;
    vec3 sca_rgb = ray_rgb + mie_rgb;
    vec3 trans_rgb = TransmittanceToLinearSRGB(trans_spectral, vec4(1.0));

    float cos_theta = dot(world_dir, u_world_light_dir);

    // Direct sun scattering shadowed by the epipolar air term (a
    // transmittance-weighted average visibility: light shafts without
    // full-res marching).
#ifdef EPIPOLAR_WATER
    vec3 sun_visibility = epipolar_light;
#else
    vec3 sun_visibility = vec3(shadow_fallback);
#endif
    result.in_scattering += (ray_rgb * PhaseRayleigh(cos_theta)
                          + mie_rgb * PhaseMieHG(cos_theta, 0.8))
        * ground_light.rgb * sun_visibility;

    // Multiple scattering
    result.in_scattering += sca_rgb * (1.0 / (4.0 * PI))
        * EvalSkyLight(world_dir)
        * AIR_FOG_SKY_STRENGTH;
    
    result.transmittance = trans_rgb;
    return result;
}

#endif
