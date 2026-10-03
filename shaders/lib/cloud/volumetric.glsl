#ifndef LIB_CLOUD_VOLUMETRIC_GLSL
#define LIB_CLOUD_VOLUMETRIC_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/cloud/multiple_scattering.glsl"
#include "/lib/scattering/phase.glsl"

// Vibroscat volumetric clouds.
//
// In-cloud multiple scattering is the isotropic geometric series owned by
// /lib/cloud/multiple_scattering.glsl, summed with this pack's three-octave
// directional phase. See licenses/THIRD_PARTY_NOTICES.md section 18.
//
// The direct term keeps this pack's three-octave directional sum on a
// 1 / (1 + tau) transmittance, and the light colour holds the sun through the
// band just below the horizon where the cloud layer still catches it. Those are
// this pack's own choices; they are described where they are implemented.

// This layer's multiple-scattering reference length, in meters. The full
// extinction of a dense sample is 100 km^-1, so one optical depth is reached
// over 10 m; the reference sits well above that and the series is saturated
// across most of the density range, which is what gives a thick water cloud
// its milky interior. It is this layer's own constant: a length calibrated for
// 100 km^-1 lands nowhere useful on a medium three decades thinner.
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
// The sun's colour is held through the band below the sea-level horizon where
// the layer still catches it over its dipped horizon, which is what makes the
// fire clouds, and is only released once the antisolar side has taken over.
const float CLOUD_TWILIGHT_FADE_START = 0.03;
const float CLOUD_TWILIGHT_FADE_END = 0.08;



bool CloudShellInterval(vec3 origin, vec3 dir, out float march_start, out float march_end
) {
    float inner_radius = ATM_PLANET_R + CLOUD_BASE_ALTITUDE;
    float outer_radius = ATM_PLANET_R + CLOUD_TOP_ALTITUDE;
    // The three RayIntersectSphere solves below share b and dot(origin,
    // origin); each solve keeps that function's exact operation sequence, so
    // every output stays bit-identical while both dot products run once.
    float b = 2.0 * dot(origin, dir);
    float origin_r2 = dot(origin, origin);

    float outer_c = origin_r2 - outer_radius * outer_radius;
    float outer_discriminant = b * b - 4.0 * outer_c;
    if (outer_discriminant <= 0.0) {
        return false;
    }
    float outer_root = sqrt(outer_discriminant);
    float outer_near = 0.5 * (-b - outer_root);
    float outer_far = 0.5 * (-b + outer_root);
    march_start = max(outer_near, 0.0);
    march_end = outer_far;

    float inner_c = origin_r2 - inner_radius * inner_radius;
    float inner_discriminant = b * b - 4.0 * inner_c;
    if (inner_discriminant > 0.0) {
        float inner_root = sqrt(inner_discriminant);
        float inner_near = 0.5 * (-b - inner_root);
        float inner_far = 0.5 * (-b + inner_root);
        if (length(origin) < inner_radius) {
            march_start = max(march_start, inner_far);
        } else if (inner_near > march_start) {
            march_end = min(march_end, inner_near);
        }
    }

    float ground_c = origin_r2 - ATM_PLANET_R * ATM_PLANET_R;
    float ground_discriminant = b * b - 4.0 * ground_c;
    if (ground_discriminant > 0.0) {
        float ground_root = sqrt(ground_discriminant);
        float ground_near = 0.5 * (-b - ground_root);
        float ground_far = 0.5 * (-b + ground_root);
        if (ground_near > 0.0) {
            march_end = min(march_end, ground_near);
        }
    }

    return march_end > march_start + 1.0e-5;
}

float CloudDistanceToShellExit(vec3 position, vec3 dir) {
    // The two shell solves share b and dot(position, position); per-sphere
    // operations match RayIntersectSphere exactly, so the sweep is
    // bit-identical to the separate calls (the unused inner far root is gone).
    float b = 2.0 * dot(position, dir);
    float origin_r2 = dot(position, position);
    float outer_radius = ATM_PLANET_R + CLOUD_TOP_ALTITUDE;
    float outer_c = origin_r2 - outer_radius * outer_radius;
    float outer_discriminant = b * b - 4.0 * outer_c;
    if (outer_discriminant <= 0.0) {
        return 0.0;
    }
    float outer_root = sqrt(outer_discriminant);
    float outer_far = 0.5 * (-b + outer_root);
    float distance_to_exit = max(outer_far, 0.0);

    float inner_radius = ATM_PLANET_R + CLOUD_BASE_ALTITUDE;
    float inner_c = origin_r2 - inner_radius * inner_radius;
    float inner_discriminant = b * b - 4.0 * inner_c;
    if (inner_discriminant > 0.0) {
        float inner_root = sqrt(inner_discriminant);
        float inner_near = 0.5 * (-b - inner_root);
        if (inner_near > 1.0e-5) {
            distance_to_exit = min(distance_to_exit, inner_near);
        }
    }
    return distance_to_exit;
}

