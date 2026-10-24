#ifndef LIB_CLOUD_CIRRUS_GLSL
#define LIB_CLOUD_CIRRUS_GLSL

// Cirrus layer.
// Shape: shared 1024x1024 R8 worley-fBm distribution atlas, sampled at
// ps.xz * 0.005 and ps.xz * 0.06, once at the shell crossing.
// Light: single shell sample with density-graded direct light, triple-lobe HG
// silver lining, shared isotropic multiple scattering and sky ambient.
// View extinction retains grazing-path thickening and above/below ordering.

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/sky_radiance.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/atmosphere/transmittance.glsl"
#include "/lib/cloud/multiple_scattering.glsl"
#include "/lib/scattering/phase.glsl"


const float CIRRUS_HEIGHT_KM = 7.0;
const float CIRRUS_RADIUS_KM = ATM_PLANET_R + CIRRUS_HEIGHT_KM;
// View extinction for the squared density field (per km).
// A thick core reaches OD ~ 1.0 over the 1 km zenith slab
// (T ~ 0.4) while thin edges stay under 0.1, so the thin-to-thick gradient
// stays visible.
// Scattering equals extinction, so the single-scattering albedo is exactly 1:
// ice barely absorbs. Everything a thicker deck returns past the first bounce
// is the multiple-scattering series, not a gain applied to this pair.
const float CIRRUS_SCATTERING = 2.0;
// This layer's multiple-scattering reference length, in km: the length over
// which one scattering order spreads inside this deck, and the scale the
// series' knee is measured against. At 2 km^-1 the knee sits at a density of
// 1 / (2 * 2.2) = 0.23, near the lower end of the density range: a thin edge
// still returns little (about 0.18x single scattering at a density of 0.05)
// while the body of the deck runs past single scattering, about 3.3x at a
// density whose vertical optical depth is near 1.5.
// It is this layer's own constant, not the volumetric layer's. A length
// calibrated for 100 km^-1 would leave this shell permanently below its knee
// and the series would contribute a tenth of a percent rather than a
// comparable share.
const float CIRRUS_MS_REFERENCE_LENGTH_KM = 2.2;
// This layer's saturation albedo for the series, which the source writes as the
// leading omega of fms. Ice crystals barely absorb in the visible, so this sits
// just under 1: the series converges to omega / (1 - omega) and the model
// diverges at exactly 1, which would leave the guard doing the work instead of
// the medium. The volumetric layer runs a different medium with a different
// value and states it next to its own extinction.
const float CIRRUS_MS_SAT_ALBEDO = 0.999;
// Triple-lobe phase: the narrow + mid forward lobes keep the silver lining,
// the backward lobe lifts the anti-lit side (cloud-bow analog) so decks
// facing away from the light keep a visible response instead of collapsing
// toward a tenth of the isotropic phase. Weights sum to 1, so the blend
// stays a normalized phase.
const HenyeyGreensteinTripleLobe CIRRUS_MIE_PHASE = HenyeyGreensteinTripleLobe(
    0.92, 0.1, // forward silver-lining peak
    0.3, 0.7,  // forward mid
    0.2, 0.2); // backward
// Effective slab thickness: the shell is sampled once, so slanted view paths
// integrate extinction over H / |cos|.
const float CIRRUS_LAYER_THICKNESS_KM = 1.0;
// Grazing clamp for the slanted paths (sin of ~3.4 degrees): caps the path
// where a ray skims the deck.
const float CIRRUS_GRAZING_MIN_MU = 0.06;
// Artistic source grading, independent of light-path optical depth: thin edges
// keep their silver lining while dense bodies retain highlight headroom.
const float CIRRUS_DIRECT_EDGE_GAIN = 0.9;
const float CIRRUS_DIRECT_BODY_GAIN = 0.4;
const float CIRRUS_BODY_DENSITY = 0.8;
const float CIRRUS_SKY_LIGHT_WEIGHT = 0.4;

// Cirrus coverage density. ps = planet-centered position (km), horizontal
// zx plane only. Two atlas reads at ps.xz * 0.005 (coarse field) and
// ps.xz * 0.06 (detail field), contrast-shaped below.
float CirrusCoverageDensity(vec3 ps) {
    // A zero coarse field cannot survive subtracting the nonnegative detail.
    // This raw atlas has one bilinear level; explicit LOD is valid in both stages.
    float large = saturate((textureLod(utex_cloud_distribution_tex, ps.xz * 0.005, 0.0).x - 0.15) / 0.85);
    if (large == 0.0) return 0.0;
    float small = 1.0 - textureLod(utex_cloud_distribution_tex, ps.xz * 0.06, 0.0).x;
    // Square the contrast-stretched ratio: the raw field saturates into
    // plateaus (0 or 0.5-0.9), and the square widens it into a ramp so the
    // optical depth reads as a gradual thin-to-thick transition.
    float density = saturate((large - small) / (1.0 - small * 0.8));
    return density * density;
}

