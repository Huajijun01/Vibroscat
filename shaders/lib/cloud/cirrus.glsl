#ifndef LIB_CLOUD_CIRRUS_GLSL
#define LIB_CLOUD_CIRRUS_GLSL

// Cirrus layer.
// Shape: offline-baked 64x64 value noise (source texture removed from
// scrolled; sampled once at the shell crossing.
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
// View extinction for the squared density field (per km).
// A thick core reaches OD ~ 1.0 over the 1 km zenith slab
// (T ~ 0.4) while thin edges stay under 0.1, so the thin-to-thick gradient
// stays visible.
// Scattering equals extinction, so the single-scattering albedo is exactly 1:
// ice barely absorbs. Everything a thicker deck returns past the first bounce
// is the multiple-scattering series, not a gain applied to this pair.
const float CIRRUS_SCATTERING = 3.0;
const float CIRRUS_EXTINCTION = CIRRUS_SCATTERING;
// This layer's multiple-scattering reference length, in km: the length over
// which one scattering order spreads inside this deck, and the scale the
// series' knee is measured against. At 3 km^-1 the knee sits at a density of
// 1 / (3 * 1.2) = 0.28, near the lower end of the density range: a thin edge
// still returns little (about 0.18x single scattering at a density of 0.05)
// while the body of the deck runs past single scattering, about 3.3x at a
// density whose vertical optical depth is near 1.5.
// It is this layer's own constant, not the volumetric layer's. A length
// calibrated for 100 km^-1 would leave this shell permanently below its knee
// and the series would contribute a tenth of a percent rather than a
// comparable share.
const float CIRRUS_MS_REFERENCE_LENGTH_KM = 1.2;
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
const float NOISE2D_SIZE = 64.0;
// Effective slab thickness: the shell is sampled once, so slanted view paths
// integrate extinction over H / |cos| instead of a fixed step.
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

