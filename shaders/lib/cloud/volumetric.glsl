#ifndef LIB_CLOUD_VOLUMETRIC_GLSL
#define LIB_CLOUD_VOLUMETRIC_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/cloud/density.glsl"
#include "/lib/cloud/lighting.glsl"
#include "/lib/cloud/multiple_scattering.glsl"
#include "/lib/cloud/signal.glsl"

// Integrate primary/sky scattering weights and true view transmittance.
// Incident light colors are applied by RelightClouds.
CloudSignal MarchVolumetricClouds(vec3 camera_atmosphere_pos, vec3 view_dir, vec2 stbn_jitter,
    float march_start, float march_end, int step_count, out vec3 surface_position, out bool hit
) {
    // One traced direction: the antisolar fold. The sun keeps its color through
    // the handover, see CloudTwilightWeight at the relight.
    float moonlight_factor = CloudMoonlightFactor(u_world_sun_dir.y);
    vec3 light_dir = CloudLightDirection(u_world_sun_dir, moonlight_factor);
    float light_cos_theta = clamp(dot(view_dir, light_dir), -1.0, 1.0);
    float light_phase_weight[CLOUD_MS_OCTAVES];
    CloudPhaseOctaves(light_cos_theta, light_phase_weight);
    float octave_attenuation[CLOUD_MS_OCTAVES];
    {
        float attenuation_factor = 1.0;
        for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
            octave_attenuation[octave] = attenuation_factor;
            attenuation_factor *= CLOUD_MS_ATTENUATION;
        }
    }

    // stbn_jitter is sampled by the pass main: the screen pass seeds it with
    // (view texel, frameCounter), the skybox with (skybox texel,
    // frameCounter / 4). x = view march jitter, y = light march base; the two
    // streams are decorrelated by the STBN stream offset (STBN_STREAM_3).
    float interval_length = march_end - march_start;
    // Coverage folds rainStrength, which no sample of this ray changes, so the
    // layer constants are built once per ray and read by both density calls.
    CloudDensityFrame layer_frame = CloudDensityFrameForRay();
    float light_scattering = 0.0;
    float sky_scattering = 0.0;
    vec3 surface_position_accumulator = vec3(0.0);
    float surface_weight = 0.0;
    float view_transmittance = 1.0;
    float inverse_step_count = 1.0 / float(step_count);
    float step_length = interval_length * inverse_step_count;
    float extinction_per_step = CLOUD_ALPHA_EXTINCTION_SRGB_GRAY * step_length;

    // One-deep prefetch of the distribution read: the next sample's position
    // is the pure step recurrence (the whole sequence shares one jittered
    // step, so independent per-segment offsets cannot line up with height
    // bands), so its 2D read issues before this sample's density decode and
    // light trace. Reads prefetched past a break, the altitude-band skip, or
    // the final step are discarded; the height profile still decodes only
    // for in-band samples.
    float sample_distance = march_start + stbn_jitter.x * step_length;
    vec3 sample_position = camera_atmosphere_pos + view_dir * sample_distance;
    float sample_altitude_km = length(sample_position) - ATM_PLANET_R;
    float sample_distribution = texture(utex_cloud_distribution_tex,
        CloudDistributionUV(sample_position.xz, layer_frame)).r;
    for (int i = 0; i < CLOUD_VIEW_MAX_STEPS; ++i) {
        if (i >= step_count) break;
        float next_distance = march_start + (float(i + 1) + stbn_jitter.x) * step_length;
        vec3 next_position = camera_atmosphere_pos + view_dir * next_distance;
        float next_altitude_km = length(next_position) - ATM_PLANET_R;
        float next_distribution = texture(utex_cloud_distribution_tex,
            CloudDistributionUV(next_position.xz, layer_frame)).r;

        // The band test and the two height ramps are evaluated once per sample
        // here and shared by whichever density path runs.
        if (sample_altitude_km > CLOUD_BASE_ALTITUDE && sample_altitude_km < CLOUD_TOP_ALTITUDE) {
            CloudHeightProfile sample_height = CloudHeightProfileFor(sample_altitude_km);
            float sample_density = DecodeCloudDensity(sample_position, layer_frame,
                sample_height, sample_distribution);
            if (sample_density >= 1.0e-4) {
                // Only PlanetHorizonOccluded consumes the squared radius below;
                // keep it off the erased-sample path.
                float sample_r2 = dot(sample_position, sample_position);

                // Per-sample scattering material for the directional light. The
                // three constants are folded into one per-sample multiply.
                float reference_optical_depth = sample_density
                    * (CLOUD_ALPHA_EXTINCTION_SRGB_GRAY * CLOUD_EXTINCTION_PER_KM_TO_PER_M
                        * CLOUD_MS_REFERENCE_LENGTH_M);
                float isotropic_orders = IsotropicOrders(
                    reference_optical_depth, CLOUD_MS_SAT_ALBEDO, CLOUD_MS_ISOTROPIC);

                float sample_light = 0.0;
                // The jitter only feeds the light trace, so compute it after the
                // horizon test has skipped erased samples.
                if (!PlanetHorizonOccluded(sample_position, sample_r2, light_dir, ATM_PLANET_R2)) {
                    float light_jitter = fract(stbn_jitter.y + (float(i) + 0.5) * GOLDEN_RATIO_CONJUGATE);
                    float light_optical_depth = CloudLightOpticalDepth(
                        sample_position, light_dir, light_jitter, layer_frame);
                    sample_light = CloudDirectionalScattering(light_phase_weight,
                        octave_attenuation, light_optical_depth, isotropic_orders);
                }
                float sky_optical_depth = CloudSkyOpticalDepth(sample_position, sample_distribution, layer_frame);
                float optical_depth = sample_density * extinction_per_step;
                float segment_transmittance = exp(-optical_depth);
                float segment_absorption = 1.0 - segment_transmittance;
                float segment_weight = view_transmittance * segment_absorption;
                surface_position_accumulator += sample_position * segment_weight;
                surface_weight += segment_weight;
                light_scattering += segment_weight * sample_light;
                // A soft transport response approximates diffuse redistribution
                // while retaining variation in the optical depth above each sample.
                sky_scattering += segment_weight / (1.0 + sky_optical_depth);
                view_transmittance *= segment_transmittance;
                if (view_transmittance < 1.0e-4) break;
            }
        }
        sample_position = next_position;
        sample_altitude_km = next_altitude_km;
        sample_distribution = next_distribution;
    }

    hit = surface_weight > 1.0e-5;
    surface_position = surface_position_accumulator / max(surface_weight, 1.0e-5);
    return CloudSignal(vec2(light_scattering, sky_scattering), view_transmittance);
}

#endif // LIB_CLOUD_VOLUMETRIC_GLSL