// Reproject current-frame point to the previous camera (shared by the
// compute pass and the temporal compositor).
bool CloudProjectToPrevious(vec3 view_dir_world, float distance_km, out vec2 previous_uv) {
    vec3 scene_pos = view_dir_world * (distance_km * 1000.0);
    vec3 camera_delta = cameraPosition - previousCameraPosition;
    vec4 previous_view = gbufferPreviousModelView
        * vec4(scene_pos + camera_delta, 1.0);
    vec4 previous_clip = gbufferPreviousProjection * previous_view;
    if (previous_clip.w <= 0.0) return false;
    vec3 previous_ndc = previous_clip.xyz / previous_clip.w;
    previous_uv = previous_ndc.xy * 0.5 + 0.5;
    return all(greaterThanEqual(previous_uv, vec2(0.0)))
        && all(lessThanEqual(previous_uv, vec2(1.0)));
}

float RemapCloudErosion(float density, float threshold) {
    threshold = Saturate(threshold);
    return Saturate((density - threshold) / max(1.0 - threshold, 1.0e-5));
}

vec2 CloudDistributionUv(vec2 world_km) {
    return world_km / CLOUD_DISTRIBUTION_SCALE_KM + vec2(
            frameTimeCounter * CLOUD_WIND_SPEED / CLOUD_DISTRIBUTION_SCALE_KM, 0.0);
}

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
    float radiance = 0.0;
    for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
        radiance += phase_weight[octave]
            / (light_optical_depth * octave_attenuation[octave] + 1.0);
    }
    return radiance + isotropic_orders / (1.0 + light_optical_depth);
}

// Eroded density in [0, 1] at one point in the cloud layer.
float SampleCloudDensity(vec3 atmosphere_position) {
    float altitude_km = length(atmosphere_position) - ATM_PLANET_R;
    // Cheap band rejection first: rejected samples never need the normalized
    // height, and the light march crosses the shell boundary on most steps.
    if (altitude_km <= CLOUD_BASE_ALTITUDE || altitude_km >= CLOUD_TOP_ALTITUDE) {
        return 0.0;
    }
    float height_fraction = Saturate((altitude_km - CLOUD_BASE_ALTITUDE)
        / max(CLOUD_TOP_ALTITUDE - CLOUD_BASE_ALTITUDE, 1.0e-5));

    vec2 world_km = atmosphere_position.xz + cameraPosition.xz * 0.001;

    vec2 distribution_uv = CloudDistributionUv(world_km);
    float distribution = texture(utex_cloud_distribution_tex, distribution_uv).r;
    float coverage = (CLOUD_COVERAGE) * (1.0 - rainStrength) + rainStrength;
    float distribution_density = Saturate((distribution - (1.0 - coverage)) / max(coverage, 1.0e-5));
    if(distribution_density < 0.001) {
        return 0.0;
    }
    float bottom_ramp = smoothstep(0.0, 0.2, height_fraction);
    // Reversed edge pair (edge0 > edge1): undefined by the GLSL spec, but the
    // common clamp((x-e0)/(e1-e0)) implementation is deterministic and the
    // rendered ramp below is the frozen baseline for the 2026-10 optimization
    // series. Do not swap or rewrite this pair without a visual re-baseline.
    float top_fade = smoothstep(distribution_density * 0.5 + 0.5, distribution_density * 0.4, height_fraction);
    float lq_density = distribution_density * bottom_ramp * top_fade;
    if(lq_density < 0.001) {
        return 0.0;
    }
    float detailed_noise = texture(utex_cloud_voronoise_tex, vec3(world_km, altitude_km) * CLOUD_FINE_EROSION_SCALE).r;
    float fine_exposure = smoothstep(0.0, 0.5, height_fraction) * 0.6 + 0.4;
    float hq_density = RemapCloudErosion(lq_density, detailed_noise * CLOUD_FINE_EROSION_STRENGTH * fine_exposure);
    return hq_density;
}

