#ifndef LIB_CLOUD_CIRRUS_GLSL
#define LIB_CLOUD_CIRRUS_GLSL

// Cirrus layer.
// Shape: periodic 64x64 R8 value noise (utex_noise2d_tex), domain-warped and
// scrolled; sampled once at the shell crossing.
// Light: thin-shell single sample; scalar scattering/extinction, triple-lobe
// (forward silver lining + backward) HG phase, the isotropic multiple
// scattering orders owned by /lib/cloud/multiple_scattering.glsl added to the
// sun and moon beams, sky ambient, up-sun density-tap self shadowing,
// grazing-path horizon thickening, camera-above/below blend ordering.

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/core.glsl"
#include "/lib/cloud/multiple_scattering.glsl"
#include "/lib/scattering/phase.glsl"


const float CIRRUS_HEIGHT_KM = 7.0;
// Single physical extinction for the squared density field (per km). Both the
// view and light paths use it; their difference comes only from the slab
// geometry H / mu. A thick core reaches OD ~ 1.0 over the 1 km zenith slab
// (T ~ 0.4) while thin edges stay under 0.1, so the thin-to-thick gradient
// stays visible.
// Scattering equals extinction, so the single-scattering albedo is exactly 1:
// ice barely absorbs. Everything a thicker deck returns past the first bounce
// is the multiple-scattering series, not a gain applied to this pair.
const float CIRRUS_SCATTERING = 3.0;
const float CIRRUS_EXTINCTION = CIRRUS_SCATTERING;
// This layer's multiple-scattering reference length, in km: the length over
// which one scattering order spreads inside this deck, and the scale the
// series' knee is measured against. At 3 km^-1 a full-density sample reaches
// one optical depth over 0.33 km, so a reference just above that puts the knee
// across the middle of the density range: at a density whose vertical optical
// depth is about 1.5 the added orders return roughly what single scattering
// does, and a thin edge returns almost nothing.
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
// Effective slab thickness: the shell is sampled once, so slanted view and
// light paths integrate extinction over H / |cos| instead of a fixed step.
const float CIRRUS_LAYER_THICKNESS_KM = 1.0;
// Grazing clamp for the slanted paths (sin of ~3.4 degrees): caps the path
// where a ray skims the deck.
const float CIRRUS_GRAZING_MIN_MU = 0.06;
// Up-sun self-shadow march: uniform 0.4 km steps (under the 0.5 km detail
// scale, ~7 taps per 2.75 km density blob), path capped at 8 steps. The slab
// geometry H / mu sets the actual path within that cap.
const float CIRRUS_LIGHT_STEP_KM = 0.2;
const int CIRRUS_LIGHT_MAX_STEPS = 3;

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
    //     float add = texture(utex_noise2d_tex, fract((pos + noise * float(i) + 0.5) / NOISE2D_SIZE)).r * p;
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

// Rational attenuation for the light trace: soft-shouldered, taps never fully
// occlude the receiver. The volumetric layer attenuates its light march on the
// same 1 / (1 + tau) curve, so both layers shadow and add their extra orders
// on one curve.
float CirrusTransmittance(float optical_depth) {
    return 1.0 / (1.0 + optical_depth);
}

// Optical depth from the receiver toward the light, unnormalized so each term
// can apply its own curve.
//
// Self-shadowing for the direct lights: march a few density taps up-sun along
// the shell tangent and shadow the receiver. A thin deck's light path grows as
// the light grazes it (H / mu), so low light sweeps a long stretch of deck and
// dense regions up-sun darken the sample. x^2 strata concentrate taps near the
// receiver, matching the volumetric light march.
float CirrusLightOpticalDepth(vec3 sample_position, vec3 shell_normal_world, vec3 light_dir, float light_mu, float jitter) {
    float light_path_km = min(CIRRUS_LAYER_THICKNESS_KM / max(light_mu, CIRRUS_GRAZING_MIN_MU),
        float(CIRRUS_LIGHT_MAX_STEPS) * CIRRUS_LIGHT_STEP_KM);
    vec3 tangential = light_dir - light_mu * shell_normal_world;
    float tangential_length = length(tangential);
    vec3 tangent_dir = tangential_length > 1.0e-5 ? tangential / tangential_length : vec3(0.0);

    // Uniform strata no wider than the fixed step; one shared jitter shifts
    // the whole sequence per frame (STBN averages under TAA).
    int step_count = int(ceil(light_path_km / CIRRUS_LIGHT_STEP_KM));
    float stratum_width = light_path_km / float(step_count);
    float optical_depth = 0.0;
    for (int i = 0; i < step_count; i++) {
        float sample_distance = (float(i) + jitter) * stratum_width;
        optical_depth += CirrusCoverageDensity(sample_position + tangent_dir * sample_distance) * stratum_width;
    }
    return optical_depth * CIRRUS_EXTINCTION;
}

