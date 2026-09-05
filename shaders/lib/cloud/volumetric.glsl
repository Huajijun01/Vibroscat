#ifndef LIB_CLOUD_VOLUMETRIC_GLSL
#define LIB_CLOUD_VOLUMETRIC_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/core.glsl"

// Vibroscat volumetric clouds.
//
// The former phi_fwd implementation was derived from HanPi Volume Cloud
// (HPVolumeCloud) by AshenOneArt:
//   https://github.com/AshenOneArt/HPVolumeCloud
//   Docs/PhiFwd_FromRTE.md (upstream repo)
// HPVolumeCloud is MIT licensed with an additional attribution requirement;
// see licenses/THIRD_PARTY_NOTICES.md section 2.
// Current multiple scattering independently solves a finite optical slab's
// P1 diffusion equation with vacuum boundaries; no additional LUT is used.

const float CLOUD_MAX_DISTANCE_KM = 180.0;
const float CLOUD_PHASE_FORWARD_WEIGHT = 0.95;
const float CLOUD_PHASE_MEAN_G = CLOUD_PHASE_FORWARD_WEIGHT * CLOUD_PHASE_FORWARD_G
    - (1.0 - CLOUD_PHASE_FORWARD_WEIGHT) * CLOUD_PHASE_BACKWARD_G;
// Visible-band water droplets: all transport coefficients share one material.
const float CLOUD_SINGLE_SCATTER_ALBEDO = 0.999;
const float CLOUD_EXTINCTION_PER_KM = 100.0;
const float CLOUD_TRANSPORT_RATIO = 1.0 - CLOUD_SINGLE_SCATTER_ALBEDO * CLOUD_PHASE_MEAN_G;
const float CLOUD_DIFFUSION_DECAY = sqrt(3.0 * (1.0 - CLOUD_SINGLE_SCATTER_ALBEDO)
    * CLOUD_TRANSPORT_RATIO);
const float CLOUD_DIRECTION_MEMORY_DECAY = CLOUD_SINGLE_SCATTER_ALBEDO * (1.0 - CLOUD_PHASE_MEAN_G);
// Coverage uses the weather map at this scale; erosion is sampled separately.
const float CLOUD_DISTRIBUTION_UV_SCALE = 2.35;

struct CloudDensitySample {
    float density;
    float height_fraction;
};

