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
// The isotropic multiple-scattering field (phi_fwd) implemented in this file
// is derived from HanPi Volume Cloud (HPVolumeCloud) by AshenOneArt:
//   https://github.com/AshenOneArt/HPVolumeCloud
//   Docs/PhiFwd_FromRTE.md (upstream repo)
// HPVolumeCloud is MIT licensed with an additional attribution requirement;
// see licenses/THIRD_PARTY_NOTICES.md section 2.

const float CLOUD_MAX_DISTANCE_KM = 180.0;
const int CLOUD_MS_OCTAVES = 3;
const float CLOUD_PHI_OMEGA0 = 0.75;
const float CLOUD_ALPHA_EXTINCTION_SRGB_GRAY = 100.0;
const float CLOUD_ALPHA_SCATTERING_SRGB_GRAY = CLOUD_ALPHA_EXTINCTION_SRGB_GRAY * CLOUD_PHI_OMEGA0;
// Isotropic multiple-scattering build rate: sigma_iso ~= (1 - g) * sigma_t
// (PhiFwd_FromRTE.md section 5.3), using the forward HG eccentricity as g.
const float CLOUD_PHI_BUILD_SCALE = 0.15;
// The distribution atlas is sampled twice: a large-scale coverage read and a
// detail read. The offset and scale keep the two reads decorrelated.
const float CLOUD_DISTRIBUTION_UV_OFFSET = 0.114514;
const float CLOUD_DISTRIBUTION_UV_SCALE = 2.35;
// Large-scale coverage modulates the base coverage by this linear boost.
const float CLOUD_COVERAGE_BOOST_BASE = -0.1;
const float CLOUD_COVERAGE_BOOST_RANGE = 0.1;

struct CloudDensitySample {
    float density;
    float height_fraction;
};

struct CloudLightTransport {
    float optical_depth;
    float isotropic_diffuse;
};

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

    march_end = min(march_end, CLOUD_MAX_DISTANCE_KM);
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

// HP boundary confidence uses a cloud-top height proxy, not density or optical
// depth. This project has no separate weather coverage-height LUT, so mirror
// the actual top-fade driver used by SampleCloudDensity: the large-scale read
// controls the lower edge of the top fade over [start, 1]. Its midpoint is the
// effective top height used for the finite-difference normal.
float CloudBoundaryHeightProxy(vec2 world_km) {
    vec2 distribution_uv = CloudDistributionUv(world_km);
    float large_scale_cloud = texture(utex_cloud_distribution_tex,
        distribution_uv + vec2(CLOUD_DISTRIBUTION_UV_OFFSET, 0.0)).r;
    float top_fade_start = 0.2 + large_scale_cloud * large_scale_cloud * 0.4;
    return Saturate(0.5 * (top_fade_start + 1.0));
}

// HP's boundary term: finite-difference the top height, build the top normal,
// and apply a wrap(N dot L) response. The caller passes a normalized light dir.
float CloudBoundaryBacklight(vec2 world_km, vec3 light_dir) {
    const float sample_step = CLOUD_DISTRIBUTION_SCALE_KM * (1.0 / 1024.0);
    float height_left = CloudBoundaryHeightProxy(world_km - vec2(sample_step, 0.0));
    float height_right = CloudBoundaryHeightProxy(world_km + vec2(sample_step, 0.0));
    float height_down = CloudBoundaryHeightProxy(world_km - vec2(0.0, sample_step));
    float height_up = CloudBoundaryHeightProxy(world_km + vec2(0.0, sample_step));
    float slab_thickness = max(CLOUD_TOP_ALTITUDE - CLOUD_BASE_ALTITUDE, 1.0e-3);
    float height_gradient_x = (height_right - height_left) * slab_thickness / max(2.0 * sample_step, 1.0e-3);
    float height_gradient_z = (height_up - height_down) * slab_thickness / max(2.0 * sample_step, 1.0e-3);
    vec3 top_normal = normalize(vec3(-height_gradient_x, 1.0, -height_gradient_z));
    float ndotl = dot(top_normal, light_dir);
    const float wrap = 0.5;
    float boundary_lit = Saturate((ndotl + wrap) / (1.0 + wrap));
    return mix(1.0, boundary_lit, Saturate(CLOUD_MS_BOUNDARY_CONFIDENCE));
}

