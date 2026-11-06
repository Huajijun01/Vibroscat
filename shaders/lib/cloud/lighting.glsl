#ifndef LIB_CLOUD_LIGHTING_GLSL
#define LIB_CLOUD_LIGHTING_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/illumination.glsl"
#include "/lib/cloud/density.glsl"
#include "/lib/cloud/geometry.glsl"
#include "/lib/cloud/signal.glsl"
#include "/lib/scattering/phase.glsl"

// Multiple-scattering reference length for the volumetric water-cloud model.
// Extinction is authored in km^-1; this conversion gives reference optical depth.
const float CLOUD_MS_REFERENCE_LENGTH_M = 300.0;
// Directional octaves: each step widens the phase, weakens its contribution
// and softens the optical-depth falloff of the next order.
const int CLOUD_MS_OCTAVES = 3;
// Sine-of-elevation window across which the traced direction hands over from the
// sun to the antisolar point. The layer sits 1.4 to 2.7 km up, so its own
// horizon dips 0.021 to 0.029 below the sea-level one; the handover starts just
// past that, where the layer stops seeing the sun.
const float CLOUD_MOON_FADE_LOW = -0.07;
const float CLOUD_MOON_FADE_HIGH = -0.02;
// The sun's color is held through the band below the sea-level horizon where
// the layer still catches it over its dipped horizon, which is what makes the
// fire clouds, and is only released once the antisolar side has taken over.
const float CLOUD_TWILIGHT_FADE_START = 0.03;
const float CLOUD_TWILIGHT_FADE_END = 0.08;
// Extinction in m^-1 for an extinction authored per kilometer.
const float CLOUD_EXTINCTION_PER_KM_TO_PER_M = 0.001;

// 0 while the sun is up, 1 once it is past the fade window. Written in the
// argument order smoothstep requires; a reversed pair is undefined by the spec.
float CloudMoonlightFactor(float sun_dir_y) {
    return 1.0 - smoothstep(CLOUD_MOON_FADE_LOW, CLOUD_MOON_FADE_HIGH, sun_dir_y);
}

// The folded light direction: the sun while it is up, the antisolar point once
// it has set. Flipping at the midpoint avoids normalizing a vector that reaches
// zero there. This pack's moon is the exact antipode of the sun, so the flip
// lands on it.
vec3 CloudLightDirection(vec3 sun_dir, float moonlight_factor) {
    return moonlight_factor < 0.5 ? sun_dir : -sun_dir;
}

// 1 while the sun is up and through the fire-cloud band below the horizon,
// fading to 0 by CLOUD_TWILIGHT_FADE_END below it.
float CloudTwilightWeight(float sun_dir_y) {
    return 1.0 - smoothstep(CLOUD_TWILIGHT_FADE_START, CLOUD_TWILIGHT_FADE_END, -sun_dir_y);
}

// Directional octaves for one light direction, evaluated once per light per ray.
void CloudPhaseOctaves(float cos_theta, out float phase_weight[CLOUD_MS_OCTAVES]) {
    float contribution_factor = 1.0;
    float eccentricity_factor = 1.0;
    for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
        float forward_g = CLOUD_PHASE_FORWARD_G * eccentricity_factor;
        float backward_g = CLOUD_PHASE_BACKWARD_G * eccentricity_factor;
        phase_weight[octave] = PhaseHenyeyGreensteinDualLobe(
            cos_theta, forward_g, backward_g) * contribution_factor;
        contribution_factor *= CLOUD_MS_CONTRIBUTION;
        eccentricity_factor *= CLOUD_MS_ECCENTRICITY;
    }
}

// 1 / (1 + optical depth) approximates the falloff of the additional scattering
// orders; each octave softens it further. The isotropic series rides the same
// transmittance.
float CloudDirectionalScattering(float phase_weight[CLOUD_MS_OCTAVES],
    float octave_attenuation[CLOUD_MS_OCTAVES], float light_optical_depth,
    float isotropic_orders
) {
    float scattering = 0.0;
    for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
        scattering += phase_weight[octave]
            / (light_optical_depth * octave_attenuation[octave] + 1.0);
    }
    return scattering + isotropic_orders / (1.0 + light_optical_depth);
}