// Slab source at one shell crossing, which the caller turns into radiance with
// the analytic (1 - T) / sigma_t integral.
//
// Single scattering keeps the triple-lobe HG phase. The orders past the first
// are the isotropic geometric series owned by
// /lib/cloud/multiple_scattering.glsl and they ride the very same light
// colours, which already carry each light's 1 / (1 + tau) self shadow. Their
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
    return (in_scattering - in_scattering * sample_transmittance) / max(sample_extinction, 1.0e-5);
}

// light_jitter is the STBN dither sampled by the pass main (its STBN slice
// advances with the pass's frame clock).
vec3 RenderCirrusClouds(vec3 view_dir, vec3 sky_color, float light_jitter,
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
        vec3 sun_dir = normalize(u_world_sun_dir);
        vec3 moon_dir = -sun_dir;

        // Sun/moon sampled separately from the transmittance LUT (same
        // expression as volumetric.glsl). The moon fetch MUST stay after the
        // sun branch: adjacent straight-line fetches of this sampler with
        // mirrored mu get merged by the driver (the LUT uv shares
        // sqrt(max(r^2 (mu^2 - 1) + R^2, 0))), and the moon then returns the
        // sun's transmittance — exactly zero at night.
        float sun_mu = dot(sample_position, sun_dir) / height;
        vec3 sun_color = Rec2020ToSRGB(SpectralToLinearRec2020(
            SampleTransmittance(utex_tslut, height, height * height, sun_mu) * ATM_SOLAR)) * ATM_EXPOSURE;
        float moon_mu = -sun_mu;

        // A light below the local horizon is occluded by the planet.
        float sun_visible = smoothstep(-0.05, 0.0, sun_mu);
        float moon_visible = smoothstep(-0.05, 0.0, moon_mu);

        // moon_dir is the exact IEEE negation of sun_dir, so the moon
        // cosine is the exact negation of the sun's; clamp commutes with it.
        float sun_cos = clamp(dot(view_dir, sun_dir), -1.0, 1.0);
        vec3 sun_phase = vec3(PhaseHenyeyGreensteinTripleLobe(sun_cos, CIRRUS_MIE_PHASE));
        vec3 moon_phase = vec3(PhaseHenyeyGreensteinTripleLobe(-sun_cos, CIRRUS_MIE_PHASE));

        // Up-sun self shadowing of the direct lights; the moon march offsets
        // the jitter by half a period to decorrelate its taps from the sun's.
        if (sun_visible > 0.0) {
            vec3 sun_half_vec = normalize(sun_dir - view_dir);
            sun_color *= CirrusTransmittance(CirrusLightOpticalDepth(
                sample_position, shell_normal_world, sun_half_vec, sun_mu, light_jitter));
        }

        vec3 moon_color = Rec2020ToSRGB(SpectralToLinearRec2020(
            SampleTransmittance(utex_tslut, height, height * height, moon_mu) * ATM_MOON_IRR)) * ATM_EXPOSURE;
        if (moon_visible > 0.0) {
            vec3 moon_half_vec = normalize(moon_dir - view_dir);
            moon_color *= CirrusTransmittance(CirrusLightOpticalDepth(
                sample_position, shell_normal_world, moon_half_vec, moon_mu, light_jitter));
        }

        // Sky ambient from the multiscatter LUT.
        vec3 ambient_irradiance = GetAmbientColor(sample_position, u_world_sun_dir) * 3.0;
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

    vec3 total_in_scattering = vec3(0.0);
    vec3 total_transmittance = vec3(1.0);
    if (ci_height_diff < 0.0) {
        // Camera above the layer: sky is behind the cirrus.
        total_in_scattering = total_in_scattering * ci_transmittance + ci_in_scattering;
    } else {
        // Camera below the layer: cirrus is in front of the sky.
        total_in_scattering = total_in_scattering + ci_in_scattering * total_transmittance;
    }

    total_transmittance *= ci_transmittance;

    return sky_color * total_transmittance + total_in_scattering;
}

#endif // LIB_CLOUD_CIRRUS_GLSL