CloudDensitySample SampleCloudDensity(vec3 atmosphere_position) {
    CloudDensitySample result;
    result.density = 0.0;
    float altitude_km = length(atmosphere_position) - ATM_PLANET_R;
    result.height_fraction = Saturate((altitude_km - CLOUD_BASE_ALTITUDE)
        / max(CLOUD_TOP_ALTITUDE - CLOUD_BASE_ALTITUDE, 1.0e-5));

    if (altitude_km <= CLOUD_BASE_ALTITUDE || altitude_km >= CLOUD_TOP_ALTITUDE) {
        return result;
    }

    vec2 world_km = atmosphere_position.xz + cameraPosition.xz * 0.001;
    vec2 distribution_uv = CloudDistributionUv(world_km);
    // float large_scale_cloud = texture(utex_cloud_distribution_tex, distribution_uv + vec2(CLOUD_DISTRIBUTION_UV_OFFSET, 0.0)).r;
    float distribution = texture(utex_cloud_distribution_tex, distribution_uv * CLOUD_DISTRIBUTION_UV_SCALE).r;
    // Rain pushes coverage toward full overcast.
    float coverage = (CLOUD_COVERAGE) * (1.0 - rainStrength) + rainStrength;
    float distribution_density = Saturate((distribution - (1.0 - coverage)) / max(coverage, 1.0e-5));
    float bottom_ramp = smoothstep(0.0, 0.15, result.height_fraction);
    // Push density away from the very bottom of the layer to keep the base soft.
    float height_penalty = Saturate((result.height_fraction - 0.15) / 0.85) * 0.5;
    // Fade the layer top; larger clouds get a thicker, softer cap.
    float top_fade = 1.0 - smoothstep(0.5, 1.0, result.height_fraction);
    float macro_density = Saturate(distribution_density - height_penalty)
        * bottom_ramp
        * top_fade;
    if (macro_density <= 0.01) {
        return result;
    }
    vec3 erosion_uv = vec3(world_km.x, altitude_km, world_km.y) / CLOUD_EROSION_SCALE_KM;
    float low_freq_erosion = texture(utex_cloud_erosion_tex, erosion_uv).r;
    // R bakes the weighted darkness sum of the erosion stages (single
    // threshold). Stronger erosion higher in the layer, base floor.
    float height_exposure = smoothstep(0.0, 0.2, result.height_fraction) * 0.95 + 0.05;
    float broad_density = macro_density;
    float erosion_threshold = (1.0 - low_freq_erosion)
        * CLOUD_EROSION_STRENGTH
        * height_exposure;
    broad_density = RemapCloudErosion(broad_density, erosion_threshold);
    // RemapCloudErosion(0, threshold) saturates to exactly +0.0, so once the
    // broad pass erased the sample the fine fetch is dead; the initialized
    // density is already the bit-exact result.
    if (broad_density > 0.0) {
        vec3 fine_erosion_uv = vec3(world_km.x, altitude_km, world_km.y) / CLOUD_FINE_EROSION_SCALE_KM + vec3(
                frameTimeCounter * CLOUD_WIND_SPEED * CLOUD_FINE_WIND_FACTOR / CLOUD_FINE_EROSION_SCALE_KM, 0.0, 0.0);
        // Fine erosion texture: Perlin fBm pre-warped by a divergence-free curl
        // field (baked curved flow).
        float fine_erosion_noise = texture(utex_cloud_fine_erosion_tex, fine_erosion_uv).r;
        // A small base weight keeps fine erosion from fully erasing the base.
        float fine_height_weight = smoothstep(0.0, CLOUD_FINE_EROSION_HEIGHT, result.height_fraction) * 0.9 + 0.1;
        float fine_threshold = (1.0 - fine_erosion_noise)
            * CLOUD_FINE_EROSION_STRENGTH
            * fine_height_weight;
        result.density = RemapCloudErosion(broad_density, fine_threshold);
    }
    return result;
}

