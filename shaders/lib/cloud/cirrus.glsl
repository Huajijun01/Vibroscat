#ifndef LIB_CLOUD_CIRRUS_GLSL
#define LIB_CLOUD_CIRRUS_GLSL

// Cirrus deck sampled once at the thin shell's crossing; returned radiance excludes the sky background.

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/illumination.glsl"
#include "/lib/cloud/multiple_scattering.glsl"
#include "/lib/scattering/phase.glsl"

const float CIRRUS_HEIGHT_KM = 7.0;
const float CIRRUS_RADIUS_KM = ATM_PLANET_R + CIRRUS_HEIGHT_KM;
const float CIRRUS_LAYER_THICKNESS_KM = 1.0;
// Grazing clamp (sin of ~3.4 degrees) for rays skimming the slab.
const float CIRRUS_GRAZING_MIN_MU = 0.06;
const float CIRRUS_BOTTOM_RADIUS_KM = CIRRUS_RADIUS_KM - 0.5 * CIRRUS_LAYER_THICKNESS_KM;
const float CIRRUS_TILE_SIZE_KM = 24.0;
const int CIRRUS_TILE_SIZE_M = 24000;
// The body stores sqrt(tau_vertical / 2), not a second scattering gain.
const float CIRRUS_OPTICAL_DEPTH_SCALE = 1.0;
// The multiple-scatter reference spans half of the layer's thickness.
const float CIRRUS_MS_REFERENCE_LENGTH_KM = 0.5;
const float CIRRUS_MS_SAT_ALBEDO = 0.999;
// View-dependent clear-sky fill: the shared default 8.0 gives 0.56 of the input sky before opacity integration.
const float CIRRUS_SKY_LIGHT_WEIGHT = 0.07;
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

#ifdef CIRRUS
float SampleCirrusOpticalDepth(vec3 sample_pos_km) {
    vec2 density_xz_km = sample_pos_km.xz + cameraPosition.xz * 0.001
        + vec2(frameTimeCounter * CIRRUS_WIND_SPEED, 0.0);
    vec2 uv = density_xz_km.yx / CIRRUS_TILE_SIZE_KM;
    float encoded = textureLod(utex_cirrus_body, uv, 0.0).r;
    if (encoded < 0.001) return 0.0;

    // The static R8 noise's baked mean is 0.49894876.
    vec2 q = fract(uv);
    vec2 bend = q * (1.0 - q);
    bend *= bend;
    float phase = uv.y + 0.125 * uv.x + dot(bend, vec2(0.28, 0.18));
    float strand = textureLod(utex_cirrus_noise,
        vec2(uv.x + 0.317, 16.0 * phase + 0.231) * 3.0, 0.0).r - 0.49894876;
    float body = encoded * encoded;
    return CIRRUS_OPTICAL_DEPTH_SCALE * body
        * (1.0 + (1.0 - 0.6 * body) * strand);
}
#endif

// Returns source radiance; extinction is integrated by RenderCirrusLayer.
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
        vec3 sun_color = AtmosphereDirectIrradianceAt(sample_r_km, sample_r_squared, sun_mu, ATM_SOLAR);
        source_radiance += sun_color
            * (PhaseHenyeyGreensteinTripleLobe(sun_cos, CIRRUS_MIE_PHASE) + isotropic_orders);
    }
    // Moon lookup stays after the sun branch: the driver merges mirrored LUT lookups incorrectly.
    if (!PlanetHorizonOccluded(sample_pos_km, sample_r_squared,
            -u_world_sun_dir, ATM_PLANET_R2)) {
        vec3 moon_color = AtmosphereDirectIrradianceAt(sample_r_km, sample_r_squared, -sun_mu, ATM_MOON_IRR);
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

#ifdef CIRRUS
CirrusLayerSample RenderCirrusLayer(vec3 view_dir, vec3 sky_color) {
    CirrusLayerSample result = CirrusLayerSample(vec3(0.0), 1.0, vec3(0.0), 1.0e9);
    vec3 ray_start_km = AtmosphereCameraPosition();
    float t_near;
    float t_far;
    if (!RayIntersectSphere(ray_start_km, view_dir, CIRRUS_RADIUS_KM, t_near, t_far)) return result;
    float entry_km = t_near > 0.0 ? t_near : t_far;
    if (entry_km <= 0.0) return result;

    vec3 sample_pos_km = ray_start_km + view_dir * entry_km;
    float tau_vertical = SampleCirrusOpticalDepth(sample_pos_km);
    if (tau_vertical <= 0.0) return result;

    // view_mu is |dot(view, shell normal)| for a sphere chord: (t_far - t_near) / (2R).
    float view_mu = (t_far - t_near) * (0.5 / CIRRUS_RADIUS_KM);
    float view_path_km = min(entry_km,
        CIRRUS_LAYER_THICKNESS_KM / max(view_mu, CIRRUS_GRAZING_MIN_MU));
    float tau_view = tau_vertical * (view_path_km / CIRRUS_LAYER_THICKNESS_KM);
    float segment_transmittance = exp(-tau_view);
    // Series form avoids cancellation in 1-exp(-tau) on thin edges (relative error < 5e-8).
    float opacity = tau_view < 0.01
        ? tau_view * (1.0 - tau_view * (0.5 - tau_view * (1.0 / 6.0)))
        : 1.0 - segment_transmittance;
    result.radiance = EvaluateCirrusLighting(sample_pos_km, view_dir, tau_vertical, sky_color)
        * opacity;
    result.surface_pos_km = sample_pos_km;
    result.entry_km = entry_km;
    result.transmittance = segment_transmittance;
    return result;
}
#endif // CIRRUS

#endif // LIB_CLOUD_CIRRUS_GLSL