// Slab source at one shell crossing, which the caller turns into radiance with
// the analytic (1 - T) / sigma_t integral.
//
// Single scattering keeps the triple-lobe HG phase. The orders past the first
// are the isotropic geometric series owned by
// /lib/cloud/multiple_scattering.glsl and they ride the very same light
// colors, which already carry the density-based artistic source gain. Their
// weight therefore follows the sample's own extinction: a denser or thicker
// deck returns more of them, and a thin edge returns almost none.
//
// The ambient path is untouched by that replacement: sky light is not the
// beam whose missing orders the series stands in for.
vec3 CirrusPhaseScattering(vec3 sample_position, vec3 view_dir, float sample_density,
    float sample_extinction, float sample_transmittance
) {
    float sun_mu = dot(sample_position, u_world_sun_dir) / CIRRUS_RADIUS_KM;
    float sun_visible = smoothstep(-0.05, 0.0, sun_mu);
    float moon_visible = smoothstep(-0.05, 0.0, -sun_mu);
    float sun_cos = clamp(dot(view_dir, u_world_sun_dir), -1.0, 1.0);
    float direct_gain = mix(CIRRUS_DIRECT_EDGE_GAIN, CIRRUS_DIRECT_BODY_GAIN,
        smoothstep(0.0, CIRRUS_BODY_DENSITY, sample_density));
    float reference_optical_depth = sample_extinction * CIRRUS_MS_REFERENCE_LENGTH_KM;
    float isotropic_orders = IsotropicOrders(
        reference_optical_depth, CIRRUS_MS_SAT_ALBEDO, CIRRUS_MS_ISOTROPIC);
    vec3 in_scattering = vec3(0.0);
    if (sun_visible > 0.0) {
        vec3 sun_color = SpectralToLinearSRGBWhiteBalanced(
            SampleTransmittance(utex_tslut, CIRRUS_RADIUS_KM, CIRRUS_RADIUS_KM * CIRRUS_RADIUS_KM, sun_mu)
            * ATM_SOLAR) * ATM_EXPOSURE;
        float sun_phase = PhaseHenyeyGreensteinTripleLobe(sun_cos, CIRRUS_MIE_PHASE);
        in_scattering += sun_color * (direct_gain * sun_visible * (sun_phase + isotropic_orders));
    }
    // Keep the moon lookup after the sun branch: mirrored straight-line
    // lookups of this LUT have been merged incorrectly by the driver.
    if (moon_visible > 0.0) {
        vec3 moon_color = SpectralToLinearSRGBWhiteBalanced(
            SampleTransmittance(utex_tslut, CIRRUS_RADIUS_KM, CIRRUS_RADIUS_KM * CIRRUS_RADIUS_KM, -sun_mu)
            * ATM_MOON_IRR) * ATM_EXPOSURE;
        float moon_phase = PhaseHenyeyGreensteinTripleLobe(-sun_cos, CIRRUS_MIE_PHASE);
        in_scattering += moon_color * (direct_gain * moon_visible * (moon_phase + isotropic_orders));
    }
    if (CLOUD_SKY_LIGHT_STRENGTH > 0.0) {
        in_scattering += GetAmbientColorAt(CIRRUS_RADIUS_KM, sun_mu)
            * (CLOUD_SKY_LIGHT_STRENGTH * CIRRUS_SKY_LIGHT_WEIGHT);
    }
    // sigma_s == sigma_t, so sigma_s * (1 - T) / sigma_t reduces to (1 - T);
    // density > 1e-5 keeps the extinction away from zero.
    return in_scattering * (1.0 - sample_transmittance);
}

vec3 RenderCirrusClouds(vec3 view_dir, vec3 sky_color,
    out vec3 cirrus_surface_pos, out float cirrus_entry_km, out vec3 cirrus_transmittance
) {
    cirrus_surface_pos = vec3(0.0);
    cirrus_entry_km = 1.0e9;
    cirrus_transmittance = vec3(1.0);
    vec3 ray_start = AtmosphereCameraPosition();
    if (sign(u_cirrus_height_diff) != sign(view_dir.y)) return sky_color;

    float t_near;
    float t_far;
    if (!RayIntersectSphere(ray_start, view_dir, CIRRUS_RADIUS_KM, t_near, t_far)) return sky_color;
    float ci_offset = t_near > 0.0 ? t_near : t_far;
    if (ci_offset <= 0.0) return sky_color;

    vec3 sample_position = ray_start + view_dir * ci_offset;
    float sample_density = CirrusCoverageDensity(sample_position);
    if (sample_density <= 1.0e-5) return sky_color;

    float sample_extinction = CIRRUS_SCATTERING * sample_density;
    // For a normalized sphere ray, |dot(view, normal)| = (t_far-t_near)/(2R).
    float view_mu = (t_far - t_near) * (0.5 / CIRRUS_RADIUS_KM);
    float view_path_km = min(ci_offset,
        CIRRUS_LAYER_THICKNESS_KM / max(view_mu, CIRRUS_GRAZING_MIN_MU));
    float sample_transmittance = exp(-sample_extinction * view_path_km);
    if (sample_transmittance == 1.0) return sky_color;

    cirrus_surface_pos = sample_position;
    cirrus_entry_km = ci_offset;
    cirrus_transmittance = vec3(sample_transmittance);
    vec3 ci_in_scattering = CirrusPhaseScattering(sample_position, view_dir,
        sample_density, sample_extinction, sample_transmittance);
    return sky_color * sample_transmittance + ci_in_scattering;
}

#endif // LIB_CLOUD_CIRRUS_GLSL