// phi_fwd: HPVolumeCloud isotropic multiple-scattering port. See the file
// header for attribution and the derivation in Docs/PhiFwd_FromRTE.md.
CloudLightTransport SampleCloudLightTransport(vec3 atmosphere_position, vec3 light_dir, float light_jitter) {
    CloudLightTransport transport;
    transport.optical_depth = 0.0;
    transport.isotropic_diffuse = 0.0;

    float light_distance = min(CloudDistanceToShellExit(atmosphere_position, light_dir), CLOUD_LIGHT_MAX_DISTANCE_KM);
    if (light_distance <= 1.0e-5) return transport;

    float inverse_step_count = 1.0 / float(CLOUD_LIGHT_STEPS);

    // March from the receiver toward the sun, matching HPVolumeCloud's source
    // semantics. Every source's build/propagation depth is measured from the
    // receiver, and all exponentials remain non-positive.
    float one_minus_omega0 = 1.0 - CLOUD_PHI_OMEGA0;
    float kappa_per_optical_depth = sqrt(3.0 * one_minus_omega0);
    float total_optical_depth = 0.0;
    float weighted_source_sum = 0.0;

    // Transform fixed x^2 strata into physical distance. Jitter moves the
    // source within each stratum while the segment width remains deterministic;
    // this keeps prefix optical depth stable for the nonlinear phi_fwd terms.
    for (int i = 0; i < CLOUD_LIGHT_STEPS; ++i) {
        float x0 = float(i) * inverse_step_count;
        float x1 = float(i + 1) * inverse_step_count;
        float segment_start = light_distance * x0 * x0;
        float segment_end = light_distance * x1 * x1;
        float interval_weight = segment_end - segment_start;
        float sample_distance = mix(segment_start, segment_end, light_jitter);
        float sample_offset = sample_distance - segment_start;
        vec3 source_position = atmosphere_position + light_dir * sample_distance;
        CloudDensitySample density_sample = SampleCloudDensity(source_position);
        float cloud_density = density_sample.density;
        // With zero density the scattering source is +0.0 and every other
        // factor is finite, so both accumulators would gain exactly +0.0;
        // skipping the step body is bit-exact and sparse skies spend most
        // light steps here.
        if (cloud_density > 0.01) {
            float sigma_t = cloud_density * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY;
            float sigma_s = cloud_density * CLOUD_ALPHA_SCATTERING_SRGB_GRAY;
            float segment_optical_depth = sigma_t * interval_weight;
            // sigma_tr ~= sigma_t in the isotropic regime: the source carries the
            // 1/D scale.
            float scattering_source = sigma_s * interval_weight;
            float optical_depth_from_receiver = total_optical_depth + sigma_t * sample_offset;
            float isotropic_build = 1.0 - exp(-optical_depth_from_receiver * CLOUD_PHI_BUILD_SCALE);
            float inverse_distance = 1.0 / max(sample_distance, 1.0e-4);
            // HP's source confidence is evaluated at each light-ray source. The
            // bottom term uses the local source height; the boundary term uses
            // that source's XZ position.
            float source_bottom_height = max(density_sample.height_fraction + CLOUD_MS_DEPTH_BIAS, 0.0);
            float source_bottom_confidence = 1.0 - exp(-source_bottom_height * CLOUD_MS_DEPTH_POWER);
            vec2 source_world_km = source_position.xz + cameraPosition.xz * 0.001;
            float source_boundary_confidence = CloudBoundaryBacklight(source_world_km, light_dir);
            float source_confidence = source_bottom_confidence * source_boundary_confidence;
            // HP's T_cum is the receiver-to-source absorption before this
            // segment; propagation reaches the jittered source point.
            float source_absorption = exp(-one_minus_omega0 * total_optical_depth);
            float source_propagation = exp(-kappa_per_optical_depth * optical_depth_from_receiver);
            weighted_source_sum += source_absorption
                * source_propagation
                * scattering_source
                * sigma_t
                * isotropic_build
                * inverse_distance
                * source_confidence;
            total_optical_depth += segment_optical_depth;
        }
    }
    transport.optical_depth = total_optical_depth;

    transport.isotropic_diffuse = weighted_source_sum * PHASE_ISOTROPIC;
    return transport;
}

float MapCloudIsotropicDiffuse(float isotropic_diffuse) {
    // Apply the soft saturation to the final phi_fwd scalar only. Boundary
    // confidence and the sun-line integration remain linear inputs to it.
    float phi_fwd_scalar = isotropic_diffuse * CLOUD_PHI_INTENSITY;
    if (CLOUD_PHI_COMPRESSION > 0.0) {
        return (1.0 - exp(-phi_fwd_scalar * CLOUD_PHI_COMPRESSION)) / CLOUD_PHI_COMPRESSION;
    }
    return phi_fwd_scalar;
}