// Reference cirrus shape algorithm. TIME -> frameTimeCounter; ps =
// planet-centered position (km), horizontal zx plane only. Noise lattice
// baked into the periodic 64x64 R8 texture; uv = fract((pos + 0.5)/64),
// linear + repeat. pos kept in [0, 64) via mod (octave transforms must not
// destroy float precision on planet-centered input).
float CirrusCoverageDensity(vec3 ps) {
    // vec2 pos = ps.zx * 0.15;

    // float noise = 0.0;
    // float p = 0.5;

    // float wind = 0.02 * frameTimeCounter;

    // pos = mod(pos * vec2(1.0, 2.2) + vec2(0.08, 0.8) * wind, NOISE2D_SIZE);

    // for (int i = 1; i < 6; ++i) {
    //     noise += add;
    //     p *= 0.5;
    //     pos = mod(pos * vec2(3.0, 2.0) + vec2(wind * float(i), 0.0) + vec2(0.0, add), NOISE2D_SIZE);
    // }

    // return exp(smoothstep(0.0, 1.0, noise) * -5.0);

    float small = 1.0 - texture(utex_cloud_distribution_tex, ps.xz * 0.06).x;
    float large = Saturate((texture(utex_cloud_distribution_tex, ps.xz * 0.005).x - 0.15) / 0.85);
    // Square the contrast-stretched ratio: the raw field saturates into
    // plateaus (0 or 0.5-0.9), and the square widens it into a ramp so the
    // optical depth reads as a gradual thin-to-thick transition.
    float density = Saturate((large - small) / (1.0 - small * 0.8));
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
vec3 CirrusPhaseScattering(vec3 sun_color, float sun_visible, vec3 sun_phase, vec3 moon_color, float moon_visible,
    vec3 moon_phase, vec3 ambient_irradiance, float sample_scattering, float sample_extinction,
    float sample_transmittance
) {
    float reference_optical_depth = sample_extinction * CIRRUS_MS_REFERENCE_LENGTH_KM;
    float isotropic_orders = CloudIsotropicOrders(
        reference_optical_depth, CIRRUS_MS_SAT_ALBEDO, CIRRUS_MS_ISOTROPIC);
    vec3 in_scattering = sun_color * sun_visible * (sun_phase + isotropic_orders)
        + moon_color * moon_visible * (moon_phase + isotropic_orders);
    in_scattering += ambient_irradiance;
    in_scattering *= sample_scattering;
    // a - a*T = a*(1 - T): the quotient collapses to one scalar division.
    return in_scattering * ((1.0 - sample_transmittance) / max(sample_extinction, 1.0e-5));
}

vec3 RenderCirrusClouds(vec3 view_dir, vec3 sky_color,
    out vec3 cirrus_surface_pos, out vec3 cirrus_transmittance
) {
    vec3 ray_start = AtmosphereCameraPosition();
    float ci_height = ATM_PLANET_R + CIRRUS_HEIGHT_KM;
    float ci_height_diff = ci_height - length(ray_start);

    float t_near;
    float t_far;
    if (!RayIntersectSphere(ray_start, view_dir, ci_height, t_near, t_far)) {
        cirrus_surface_pos = vec3(0.0);
        cirrus_transmittance = vec3(1.0);
        return sky_color;
    }
    float ci_offset = t_near > 0.0 ? t_near : t_far;
    if (sign(ci_height_diff) != sign(view_dir.y) || ci_offset <= 0.0) {
        cirrus_surface_pos = vec3(0.0);
        cirrus_transmittance = vec3(1.0);
        return sky_color;
    }

    vec3 sample_position = ray_start + view_dir * ci_offset;
    cirrus_surface_pos = sample_position;
    cirrus_transmittance = vec3(1.0);
    float height = length(sample_position);
    vec3 shell_normal_world = sample_position / height;
    float sample_density = CirrusCoverageDensity(sample_position);

    vec3 ci_in_scattering = vec3(0.0);
    vec3 ci_transmittance = vec3(1.0);

    if (sample_density > 1.0e-5) {
        vec3 sun_dir = u_world_sun_dir;

        // Sun/moon sampled separately from the transmittance LUT (same
        // expression as volumetric.glsl). The moon fetch MUST stay after the
        // sun branch: adjacent straight-line fetches of this sampler with
        // mirrored mu get merged by the driver (the LUT uv shares
        // sqrt(max(r^2 (mu^2 - 1) + R^2, 0))), and the moon then returns the
        // sun's transmittance — exactly zero at night.
        float sun_mu = dot(sample_position, sun_dir) / height;
        float moon_mu = -sun_mu;

        // A light below the local horizon is occluded by the planet.
        float sun_visible = smoothstep(-0.05, 0.0, sun_mu);
        float moon_visible = smoothstep(-0.05, 0.0, moon_mu);

        // moon_dir is the exact IEEE negation of sun_dir, so the moon
        // cosine is the exact negation of the sun's; clamp commutes with it.
        float sun_cos = clamp(dot(view_dir, sun_dir), -1.0, 1.0);
        vec3 sun_phase = vec3(PhaseHenyeyGreensteinTripleLobe(sun_cos, CIRRUS_MIE_PHASE));
        vec3 moon_phase = vec3(PhaseHenyeyGreensteinTripleLobe(-sun_cos, CIRRUS_MIE_PHASE));
        float direct_gain = mix(CIRRUS_DIRECT_EDGE_GAIN, CIRRUS_DIRECT_BODY_GAIN,
            smoothstep(0.0, CIRRUS_BODY_DENSITY, sample_density));

        // Each light's LUT colour is only consumed behind its own visibility
        // factor (CirrusPhaseScattering multiplies it in), so a light fully
        // below the horizon skips the transmittance fetch and both colour
        // matrices; the factor it would multiply into is exactly zero.
        // The moon fetch MUST stay after the sun branch (driver bug above).
        vec3 sun_color = vec3(0.0);
        if (sun_visible > 0.0) {
            sun_color = Rec2020ToSRGB(SpectralToLinearRec2020(
                SampleTransmittance(utex_tslut, height, height * height, sun_mu) * ATM_SOLAR)) * ATM_EXPOSURE;
            sun_color *= direct_gain;
        }

        vec3 moon_color = vec3(0.0);
        if (moon_visible > 0.0) {
            moon_color = Rec2020ToSRGB(SpectralToLinearRec2020(
                SampleTransmittance(utex_tslut, height, height * height, moon_mu) * ATM_MOON_IRR)) * ATM_EXPOSURE;
            moon_color *= direct_gain;
        }

        // Sky ambient from the multiscatter LUT.
        vec3 ambient_irradiance = GetAmbientColor(sample_position, u_world_sun_dir)
            * (CLOUD_SKY_LIGHT_STRENGTH * CIRRUS_SKY_LIGHT_WEIGHT);
        // ambient_irradiance *= 0.8 + 0.2 * ci_transmittance;

        float sample_scattering = CIRRUS_SCATTERING * sample_density;
        float sample_extinction = CIRRUS_EXTINCTION * sample_density;
        // Slanted path through the effective slab: optical depth grows where
        // the view grazes the deck, so the horizon reads thick while the
        // zenith keeps the overhead thickness (capped by the true distance).
        float view_path_km = min(ci_offset,
            CIRRUS_LAYER_THICKNESS_KM / max(abs(dot(view_dir, shell_normal_world)), CIRRUS_GRAZING_MIN_MU));
        float sample_optical_depth = sample_extinction * view_path_km;
        float sample_transmittance = exp(-sample_optical_depth);

        ci_in_scattering = CirrusPhaseScattering(sun_color, sun_visible, sun_phase, moon_color, moon_visible, moon_phase,
                                           ambient_irradiance, sample_scattering, sample_extinction, sample_transmittance);
        ci_transmittance = vec3(sample_transmittance);
        cirrus_transmittance = ci_transmittance;
    }

    // if (max(ci_in_scattering, ci_transmittance).r < 1.0e-5) {
    //     return sky_color;
    // }

    // Single-layer composite. The former multi-layer scaffolding multiplied
    // the fresh terms by the initial zero/one transmittances; IEEE forbids
    // folding 0 * x, so write the degenerate products out. ci_transmittance
    // is exp(-od) and finite positive, so both removed products were
    // bit-identical to their operands.
    return sky_color * ci_transmittance + ci_in_scattering;
}

#endif // LIB_CLOUD_CIRRUS_GLSL
