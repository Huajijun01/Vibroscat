#ifndef LIB_ATMOSPHERE_AIR_FOG_GLSL
#define LIB_ATMOSPHERE_AIR_FOG_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/scattering/phase.glsl"

const HenyeyGreensteinTripleLobe AIRFOG_MIE_PHASE = HenyeyGreensteinTripleLobe(
    0.85, 0.15,  // forward peak
    0.5, 0.8,  // forward mid
    0.3, 0.05); // backward

const float AIR_FOG_MAX_HEIGHT_MULTIPLIER = 2.0;

struct AirFogDensityProfile {
    float clear_density;
    float rain_density;
    float eye_height_m;
};

struct AirFogMedium {
    vec3 extinction;
    vec3 scattering_ray;
    vec3 scattering_mie;
    float rain_mie;
};

AirFogDensityProfile AirFogProfile() {
    float dark_density = mix(AIR_FOG_DENSITY_NIGHT, AIR_FOG_DENSITY_DUSK, u_airfog_twilight_weight);
    float clear_density = mix(dark_density, AIR_FOG_DENSITY_DAY, u_airfog_day_weight);
    // Absolute camera altitude avoids cameraPosition's feet-player offset (Iris contract).
    return AirFogDensityProfile(clear_density,
        AIR_FOG_DENSITY_RAIN * saturate(rainStrength * u_rain_biome), u_eye_height_m);
}

AirFogMedium AirFogReferenceMedium() {
    AtmosphereMedia reference = AtmosphereMediaAt(ATM_PLANET_R + 0.2 + AIR_FOG_REFERENCE_HEIGHT_M * 0.001);
    // Convert coefficients to RGB before Beer-Lambert, never exp(-tau): the radiance matrix is not multiplicative.
    vec3 white = SpectralToLinearSRGB(vec4(1.0));
    // Coefficients sit far below 1, so the saturates only scrub signed-conversion artifacts.
    vec3 ray = saturate(SpectralToLinearSRGB(reference.sigma_s_ray * 0.001) / white);
    vec3 mie = saturate(SpectralToLinearSRGB(reference.sigma_s_mie * 0.001) / white);
    vec4 absorption_spectral = reference.sigma_t - reference.sigma_s_ray - reference.sigma_s_mie;
    vec3 absorption = saturate(SpectralToLinearSRGB(absorption_spectral * 0.001) / white);
    return AirFogMedium(ray + mie + absorption, ray, mie,
        dot(reference.sigma_s_mie, vec4(0.25)) * 0.001);
}

// Profiles meet the reference height with matching value and slope; all exp arguments are nonpositive.
float AirFogHeightColumn(float lower_height_m, float upper_height_m, float length_m) {
    bool above_reference = lower_height_m >= AIR_FOG_REFERENCE_HEIGHT_M;
    float lower_density_span = AIR_FOG_MAX_HEIGHT_MULTIPLIER - 1.0;
    float scale_height_m = above_reference ? AIR_FOG_SCALE_HEIGHT_M
        : lower_density_span * AIR_FOG_SCALE_HEIGHT_M;
    float x = (upper_height_m - lower_height_m) / scale_height_m;
    float height_integral = (1.0 - exp(-x)) / x;
    float mean_density;
    if (above_reference) {
        mean_density = exp((AIR_FOG_REFERENCE_HEIGHT_M - lower_height_m) / scale_height_m)
            * height_integral;
    } else {
        mean_density = AIR_FOG_MAX_HEIGHT_MULTIPLIER - lower_density_span
            * exp((upper_height_m - AIR_FOG_REFERENCE_HEIGHT_M) / scale_height_m) * height_integral;
    }
    return length_m * mean_density;
}

// Crossing rays split at the reference plane so the two halves stay additive.
float AirFogColumnDensity(AirFogDensityProfile profile, float direction_y, float length_m) {
    float height_delta = direction_y * length_m;
    float lower_height_m = profile.eye_height_m + min(height_delta, 0.0);
    float upper_height_m = profile.eye_height_m + max(height_delta, 0.0);
    float column;
    if (lower_height_m < AIR_FOG_REFERENCE_HEIGHT_M && upper_height_m > AIR_FOG_REFERENCE_HEIGHT_M) {
        float lower_length_m = length_m * (AIR_FOG_REFERENCE_HEIGHT_M - lower_height_m)
            / (upper_height_m - lower_height_m);
        column = AirFogHeightColumn(lower_height_m, AIR_FOG_REFERENCE_HEIGHT_M, lower_length_m)
            + AirFogHeightColumn(AIR_FOG_REFERENCE_HEIGHT_M, upper_height_m, length_m - lower_length_m);
    } else {
        column = AirFogHeightColumn(lower_height_m, upper_height_m, length_m);
    }
    return profile.clear_density * column;
}

vec3 AirFogOpticalDepth(AirFogDensityProfile profile, AirFogMedium medium,
        float direction_y, float length_m) {
    return medium.extinction * AirFogColumnDensity(profile, direction_y, length_m)
        + vec3(medium.rain_mie * profile.rain_density * length_m);
}

