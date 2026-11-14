#ifndef LIB_CLOUD_LIGHTING_GLSL
#define LIB_CLOUD_LIGHTING_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/illumination.glsl"
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/cloud/density.glsl"
#include "/lib/cloud/geometry.glsl"
#include "/lib/cloud/signal.glsl"
#include "/lib/scattering/phase.glsl"

// Extinction (km^-1) times this length (m) gives the dimensionless reference optical depth.
const float CLOUD_MS_REFERENCE_LENGTH_M = 200.0;
const int CLOUD_MS_OCTAVES = 6;
// Sun-to-antisolar handover window; the 1.4-2.7 km layer's own horizon dips 0.021-0.029,
// so the fade starts just past where the layer stops seeing the sun.
const float CLOUD_MOON_FADE_LOW = -0.07;
const float CLOUD_MOON_FADE_HIGH = -0.02;
// Holds the sun's color through the below-horizon band where the layer still catches it (fire clouds).
const float CLOUD_TWILIGHT_FADE_START = 0.03;
const float CLOUD_TWILIGHT_FADE_END = 0.08;
const float CLOUD_EXTINCTION_PER_KM_TO_PER_M = 0.001;

float CloudMoonlightFactor(float sun_dir_y) {
    return 1.0 - smoothstep(CLOUD_MOON_FADE_LOW, CLOUD_MOON_FADE_HIGH, sun_dir_y);
}

// Sun while up, else its antipode: this pack's moon is the exact antipode of the sun.
vec3 CloudLightDirection(vec3 sun_dir, float moonlight_factor) {
    return moonlight_factor < 0.5 ? sun_dir : -sun_dir;
}

float CloudTwilightWeight(float sun_dir_y) {
    return 1.0 - smoothstep(CLOUD_TWILIGHT_FADE_START, CLOUD_TWILIGHT_FADE_END, -sun_dir_y);
}

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

// 1 / (1 + optical depth) approximates the per-octave falloff of the higher scattering orders.
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
    float base_step_length = trace_distance * inverse_step_count * inverse_step_count;
    float sample_distance = CLOUD_LIGHT_START_OFFSET_KM + light_jitter * base_step_length;
    float optical_depth = 0.0;
    for (int i = 0; i < CLOUD_LIGHT_STEPS; ++i) {
        // Lengths (2i + 1) * base sum to trace_distance and keep every sample before light_distance.
        float step_length = base_step_length * float(2 * i + 1);
        vec3 sample_position = atmosphere_position + light_dir * sample_distance;
        float sample_altitude_km = length(sample_position) - ATM_PLANET_R;
        float sample_density = 0.0;
        if (sample_altitude_km > CLOUD_BASE_ALTITUDE && sample_altitude_km < CLOUD_TOP_ALTITUDE) {
            sample_density = SampleCloudDensityLowQuality(sample_position, frame,
                CloudHeightProfileFor(sample_altitude_km));
        }
        optical_depth += sample_density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY
            * step_length;
        sample_distance += step_length;
    }
    return optical_depth;
}

// Light colors share the sky LUT's sRGB-domain white balance; the compositor adds
// the background scaled by the signal's true transmittance.
vec3 RelightClouds(CloudSignal signal, vec3 surface_position, float surface_r,
    vec3 background_sky_color) {
    float surface_r2 = surface_r * surface_r;
    float sun_mu = dot(surface_position, u_world_sun_dir) / surface_r;
    float moon_mu = -sun_mu;
    vec3 sun_color = AtmosphereDirectIrradianceAt(surface_r, surface_r2, sun_mu, ATM_SOLAR);
    vec3 moon_color = AtmosphereDirectIrradianceAt(surface_r, surface_r2, moon_mu, ATM_MOON_IRR);
    // The integrated sky weight already includes view absorption; only its incident color is evaluated here.
    // EvalSkyLightAverage reads the previous frame's SH bake (prepare2 updates it after); frame 0 seeds from clear sky.
    vec3 ambient_sky_color = frameCounter == 0
        ? background_sky_color
        : EvalSkyLightAverage() / PI;
    vec3 ambient_cloud_radiance = mix(
        ambient_sky_color * CLOUD_AMBIENT_STRENGTH,
        background_sky_color,
        signal.transmittance) * signal.scattering.y;
    // One traced direction, so the light color sums both illuminants.
    vec3 light_color = sun_color * CloudTwilightWeight(u_world_sun_dir.y)
        + moon_color * CloudMoonlightFactor(u_world_sun_dir.y);
    return signal.scattering.x * light_color + ambient_cloud_radiance;
}

#endif // LIB_CLOUD_LIGHTING_GLSL
