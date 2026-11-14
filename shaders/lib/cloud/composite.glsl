#ifndef LIB_CLOUD_COMPOSITE_GLSL
#define LIB_CLOUD_COMPOSITE_GLSL

// Final cloud compositor: volumetric + cirrus over the sky (linear RGB).

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/celestial.glsl"
#include "/lib/atmosphere/transmittance.glsl"
#include "/lib/cloud/cirrus.glsl"
#include "/lib/cloud/lighting.glsl"
#include "/lib/cloud/signal.glsl"

// Match the volumetric march cutoff: at most 0.01% of a hidden layer remains.
const float CLOUD_LAYER_OPAQUE_TRANSMITTANCE = 1.0e-4;

vec3 RenderCloudLayers(vec3 view_dir, vec3 sky_color,
    CloudSignal volumetric_signal,
    vec3 volumetric_surface_pos,
    float volumetric_entry_km,
    out vec3 cloud_transmittance,
    inout vec4 view_transmittance,
    inout bool view_transmittance_cached
) {
    bool volumetric_hit = volumetric_signal.transmittance < 0.99999;
    float volumetric_transmittance = volumetric_hit ? volumetric_signal.transmittance : 1.0;

    vec3 cirrus_surface_pos = vec3(0.0);
    float cirrus_entry_km = 1.0e9;
    vec3 cirrus_transmittance = vec3(1.0);
    vec3 cirrus_scattering = vec3(0.0);
    bool cirrus_hit = false;
#ifdef CIRRUS
    // Only from below can an opaque volumetric layer cull cirrus; above the shell the ray order reverses.
    bool cirrus_occluded = volumetric_transmittance <= CLOUD_LAYER_OPAQUE_TRANSMITTANCE
        && u_camera_radius_km < CIRRUS_BOTTOM_RADIUS_KM
        && ATM_PLANET_R + CLOUD_TOP_ALTITUDE < CIRRUS_BOTTOM_RADIUS_KM;
    if (!cirrus_occluded) {
        CirrusLayerSample cirrus = RenderCirrusLayer(view_dir, sky_color);
        cirrus_scattering = cirrus.radiance;
        cirrus_surface_pos = cirrus.surface_pos_km;
        cirrus_entry_km = cirrus.entry_km;
        cirrus_transmittance = vec3(cirrus.transmittance);
        cirrus_hit = cirrus.transmittance < 1.0;
    }
#endif
    bool cirrus_present = cirrus_entry_km < 1.0e9;
    cloud_transmittance = vec3(volumetric_transmittance) * cirrus_transmittance;
    if (!volumetric_hit && !cirrus_present) return sky_color;

    float volumetric_surface_r = 0.0;
    vec3 volumetric_scattering = vec3(0.0);
    if (volumetric_hit) {
        volumetric_surface_r = length(volumetric_surface_pos);
        volumetric_scattering = RelightClouds(volumetric_signal,
            volumetric_surface_pos, volumetric_surface_r, sky_color);
    }

    // Volumetric share weighs (1 - T) by the march's integrated sky weight (scattering.y); cirrus keeps
    // the raw (1 - T). vec4(1.0) transmittance: the fades below already carry camera-to-cloud propagation.
#if defined(CLOUD_MILKYWAY_GLOW) || defined(CIRRUS_MILKYWAY_GLOW)
#if defined(CLOUD_MILKYWAY_GLOW) && defined(CIRRUS_MILKYWAY_GLOW)
    bool milkyway_scattered = volumetric_hit || cirrus_hit;
#elif defined(CLOUD_MILKYWAY_GLOW)
    bool milkyway_scattered = volumetric_hit;
#else
    bool milkyway_scattered = cirrus_hit;
#endif
    if (u_star_night_fade > 0.0 && milkyway_scattered) {
        vec3 milkyway_glow = RenderMilkyWayGlow(view_dir, vec4(1.0),
            CelestialContextFor(view_dir));
#ifdef CLOUD_MILKYWAY_GLOW
        volumetric_scattering += milkyway_glow
            * (volumetric_signal.scattering.y * CLOUD_MILKYWAY_TRANSMISSION);
#endif
#ifdef CIRRUS_MILKYWAY_GLOW
        cirrus_scattering += milkyway_glow
            * ((1.0 - cirrus_transmittance) * CIRRUS_MILKYWAY_TRANSMISSION);
#endif
    }
#endif

    bool ground_hit = PlanetHorizonOccluded(AtmosphereCameraPosition(),
        u_camera_radius_sq, view_dir, ATM_PLANET_R2);
    vec4 camera_transmittance = view_transmittance;
    if (ground_hit || !view_transmittance_cached) {
        camera_transmittance = SampleTransmittance(utex_tslut,
            u_camera_radius_km, u_camera_radius_km * u_camera_radius_km, ground_hit ? -view_dir.y : view_dir.y);
    }
    view_transmittance = camera_transmittance;
    // Ground-hit paths use the reciprocal direction, unsuitable for celestial light.
    view_transmittance_cached = !ground_hit;

    // Fades blend composites toward the sky but must not touch true transmittance, or the layer behind shows through.
    vec3 volumetric_faded = sky_color;
    if (volumetric_hit) {
        vec3 volumetric_composite = volumetric_scattering + sky_color * volumetric_transmittance;
        vec3 volumetric_fade = AtmosphereTransmittanceToSurface(volumetric_surface_pos,
            view_dir, volumetric_surface_r, ground_hit, camera_transmittance);
        volumetric_faded = mix(sky_color, volumetric_composite, volumetric_fade);
    }
    vec3 cirrus_faded = sky_color;
    if (cirrus_present) {
        vec3 cirrus_composite = cirrus_scattering + sky_color * cirrus_transmittance;
        vec3 cirrus_fade = AtmosphereTransmittanceToSurface(cirrus_surface_pos,
            view_dir, length(cirrus_surface_pos), ground_hit, camera_transmittance);
        cirrus_faded = mix(sky_color, cirrus_composite, cirrus_fade);
    }
    if (!cirrus_present) return volumetric_faded;
    if (!volumetric_hit) return cirrus_faded;

    // Ray-entry depth sort: the nearer layer composites in front.
    bool volumetric_in_front = volumetric_entry_km < cirrus_entry_km;
    if (volumetric_in_front) {
        return volumetric_faded + (cirrus_faded - sky_color) * volumetric_transmittance;
    }
    return cirrus_faded + (volumetric_faded - sky_color) * cirrus_transmittance;
}

#endif // LIB_CLOUD_COMPOSITE_GLSL