float AirFogSegmentLength(float depth_distance_m, float radius_m) {
    return min(depth_distance_m, radius_m);
}

struct AirFogResult {
    vec3 transmittance;
    vec3 in_scattering;
};

struct AirFogIntegral {
    vec3 transmittance;
    vec3 scattering_ray;
    vec3 scattering_mie;
};

struct AirFogSource {
    vec3 ray;
    vec3 mie;
};

// The epipolar air-shadow ratio (lib/volume/air_epipolar.glsl) must reuse this whole-ray source.
AirFogSource AirFogSourceFunction(AirFogMedium medium, float clear_column, float rain_tau) {
    vec3 tau = medium.extinction * clear_column + vec3(rain_tau);
    vec3 inv_tau = 1.0 / max(tau, vec3(1e-20));
    return AirFogSource(medium.scattering_ray * clear_column * inv_tau,
        (medium.scattering_mie * clear_column + vec3(rain_tau)) * inv_tau);
}

// Constant source: integral S*sigma_t(s)*T(s) ds = S*(1-T(L)), in closed form.
AirFogIntegral IntegrateAirFogScattering(AirFogDensityProfile profile, AirFogMedium medium,
        float direction_y, float length_m) {
    float clear_column = AirFogColumnDensity(profile, direction_y, length_m);
    float rain_tau = medium.rain_mie * profile.rain_density * length_m;
    vec3 tau = medium.extinction * clear_column + vec3(rain_tau);
    vec3 transmittance = exp(-tau);
    vec3 removed = 1.0 - transmittance;
    AirFogSource source = AirFogSourceFunction(medium, clear_column, rain_tau);
    return AirFogIntegral(transmittance, source.ray * removed, source.mie * removed);
}

// SH phase moments: Rayleigh (1,0,0.1), HG (1,g,g^2); surface irradiance uses different moments.
AirFogSource AirFogSkySource(vec3 world_dir) {
    vec3 basis_l1 = SH_Y1 * world_dir.yzx;
    vec4 basis_l2 = vec4(SH_Y20 * (3.0 * world_dir.y * world_dir.y - 1.0),
        SH_Y21 * world_dir.y * world_dir.z, SH_Y21 * world_dir.x * world_dir.z,
        SH_Y21 * world_dir.x * world_dir.y);
    float basis_l22 = SH_Y22 * (world_dir.x * world_dir.x - world_dir.z * world_dir.z);
    vec3 l0 = vec3(sky_sh_r0.x, sky_sh_g0.x, sky_sh_b0.x) * SH_Y0;
    vec3 l1 = vec3(dot(sky_sh_r0.yzw, basis_l1), dot(sky_sh_g0.yzw, basis_l1),
        dot(sky_sh_b0.yzw, basis_l1));
    vec3 l2 = vec3(dot(sky_sh_r1, basis_l2), dot(sky_sh_g1, basis_l2), dot(sky_sh_b1, basis_l2))
        + vec3(sky_sh_r2.x, sky_sh_g2.x, sky_sh_b2.x) * basis_l22;
    float mie_l1 = AIRFOG_MIE_PHASE.peak_weight * AIRFOG_MIE_PHASE.peak_g
        + AIRFOG_MIE_PHASE.mid_weight * AIRFOG_MIE_PHASE.mid_g - AIRFOG_MIE_PHASE.back_weight * AIRFOG_MIE_PHASE.back_g;
    float mie_l2 = AIRFOG_MIE_PHASE.peak_weight * AIRFOG_MIE_PHASE.peak_g * AIRFOG_MIE_PHASE.peak_g
        + AIRFOG_MIE_PHASE.mid_weight * AIRFOG_MIE_PHASE.mid_g * AIRFOG_MIE_PHASE.mid_g
        + AIRFOG_MIE_PHASE.back_weight * AIRFOG_MIE_PHASE.back_g * AIRFOG_MIE_PHASE.back_g;
    return AirFogSource(max(l0 + 0.1 * l2, vec3(0.0)), max(l0 + mie_l1 * l1 + mie_l2 * l2, vec3(0.0)));
}

AirFogResult AirFogRender(vec3 world_dir, float length_m, AirFogDensityProfile profile,
        AirFogMedium medium, vec3 visibility) {
    AirFogIntegral integral = IntegrateAirFogScattering(profile, medium, world_dir.y, length_m);
    vec3 ray_rgb = integral.scattering_ray * AIR_FOG_INTENSITY;
    vec3 mie_rgb = integral.scattering_mie * AIR_FOG_INTENSITY;
    float cos_theta = dot(world_dir, u_world_light_dir);
    vec3 direct = (ray_rgb * PhaseRayleigh(cos_theta)
        + mie_rgb * PhaseHenyeyGreensteinTripleLobe(cos_theta, AIRFOG_MIE_PHASE)) * ground_light.rgb * visibility;
    AirFogSource sky = AirFogSkySource(world_dir);
    vec3 ambient = (ray_rgb * sky.ray + mie_rgb * sky.mie) * AIR_FOG_SKY_STRENGTH;
    return AirFogResult(integral.transmittance, direct + ambient);
}

#endif // LIB_ATMOSPHERE_AIR_FOG_GLSL
