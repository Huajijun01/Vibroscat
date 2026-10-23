#ifndef LIB_ATMOSPHERE_AIR_FOG_GLSL
#define LIB_ATMOSPHERE_AIR_FOG_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/scattering/phase.glsl"

const HenyeyGreensteinTripleLobe AIRFOG_MIE_PHASE = HenyeyGreensteinTripleLobe(
    0.85, 0.15,  // forward peak
    0.5, 0.8,  // forward mid
    0.3, 0.05); // backward

// Exponential-height density with day/night and weather response.
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
    float day_weight = u_airfog_day_weight;
    float twilight_weight = u_airfog_twilight_weight;
    float dark_density = mix(AIR_FOG_DENSITY_NIGHT, AIR_FOG_DENSITY_DUSK, twilight_weight);
    float clear_density = mix(dark_density, AIR_FOG_DENSITY_DAY, day_weight);
    // Absolute camera coordinates avoid the wrapped cameraPosition altitude.
    // World space offsets feet-player space by cameraPosition (Iris contract).
    float eye_height_m = u_eye_height_m;
    return AirFogDensityProfile(clear_density,
        AIR_FOG_DENSITY_RAIN * clamp(rainStrength * u_rain_biome, 0.0, 1.0), eye_height_m);
}

AirFogMedium AirFogReferenceMedium() {
    // Clear air uses RGB coefficients derived from the reference atmosphere.
    // Rain is a separate neutral,
    // conservative droplet medium: it adds only Mie scattering/extinction.
    // Its reference coefficient is fixed, independent of world/camera height.
    AtmosphereMedia reference = AtmosphereMediaAt(ATM_PLANET_R + 0.2 + AIR_FOG_REFERENCE_HEIGHT_M * 0.001);
    // The compositor transports RGB radiance by channel. Convert reference
    // COEFFICIENTS once, before Beer-Lambert; fitting exp(-tau) with a signed
    // radiance matrix is not a multiplicative RGB transmission operator.
    vec3 white = SpectralToLinearSRGB(vec4(1.0));
    vec3 ray = max(SpectralToLinearSRGB(reference.sigma_s_ray * 0.001) / white, vec3(0.0));
    vec3 mie = max(SpectralToLinearSRGB(reference.sigma_s_mie * 0.001) / white, vec3(0.0));
    vec4 absorption_spectral = reference.sigma_t - reference.sigma_s_ray - reference.sigma_s_mie;
    vec3 absorption = max(SpectralToLinearSRGB(absorption_spectral * 0.001) / white, vec3(0.0));
    return AirFogMedium(ray + mie + absorption, ray, mie,
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

// Approximate a mixed column with one constant scattering source function.
// Clear/rain columns set its Rayleigh/Mie proportions; rain adds only neutral
// Mie scattering and extinction. Pure clear air, pure rain and horizontal
// columns have constant proportions already. E must reuse this WHOLE-ray
// source, rather than recomputing different proportions inside each bin.
AirFogSource AirFogSourceFunction(AirFogMedium medium, float clear_column, float rain_tau) {
    vec3 tau = medium.extinction * clear_column + vec3(rain_tau);
    vec3 inv_tau = 1.0 / max(tau, vec3(1e-20));
    return AirFogSource(medium.scattering_ray * clear_column * inv_tau,
        (medium.scattering_mie * clear_column + vec3(rain_tau)) * inv_tau);
}

vec3 AirFogRemovedFraction(vec3 tau, vec3 transmittance) {
    // Plain 1-exp(-tau); the stable near-zero mix is parked below and changes no endpoint.
    // return mix(vec3(1.0) - transmittance,
    //     tau * (1.0 - tau * 0.5), lessThan(tau, vec3(0.001)));
    return 1.0 - transmittance;
}

// For a constant source S, integral S*sigma_t(s)*T(s) ds = S*(1-T(L)),
// since dT/ds = -sigma_t(s)*T(s). T uses the full exponential-height column
// plus the height-independent rain column. No numerical integration/cutoff.
AirFogIntegral IntegrateAirFogScattering(AirFogDensityProfile profile, AirFogMedium medium,
        float direction_y, float length_m) {
    float clear_column = AirFogColumnDensity(profile, direction_y, length_m);
    float rain_tau = medium.rain_mie * profile.rain_density * length_m;
    vec3 tau = medium.extinction * clear_column + vec3(rain_tau);
    vec3 transmittance = exp(-tau);
    vec3 removed = AirFogRemovedFraction(tau, transmittance);
    AirFogSource source = AirFogSourceFunction(medium, clear_column, rain_tau);
    return AirFogIntegral(transmittance, source.ray * removed, source.mie * removed);
}

// Convolve the incident sky RADIANCE SH with the normalized phase functions.
// Rayleigh's moments are (1,0,0.1); HG's are (1,g,g^2). Surface irradiance
// uses different moments (pi,2pi/3,pi/4) and is not a volume source.
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
    // Use the existing ground sun/moon color as constant incident light;
    // there is no light-directed transmittance integration in this medium.
    vec3 direct = (ray_rgb * PhaseRayleigh(cos_theta)
        + mie_rgb * PhaseHenyeyGreensteinTripleLobe(cos_theta, AIRFOG_MIE_PHASE)) * ground_light.rgb * visibility;
    AirFogSource sky = AirFogSkySource(world_dir);
    vec3 ambient = (ray_rgb * sky.ray + mie_rgb * sky.mie) * AIR_FOG_SKY_STRENGTH;
    return AirFogResult(integral.transmittance, direct + ambient);
}

#endif // LIB_ATMOSPHERE_AIR_FOG_GLSL