// Low-quality density for the light-transport trace: the same field with the
// voronoise threshold replaced by the baked texture mean times the same 0.5
// factor, which keeps the expected threshold equal to the view path and
// saves one 3D read per light step.
float SampleCloudDensityLowQuality(vec3 atmosphere_position) {
    float altitude_km = length(atmosphere_position) - ATM_PLANET_R;
    // Same cheap-first ordering as SampleCloudDensity; keep in sync.
    if (altitude_km <= CLOUD_BASE_ALTITUDE || altitude_km >= CLOUD_TOP_ALTITUDE) {
        return 0.0;
    }
    float height_fraction = Saturate((altitude_km - CLOUD_BASE_ALTITUDE)
        / max(CLOUD_TOP_ALTITUDE - CLOUD_BASE_ALTITUDE, 1.0e-5));

    vec2 world_km = atmosphere_position.xz + cameraPosition.xz * 0.001;

    vec2 distribution_uv = CloudDistributionUv(world_km);
    float distribution = texture(utex_cloud_distribution_tex, distribution_uv).r;
    float coverage = (CLOUD_COVERAGE) * (1.0 - rainStrength) + rainStrength;
    float distribution_density = Saturate((distribution - (1.0 - coverage)) / max(coverage, 1.0e-5));
    if(distribution_density < 0.001) {
        return 0.0;
    }
    float bottom_ramp = smoothstep(0.0, 0.2, height_fraction);
    // Same intentionally reversed smoothstep pair as SampleCloudDensity; keep
    // the two implementations bit-identical on this ramp.
    float top_fade = smoothstep(distribution_density * 0.5 + 0.5, distribution_density * 0.4, height_fraction);
    float lq_density = distribution_density * bottom_ramp * top_fade;

    const float fine_average = 0.481373506;
    float fine_exposure = smoothstep(0.0, 0.5, height_fraction) * 0.6 + 0.4;

    float hq_density = RemapCloudErosion(lq_density, fine_average * CLOUD_FINE_EROSION_STRENGTH * fine_exposure);
    return hq_density;
}

// Optical depth toward the light, starting past a configurable near segment.
// CLOUD_LIGHT_STEPS quadratic strata are densest near that start; each is
// sampled at a jittered point and weighted by its exact interval length.
// Densities take the low-quality path; every accepted view sample retraces it.
float CloudLightOpticalDepth(vec3 atmosphere_position, vec3 light_dir, float light_jitter) {
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
        float sample_density = SampleCloudDensityLowQuality(
            atmosphere_position + light_dir * sample_distance);
        optical_depth += sample_density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY
            * (segment_end - segment_start);
        segment_start = segment_end;
    }
    return optical_depth;
}

