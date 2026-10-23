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

    float inner_r2 = inner_radius * inner_radius;
    float inner_c = origin_r2 - inner_r2;
    float inner_discriminant = b * b - 4.0 * inner_c;
    if (inner_discriminant > 0.0) {
        float inner_root = sqrt(inner_discriminant);
        float inner_near = 0.5 * (-b - inner_root);
        float inner_far = 0.5 * (-b + inner_root);
        // Non-negative radii: the squared form selects identically and the
        // side comparison is not part of the root sequence above.
        if (origin_r2 < inner_r2) {
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
    vec3 camera_delta = u_camera_delta;
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
    threshold = saturate(threshold);
    return saturate((density - threshold) / max(1.0 - threshold, 1.0e-5));
}

// Distribution-space UV of a world-space XZ position. The first term is the
// per-sample one; the second is the wind scroll, which no sample changes and
// now arrives precomputed in CloudLayerFrame. Both scale factors are setting
// literals, so this stays a reciprocal multiply rather than a divide.
vec2 CloudDistributionUv(vec2 world_km, vec2 wind_offset) {
    return world_km * (1.0 / CLOUD_DISTRIBUTION_SCALE_KM) + wind_offset;
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

// Per-frame layer constants shared by both density functions. Coverage folds
// CLOUD_COVERAGE and rainStrength, so it is constant across every sample of
// every view and light march; the density functions used to rebuild it (and
// its max() guard) once per sample. distribution_floor is 1 - coverage and
// inv_coverage is the coverage floor reciprocal, both folded here so a sample
// spends one divide instead of a divide plus a max. world_km_offset is the
// camera term of the distribution-space position plus the wind scroll, which
// no sample changes: the distribution UV is world_km * scale + this offset.
struct CloudLayerFrame {
    float coverage;
    float distribution_floor;
    float inv_coverage;
    vec2 world_km_offset;
    vec2 distribution_offset;
};

CloudLayerFrame CloudLayerFrameForRay() {
    CloudLayerFrame frame;
    frame.coverage = CLOUD_COVERAGE * (1.0 - rainStrength) + rainStrength;
    frame.distribution_floor = 1.0 - frame.coverage;
    frame.inv_coverage = 1.0 / max(frame.coverage, 1.0e-5);
    frame.world_km_offset = u_cloud_world_km_offset;
    frame.distribution_offset = frame.world_km_offset * (1.0 / CLOUD_DISTRIBUTION_SCALE_KM)
        + vec2(frameTimeCounter * (CLOUD_WIND_SPEED / CLOUD_DISTRIBUTION_SCALE_KM), 0.0);
    return frame;
}

// Normalized height in the cloud layer plus the two ramps that depend only on
// it. Both ramps are frozen baseline expressions: the top pair is the
// intentionally reversed smoothstep (edge0 > edge1) documented at its call
// site, kept verbatim. Rebuilding them per sample cost four smoothsteps per
// accepted sample; they are pure functions of the sample height.
struct CloudHeightProfile {
    float height_fraction;
    float bottom_ramp;
    float fine_exposure;
};

CloudHeightProfile CloudHeightProfileFor(float altitude_km) {
    CloudHeightProfile profile;
    profile.height_fraction = saturate((altitude_km - CLOUD_BASE_ALTITUDE)
        / max(CLOUD_TOP_ALTITUDE - CLOUD_BASE_ALTITUDE, 1.0e-5));
    profile.bottom_ramp = smoothstep(0.0, 0.2, profile.height_fraction);
    profile.fine_exposure = smoothstep(0.0, 0.5, profile.height_fraction) * 0.6 + 0.4;
    return profile;
}

// Eroded density in [0, 1] at one point in the cloud layer. The band test the
// callers used to keep here is now the callers' own (they need the raw
// altitude for CloudHeightProfileFor anyway), so the cheap rejection and the
// height profile are evaluated once per sample instead of twice.
float SampleCloudDensity(vec3 atmosphere_position, CloudLayerFrame frame, CloudHeightProfile profile
) {
    vec2 density_world_km = atmosphere_position.xz + frame.world_km_offset;
    float distribution_density = saturate((
        texture(utex_cloud_distribution_tex,
            CloudDistributionUv(density_world_km, frame.distribution_offset)).r
        - frame.distribution_floor) * frame.inv_coverage);
    if(distribution_density < 0.001) {
        return 0.0;
    }
    // Reversed edge pair (edge0 > edge1): undefined by the GLSL spec, but the
    // common clamp((x-e0)/(e1-e0)) implementation is deterministic and the
    // rendered ramp below is the frozen baseline for the 2026-10 optimization
    // series. Do not swap or rewrite this pair without a visual re-baseline.
    // Both ramps now ride CloudHeightProfileFor, which reproduces its
    // smoothsteps verbatim; only the number of evaluations changed.
    float top_fade = smoothstep(distribution_density * 0.5 + 0.5, distribution_density * 0.4,
        profile.height_fraction);
    float lq_density = distribution_density * profile.bottom_ramp * top_fade;
    if(lq_density < 0.001) {
        return 0.0;
    }
    float detailed_noise = texture(utex_cloud_voronoise_tex,
        vec3(density_world_km, length(atmosphere_position) - ATM_PLANET_R) * CLOUD_FINE_EROSION_SCALE).r;
    float hq_density = RemapCloudErosion(lq_density,
        detailed_noise * CLOUD_FINE_EROSION_STRENGTH * profile.fine_exposure);
    return hq_density;
}

// Baked R8 volume means, sum(bytes) / (255 * sample count): the convention
// the bakes quantify in. The low-quality light-trace paths replace their
// per-point 3D reads with these, keeping the expected erosion threshold
// equal to the view path while dropping the 3D reads per light step.
const float CLOUD_VORONOISE_MEAN = 0.484805118;
const float CLOUD_EROSION_COMPOSITE_MEAN = 0.533126322;

// Low-quality density for the light-transport trace: the same field with the
// voronoise threshold replaced by the baked texture mean times the same
// CLOUD_FINE_EROSION_STRENGTH * fine_exposure scale, which keeps the expected
// threshold equal to the view path and saves one 3D read per light step.
float SampleCloudDensityLowQuality(vec3 atmosphere_position, CloudLayerFrame frame, CloudHeightProfile profile
) {
    float distribution_density = saturate((
        texture(utex_cloud_distribution_tex,
            CloudDistributionUv(atmosphere_position.xz + frame.world_km_offset,
                frame.distribution_offset)).r
        - frame.distribution_floor) * frame.inv_coverage);
    if(distribution_density < 0.001) {
        return 0.0;
    }
    // Same intentionally reversed smoothstep pair as SampleCloudDensity; keep
    // the two implementations bit-identical on this ramp.
    float top_fade = smoothstep(distribution_density * 0.5 + 0.5, distribution_density * 0.4,
        profile.height_fraction);
    float lq_density = distribution_density * profile.bottom_ramp * top_fade;

    float hq_density = RemapCloudErosion(lq_density,
        CLOUD_VORONOISE_MEAN * CLOUD_FINE_EROSION_STRENGTH * profile.fine_exposure);
    return hq_density;
}

#if CLOUD_SHAPE_MODE == 1

const float CLOUD_DISTRIBUTION_UV_OFFSET = 0.114514;

float SampleCloudDensityHighQuality(vec3 atmosphere_position, CloudLayerFrame frame, CloudHeightProfile profile
) {
    vec2 density_world_km = atmosphere_position.xz + frame.world_km_offset;
    vec2 distribution_uv = CloudDistributionUv(density_world_km, frame.distribution_offset);
    float large_scale_cloud = texture(utex_cloud_distribution_tex,
        distribution_uv + vec2(CLOUD_DISTRIBUTION_UV_OFFSET, 0.0)).r;
    float distribution_density = saturate((
        texture(utex_cloud_distribution_tex, distribution_uv).r
        - frame.distribution_floor) * frame.inv_coverage);
    if(distribution_density < 0.001) {
        return 0.0;
    }
    float bottom_ramp = smoothstep(0.0, 0.2 - large_scale_cloud * 0.1,
        profile.height_fraction);
    float height_penalty = saturate((profile.height_fraction - 0.15) / 0.85) * 0.5;
    float top_fade = 1.0 - smoothstep(0.2 + large_scale_cloud * large_scale_cloud * 0.4, 1.0,
        profile.height_fraction);
    float macro_density = saturate(distribution_density - height_penalty) * bottom_ramp * top_fade;
    if(macro_density < 0.001) {
        return 0.0;
    }

    // Broad erosion exposure ramps up with height on the shared bottom_ramp.
    float height_exposure = profile.bottom_ramp * 0.95 + 0.05;
    vec3 erosion_coordinates = vec3(density_world_km, length(atmosphere_position) - ATM_PLANET_R);
    float broad_density = RemapCloudErosion(macro_density,
        texture(utex_cloud_erosion_tex,
            erosion_coordinates * (1.0 / CLOUD_HQ_EROSION_SCALE_KM)).r
            * CLOUD_HQ_EROSION_STRENGTH * height_exposure);

    // Fine detail fades in with height so the condensation base stays smooth.
    float fine_weight = smoothstep(0.0, CLOUD_HQ_FINE_EROSION_HEIGHT, profile.height_fraction) * 0.9 + 0.1;
    return RemapCloudErosion(broad_density,
        texture(utex_cloud_voronoise_tex,
            erosion_coordinates * CLOUD_HQ_FINE_EROSION_SCALE).r
            * CLOUD_HQ_FINE_EROSION_STRENGTH * fine_weight);
}

// Low-quality high-end density for the light-transport trace: the same field
// with both 3D reads replaced by their baked means, keeping both expected
// erosion thresholds equal to the high-end view path.
float SampleCloudDensityHighQualityLowQuality(vec3 atmosphere_position, CloudLayerFrame frame, CloudHeightProfile profile
) {
    vec2 distribution_uv = CloudDistributionUv(atmosphere_position.xz + frame.world_km_offset,
        frame.distribution_offset);
    float large_scale_cloud = texture(utex_cloud_distribution_tex,
        distribution_uv + vec2(CLOUD_DISTRIBUTION_UV_OFFSET, 0.0)).r;
    float distribution_density = saturate((
        texture(utex_cloud_distribution_tex, distribution_uv).r
        - frame.distribution_floor) * frame.inv_coverage);
    if(distribution_density < 0.001) {
        return 0.0;
    }
    float bottom_ramp = smoothstep(0.0, 0.2 - large_scale_cloud * 0.1,
        profile.height_fraction);
    float height_penalty = saturate((profile.height_fraction - 0.15) / 0.85) * 0.5;
    float top_fade = 1.0 - smoothstep(0.2 + large_scale_cloud * large_scale_cloud * 0.4, 1.0,
        profile.height_fraction);
    float macro_density = saturate(distribution_density - height_penalty) * bottom_ramp * top_fade;

    float height_exposure = profile.bottom_ramp * 0.95 + 0.05;
    float broad_density = RemapCloudErosion(macro_density,
        CLOUD_EROSION_COMPOSITE_MEAN * CLOUD_HQ_EROSION_STRENGTH * height_exposure);
    float fine_weight = smoothstep(0.0, CLOUD_HQ_FINE_EROSION_HEIGHT, profile.height_fraction) * 0.9 + 0.1;
    return RemapCloudErosion(broad_density,
        CLOUD_VORONOISE_MEAN * CLOUD_HQ_FINE_EROSION_STRENGTH * fine_weight);
}
#endif // CLOUD_SHAPE_MODE == 1

// Optical depth toward the light, starting past a configurable near segment.
// CLOUD_LIGHT_STEPS quadratic strata are densest near that start; each is
// sampled at a jittered point and weighted by its exact interval length.
// Densities take the low-quality path; every accepted view sample retraces it.
float CloudLightOpticalDepth(vec3 atmosphere_position, vec3 light_dir, float light_jitter,
    CloudLayerFrame frame
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
        // Same cheap band rejection the density functions used to open with.
        if (sample_altitude_km > CLOUD_BASE_ALTITUDE && sample_altitude_km < CLOUD_TOP_ALTITUDE) {
#if CLOUD_SHAPE_MODE == 1
            sample_density = SampleCloudDensityHighQualityLowQuality(sample_position, frame,
                CloudHeightProfileFor(sample_altitude_km));
#else
            sample_density = SampleCloudDensityLowQuality(sample_position, frame,
                CloudHeightProfileFor(sample_altitude_km));
#endif
        }
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
    vec3 sun_dir = u_world_sun_dir;
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
    // Moon direction is u_world_moon_dir, the host-built antipode of the sun;
    // its view cosine is the exact negation of the sun's. Each light keeps its
    // own march and its own earth-occlusion gate.
    vec3 moon_dir = u_world_moon_dir;
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
    // streams are decorrelated by the STBN stream offset (STBN_STREAM_3).
    float view_jitter = stbn_jitter.x;
    float light_jitter_base = stbn_jitter.y;
    float interval_length = march_end - march_start;
    // Coverage folds rainStrength, which no sample of this ray changes; build
    // the layer constants once instead of once per sample in each density call.
    CloudLayerFrame layer_frame = CloudLayerFrameForRay();
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
    float extinction_per_step = CLOUD_ALPHA_EXTINCTION_SRGB_GRAY * step_length;

    for (int i = 0; i < CLOUD_VIEW_MAX_STEPS; ++i) {
        if (i >= step_count) break;
        // Shift the complete ray-march sequence by one shared jittered step;
        // independent per-segment offsets can line up with cloud height bands.
        float sample_distance = march_start + (float(i) + view_jitter) * step_length;

        vec3 sample_position = camera_atmosphere_pos + view_dir * sample_distance;
        // The band test and the two height ramps are evaluated once per sample
        // here; both density paths used to repeat them (four smoothsteps per
        // accepted sample before this change).
        float sample_altitude_km = length(sample_position) - ATM_PLANET_R;
        if (sample_altitude_km <= CLOUD_BASE_ALTITUDE || sample_altitude_km >= CLOUD_TOP_ALTITUDE) continue;
        CloudHeightProfile sample_height = CloudHeightProfileFor(sample_altitude_km);
#if CLOUD_SHAPE_MODE == 1
        float sample_density = SampleCloudDensityHighQuality(sample_position, layer_frame, sample_height);
#else
        float sample_density = SampleCloudDensity(sample_position, layer_frame, sample_height);
#endif
        if (sample_density < 1.0e-4) continue;

        // Only PlanetHorizonOccluded consumes the squared radius below;
        // keep it off the erased-sample path.
        float sample_r2 = dot(sample_position, sample_position);

        // Per-sample scattering material, shared by both light channels. The
        // three constants are folded into one per-sample multiply.
        float reference_optical_depth = sample_density
            * (CLOUD_ALPHA_EXTINCTION_SRGB_GRAY * CLOUD_EXTINCTION_PER_KM_TO_PER_M
                * CLOUD_MS_REFERENCE_LENGTH_M);
        float isotropic_orders = CloudIsotropicOrders(
            reference_optical_depth, CLOUD_MS_SAT_ALBEDO, CLOUD_MS_ISOTROPIC);

#ifdef CLOUD_SINGLE_LIGHT
        float sample_light = 0.0;
        // The jitter only feeds the light trace, so compute it after the
        // horizon test has skipped erased samples.
        if (!PlanetHorizonOccluded(sample_position, sample_r2, light_dir, ATM_PLANET_R2)) {
            float light_jitter = fract(light_jitter_base + (float(i) + 0.5) * GOLDEN_RATIO);
            float light_optical_depth = CloudLightOpticalDepth(
                sample_position, light_dir, light_jitter, layer_frame);
            sample_light = CloudDirectionalScattering(light_phase_weight,
                octave_attenuation, light_optical_depth, isotropic_orders);
        }
#else
        float light_jitter = fract(light_jitter_base + (float(i) + 0.5) * GOLDEN_RATIO);
        float sample_sun = 0.0;
        if (!PlanetHorizonOccluded(sample_position, sample_r2, sun_dir, ATM_PLANET_R2)) {
            float light_optical_depth = CloudLightOpticalDepth(
                sample_position, sun_dir, light_jitter, layer_frame);
            sample_sun = CloudDirectionalScattering(sun_phase_weight,
                octave_attenuation, light_optical_depth, isotropic_orders);
        }
        float sample_moon = 0.0;
        if (!PlanetHorizonOccluded(sample_position, sample_r2, moon_dir, ATM_PLANET_R2)) {
            // Half-period offset decorrelates the moon march from the sun's.
            float moon_light_jitter = fract(light_jitter + 0.5);
            float light_optical_depth = CloudLightOpticalDepth(
                sample_position, moon_dir, moon_light_jitter, layer_frame);
            sample_moon = CloudDirectionalScattering(moon_phase_weight,
                octave_attenuation, light_optical_depth, isotropic_orders);
        }
#endif
        float optical_depth = sample_density * extinction_per_step;
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