vec3 MarchVolumetricClouds(vec3 camera_atmosphere_pos, vec3 view_dir, vec2 stbn_jitter,
    float march_start, float march_end, int step_count, out vec3 surface_position, out bool hit
) {
    vec3 sun_dir = normalize(u_world_sun_dir);
    // Moon sits opposite the sun (no separate uniform); its view cosine is the
    // exact negation of the sun's. Each light is gated by earth occlusion below.
    vec3 moon_dir = -sun_dir;
    float sun_cos_theta = clamp(dot(view_dir, sun_dir), -1.0, 1.0);
    // Phase terms depend only on the fixed cosine + constant octave factors:
    // evaluated once per ray.
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
            sun_phase_weight[octave] = PhaseHenyeyGreensteinDualLobe(sun_cos_theta, forward_g, backward_g)
                * contribution_factor;
            moon_phase_weight[octave] = PhaseHenyeyGreensteinDualLobe(-sun_cos_theta, forward_g, backward_g)
                * contribution_factor;
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
    float direct_sun_radiance = 0.0;
    float direct_moon_radiance = 0.0;
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
        CloudDensitySample density_sample = SampleCloudDensity(sample_position);
        if (density_sample.density < 1.0e-4) continue;

        // Only PlanetHorizonOccluded consumes the squared radius below;
        // keep it off the erased-sample path.
        float sample_r2 = dot(sample_position, sample_position);

        float light_jitter = fract(light_jitter_base + (float(i) + 0.5) * 0.61803398875);
        float sample_sun_radiance = 0.0;
        float sample_moon_radiance = 0.0;
        if (!PlanetHorizonOccluded(sample_position, sample_r2, sun_dir, ATM_PLANET_R2)) {
            CloudLightTransport sun_transport = SampleCloudLightTransport(sample_position, sun_dir, light_jitter);
            float directional_sun_radiance = 0.0;
            for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
                // 1 / (1 + accumulated optical depth) approximates the
                // falloff of additional scattering orders.
                directional_sun_radiance += sun_phase_weight[octave] / (sun_transport.optical_depth
                        * octave_attenuation[octave] + 1.0);
            }
            sample_sun_radiance = directional_sun_radiance
                * CLOUD_PHI_OMEGA0
                + MapCloudIsotropicDiffuse(sun_transport.isotropic_diffuse);
        }
        if (!PlanetHorizonOccluded(sample_position, sample_r2, moon_dir, ATM_PLANET_R2)) {
            // Half-period offset decorrelates the moon march from the sun's.
            float moon_light_jitter = fract(light_jitter + 0.5);
            CloudLightTransport moon_transport = SampleCloudLightTransport(sample_position, moon_dir, moon_light_jitter);
            float directional_moon_radiance = 0.0;
            for (int octave = 0; octave < CLOUD_MS_OCTAVES; ++octave) {
                directional_moon_radiance += moon_phase_weight[octave] / (moon_transport.optical_depth
                        * octave_attenuation[octave] + 1.0);
            }
            sample_moon_radiance = directional_moon_radiance
                * CLOUD_PHI_OMEGA0
                + MapCloudIsotropicDiffuse(moon_transport.isotropic_diffuse);
        }
        float optical_depth = density_sample.density
            * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY
            * step_length;
        float segment_transmittance = exp(-optical_depth);
        float step_transmittance = view_transmittance;
        float segment_absorption = 1.0 - segment_transmittance;
        float segment_weight = step_transmittance * segment_absorption;
        surface_position_accumulator += sample_position * segment_weight;
        surface_weight += segment_weight;
        direct_sun_radiance += segment_weight
            * sample_sun_radiance;
        direct_moon_radiance += segment_weight
            * sample_moon_radiance;
        view_transmittance *= segment_transmittance;
        if (view_transmittance < 1.0e-4) break;
    }

    hit = surface_weight > 1.0e-5;
    surface_position = surface_position_accumulator / max(surface_weight, 1.0e-5);
    // Packed output: x = normalized sun irradiance, y = normalized moon
    // irradiance, z = remaining view transmittance.
    return vec3(direct_sun_radiance, direct_moon_radiance, view_transmittance);
}

#endif
