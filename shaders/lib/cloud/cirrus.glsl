#ifndef LIB_CLOUD_CIRRUS_GLSL
#define LIB_CLOUD_CIRRUS_GLSL

// Cirrus layer.
// Shape: periodic 64x64 R8 value noise (utex_noise2d_tex), domain-warped and
// scrolled; sampled once at the shell crossing.
// Light: thin-shell single sample; scalar scattering/extinction, triple-lobe
// (forward silver lining + backward) HG phase, mixed rational/exp
// attenuation, multi-octave phase scattering, sky ambient, up-sun
// density-tap self shadowing, grazing-path horizon thickening,
// camera-above/below blend ordering.

#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/core.glsl"


const float CIRRUS_HEIGHT_KM = 7.0;
const float CIRRUS_UNIFORM_PHASE = 1.0 / (4.0 * PI);
// Single physical extinction for the squared density field (per km). Both the
// view and light paths use it; their difference comes only from the slab
// geometry H / mu. A thick core reaches OD ~ 1.0 over the 1 km zenith slab
// (T ~ 0.4) while thin edges stay under 0.1, so the thin-to-thick gradient
// stays visible.
const float CIRRUS_SCATTERING = 3.0;
const float CIRRUS_EXTINCTION = CIRRUS_SCATTERING;
// Radiance rebalance for the larger (1 - T) of the denser field.
const float CIRRUS_SCATTERING_BOOST = 1.5;
// Triple-lobe phase: the narrow + mid forward lobes keep the silver lining,
// the backward lobe lifts the anti-lit side (cloud-bow analog) so decks
// facing away from the light keep a visible response instead of collapsing
// toward a tenth of the isotropic phase.
const float CIRRUS_PHASE_PEAK_G = 0.92;
const float CIRRUS_PHASE_PEAK_WEIGHT = 0.1;
const float CIRRUS_PHASE_MID_G = 0.3;
const float CIRRUS_PHASE_MID_WEIGHT = 0.8;
const float CIRRUS_PHASE_BACK_G = 0.2;
const float CIRRUS_PHASE_BACK_WEIGHT = 0.1;
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
float GetFlaCloNoise(vec3 ps) {
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
    float large = smoothstep(0.1, 1.0, texture(utex_cloud_distribution_tex, ps.xz * 0.005).x);
    // Square the contrast-stretched ratio: the raw field saturates into
    // plateaus (0 or 0.5-0.9), and the square widens it into a ramp so the
    // optical depth reads as a gradual thin-to-thick transition.
    float density = Saturate((large - small) / (1.0 - small));
    return density * density;
}

float CirrusDensity(vec3 atmosphere_position) {
    return GetFlaCloNoise(atmosphere_position);
}

// Rational attenuation for the shadow march: soft-shouldered, taps never
// fully occlude the receiver.
float CirrusTransmittance(float optical_depth) {
    return 1.0 / (1.0 + optical_depth);
}

// Triple-lobe phase (forward peak / forward mid / backward).
float CirrusPhase(float cos_theta) {
    return CIRRUS_PHASE_PEAK_WEIGHT * PhaseMieHG(cos_theta, CIRRUS_PHASE_PEAK_G)
        + CIRRUS_PHASE_MID_WEIGHT * PhaseMieHG(cos_theta, CIRRUS_PHASE_MID_G)
        + CIRRUS_PHASE_BACK_WEIGHT * PhaseMieHG(cos_theta, -CIRRUS_PHASE_BACK_G);
}

// Self-shadowing for the direct lights: march a few density taps up-sun along
// the shell tangent and Beer-shadow the receiver. A thin deck's light path
// grows as the light grazes it (H / mu), so low light sweeps a long stretch
// of deck and dense regions up-sun darken the sample. x^2 strata concentrate
// taps near the receiver, matching the volumetric light march.
float CirrusLightTransmittance(vec3 sample_position, vec3 normal, vec3 light_dir, float light_mu, float jitter) {
    float light_path_km = min(CIRRUS_LAYER_THICKNESS_KM / max(light_mu, CIRRUS_GRAZING_MIN_MU),
        float(CIRRUS_LIGHT_MAX_STEPS) * CIRRUS_LIGHT_STEP_KM);
    vec3 tangential = light_dir - light_mu * normal;
    float tangential_length = length(tangential);
    vec3 tangent_dir = tangential_length > 1.0e-5 ? tangential / tangential_length : vec3(0.0);

    // Uniform strata no wider than the fixed step; one shared jitter shifts
    // the whole sequence per frame (STBN averages under TAA).
    int step_count = int(ceil(light_path_km / CIRRUS_LIGHT_STEP_KM));
    float stratum_width = light_path_km / float(step_count);
    float optical_depth = 0.0;
    for (int i = 0; i < step_count; ++i) {
        float sample_distance = (float(i) + jitter) * stratum_width;
        optical_depth += CirrusDensity(sample_position + tangent_dir * sample_distance) * stratum_width;
    }
    return CirrusTransmittance(optical_depth * CIRRUS_EXTINCTION);
}

