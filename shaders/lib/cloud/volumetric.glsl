#ifndef LIB_CLOUD_VOLUMETRIC_GLSL
#define LIB_CLOUD_VOLUMETRIC_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/core.glsl"
#include "/lib/scattering/phase.glsl"

// Vibroscat volumetric clouds.
//
// The scattering model is the HaringPro multiple-scattering approximation used
// by Revelation (Apache-2.0), transcribed from
//   shaders/lib/atmosphere/clouds/Render.glsl
//     CloudMultiScatteringApproxHaringPro + RenderClouds
// The multiple-scattering term itself follows
//   https://zhuanlan.zhihu.com/p/457997155
// See licenses/THIRD_PARTY_NOTICES.md section 19.
//
// Three deliberate deviations from upstream:
//   - the phase input stays this pack's dual-lobe HG (lib/scattering/phase.glsl)
//     instead of Revelation's baked Mie phase LUT, so no third-party texture or
//     custom image enters the pack;
//   - the directional term keeps this pack's three-octave HanPi sum, carried
//     alongside the HaringPro isotropic series rather than upstream's single
//     phase term;
//   - the light-path transmittance uses this pack's historical 1 / (1 + tau)
//     instead of upstream's Beer exp(-tau).

// --- HaringPro constants -----------------------------------------------
// The fms knee is calibrated on extinction in m^-1, so it is evaluated on the
// per-meter extinction even though this file marches in kilometers.
const float CLOUD_EXTINCTION_PER_KM_TO_PER_M = 0.001;
const float CLOUD_MS_FMS_SCALE = 300.0;
// 1 - fms only needs a guard against an albedo of exactly 1. At the default
// albedo the ratio peaks at 999 and never reaches this floor.
const float CLOUD_MS_FMS_FLOOR = 1.0e-4;
// HanPi directional octaves: each step widens the phase, weakens its
// contribution and softens the optical-depth falloff of the next order.
const int CLOUD_MS_OCTAVES = 3;

const float CLOUD_ALPHA_EXTINCTION_SRGB_GRAY = 100.0;
// The distribution atlas is sampled twice: a large-scale coverage read and a
// detail read. The scale keeps the two reads decorrelated.
const float CLOUD_DISTRIBUTION_UV_SCALE = 2.35;
// Large-scale coverage modulates the base coverage by this linear boost.
const float CLOUD_COVERAGE_BOOST_BASE = -0.1;
const float CLOUD_COVERAGE_BOOST_RANGE = 0.1;

bool CloudShellInterval(vec3 origin, vec3 dir, out float march_start, out float march_end
) {
    float inner_radius = ATM_PLANET_R + CLOUD_BASE_ALTITUDE;
    float outer_radius = ATM_PLANET_R + CLOUD_TOP_ALTITUDE;
    float outer_near;
    float outer_far;
    if (!RayIntersectSphere(origin, dir, outer_radius, outer_near, outer_far)) {
        return false;
    }

    march_start = max(outer_near, 0.0);
    march_end = outer_far;

    float inner_near;
    float inner_far;
    if (RayIntersectSphere(origin, dir, inner_radius, inner_near, inner_far)) {
        if (length(origin) < inner_radius) {
            march_start = max(march_start, inner_far);
        } else if (inner_near > march_start) {
            march_end = min(march_end, inner_near);
        }
    }

    float ground_near;
    float ground_far;
    if (RayIntersectSphere(origin, dir, ATM_PLANET_R, ground_near, ground_far)
            && ground_near > 0.0) {
        march_end = min(march_end, ground_near);
    }

    return march_end > march_start + 1.0e-5;
}

