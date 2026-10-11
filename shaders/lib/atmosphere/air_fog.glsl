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

// J = integral exp(-beta_t*A_clear(s) - c*s) ds. Unlike the dry integral,
// the mixed exponential/constant medium has a non-elementary source split.
// Evaluate this smooth positive integral with 16-point Gauss-Legendre.
// Clip only its negligible tail (all bands below exp(-16)); T itself stays
// the exact closed-form endpoint. No shadow-map samples are taken here.
vec4 AirFogTransmittanceIntegral(AirFogDensityProfile profile, AirFogMedium medium,
        float direction_y, float length_m) {
    float rain_extinction = medium.rain_mie * profile.rain_density;
    float beta_min = min(min(medium.extinction.x, medium.extinction.y),
        min(medium.extinction.z, medium.extinction.w));
    float upper = min(length_m, 16.0 / rain_extinction);
    float lower = 0.0;
    if (beta_min * AirFogColumnDensity(profile, direction_y, upper)
            + rain_extinction * upper > 16.0) {
        for (int i = 0; i < 12; ++i) {
            float midpoint = (lower + upper) * 0.5;
            float tau = beta_min * AirFogColumnDensity(profile, direction_y, midpoint)
                + rain_extinction * midpoint;
            if (tau < 16.0) lower = midpoint;
            else upper = midpoint;
        }
    }
    const vec2 nodes[8] = vec2[8](
        vec2(0.0950125098, 0.1894506105), vec2(0.2816035508, 0.1826034150),
        vec2(0.4580167777, 0.1691565194), vec2(0.6178762444, 0.1495959888),
        vec2(0.7554044084, 0.1246289713), vec2(0.8656312024, 0.0951585117),
        vec2(0.9445750231, 0.0622535239), vec2(0.9894009349, 0.0271524594));
    vec4 integral = vec4(0.0);
    float half_length = upper * 0.5;
    for (int i = 0; i < 8; ++i) {
        float offset = half_length * nodes[i].x;
        integral += nodes[i].y * (
            exp(-AirFogOpticalDepth(profile, medium, direction_y, half_length - offset))
            + exp(-AirFogOpticalDepth(profile, medium, direction_y, half_length + offset)));
    }
    return integral * half_length;
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

// Shared source integral for the composite and each equal-distance shadow bin.
// Multiplying a bin by its camera-to-bin transmittance makes the integrals
// additive, including the changing clear/rain source proportions.
AirFogIntegral IntegrateAirFogScattering(AirFogDensityProfile profile, AirFogMedium medium,
        float direction_y, float length_m) {
    float clear_column = AirFogColumnDensity(profile, direction_y, length_m);
    float rain_tau = medium.rain_mie * profile.rain_density * length_m;
    vec4 tau = medium.extinction * clear_column + vec4(rain_tau);
    vec4 trans_spectral = exp(-tau);
    // Stable 1-exp(-tau) near zero; exact zero density produces no scattering.
    vec4 removed = mix(vec4(1.0) - trans_spectral, tau * (1.0 - tau * 0.5), lessThan(tau, vec4(0.001)));
    vec4 rain_removed = vec4(0.0);
    if (rain_tau > 0.0) {
        if (profile.clear_density == 0.0
                || abs(direction_y * length_m) / AIR_FOG_SCALE_HEIGHT_M < 0.001) {
            // Pure rain or horizontal rays: exactly homogeneous source split.
            rain_removed = removed * vec4(rain_tau) / max(tau, vec4(1e-20));
        } else {
            rain_removed = clamp(medium.rain_mie * profile.rain_density
                * AirFogTransmittanceIntegral(profile, medium, direction_y, length_m), vec4(0.0), removed);
        }
    }
    // -dT/ds = (beta_t*rho_clear + c)*T conserves removed energy.
    vec4 quotient = (removed - rain_removed) / max(medium.extinction, vec4(1e-8));
    return AirFogIntegral(trans_spectral, medium.scattering_ray * quotient,
        medium.scattering_mie * quotient + rain_removed);
}

AirFogResult AirFogRender(vec3 world_dir, float length_m, AirFogDensityProfile profile,
        AirFogMedium medium, vec3 visibility) {
    AirFogIntegral integral = IntegrateAirFogScattering(profile, medium, world_dir.y, length_m);
    vec3 ray_rgb = SpectralFractionToLinearSRGB(integral.scattering_ray) * AIR_FOG_INTENSITY;
    vec3 mie_rgb = SpectralFractionToLinearSRGB(integral.scattering_mie) * AIR_FOG_INTENSITY;
    float cos_theta = dot(world_dir, u_world_light_dir);
    vec3 direct = (ray_rgb * PhaseRayleigh(cos_theta)
        + mie_rgb * PhaseHenyeyGreensteinTripleLobe(cos_theta, ATM_MIE_PHASE)) * ground_light.rgb * visibility;
    vec3 ambient = (ray_rgb + mie_rgb) * PHASE_ISOTROPIC
        * EvalSkyLight(world_dir) * AIR_FOG_SKY_STRENGTH;
    return AirFogResult(TransmittanceToLinearSRGB(integral.transmittance, vec4(1.0)), direct + ambient);
}

#endif // LIB_ATMOSPHERE_AIR_FOG_GLSL
