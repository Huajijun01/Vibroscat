#ifndef LIB_ATMOSPHERE_AIR_FOG_GLSL
#define LIB_ATMOSPHERE_AIR_FOG_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/scattering/phase.glsl"

// Independent exponential-height model, informed by the density/time/weather
// concepts in iterationT and Photon. See third-party notices and the local
// derivation in docs/epipolar-air-fog.md. No reference-pack code is transferred.
struct AirFogDensityProfile {
    float clear_density;
    float rain_density;
    float eye_height_m;
};

struct AirFogMedium {
    vec4 extinction;
    vec4 scattering_ray;
    vec4 scattering_mie;
};

AirFogDensityProfile AirFogProfile() {
    float sun_height = u_world_sun_dir.y;
    float day_weight = smoothstep(0.0, 0.25, sun_height);
    float twilight_weight = smoothstep(-0.25, 0.0, sun_height);
    float dark_density = mix(AIR_FOG_DENSITY_NIGHT, AIR_FOG_DENSITY_DUSK, twilight_weight);
    float clear_density = mix(dark_density, AIR_FOG_DENSITY_DAY, day_weight);
    // Absolute camera coordinates avoid the wrapped cameraPosition altitude.
    // World space offsets feet-player space by cameraPosition (Iris contract).
    float eye_height_m = float(cameraPositionInt.y) + cameraPositionFract.y
        + gbufferModelViewInverse[3].y;
    return AirFogDensityProfile(clear_density,
        AIR_FOG_DENSITY_RAIN * clamp(rainStrength * u_rain_biome, 0.0, 1.0), eye_height_m);
}

AirFogMedium AirFogReferenceMedium() {
    // Fixed spectral composition at the height reference. A shared density
    // multiplies all coefficients, so the scattering/extinction ratios stay
    // constant along the ray and the scattering integral has a closed form.
    AtmosphereMedia reference = AtmosphereMediaAt(0.2 + AIR_FOG_REFERENCE_HEIGHT_M * 0.001);
    return AirFogMedium(reference.sigma_t * 0.001,
        reference.sigma_s_ray * 0.001, reference.sigma_s_mie * 0.001);
}

// Integral of rho(s) = D exp(-(y0 + direction_y*s - y_ref)/H) + R.
// Factor the lower endpoint so every exp in the quotient has a nonpositive
// argument. For near-horizontal rays use the Taylor limit of (1-exp(-x))/x.
float AirFogColumnDensity(AirFogDensityProfile profile, float direction_y, float length_m) {
    float height_delta = direction_y * length_m;
    float x = abs(height_delta) / AIR_FOG_SCALE_HEIGHT_M;
    float height_integral;
    if (x < 0.01) {
        height_integral = 1.0 - x * 0.5 + x * x / 6.0 - x * x * x / 24.0;
    } else {
        height_integral = (1.0 - exp(-x)) / x;
    }
    float lower_height = profile.eye_height_m + min(height_delta, 0.0);
    float density_at_lower = profile.clear_density
        * exp((AIR_FOG_REFERENCE_HEIGHT_M - lower_height) / AIR_FOG_SCALE_HEIGHT_M);
    return length_m * (density_at_lower * height_integral + profile.rain_density);
}

float AirFogSegmentLength(float depth_distance_m, float radius_m) {
    return min(depth_distance_m, radius_m);
}

struct AirFogResult {
    vec3 transmittance;
    vec3 in_scattering;
};

AirFogResult AirFogRender(vec3 world_dir, float length_m, AirFogDensityProfile profile,
        AirFogMedium medium, vec3 visibility) {
    float column_density = AirFogColumnDensity(profile, world_dir.y, length_m);
    vec4 tau = medium.extinction * column_density;
    vec4 trans_spectral = exp(-tau);
    // Stable 1-exp(-tau) near zero; exact zero density produces no scattering.
    vec4 removed = mix(vec4(1.0) - trans_spectral, tau * (1.0 - tau * 0.5), lessThan(tau, vec4(0.001)));
    vec4 quotient = removed / max(medium.extinction, vec4(1e-8));
    vec3 ray_rgb = SpectralFractionToLinearSRGB(medium.scattering_ray * quotient) * AIR_FOG_INTENSITY;
    vec3 mie_rgb = SpectralFractionToLinearSRGB(medium.scattering_mie * quotient) * AIR_FOG_INTENSITY;
    float cos_theta = dot(world_dir, u_world_light_dir);
    vec3 direct = (ray_rgb * PhaseRayleigh(cos_theta)
        + mie_rgb * PhaseHenyeyGreensteinTripleLobe(cos_theta, ATM_MIE_PHASE)) * ground_light.rgb * visibility;
    vec3 ambient = (ray_rgb + mie_rgb) * PHASE_ISOTROPIC
        * EvalSkyLight(world_dir) * AIR_FOG_SKY_STRENGTH;
    return AirFogResult(TransmittanceToLinearSRGB(trans_spectral, vec4(1.0)), direct + ambient);
}

#endif // LIB_ATMOSPHERE_AIR_FOG_GLSL