struct CloudLightTransport {
    float optical_depth;
    float multiple_scattering;
    float phase_optical_depth;
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

float CloudDistanceToShellExit(vec3 position, vec3 dir, out float lit_height, out float opposite_height) {
    float radius = length(position);
    float top_height = max(ATM_PLANET_R + CLOUD_TOP_ALTITUDE - radius, 0.0);
    float bottom_height = max(radius - (ATM_PLANET_R + CLOUD_BASE_ALTITUDE), 0.0);
    float radial_projection = dot(position, dir);
    // Difference-of-squares products and rationalized near roots preserve
    // shallow cloud distances without subtracting planet-sized squared radii.
    float outer_gap = top_height * (2.0 * radius + top_height);
    float outer_root = sqrt(radial_projection * radial_projection + outer_gap);
    float distance_to_exit = radial_projection >= 0.0
        ? outer_gap / max(outer_root + radial_projection, 1.0e-5)
        : outer_root - radial_projection;
    lit_height = top_height;
    opposite_height = bottom_height;

    float inner_gap = bottom_height * (2.0 * radius - bottom_height);
    float inner_discriminant = radial_projection * radial_projection - inner_gap;
    if (radial_projection < 0.0 && inner_discriminant > 0.0) {
        float inner_distance = inner_gap / (-radial_projection + sqrt(inner_discriminant));
        if (inner_distance < distance_to_exit) {
            distance_to_exit = inner_distance;
            lit_height = bottom_height;
            opposite_height = top_height;
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

// Light below the local horizon is planet-occluded: near sphere intersection
// only (no far root); caller passes r2 to share the dot product.
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
    float distribution = texture(utex_cloud_distribution_tex, distribution_uv * CLOUD_DISTRIBUTION_UV_SCALE).r;
    // Rain pushes coverage toward full overcast.
    float coverage = (CLOUD_COVERAGE) * (1.0 - u_rain_strength) + u_rain_strength;
    float distribution_density = Saturate((distribution - (1.0 - coverage)) / max(coverage, 1.0e-5));
    float bottom_ramp = smoothstep(0.0, 0.15, result.height_fraction);
    // Push density away from the very bottom of the layer to keep the base soft.
    float height_penalty = Saturate((result.height_fraction - 0.15) / 0.85) * 0.5;
    // Fade the fixed spherical layer top.
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

float CloudDirectionalPhase(float cos_theta) {
    return mix(PhaseMieHG(cos_theta, -CLOUD_PHASE_BACKWARD_G),
        PhaseMieHG(cos_theta, CLOUD_PHASE_FORWARD_G), CLOUD_PHASE_FORWARD_WEIGHT);
}

float CloudMultipleScatteringPhase(float low_order_phase, float slab_optical_depth) {
    // A lit face can receive long paths from the whole slab even when the
    // direct sun depth is zero. Use slab thickness for angular memory.
    float direction_memory = exp(-CLOUD_DIRECTION_MEMORY_DECAY * slab_optical_depth);
    return mix(1.0 / (4.0 * PI), low_order_phase, direction_memory);
}

// -D Phi'' + (1 - omega) Phi = omega exp(-t / mu), in optical-depth units.
// Vacuum (Marshak) boundaries: Phi(0) - 2D Phi'(0) = 0,
// Phi(L) + 2D Phi'(L) = 0. The incident source is isotropized by P1.
float CloudSlabFluence(float receiver_depth, float slab_depth, float light_cosine) {
    float depth = max(slab_depth, 0.0);
    if (depth <= 0.0) return 0.0;
    float t = clamp(receiver_depth, 0.0, depth);
    float mu = clamp(light_cosine, 1.0e-4, 1.0);
    float absorption = 1.0 - CLOUD_SINGLE_SCATTER_ALBEDO;
    float diffusion = 1.0 / (3.0 * CLOUD_TRANSPORT_RATIO);
    float boundary_length = 2.0 * diffusion;
    float full_path = depth / mu;
    float direct_exit = exp(-full_path);

    // The thin solution is almost uniform. This limit avoids cancellation
    // between the particular and homogeneous terms in single precision.
    if (depth < 0.01 * diffusion) {
        float deposited = full_path < 1.0e-3
            ? full_path * (1.0 - 0.5 * full_path + full_path * full_path / 6.0)
            : 1.0 - direct_exit;
        return CLOUD_SINGLE_SCATTER_ALBEDO * mu * deposited / (1.0 + absorption * depth);
    }

    float decay_near = exp(-CLOUD_DIFFUSION_DECAY * t);
    float decay_far = exp(-CLOUD_DIFFUSION_DECAY * (depth - t));
    float decay_full = decay_near * decay_far;
    float boundary_decay = boundary_length * CLOUD_DIFFUSION_DECAY;
    float reflection = (1.0 - boundary_decay) / (1.0 + boundary_decay);
    // Multiply the source coefficients by mu^2 to avoid large 1/mu^2 terms.
    float source_scale = CLOUD_SINGLE_SCATTER_ALBEDO / (diffusion - absorption * mu * mu);
    float particular = -source_scale * mu * mu;
    float near_source = source_scale * mu * (mu + boundary_length) / (1.0 + boundary_decay);
    float far_source = source_scale * mu * (mu - boundary_length) * direct_exit / (1.0 + boundary_decay);
    float denominator = 1.0 - reflection * reflection * decay_full * decay_full;
    float near_coefficient = (near_source - reflection * decay_full * far_source) / denominator;
    float far_coefficient = (far_source - reflection * decay_full * near_source) / denominator;
    float fluence = particular * exp(-t / mu)
        + near_coefficient * decay_near + far_coefficient * decay_far;
    return max(fluence, 0.0);
}

CloudLightTransport SampleCloudLightTransport(vec3 atmosphere_position, vec3 light_dir, float light_jitter,
    float receiver_density
) {
    CloudLightTransport transport;
    transport.optical_depth = 0.0;
    transport.multiple_scattering = 0.0;
    transport.phase_optical_depth = 0.0;

    float lit_height;
    float opposite_height;
    float shell_distance = CloudDistanceToShellExit(atmosphere_position, light_dir, lit_height, opposite_height);
    float light_distance = min(shell_distance, CLOUD_LIGHT_MAX_DISTANCE_KM);
    if (light_distance <= 1.0e-5) return transport;

    float inverse_step_count = 1.0 / float(CLOUD_LIGHT_STEPS);
    vec3 camera_atmosphere_pos = AtmosphereCameraPosition();
    float occupied_end = 0.0;
    int trailing_clear_samples = 0;

    // Keep the existing stratified density budget; only optical depth is
    // accumulated here. Finite-slab transport is evaluated once after the loop.
    for (int i = 0; i < CLOUD_LIGHT_STEPS; ++i) {
        float x0 = float(i) * inverse_step_count;
        float x1 = float(i + 1) * inverse_step_count;
        float segment_start = light_distance * x0 * x0;
        float segment_end = light_distance * x1 * x1;
        float interval_weight = segment_end - segment_start;
        float sample_distance = mix(segment_start, segment_end, light_jitter);
        vec3 source_position = atmosphere_position + light_dir * sample_distance;
        CloudDensitySample density_sample = SampleCloudDensity(source_position, camera_atmosphere_pos);
        float cloud_density = density_sample.density;
        if (cloud_density >= 1.0e-4) {
            occupied_end = segment_end;
            trailing_clear_samples = 0;
        } else {
            ++trailing_clear_samples;
        }
        float sigma_t = cloud_density * CLOUD_EXTINCTION_PER_KM;
        float segment_optical_depth = sigma_t * interval_weight;
        transport.optical_depth += segment_optical_depth;
    }

    // Keep the full shell unless at least two trailing samples observe clear
    // space. That shorter support estimates a locally tilted side boundary;
    // it is not a recovered normal or proof of an empty unsampled ray tail.
    float effective_exit = shell_distance;
    if (trailing_clear_samples >= 2) {
        float first_interval = light_distance * inverse_step_count * inverse_step_count;
        effective_exit = min(effective_exit, max(occupied_end, first_interval));
    }
    float light_cosine = clamp(lit_height / max(effective_exit, 1.0e-5), 1.0e-4, 1.0);
    float receiver_depth = light_cosine * transport.optical_depth;
    // The opposite column assumes locally uniform density, using no new reads.
    float opposite_depth = receiver_density * CLOUD_EXTINCTION_PER_KM * opposite_height;
    transport.phase_optical_depth = receiver_depth + opposite_depth;
    float fluence = CloudSlabFluence(receiver_depth, transport.phase_optical_depth, light_cosine);
    // Phi contains scattered incident light; one more collision produces the
    // second-and-higher-order source, with its angular budget applied by caller.
    transport.multiple_scattering = CLOUD_SINGLE_SCATTER_ALBEDO * fluence;
    return transport;
}

vec3 MarchVolumetricClouds(vec3 camera_atmosphere_pos, vec3 view_dir, ivec2 dither_coord, int dither_slice,
    float march_start, float march_end, int step_count, out vec3 surface_position, out bool hit
) {
    vec3 sun_dir = normalize(u_world_sun_dir);
    // Moon sits opposite the sun (no separate uniform); its view cosine is the
    // exact negation of the sun's. Each light is gated by earth occlusion below.
    vec3 moon_dir = -sun_dir;
    float sun_cos_theta = clamp(dot(view_dir, sun_dir), -1.0, 1.0);
    // HG evaluation is invariant along the view ray. The second-order lobe
    // matches the squared first angular moment of the normalized dual HG.
    float sun_phase = CloudDirectionalPhase(sun_cos_theta);
    float moon_phase = CloudDirectionalPhase(-sun_cos_theta);
    float second_order_g = CLOUD_PHASE_MEAN_G * CLOUD_PHASE_MEAN_G;
    float sun_ms_phase = PhaseMieHG(sun_cos_theta, second_order_g);
    float moon_ms_phase = PhaseMieHG(-sun_cos_theta, second_order_g);
    // STBN 3D blue noise: the screen pass advances the time slice per frame;
    // the skybox pins slice 0 (temporal stability).
    // View/light use R2-separated read offsets (decorrelated).
    ivec2 stbn_base = dither_coord & ivec2(127, 127);
    int stbn_frame = dither_slice & 63;
    float view_jitter = SampleSTBN(stbn_base, stbn_frame);
    float light_jitter_base = SampleSTBN(stbn_base, stbn_frame + 32);
    float interval_length = march_end - march_start;
    float direct_sun_radiance = 0.0;
    float direct_moon_radiance = 0.0;
    vec3 surface_position_accumulator = vec3(0.0);
    float surface_weight = 0.0;
    float view_transmittance = 1.0;
    float inverse_step_count = 1.0 / float(step_count);

    for (int i = 0; i < CLOUD_VIEW_MAX_STEPS; ++i) {
        if (i >= step_count) break;
        float step_length = interval_length * inverse_step_count;
        // Shift the complete ray-march sequence by one shared jittered step;
        // independent per-segment offsets can line up with cloud height bands.
        float sample_distance = march_start + (float(i) + view_jitter) * step_length;

        vec3 sample_position = camera_atmosphere_pos + view_dir * sample_distance;
        float sample_r2 = dot(sample_position, sample_position);
        CloudDensitySample density_sample = SampleCloudDensity(sample_position, camera_atmosphere_pos);
        if (density_sample.density < 1.0e-4) continue;

        float light_jitter = fract(light_jitter_base + (float(i) + 0.5) * 0.61803398875);
        float sample_sun_radiance = 0.0;
        float sample_moon_radiance = 0.0;
        if (!CloudLightBlockedByEarth(sample_position, sample_r2, sun_dir)) {
            CloudLightTransport sun_transport = SampleCloudLightTransport(sample_position, sun_dir, light_jitter,
                density_sample.density);
            sample_sun_radiance = CLOUD_SINGLE_SCATTER_ALBEDO * sun_phase * exp(-sun_transport.optical_depth)
                + sun_transport.multiple_scattering
                    * CloudMultipleScatteringPhase(sun_ms_phase, sun_transport.phase_optical_depth);
        }
        if (!CloudLightBlockedByEarth(sample_position, sample_r2, moon_dir)) {
            // Half-period offset decorrelates the moon march from the sun's.
            float moon_light_jitter = fract(light_jitter + 0.5);
            CloudLightTransport moon_transport = SampleCloudLightTransport(sample_position, moon_dir, moon_light_jitter,
                density_sample.density);
            sample_moon_radiance = CLOUD_SINGLE_SCATTER_ALBEDO * moon_phase * exp(-moon_transport.optical_depth)
                + moon_transport.multiple_scattering
                    * CloudMultipleScatteringPhase(moon_ms_phase, moon_transport.phase_optical_depth);
        }
        float optical_depth = density_sample.density
            * CLOUD_EXTINCTION_PER_KM
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