// Multi-octave phase scattering: 4 orders with per-order falloffs, packaged
// as a single function. Each order blends the HG phase toward the uniform
// phase and attenuates the light/ambient contributions.
vec3 CirrusPhaseScattering(vec3 sun_color, float sun_visible, vec3 sun_phase, vec3 moon_color, float moon_visible,
    vec3 moon_phase, vec3 ambient_irradiance, float sample_scattering, float sample_extinction, float sample_transmittance
) {
    vec3 in_sctr = sun_color * sun_visible * sun_phase + moon_color * moon_visible * moon_phase + ambient_irradiance;
    in_sctr *= sample_scattering * CIRRUS_SCATTERING_BOOST;
    return (in_sctr - in_sctr * sample_transmittance) / max(sample_extinction, 1.0e-5);
}

vec3 RenderCirrusClouds(vec3 view_dir, vec3 sky_color, ivec2 dither_coord, int dither_slice,
    out vec3 cirrus_surface_pos, out vec3 cirrus_transmittance
) {
    vec3 ray_start = vec3(0.0, ATM_PLANET_R + u_cam_altitude, 0.0);
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
    vec3 normal = sample_position / height;
    float sample_density = CirrusDensity(sample_position);

    vec3 ci_in_sctr = vec3(0.0);
    vec3 ci_transmittance = vec3(1.0);

    if (sample_density > 1.0e-5) {
        vec3 sun_dir = normalize(u_world_sun_dir);
        vec3 moon_dir = -sun_dir;

        // Sun/moon sampled separately from the transmittance LUT (same
        // expression as volumetric.glsl).
        float sun_mu = dot(sample_position, sun_dir) / height;
        vec3 sun_color = SpectralToLinearSRGB(SampleTransmittance(TRANSMITTANCE_LUT, height, height * height, sun_mu) * ATM_SOLAR) * ATM_EXPOSURE;
        float moon_mu = -sun_mu;
        vec3 moon_color = SpectralToLinearSRGB(SampleTransmittance(TRANSMITTANCE_LUT, height, height * height, moon_mu) * ATM_MOON_IRR) * ATM_EXPOSURE;

        // A light below the local horizon is occluded by the planet.
        float sun_visible = smoothstep(-0.05, 0.0, sun_mu);
        float moon_visible = smoothstep(-0.05, 0.0, moon_mu);

        vec3 sun_phase = vec3(CirrusPhase(clamp(dot(view_dir, sun_dir), -1.0, 1.0)));
        vec3 moon_phase = vec3(CirrusPhase(clamp(dot(view_dir, moon_dir), -1.0, 1.0)));

        // Up-sun self shadowing of the direct lights; the moon march offsets
        // the jitter by half a period to decorrelate its taps from the sun's.
        float light_jitter = SampleSTBN(dither_coord, dither_slice);
        if (sun_visible > 0.0) {
            sun_color *= CirrusLightTransmittance(sample_position, normal, sun_dir, sun_mu, light_jitter);
        }
        if (moon_visible > 0.0) {
            moon_color *= CirrusLightTransmittance(sample_position, normal, moon_dir, moon_mu,
                fract(light_jitter + 0.5));
        }

        // Sky ambient from the multiscatter LUT.
        vec3 ambient_irradiance = GetAmbientColor(sample_position, u_world_sun_dir);
        ambient_irradiance *= 0.8 + 0.2 * ci_transmittance;

        float sample_scattering = CIRRUS_SCATTERING * sample_density;
        float sample_extinction = CIRRUS_EXTINCTION * sample_density;
        // Slanted path through the effective slab: optical depth grows where
        // the view grazes the deck, so the horizon reads thick while the
        // zenith keeps the overhead thickness (capped by the true distance).
        float view_path_km = min(ci_offset,
            CIRRUS_LAYER_THICKNESS_KM / max(abs(dot(view_dir, normal)), CIRRUS_GRAZING_MIN_MU));
        float sample_optical_depth = sample_extinction * view_path_km;
        float sample_transmittance = exp(-sample_optical_depth);

        ci_in_sctr = CirrusPhaseScattering(sun_color, sun_visible, sun_phase, moon_color, moon_visible, moon_phase,
                                           ambient_irradiance, sample_scattering, sample_extinction, sample_transmittance);
        ci_transmittance = vec3(sample_transmittance);
        cirrus_transmittance = ci_transmittance;
    }

    if (max(ci_in_sctr, ci_transmittance).r < 1.0e-5) {
        return sky_color;
    }

    vec3 total_in_sctr = vec3(0.0);
    vec3 total_transmittance = vec3(1.0);
    if (ci_height_diff < 0.0) {
        // Camera above the layer: sky is behind the cirrus.
        total_in_sctr = total_in_sctr * ci_transmittance + ci_in_sctr;
    } else {
        // Camera below the layer: cirrus is in front of the sky.
        total_in_sctr = total_in_sctr + ci_in_sctr * total_transmittance;
    }

    total_transmittance *= ci_transmittance;

    return sky_color * total_transmittance + total_in_sctr;
}

#endif
