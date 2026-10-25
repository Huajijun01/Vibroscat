#ifndef LIB_CLOUD_CIRRUS_GLSL
#define LIB_CLOUD_CIRRUS_GLSL

// World-anchored vertical optical depth on a finite spherical layer.
// Returns cloud radiance and true transmittance, without the sky background.

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/atmosphere/transmittance.glsl"
#include "/lib/cloud/multiple_scattering.glsl"
#include "/lib/scattering/phase.glsl"

const float CIRRUS_HEIGHT_KM = 7.0;
const float CIRRUS_RADIUS_KM = ATM_PLANET_R + CIRRUS_HEIGHT_KM;
const float CIRRUS_LAYER_THICKNESS_KM = 1.0;
const float CIRRUS_BOTTOM_RADIUS_KM = CIRRUS_RADIUS_KM - 0.5 * CIRRUS_LAYER_THICKNESS_KM;
const float CIRRUS_TOP_RADIUS_KM = CIRRUS_RADIUS_KM + 0.5 * CIRRUS_LAYER_THICKNESS_KM;
const float CIRRUS_TILE_SIZE_KM = 24.0;
const int CIRRUS_TILE_SIZE_M = 24000;
// The body stores sqrt(tau_vertical / 2), not a second scattering gain.
const float CIRRUS_OPTICAL_DEPTH_SCALE = 2.0;
// The multiple-scatter reference spans half of the layer's thickness.
const float CIRRUS_MS_REFERENCE_LENGTH_KM = 0.5;
const float CIRRUS_MS_SAT_ALBEDO = 0.999;
// Normalize the shared sky-light control's default 8.0 to one sky radiance.
// This artistic fill replaces the attenuated blue background at thin edges.
const float CIRRUS_SKY_LIGHT_WEIGHT = 0.125;
const HenyeyGreensteinTripleLobe CIRRUS_MIE_PHASE = HenyeyGreensteinTripleLobe(
    0.92, 0.1,
    0.3, 0.7,
    0.2, 0.2);

struct CirrusLayerSample {
    vec3 radiance;
    float transmittance;
    vec3 surface_pos_km;
    float entry_km;
};

// Outer-sphere interval minus the inner sphere, clipped before the planet.
// An elevated grazing ray can encounter two disjoint cloud intervals.
bool IntersectCirrusLayer(vec3 ray_start_km, vec3 view_dir, out vec4 intervals_km) {
    intervals_km = vec4(0.0);
    float outer_near;
    float outer_far;
    if (!RayIntersectSphere(ray_start_km, view_dir, CIRRUS_TOP_RADIUS_KM,
            outer_near, outer_far)) return false;
    float start_km = max(outer_near, 0.0);
    float end_km = outer_far;
    float ground_near;
    float ground_far;
    if (RayIntersectSphere(ray_start_km, view_dir, ATM_PLANET_R,
            ground_near, ground_far) && ground_near > 0.0) {
        end_km = min(end_km, ground_near);
    }
    if (end_km <= start_km) return false;

    float inner_near;
    float inner_far;
    if (RayIntersectSphere(ray_start_km, view_dir, CIRRUS_BOTTOM_RADIUS_KM,
            inner_near, inner_far) && inner_far > start_km && inner_near < end_km) {
        intervals_km = vec4(start_km, max(start_km, min(inner_near, end_km)),
            min(end_km, max(inner_far, start_km)), end_km);
    } else {
        intervals_km.xy = vec2(start_km, end_km);
    }
    return intervals_km.y > intervals_km.x || intervals_km.w > intervals_km.z;
}

float SampleCirrusOpticalDepth(vec3 sample_pos_km, float footprint_km) {
#ifdef CIRRUS
    // Reduce absolute integer meters before the float conversion. Both the
    // body and the bent strand transform repeat over this 24 km period.
    ivec2 camera_tile_m = cameraPositionInt.xz % CIRRUS_TILE_SIZE_M;
    vec2 absolute_km = sample_pos_km.xz
        + (vec2(camera_tile_m) + cameraPositionFract.xz) * 0.001;
    vec2 uv = absolute_km.yx / CIRRUS_TILE_SIZE_KM;
    float footprint_uv = footprint_km / CIRRUS_TILE_SIZE_KM;
    float body;
    if (footprint_uv * 1024.0 > 1.0) {
        float offset_uv = 0.25 * footprint_uv;
        vec4 encoded = vec4(
            textureLod(utex_cirrus_body, uv + vec2(offset_uv), 0.0).r,
            textureLod(utex_cirrus_body, uv - vec2(offset_uv), 0.0).r,
            textureLod(utex_cirrus_body, uv + vec2(offset_uv, -offset_uv), 0.0).r,
            textureLod(utex_cirrus_body, uv + vec2(-offset_uv, offset_uv), 0.0).r);
        body = 0.25 * dot(encoded, encoded);
    } else {
        float encoded = textureLod(utex_cirrus_body, uv, 0.0).r;
        body = encoded * encoded;
    }
    if (body == 0.0) return 0.0;

    // The static R8 noise's baked mean is 0.49894876. Unresolved strands
    // fade to that mean, rather than aliasing or changing the cloud coverage.
    float detail_weight = 1.0 - smoothstep(0.5, 2.0, footprint_uv * 4096.0);
    float strand = 0.0;
    if (detail_weight > 0.0) {
        vec2 q = fract(uv);
        vec2 bend = q * (1.0 - q);
        bend *= bend;
        float phase = uv.y + 0.125 * uv.x + dot(bend, vec2(0.28, 0.18));
        strand = textureLod(utex_cirrus_noise,
            vec2(uv.x + 0.317, 16.0 * phase + 0.231) * 2.0, 0.0).r - 0.49894876;
    }
    return CIRRUS_OPTICAL_DEPTH_SCALE * body
        * (1.0 + (1.0 - 0.6 * body) * strand * detail_weight);
#else
    return 0.0;
#endif
}