float CloudDistanceToShellExit(vec3 position, vec3 dir) {
    float outer_near;
    float outer_far;
    float outer_radius = ATM_PLANET_R + CLOUD_TOP_ALTITUDE;
    if (!RayIntersectSphere(position, dir, outer_radius, outer_near, outer_far)) {
        return 0.0;
    }

    float distance_to_exit = max(outer_far, 0.0);
    float inner_near;
    float inner_far;
    float inner_radius = ATM_PLANET_R + CLOUD_BASE_ALTITUDE;
    if (RayIntersectSphere(position, dir, inner_radius, inner_near, inner_far)
            && inner_near > 1.0e-5) {
        distance_to_exit = min(distance_to_exit, inner_near);
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

// Eroded density in [0, 1] at one point in the cloud layer.
float SampleCloudDensity(vec3 atmosphere_position) {
    float altitude_km = length(atmosphere_position) - ATM_PLANET_R;
    float height_fraction = Saturate((altitude_km - CLOUD_BASE_ALTITUDE)
        / max(CLOUD_TOP_ALTITUDE - CLOUD_BASE_ALTITUDE, 1.0e-5));

    if (altitude_km <= CLOUD_BASE_ALTITUDE || altitude_km >= CLOUD_TOP_ALTITUDE) {
        return 0.0;
    }

    vec2 world_km = atmosphere_position.xz + cameraPosition.xz * 0.001;
    vec2 distribution_uv = CloudDistributionUv(world_km);
    float distribution = texture(utex_cloud_distribution_tex, distribution_uv * CLOUD_DISTRIBUTION_UV_SCALE).r;
    // Rain pushes coverage toward full overcast.
    float coverage = (CLOUD_COVERAGE) * (1.0 - rainStrength) + rainStrength;
    float distribution_density = Saturate((distribution - (1.0 - coverage)) / max(coverage, 1.0e-5));
    float bottom_ramp = smoothstep(0.0, 0.15, height_fraction);
    // Push density away from the very bottom of the layer to keep the base soft.
    float height_penalty = Saturate((height_fraction - 0.15) / 0.85) * 0.5;
    // Fade the layer top; larger clouds get a thicker, softer cap.
    float top_fade = 1.0 - smoothstep(0.5, 1.0, height_fraction);
    float macro_density = Saturate(distribution_density - height_penalty)
        * bottom_ramp
        * top_fade;
    if (macro_density <= 0.01) {
        return 0.0;
    }
    vec3 erosion_uv = vec3(world_km.x, altitude_km, world_km.y) / CLOUD_EROSION_SCALE_KM;
    float low_freq_erosion = texture(utex_cloud_erosion_tex, erosion_uv).r;
    // R bakes the weighted darkness sum of the erosion stages (single
    // threshold). Stronger erosion higher in the layer, base floor.
    float height_exposure = smoothstep(0.0, 0.2, height_fraction) * 0.95 + 0.05;
    float broad_density = macro_density;
    float erosion_threshold = (1.0 - low_freq_erosion)
        * CLOUD_EROSION_STRENGTH
        * height_exposure;
    broad_density = RemapCloudErosion(broad_density, erosion_threshold);
    // RemapCloudErosion(0, threshold) saturates to exactly +0.0, so once the
    // broad pass erased the sample the fine fetch is dead; the early return is
    // already the bit-exact result.
    if (broad_density <= 0.0) {
        return 0.0;
    }
    vec3 fine_erosion_uv = vec3(world_km.x, altitude_km, world_km.y) / CLOUD_FINE_EROSION_SCALE_KM + vec3(
            frameTimeCounter * CLOUD_WIND_SPEED * CLOUD_FINE_WIND_FACTOR / CLOUD_FINE_EROSION_SCALE_KM, 0.0, 0.0);
    // Fine erosion texture: Perlin fBm pre-warped by a divergence-free curl
    // field (baked curved flow).
    float fine_erosion_noise = texture(utex_cloud_fine_erosion_tex, fine_erosion_uv).r;
    // A small base weight keeps fine erosion from fully erasing the base.
    float fine_height_weight = smoothstep(0.0, CLOUD_FINE_EROSION_HEIGHT, height_fraction) * 0.9 + 0.1;
    float fine_threshold = (1.0 - fine_erosion_noise)
        * CLOUD_FINE_EROSION_STRENGTH
        * fine_height_weight;
    return RemapCloudErosion(broad_density, fine_threshold);
}

// Optical depth from the receiver toward the light, over the same quadratic
// strata Revelation's CloudVolumeOpticalDepth uses: CLOUD_LIGHT_STEPS steps,
// densest at the receiver, each sampled at a jittered point inside its
// interval. Revelation weights the samples by (i + 0.5) and rescales by its own
// step length; this keeps the exact interval weight instead.
float CloudLightOpticalDepth(vec3 atmosphere_position, vec3 light_dir, float light_jitter) {
    float light_distance = min(
        CloudDistanceToShellExit(atmosphere_position, light_dir),
        CLOUD_LIGHT_MAX_DISTANCE_KM
    );
    if (light_distance <= 1.0e-5) return 0.0;

    float inverse_step_count = 1.0 / float(CLOUD_LIGHT_STEPS);
    float optical_depth = 0.0;
    for (int i = 0; i < CLOUD_LIGHT_STEPS; ++i) {
        float x0 = float(i) * inverse_step_count;
        float x1 = float(i + 1) * inverse_step_count;
        float segment_start = light_distance * x0 * x0;
        float segment_end = light_distance * x1 * x1;
        float sample_distance = mix(segment_start, segment_end, light_jitter);
        float sample_density = SampleCloudDensity(
            atmosphere_position + light_dir * sample_distance);
        optical_depth += sample_density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY
            * (segment_end - segment_start);
    }
    return optical_depth;
}

// Single-scattering albedo is applied here; light colors and intensity scaling
// stay at the relight consumer.
vec3 MarchVolumetricClouds(vec3 camera_atmosphere_pos, vec3 view_dir, vec2 stbn_jitter,
    float march_start, float march_end, int step_count, out vec3 surface_position, out bool hit
) {
    vec3 sun_dir = normalize(u_world_sun_dir);
    // Moon sits opposite the sun (no separate uniform); its view cosine is the
    // exact negation of the sun's. Each light keeps its own march and its own
    // earth-occlusion gate.
    vec3 moon_dir = -sun_dir;
    float sun_cos_theta = clamp(dot(view_dir, sun_dir), -1.0, 1.0);
    // Revelation samples one phase per ray from its Mie LUT; the pack keeps its
    // dual-lobe HG at the same point in the pipeline, once per octave. The
    // terms depend only on the fixed cosine and the constant octave factors, so
    // they are evaluated once per ray.
    float sun_phase_weight[CLOUD_MS_OCTAVES];
    float moon_phase_weight[CLOUD_MS_OCTAVES];
    float octave_attenuation[CLOUD_MS_OCTAVES];
    {
        float attenuation_factor = 1.0;
        float contribution_factor = 1.0;
        float eccentricity_factor = 1.0;
        for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
            float forward_g = CLOUD_PHASE_FORWARD_G * eccentricity_factor;
            float backward_g = CLOUD_PHASE_BACKWARD_G * eccentricity_factor;
            sun_phase_weight[octave] = PhaseHenyeyGreensteinDualLobe(
                sun_cos_theta, forward_g, backward_g) * contribution_factor;
            moon_phase_weight[octave] = PhaseHenyeyGreensteinDualLobe(
                -sun_cos_theta, forward_g, backward_g) * contribution_factor;
            octave_attenuation[octave] = attenuation_factor;
            attenuation_factor *= CLOUD_MS_ATTENUATION;
            contribution_factor *= CLOUD_MS_CONTRIBUTION;
            eccentricity_factor *= CLOUD_MS_ECCENTRICITY;
        }
    }

    // stbn_jitter is sampled by the pass main: the screen pass seeds it with
    // (view texel, frameCounter), the skybox with (skybox texel,
    // frameCounter / 4). x = view march jitter, y = light march base; the two
    // streams are decorrelated by their STBN slice offset (STBN_SLICE_LIGHT).
    float view_jitter = stbn_jitter.x;
    float light_jitter_base = stbn_jitter.y;
    float interval_length = march_end - march_start;
    float sun_radiance = 0.0;
    float moon_radiance = 0.0;
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

        // Per-sample scattering material, shared by both light channels. fms is
        // the energy still available after one more scattering event;
        // fms / (1 - fms) is the geometric series of every order past the
        // first, carried by the isotropic phase.
        float sigma_t_per_m = sample_density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY * CLOUD_EXTINCTION_PER_KM_TO_PER_M;
        float fms = CLOUD_MS_ALBEDO
            * (1.0 - exp2(-CLOUD_MS_FMS_SCALE * sigma_t_per_m));
        float isotropic_orders = PHASE_ISOTROPIC * fms
            / max(1.0 - fms, CLOUD_MS_FMS_FLOOR);

        float light_jitter = fract(light_jitter_base + (float(i) + 0.5) * GOLDEN_RATIO);
        float sample_sun = 0.0;
        if (!PlanetHorizonOccluded(sample_position, sample_r2, sun_dir, ATM_PLANET_R2)) {
            float light_optical_depth = CloudLightOpticalDepth(
                sample_position, sun_dir, light_jitter);
            // 1 / (1 + optical depth) approximates the falloff of the
            // additional scattering orders; each octave softens it further.
            float sun_octave_radiance = 0.0;
            for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
                sun_octave_radiance += sun_phase_weight[octave]
                    / (light_optical_depth * octave_attenuation[octave] + 1.0);
            }
            sample_sun = sun_octave_radiance
                + isotropic_orders / (1.0 + light_optical_depth);
        }
        float sample_moon = 0.0;
        if (!PlanetHorizonOccluded(sample_position, sample_r2, moon_dir, ATM_PLANET_R2)) {
            // Half-period offset decorrelates the moon march from the sun's.
            float moon_light_jitter = fract(light_jitter + 0.5);
            float light_optical_depth = CloudLightOpticalDepth(
                sample_position, moon_dir, moon_light_jitter);
            float moon_octave_radiance = 0.0;
            for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
                moon_octave_radiance += moon_phase_weight[octave]
                    / (light_optical_depth * octave_attenuation[octave] + 1.0);
            }
            sample_moon = moon_octave_radiance
                + isotropic_orders / (1.0 + light_optical_depth);
        }
        float optical_depth = sample_density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY
            * step_length;
        float segment_transmittance = exp(-optical_depth);
        float step_transmittance = view_transmittance;
        float segment_absorption = 1.0 - segment_transmittance;
        float segment_weight = step_transmittance * segment_absorption;
        surface_position_accumulator += sample_position * segment_weight;
        surface_weight += segment_weight;
        sun_radiance += segment_weight * sample_sun;
        moon_radiance += segment_weight * sample_moon;
        view_transmittance *= segment_transmittance;
        if (view_transmittance < 1.0e-4) break;
    }

    hit = surface_weight > 1.0e-5;
    surface_position = surface_position_accumulator / max(surface_weight, 1.0e-5);
    // Revelation scales the complete accumulated scattering by the
    // single-scattering albedo at the end of the march; the fms series carries
    // its own copy of it. Packed output: x = sun in-scatter, y = moon
    // in-scatter, z = remaining view transmittance.
    float albedo = CLOUD_MS_ALBEDO;
    return vec3(sun_radiance * albedo, moon_radiance * albedo, view_transmittance);
}

#endif