// Single-scattering albedo is applied here; light colors and intensity scaling
// stay at the relight consumer.
vec3 MarchVolumetricClouds(vec3 camera_atmosphere_pos, vec3 view_dir, vec2 stbn_jitter,
    float march_start, float march_end, int step_count, out vec3 surface_position, out bool hit
) {
    vec3 sun_dir = normalize(u_world_sun_dir);
    // The phase terms depend only on the fixed cosines and the constant octave
    // factors, so they are evaluated once per light per ray.
#ifdef CLOUD_SINGLE_LIGHT
    // One traced direction: the antisolar fold. The sun keeps its colour through
    // the handover, see CloudTwilightWeight at the relight.
    float moonlight_factor = CloudMoonlightFactor(sun_dir.y);
    vec3 light_dir = CloudLightDirection(sun_dir, moonlight_factor);
    float light_cos_theta = clamp(dot(view_dir, light_dir), -1.0, 1.0);
    float light_phase_weight[CLOUD_MS_OCTAVES];
    CloudPhaseOctaves(light_cos_theta, light_phase_weight);
#else
    // Moon sits opposite the sun (no separate uniform); its view cosine is the
    // exact negation of the sun's. Each light keeps its own march and its own
    // earth-occlusion gate.
    vec3 moon_dir = -sun_dir;
    float sun_cos_theta = clamp(dot(view_dir, sun_dir), -1.0, 1.0);
    float sun_phase_weight[CLOUD_MS_OCTAVES];
    float moon_phase_weight[CLOUD_MS_OCTAVES];
    CloudPhaseOctaves(sun_cos_theta, sun_phase_weight);
    CloudPhaseOctaves(-sun_cos_theta, moon_phase_weight);
#endif
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
    // streams are decorrelated by their STBN slice offset (STBN_SLICE_LIGHT).
    float view_jitter = stbn_jitter.x;
    float light_jitter_base = stbn_jitter.y;
    float interval_length = march_end - march_start;
#ifdef CLOUD_SINGLE_LIGHT
    float light_radiance = 0.0;
#else
    float sun_radiance = 0.0;
    float moon_radiance = 0.0;
#endif
    vec3 surface_position_accumulator = vec3(0.0);
    float surface_weight = 0.0;
    float view_transmittance = 1.0;
    float inverse_step_count = 1.0 / float(step_count);
    float step_length = interval_length * inverse_step_count;

    for (int i = 0; i < CLOUD_VIEW_MAX_STEPS; ++i) {
        if (i >= step_count) break;
        // Shift the complete ray-march sequence by one shared jittered step;
        // independent per-segment offsets can line up with cloud height bands.
        float sample_distance = march_start + (float(i) + view_jitter) * step_length;

        vec3 sample_position = camera_atmosphere_pos + view_dir * sample_distance;
        float sample_density = SampleCloudDensity(sample_position);
        if (sample_density < 1.0e-4) continue;

        // Only PlanetHorizonOccluded consumes the squared radius below;
        // keep it off the erased-sample path.
        float sample_r2 = dot(sample_position, sample_position);

        // Per-sample scattering material, shared by both light channels.
        float sigma_t_per_m = sample_density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY * CLOUD_EXTINCTION_PER_KM_TO_PER_M;
        float reference_optical_depth = sigma_t_per_m * CLOUD_MS_REFERENCE_LENGTH_M;
        float isotropic_orders = CloudIsotropicOrders(
            reference_optical_depth, CLOUD_MS_SAT_ALBEDO, CLOUD_MS_ISOTROPIC);

        float light_jitter = fract(light_jitter_base + (float(i) + 0.5) * GOLDEN_RATIO);
#ifdef CLOUD_SINGLE_LIGHT
        float sample_light = 0.0;
        if (!PlanetHorizonOccluded(sample_position, sample_r2, light_dir, ATM_PLANET_R2)) {
            float light_optical_depth = CloudLightOpticalDepth(
                sample_position, light_dir, light_jitter);
            sample_light = CloudDirectionalScattering(light_phase_weight,
                octave_attenuation, light_optical_depth, isotropic_orders);
        }
#else
        float sample_sun = 0.0;
        if (!PlanetHorizonOccluded(sample_position, sample_r2, sun_dir, ATM_PLANET_R2)) {
            float light_optical_depth = CloudLightOpticalDepth(
                sample_position, sun_dir, light_jitter);
            sample_sun = CloudDirectionalScattering(sun_phase_weight,
                octave_attenuation, light_optical_depth, isotropic_orders);
        }
        float sample_moon = 0.0;
        if (!PlanetHorizonOccluded(sample_position, sample_r2, moon_dir, ATM_PLANET_R2)) {
            // Half-period offset decorrelates the moon march from the sun's.
            float moon_light_jitter = fract(light_jitter + 0.5);
            float light_optical_depth = CloudLightOpticalDepth(
                sample_position, moon_dir, moon_light_jitter);
            sample_moon = CloudDirectionalScattering(moon_phase_weight,
                octave_attenuation, light_optical_depth, isotropic_orders);
        }
#endif
        float optical_depth = sample_density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY
            * step_length;
        float segment_transmittance = exp(-optical_depth);
        float step_transmittance = view_transmittance;
        float segment_absorption = 1.0 - segment_transmittance;
        float segment_weight = step_transmittance * segment_absorption;
        surface_position_accumulator += sample_position * segment_weight;
        surface_weight += segment_weight;
#ifdef CLOUD_SINGLE_LIGHT
        light_radiance += segment_weight * sample_light;
#else
        sun_radiance += segment_weight * sample_sun;
        moon_radiance += segment_weight * sample_moon;
#endif
        view_transmittance *= segment_transmittance;
        if (view_transmittance < 1.0e-4) break;
    }

    hit = surface_weight > 1.0e-5;
    surface_position = surface_position_accumulator / max(surface_weight, 1.0e-5);
    // Packed output: x = in-scatter, y = second light channel, z = remaining
    // view transmittance.
#ifdef CLOUD_SINGLE_LIGHT
    // The folded trace feeds the directional channel; the channel the separate
    // moon march used to fill stays clear.
    return vec3(light_radiance, 0.0, view_transmittance);
#else
    return vec3(sun_radiance, moon_radiance, view_transmittance);
#endif
}

#endif // LIB_CLOUD_VOLUMETRIC_GLSL