// Optical depth toward the light, starting past a configurable near segment.
// CLOUD_LIGHT_STEPS quadratic strata are densest near that start; each is
// sampled at a jittered point and weighted by its exact interval length.
// Densities take the low-quality path; every accepted view sample retraces it.
float CloudLightOpticalDepth(vec3 atmosphere_position, vec3 light_dir, float light_jitter,
    CloudDensityFrame frame
) {
    float light_distance = min(
        CloudDistanceToShellExit(atmosphere_position, light_dir),
        CLOUD_LIGHT_MAX_DISTANCE_KM
    );
    float trace_distance = light_distance - CLOUD_LIGHT_START_OFFSET_KM;
    if (trace_distance <= 1.0e-5) return 0.0;

    float inverse_step_count = 1.0 / float(CLOUD_LIGHT_STEPS);
    float optical_depth = 0.0;
    // The i = 0 start is exactly the base offset (trace_distance > 0 is
    // guaranteed above, so trace_distance * 0.0 * 0.0 == +0.0), and each
    // later start is the previous end bit-for-bit: float(i + 1) counts the
    // same integer both ways, so the stratum boundary products are shared
    // instead of recomputed per step.
    float segment_start = CLOUD_LIGHT_START_OFFSET_KM;
    for (int i = 0; i < CLOUD_LIGHT_STEPS; ++i) {
        float x1 = float(i + 1) * inverse_step_count;
        float segment_end = CLOUD_LIGHT_START_OFFSET_KM + trace_distance * x1 * x1;
        float sample_distance = mix(segment_start, segment_end, light_jitter);
        vec3 sample_position = atmosphere_position + light_dir * sample_distance;
        float sample_altitude_km = length(sample_position) - ATM_PLANET_R;
        float sample_density = 0.0;
        // Same cheap altitude-band rejection the density functions open with.
        if (sample_altitude_km > CLOUD_BASE_ALTITUDE && sample_altitude_km < CLOUD_TOP_ALTITUDE) {
            sample_density = SampleCloudDensityLowQuality(sample_position, frame,
                CloudHeightProfileFor(sample_altitude_km));
        }
        optical_depth += sample_density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY
            * (segment_end - segment_start);
        segment_start = segment_end;
    }
    return optical_depth;
}

// Convert primary/sky weights into RGB with the current sun/moon and ambient
// illumination. Light colors share the sky LUT's sRGB-domain white balance.
// The compositor adds the background scaled by the signal's true transmittance.
vec3 RelightClouds(CloudSignal signal, vec3 surface_position, float surface_r,
    vec3 background_sky_color) {
    float surface_r2 = surface_r * surface_r;
    float sun_mu = dot(surface_position, u_world_sun_dir) / surface_r;
    // moon_mu is just -sun_mu; the host's moon_dir is the antipode of sun_dir.
    float moon_mu = -sun_mu;
    vec3 sun_color = AtmosphereDirectIrradianceAt(surface_r, surface_r2, sun_mu, ATM_SOLAR);
    vec3 moon_color = AtmosphereDirectIrradianceAt(surface_r, surface_r2, moon_mu, ATM_MOON_IRR);
    // The integrated sky weight already includes view absorption; only its
    // incident color is evaluated here. As the view transmittance rises
    // toward the thin edges, the incident color hands over from the
    // multiple-scattering LUT to the background sky itself, so the edge tint
    // matches the color the compositor blends over instead of carrying a
    // mismatched LUT color.
    vec3 ambient_cloud_radiance = mix(
        AtmosphereAmbientRadianceAt(surface_r, sun_mu) * CLOUD_SKY_LIGHT_STRENGTH,
        background_sky_color,
        signal.transmittance) * signal.scattering.y;
    // One trace means one directional channel, so the light color carries both
    // illuminants. The sun keeps its color through the fire-cloud band, where
    // it has crossed the sea-level horizon but the layer still catches it over
    // its own dipped one, and is released once the antisolar side has taken
    // over.
    vec3 light_color = sun_color * CloudTwilightWeight(u_world_sun_dir.y)
        + moon_color * CloudMoonlightFactor(u_world_sun_dir.y);
    return signal.scattering.x * light_color + ambient_cloud_radiance;
}

#endif // LIB_CLOUD_LIGHTING_GLSL