// Source radiance: extinction is already integrated by RenderCirrusLayer.
// Single scattering has no extra density factor, so thin edges respond linearly.
vec3 EvaluateCirrusLighting(vec3 sample_pos_km, vec3 view_dir, float tau_vertical,
    vec3 sky_color
) {
    float sample_r_km = length(sample_pos_km);
    float sample_r_squared = sample_r_km * sample_r_km;
    float sun_mu = dot(sample_pos_km, u_world_sun_dir) / sample_r_km;
    float sun_cos = clamp(dot(view_dir, u_world_sun_dir), -1.0, 1.0);
    float isotropic_orders = IsotropicOrders(
        tau_vertical * (CIRRUS_MS_REFERENCE_LENGTH_KM / CIRRUS_LAYER_THICKNESS_KM),
        CIRRUS_MS_SAT_ALBEDO, CIRRUS_MS_ISOTROPIC);
    vec3 source_radiance = vec3(0.0);
    if (!PlanetHorizonOccluded(sample_pos_km, sample_r_squared,
            u_world_sun_dir, ATM_PLANET_R2)) {
        vec3 sun_color = SpectralToLinearSRGBWhiteBalanced(
            SampleTransmittance(utex_tslut, sample_r_km, sample_r_squared, sun_mu)
            * ATM_SOLAR) * ATM_EXPOSURE;
        source_radiance += sun_color
            * (PhaseHenyeyGreensteinTripleLobe(sun_cos, CIRRUS_MIE_PHASE) + isotropic_orders);
    }
    // Keep the moon lookup after the sun branch: mirrored straight-line
    // lookups of this LUT have been merged incorrectly by the driver.
    if (!PlanetHorizonOccluded(sample_pos_km, sample_r_squared,
            -u_world_sun_dir, ATM_PLANET_R2)) {
        vec3 moon_color = SpectralToLinearSRGBWhiteBalanced(
            SampleTransmittance(utex_tslut, sample_r_km, sample_r_squared, -sun_mu)
            * ATM_MOON_IRR) * ATM_EXPOSURE;
        source_radiance += moon_color
            * (PhaseHenyeyGreensteinTripleLobe(-sun_cos, CIRRUS_MIE_PHASE) + isotropic_orders);
    }
    if (CLOUD_SKY_LIGHT_STRENGTH > 0.0) {
        // Both consumers pass the clear sky before stars, discs or clouds.
        source_radiance += sky_color
            * (CLOUD_SKY_LIGHT_STRENGTH * CIRRUS_SKY_LIGHT_WEIGHT);
    }
    return source_radiance;
}

CirrusLayerSample RenderCirrusLayer(vec3 view_dir, float angular_footprint, vec3 sky_color) {
    CirrusLayerSample result = CirrusLayerSample(vec3(0.0), 1.0, vec3(0.0), 1.0e9);
    vec3 ray_start_km = AtmosphereCameraPosition();
    vec4 intervals_km;
    if (!IntersectCirrusLayer(ray_start_km, view_dir, intervals_km)) return result;

    vec3 weighted_position_km = vec3(0.0);
    float total_opacity = 0.0;
    for (int interval_index = 0; interval_index < 2; ++interval_index) {
        vec2 interval_km = interval_index == 0 ? intervals_km.xy : intervals_km.zw;
        float path_km = interval_km.y - interval_km.x;
        if (path_km <= 0.0) continue;
        float sample_distance_km = 0.5 * (interval_km.x + interval_km.y);
        vec3 sample_pos_km = ray_start_km + view_dir * sample_distance_km;
        float view_mu = abs(dot(view_dir, normalize(sample_pos_km)));
        // Finite-shell geometry handles the actual grazing path. This floor
        // only bounds the approximate projected footprint at a tangent.
        float footprint_km = sample_distance_km * angular_footprint / max(view_mu, 0.05);
        float tau_vertical = SampleCirrusOpticalDepth(sample_pos_km, footprint_km);
        if (tau_vertical <= 0.0) continue;
        float tau_view = tau_vertical * (path_km / CIRRUS_LAYER_THICKNESS_KM);
        float segment_transmittance = exp(-tau_view);
        // Avoid cancellation in 1-exp(-tau) at the routinely sampled thin
        // feather edges. The relative series error is below 5e-8 here.
        float opacity = tau_view < 0.01
            ? tau_view * (1.0 - tau_view * (0.5 - tau_view * (1.0 / 6.0)))
            : 1.0 - segment_transmittance;
        float contribution = result.transmittance * opacity;
        result.radiance += EvaluateCirrusLighting(sample_pos_km, view_dir, tau_vertical, sky_color)
            * contribution;
        weighted_position_km += sample_pos_km * contribution;
        total_opacity += contribution;
        result.entry_km = min(result.entry_km, interval_km.x);
        result.transmittance *= segment_transmittance;
    }
    if (total_opacity > 0.0) {
        result.surface_pos_km = weighted_position_km / total_opacity;
    }
    return result;
}

#endif // LIB_CLOUD_CIRRUS_GLSL
