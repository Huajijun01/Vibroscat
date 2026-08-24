#ifndef LIB_CLOUD_CIRRUS_GLSL
#define LIB_CLOUD_CIRRUS_GLSL

// Cirrus layer.
// Shape: periodic 64x64 R8 value noise (utex_noise2d_tex), domain-warped and
// scrolled; sampled once at the shell crossing.
// Light: thin-shell single sample; scalar scattering/extinction, HG phase,
// Beer-Lambert + powder term, multi-octave phase scattering, sky ambient,
// camera-above/below blend ordering.

#include "/lib/atmosphere/core.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"


const float CIRRUS_HEIGHT_KM = 7.0;
const float CIRRUS_UNIFORM_PHASE = 1.0 / (4.0 * PI);
const float CIRRUS_SCATTERING = 0.2;
const float CIRRUS_EXTINCTION = CIRRUS_SCATTERING;
const float CIRRUS_ASYM = 0.5;
const float NOISE2D_SIZE = 64.0;

// Reference cirrus shape algorithm. TIME → frameTimeCounter; ps =
// planet-centered position (km), horizontal zx plane only. Noise lattice
// baked into the periodic 64x64 R8 texture; uv = fract((pos + 0.5)/64),
// linear + repeat. pos kept in [0, 64) via mod (octave transforms must not
// destroy float precision on planet-centered input).
float GetFlaCloNoise(vec3 ps) {
    vec2 pos = ps.zx * 0.15;

    float noise = 0.0;
    float p = 0.5;

    float wind = 0.02 * frameTimeCounter;

    pos = mod(pos * vec2(1.0, 2.2) + vec2(0.08, 0.8) * wind, NOISE2D_SIZE);

    for (int i = 1; i < 6; ++i) {
        float add = texture(utex_noise2d_tex, fract((pos + noise * float(i) + 0.5) / NOISE2D_SIZE)).r * p;
        noise += add;
        p *= 0.5;
        pos = mod(pos * vec2(3.0, 2.0) + vec2(wind * float(i), 0.0) + vec2(0.0, add), NOISE2D_SIZE);
    }

    return exp(smoothstep(0.0, 1.0, noise) * -5.0);
}

float CirrusDensity(vec3 atmosphere_position) {
    return GetFlaCloNoise(atmosphere_position);
}

// Multi-octave phase scattering: 4 orders with per-order falloffs, packaged
// as a single function. Each order blends the HG phase toward the uniform
// phase and attenuates the light/ambient contributions.
vec3 CirrusPhaseScattering(vec3 sun_color, float sun_visible, vec3 sun_phase, vec3 moon_color, float moon_visible,
    vec3 moon_phase, vec3 ambient_irradiance, float sample_scattering, float sample_extinction, float sample_transmittance
) {
    vec3 in_sctr = sun_color * sun_visible * sun_phase + moon_color * moon_visible * moon_phase + ambient_irradiance;
    // multiply 6.0 to boost luminance
    in_sctr *= sample_scattering * 6.0;
    return (in_sctr - in_sctr * sample_transmittance) / max(sample_extinction, 1.0e-5);
}

vec3 RenderCirrusClouds(vec3 view_dir, vec3 sky_color, out vec3 cirrus_surface_pos, out vec3 cirrus_transmittance
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
        float sun_visible = smoothstep(0.0, 0.05, sun_mu);
        float moon_visible = smoothstep(0.0, 0.05, moon_mu);

        vec3 sun_phase = vec3(PhaseMieHG(clamp(dot(view_dir, sun_dir), -1.0, 1.0), CIRRUS_ASYM));
        vec3 moon_phase = vec3(PhaseMieHG(clamp(dot(view_dir, moon_dir), -1.0, 1.0), CIRRUS_ASYM));

        // Sky ambient from the multiscatter LUT.
        vec3 ambient_irradiance = GetAmbientColor(sample_position, u_world_sun_dir);
        ambient_irradiance *= 0.8 + 0.2 * ci_transmittance;

        float sample_scattering = CIRRUS_SCATTERING * sample_density;
        float sample_extinction = CIRRUS_EXTINCTION * sample_density;
        float sample_optical_depth = sample_extinction; // 1 km step
        float sample_transmittance = max(exp(-sample_optical_depth), exp(-sample_optical_depth * 0.25) * 0.7);

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