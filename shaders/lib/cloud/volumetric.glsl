#ifndef LIB_CLOUD_VOLUMETRIC_GLSL
#define LIB_CLOUD_VOLUMETRIC_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/atmosphere/core.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"

// Vibroscat volumetric clouds.
//
// The isotropic multiple-scattering field (phi_fwd) implemented in this file
// is derived from HanPi Volume Cloud (HPVolumeCloud) by AshenOneArt:
//   https://github.com/AshenOneArt/HPVolumeCloud
//   Docs/PhiFwd_FromRTE.md (upstream repo)
// HPVolumeCloud is MIT licensed with an additional attribution requirement;
// see licenses/THIRD_PARTY_NOTICES.md section 2.

#include "/lib/atmosphere/atmosphere_geometry.glsl"

const float CLOUD_MAX_DISTANCE_KM = 180.0;
const int CLOUD_MS_OCTAVES = 3;
const float CLOUD_PHI_OMEGA0 = 0.94;
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

// Light below the local horizon is planet-occluded: near sphere intersection
// only (no far root); caller passes r² to share the dot product.
bool CloudLightBlockedByEarth(vec3 atmosphere_position, float atmosphere_r2, vec3 light_dir
) {
    float b = 2.0 * dot(atmosphere_position, light_dir);
    float c = atmosphere_r2 - ATM_PLANET_R2;
    float discriminant = b * b - 4.0 * c;
    if (discriminant <= 0.0) return false;

    float ground_near = 0.5 * (-b - sqrt(discriminant));
    return ground_near > 1.0e-5;
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
    float sample_step = CLOUD_DISTRIBUTION_SCALE_KM
        / max(float(textureSize(utex_cloud_distribution_tex, 0).x), 1.0);
    float hL = CloudBoundaryHeightProxy(world_km - vec2(sample_step, 0.0));
    float hR = CloudBoundaryHeightProxy(world_km + vec2(sample_step, 0.0));
    float hD = CloudBoundaryHeightProxy(world_km - vec2(0.0, sample_step));
    float hU = CloudBoundaryHeightProxy(world_km + vec2(0.0, sample_step));
    float slab_thickness = max(CLOUD_TOP_ALTITUDE - CLOUD_BASE_ALTITUDE, 1.0e-3);
    float dHdx = (hR - hL) * slab_thickness / max(2.0 * sample_step, 1.0e-3);
    float dHdz = (hU - hD) * slab_thickness / max(2.0 * sample_step, 1.0e-3);
    vec3 top_normal = normalize(vec3(-dHdx, 1.0, -dHdz));
    float n_dot_l = dot(top_normal, light_dir);
    const float wrap = 0.5;
    float boundary_lit = Saturate((n_dot_l + wrap) / (1.0 + wrap));
    return mix(1.0, boundary_lit, Saturate(CLOUD_MS_BOUNDARY_CONFIDENCE));
}

CloudDensitySample SampleCloudDensity(vec3 atmosphere_position, vec3 camera_atmosphere_pos
) {
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
    float large_scale_cloud = texture(utex_cloud_distribution_tex, distribution_uv + vec2(CLOUD_DISTRIBUTION_UV_OFFSET, 0.0)).r;
    float distribution = texture(utex_cloud_distribution_tex, distribution_uv * CLOUD_DISTRIBUTION_UV_SCALE).r;
    // Rain pushes coverage toward full overcast.
    float coverage = Saturate(CLOUD_COVERAGE + CLOUD_COVERAGE_BOOST_BASE + CLOUD_COVERAGE_BOOST_RANGE * large_scale_cloud
    ) * (1.0 - u_rain_strength) + u_rain_strength;
    float distribution_density = Saturate((distribution - (1.0 - coverage)) / max(coverage, 1.0e-5));
    float bottom_ramp = smoothstep(0.0, 0.2 - large_scale_cloud * 0.1, result.height_fraction);
    // Push density away from the very bottom of the layer to keep the base soft.
    float height_penalty = Saturate((result.height_fraction - 0.15) / 0.85) * 0.5;
    // Fade the layer top; larger clouds get a thicker, softer cap.
    float top_fade = 1.0 - smoothstep(0.2 + large_scale_cloud * large_scale_cloud * 0.4, 1.0, result.height_fraction);
    float macro_density = Saturate(distribution_density - height_penalty)
        * bottom_ramp
        * top_fade;
    if (macro_density <= 0.0) {
        return result;
    }
    vec3 erosion_uv = vec3(world_km.x, altitude_km, world_km.y) / CLOUD_EROSION_SCALE_KM;
    float low_freq_erosion = texture(utex_cloud_erosion_tex, erosion_uv).r;
    // R bakes the weighted darkness sum of the erosion stages (single
    // threshold). Stronger erosion higher in the layer, base floor.
    float height_exposure = smoothstep(0.0, 0.2, result.height_fraction) * 0.95 + 0.05;
    float broad_density = macro_density;
    float erosion_threshold = low_freq_erosion
        * CLOUD_EROSION_STRENGTH
        * height_exposure;
    broad_density = RemapCloudErosion(broad_density, erosion_threshold);
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
    float eroded_density = RemapCloudErosion(broad_density, fine_threshold);

    result.density = eroded_density;
    return result;
}

