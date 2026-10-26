#ifndef LIB_CLOUD_COMPOSITE_GLSL
#define LIB_CLOUD_COMPOSITE_GLSL

// High-level cloud compositor: final sky color with volumetric clouds +
// cirrus. Each layer fades toward the sky by the atmospheric transmittance
// to its surface position (linear RGB).

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/celestial.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/sky_radiance.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/atmosphere/transmittance.glsl"
#include "/lib/cloud/cirrus.glsl"
#include "/lib/cloud/volumetric.glsl"

// Match the volumetric march cutoff: at most 0.01% of a hidden layer remains.
const float CLOUD_LAYER_OPAQUE_TRANSMITTANCE = 1.0e-4;

// Atmospheric transmittance along the camera->cloud-surface ray (UE
// GetTransmittance scheme; (r, mu) camera, (r_d, mu_d) surface, same ray):
//   ground miss:  T = T_lut(r, mu)      / T_lut(r_d, mu_d)
//   ground hit:   T = T_lut(r_d, -mu_d) / T_lut(r, -mu)   (reciprocity)
// The baked LUT stores the full chord for non-ground directions (incl.
// slightly negative cosines), so the first branch is valid for dir.y < 0.
vec3 AtmosphereTransmittanceToSurface(vec3 surface_pos, vec3 view_dir, float surface_r,
    bool ground_hit, vec4 camera_transmittance
) {
    float surface_mu = dot(surface_pos, view_dir) / surface_r;
    vec4 numerator;
    vec4 denominator;
    if (ground_hit) {
        numerator = SampleTransmittance(utex_tslut, surface_r, surface_r * surface_r, -surface_mu);
        denominator = camera_transmittance;
    } else {
        numerator = camera_transmittance;
        denominator = SampleTransmittance(utex_tslut, surface_r, surface_r * surface_r, surface_mu);
    }
    // The caller shares the camera lookup and horizon test across both layers.
    // tslut transmittances decode in [0,1], so the ratio never goes negative.
    vec4 segment_transmittance = saturate(numerator / max(denominator, vec4(1.0e-5)));
    return saturate(SpectralFractionToLinearSRGB(segment_transmittance));
}

// Re-light unlit cloud radiance with the current sun/moon; the consumer
// adds skyColor * cloudData.z afterwards. Light colors use the sky's
// sRGB-domain white balance (the same conversion as the sky LUT), so cloud
// and sky hues stay locked as transmittance changes through the day.
vec3 RelightClouds(vec3 cloud_data, vec3 surface_position, float surface_r) {
    float surface_r2 = surface_r * surface_r;
    float sun_mu = dot(surface_position, u_world_sun_dir) / surface_r;
    // moon_mu is just -sun_mu; the host's moon_dir is the antipode of sun_dir.
    float moon_mu = -sun_mu;
    vec3 sun_color = SpectralToLinearSRGBWhiteBalanced(
        SampleTransmittance(utex_tslut, surface_r, surface_r2, sun_mu) * ATM_SOLAR) * ATM_EXPOSURE;
    vec3 moon_color = SpectralToLinearSRGBWhiteBalanced(
        SampleTransmittance(utex_tslut, surface_r, surface_r2, moon_mu) * ATM_MOON_IRR) * ATM_EXPOSURE;
    // Ambient evaluated once at the shared surface position, scaled by the
    // absorbed fraction (1 - T).
    vec3 ambient_cloud_radiance = GetAmbientColorAt(surface_r, sun_mu)
        * (1.0 - cloud_data.z)
        * CLOUD_SKY_LIGHT_STRENGTH;
#ifdef CLOUD_SINGLE_LIGHT
    // One trace means one directional channel, so the light colour carries both
    // illuminants. The sun keeps its colour through the fire-cloud band, where
    // it has crossed the sea-level horizon but the layer still catches it over
    // its own dipped one, and is released once the antisolar side has taken
    // over.
    vec3 light_color = sun_color * TwilightWeight(u_world_sun_dir.y)
        + moon_color * MoonlightFactor(u_world_sun_dir.y);
    return cloud_data.x * light_color + ambient_cloud_radiance;
#else
    return cloud_data.x * sun_color + cloud_data.y * moon_color + ambient_cloud_radiance;
#endif
}

// Compose volumetric + cirrus over the sky. Layer order follows the ray:
// the first-entered layer draws in front (correct occlusion from below,
// between layers, above the cirrus shell).
vec3 RenderCloudLayers(vec3 view_dir, vec3 sky_color,
    vec3 volumetric_radiance,   // packed march output: x = sun, y = moon, z = T
    vec3 volumetric_surface_pos, // km planet-centered volumetric cloud surface
    float volumetric_entry_km,   // ray entry distance into the volumetric shell
    out vec3 cloud_transmittance, // combined REAL transmittance of the cloud layers
    inout vec4 view_transmittance,
    inout bool view_transmittance_cached
) {
    bool volumetric_hit = volumetric_radiance.z < 0.99999;
    float volumetric_transmittance = volumetric_hit ? volumetric_radiance.z : 1.0;

    // Each cloud owns its integrated radiance and true transmittance.
    // The compositor owns the background and atmospheric propagation.
    vec3 cirrus_surface_pos = vec3(0.0);
    float cirrus_entry_km = 1.0e9;
    vec3 cirrus_transmittance = vec3(1.0);
    vec3 cirrus_scattering = vec3(0.0);
    bool cirrus_hit = false;
#ifdef CIRRUS
    // Below the cirrus shell, the lower volumetric shell is encountered first.
    // Above cirrus the order reverses, so an opaque volumetric layer cannot cull it.
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
        volumetric_scattering = RelightClouds(volumetric_radiance,
            volumetric_surface_pos, volumetric_surface_r);
    }

    // Transmitted Milky Way glow, evaluated once and shared by both layers:
    // it is a function of the view ray and the background map alone, so both
    // layer composites evaluate the identical call. Isotropic single
    // scattering of a constant background integrates to source * (1 - T) over
    // the marched column, and the deck's scattering albedo is 1, so each
    // layer scales the shared glow by its own (1 - T) share; a missed layer
    // keeps its transmittance at 1 and adds exact zero, so the adds below
    // carry no per-layer runtime gate. vec4(1.0) transmittance: the fades
    // below carry camera-to-cloud propagation for this term as for the rest
    // of the composite. The layer toggles compile each share away entirely.
#if defined(CLOUD_MILKYWAY_GLOW) || defined(CIRRUS_MILKYWAY_GLOW)
    // The glow call runs only where a compiled-in layer actually holds
    // cloud along the ray.
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
            * ((1.0 - volumetric_transmittance) * CLOUD_MILKYWAY_TRANSMISSION);
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

    // Atmospheric fades blend each composite toward the sky but must NOT
    // touch the true transmittance (a faded far cloud would otherwise let
    // the layer behind show through).
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

    // Depth sort by ray entry: nearer layer drawn last (from the ground the
    // volumetric layer occludes cirrus behind; from above the order flips).
    bool volumetric_in_front = volumetric_entry_km < cirrus_entry_km;
    if (volumetric_in_front) {
        return volumetric_faded + (cirrus_faded - sky_color) * volumetric_transmittance;
    }
    return cirrus_faded + (volumetric_faded - sky_color) * cirrus_transmittance;
}

#endif // LIB_CLOUD_COMPOSITE_GLSL
