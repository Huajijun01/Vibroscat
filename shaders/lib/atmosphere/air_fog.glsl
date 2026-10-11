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
    float rain_mie;
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
    // Clear air keeps the atmosphere spectrum. Rain is a separate neutral,
    // conservative droplet medium: it adds only Mie scattering/extinction.
    // Its reference coefficient is fixed, independent of world/camera height.
    AtmosphereMedia reference = AtmosphereMediaAt(0.2 + AIR_FOG_REFERENCE_HEIGHT_M * 0.001);
    return AirFogMedium(reference.sigma_t * 0.001,
        reference.sigma_s_ray * 0.001, reference.sigma_s_mie * 0.001,
        dot(reference.sigma_s_mie, vec4(0.25)) * 0.001);
}

// Clear-air column: integral of D exp(-(y0 + direction_y*s - y_ref)/H).
// Rain's constant column R*L is added only to its own Mie coefficient.
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
    return length_m * density_at_lower * height_integral;
}

vec4 AirFogOpticalDepth(AirFogDensityProfile profile, AirFogMedium medium,
        float direction_y, float length_m) {
    return medium.extinction * AirFogColumnDensity(profile, direction_y, length_m)
        + vec4(medium.rain_mie * profile.rain_density * length_m);
}

float AirFogSegmentLength(float depth_distance_m, float radius_m) {
    return min(depth_distance_m, radius_m);
}

struct AirFogResult {
    vec3 transmittance;
    vec3 in_scattering;
};

struct AirFogIntegral {
    vec4 transmittance;
    vec4 scattering_ray;
    vec4 scattering_mie;
};

struct AirFogSource {
    vec4 ray;
    vec4 mie;
};

// Approximate a mixed column with one constant scattering source function.
// Clear/rain columns set its Rayleigh/Mie proportions; rain adds only neutral
// Mie scattering and extinction. Pure clear air, pure rain and horizontal
// columns have constant proportions already. E must reuse this WHOLE-ray
// source, rather than recomputing different proportions inside each bin.
AirFogSource AirFogSourceFunction(AirFogMedium medium, float clear_column, float rain_tau) {
    vec4 tau = medium.extinction * clear_column + vec4(rain_tau);
    vec4 inv_tau = 1.0 / max(tau, vec4(1e-20));
    return AirFogSource(medium.scattering_ray * clear_column * inv_tau,
        (medium.scattering_mie * clear_column + vec4(rain_tau)) * inv_tau);
}

vec4 AirFogRemovedFraction(vec4 tau, vec4 transmittance) {
    // Stable 1-exp(-tau) near zero. This changes no integration endpoint.
    return mix(vec4(1.0) - transmittance,
        tau * (1.0 - tau * 0.5), lessThan(tau, vec4(0.001)));
}

// For a constant source S, integral S*sigma_t(s)*T(s) ds = S*(1-T(L)),
// since dT/ds = -sigma_t(s)*T(s). T uses the full exponential-height column
// plus the height-independent rain column. No numerical integration/cutoff.
AirFogIntegral IntegrateAirFogScattering(AirFogDensityProfile profile, AirFogMedium medium,
        float direction_y, float length_m) {
    float clear_column = AirFogColumnDensity(profile, direction_y, length_m);
    float rain_tau = medium.rain_mie * profile.rain_density * length_m;
    vec4 tau = medium.extinction * clear_column + vec4(rain_tau);
    vec4 trans_spectral = exp(-tau);
    vec4 removed = AirFogRemovedFraction(tau, trans_spectral);
    AirFogSource source = AirFogSourceFunction(medium, clear_column, rain_tau);
    return AirFogIntegral(trans_spectral, source.ray * removed, source.mie * removed);
}

AirFogResult AirFogRender(vec3 world_dir, float length_m, AirFogDensityProfile profile,
        AirFogMedium medium, vec3 visibility) {
    AirFogIntegral integral = IntegrateAirFogScattering(profile, medium, world_dir.y, length_m);
    vec3 ray_rgb = SpectralFractionToLinearSRGB(integral.scattering_ray) * AIR_FOG_INTENSITY;
    vec3 mie_rgb = SpectralFractionToLinearSRGB(integral.scattering_mie) * AIR_FOG_INTENSITY;
    float cos_theta = dot(world_dir, u_world_light_dir);
    // Use the existing ground sun/moon color as constant incident light;
    // there is no light-directed transmittance integration in this medium.
    vec3 direct = (ray_rgb * PhaseRayleigh(cos_theta)
        + mie_rgb * PhaseHenyeyGreensteinTripleLobe(cos_theta, ATM_MIE_PHASE)) * ground_light.rgb * visibility;
    vec3 ambient = (ray_rgb + mie_rgb) * PHASE_ISOTROPIC
        * EvalSkyLight(world_dir) * AIR_FOG_SKY_STRENGTH;
    return AirFogResult(TransmittanceToLinearSRGB(integral.transmittance, vec4(1.0)), direct + ambient);
}

#endif // LIB_ATMOSPHERE_AIR_FOG_GLSL