float CloudDirectionalPhase(float cos_theta, float eccentricity_factor) {
    return PhaseMieHG(cos_theta, CLOUD_PHASE_FORWARD_G * eccentricity_factor) + PhaseMieHG(cos_theta,
        -CLOUD_PHASE_BACKWARD_G * eccentricity_factor);
}

// phi_fwd: HPVolumeCloud isotropic multiple-scattering port. See the file
// header for attribution and the derivation in Docs/PhiFwd_FromRTE.md.
CloudLightTransport SampleCloudLightTransport(vec3 atmosphere_position, vec3 light_dir, float light_jitter,
    float receiver_height_fraction
) {
    CloudLightTransport transport;
    transport.optical_depth = 0.0;
    transport.isotropic_diffuse = 0.0;

    float light_distance = min(CloudDistanceToShellExit(atmosphere_position, light_dir), CLOUD_LIGHT_MAX_DISTANCE_KM);
    if (light_distance <= 1.0e-5) return transport;

    float inverse_step_count = 1.0 / float(CLOUD_LIGHT_STEPS);
    float interval_scale = 2.0 * light_distance * inverse_step_count;
    vec3 camera_atmosphere_pos = AtmosphereCameraPosition();

    // March from the receiver toward the sun, matching HPVolumeCloud's source
    // semantics. Every source's build/propagation depth is measured from the
    // receiver, and all exponentials remain non-positive.
    float one_minus_omega0 = 1.0 - CLOUD_PHI_OMEGA0;
    float kappa_per_optical_depth = sqrt(3.0 * one_minus_omega0);
    float total_optical_depth = 0.0;
    float weighted_source_sum = 0.0;

    // HP evaluates both confidence terms at the receiver and applies the
    // resulting source confidence to every light-ray source.
    float receiver_bottom_height = max(receiver_height_fraction + CLOUD_MS_DEPTH_BIAS, 0.0);
    float receiver_bottom_confidence = 1.0 - exp(-receiver_bottom_height * CLOUD_MS_DEPTH_POWER);
    vec2 receiver_world_km = atmosphere_position.xz + cameraPosition.xz * 0.001;
    float receiver_boundary_confidence = CloudBoundaryBacklight(receiver_world_km, light_dir);
    float source_confidence = receiver_bottom_confidence * receiver_boundary_confidence;

    // Transform uniform x samples by x^2. The analytic Jacobian keeps the
    // constant-density optical depth unbiased while concentrating work nearby.
    for (int i = 0; i < CLOUD_LIGHT_STEPS; ++i) {
        float x_position = (float(i) + light_jitter) * inverse_step_count;
        float sample_distance = light_distance * x_position * x_position;
        float midpoint_fraction = (float(i) + 0.5) * inverse_step_count;
        float interval_weight = midpoint_fraction * interval_scale;
        vec3 source_position = atmosphere_position + light_dir * sample_distance;
        CloudDensitySample density_sample = SampleCloudDensity(source_position, camera_atmosphere_pos);
        float cloud_density = density_sample.density;
        float sigma_t = cloud_density * CLOUD_ALPHA_EXTINCTION_SRGB_GRAY;
        float sigma_s = cloud_density * CLOUD_ALPHA_SCATTERING_SRGB_GRAY;
        float segment_optical_depth = sigma_t * interval_weight;
        // sigma_tr ~= sigma_t in the isotropic regime: the source carries the
        // 1/D scale.
        float scattering_source = sigma_s * interval_weight;
        float optical_depth_from_receiver = total_optical_depth + 0.5 * segment_optical_depth;
        float isotropic_build = 1.0 - exp(-optical_depth_from_receiver * CLOUD_PHI_BUILD_SCALE);
        float inverse_distance = 1.0 / max(sample_distance, 0.5 * interval_weight);
        // HP's T_cum is the receiver-to-source absorption before this
        // segment; propagation reaches the source midpoint.
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
    transport.optical_depth = total_optical_depth;

    transport.isotropic_diffuse = weighted_source_sum
        * (1.0 / (4.0 * PI));
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

vec3 MarchVolumetricClouds(vec3 camera_atmosphere_pos, vec3 view_dir, ivec2 dither_coord, int dither_slice,
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
            sun_phase_weight[octave] = CloudDirectionalPhase(sun_cos_theta, eccentricity_factor) * contribution_factor;
            moon_phase_weight[octave] = CloudDirectionalPhase(-sun_cos_theta, eccentricity_factor) * contribution_factor;
            octave_attenuation[octave] = attenuation_factor;
            attenuation_factor *= CLOUD_MS_ATTENUATION;
            contribution_factor *= CLOUD_MS_CONTRIBUTION;
            eccentricity_factor *= CLOUD_MS_ECCENTRICITY;
        }
    }
    // STBN 3D blue noise: the screen pass advances the time slice per
    // checkerboard cycle, the skybox pins slice 0 (temporal stability).
    // View/light use R2-separated read offsets (decorrelated).
    ivec2 stbn_base = dither_coord & ivec2(127, 127);
    int stbn_frame = dither_slice & 63;
    float view_jitter = SampleSTBN(stbn_base, stbn_frame);
    float light_jitter_base = SampleSTBN(stbn_base + ivec2(64), stbn_frame);
    float interval_length = march_end - march_start;
    float direct_sun_radiance = 0.0;
    float direct_moon_radiance = 0.0;
    vec3 surface_position_accumulator = vec3(0.0);
    float surface_weight = 0.0;
    float view_transmittance = 1.0;
    float inverse_step_count = 1.0 / float(step_count);

    for (int i = 0; i < CLOUD_VIEW_MAX_STEPS; ++i) {
        if (i >= step_count) break;
        float segment_start_fraction = float(i) * inverse_step_count;
        float segment_end_fraction = float(i + 1) * inverse_step_count;
        float segment_start = march_start + interval_length * segment_start_fraction;
        float segment_end = march_start + interval_length * segment_end_fraction;
        float step_length = max(segment_end - segment_start, 0.0);
        float sample_distance = mix(segment_start, segment_end, view_jitter);

        vec3 sample_position = camera_atmosphere_pos + view_dir * sample_distance;
        float sample_r2 = dot(sample_position, sample_position);
        CloudDensitySample density_sample = SampleCloudDensity(sample_position, camera_atmosphere_pos);
        if (density_sample.density < 1.0e-4) continue;

        float light_jitter = fract(light_jitter_base + (float(i) + 0.5) * 0.61803398875);
        float sample_sun_radiance = 0.0;
        float sample_moon_radiance = 0.0;
        if (!CloudLightBlockedByEarth(sample_position, sample_r2, sun_dir)) {
            CloudLightTransport sun_transport = SampleCloudLightTransport(sample_position, sun_dir, light_jitter,
                density_sample.height_fraction);
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
        if (!CloudLightBlockedByEarth(sample_position, sample_r2, moon_dir)) {
            // Half-period offset decorrelates the moon march from the sun's.
            float moon_light_jitter = fract(light_jitter + 0.5);
            CloudLightTransport moon_transport = SampleCloudLightTransport(sample_position, moon_dir, moon_light_jitter,
                density_sample.height_fraction);
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
