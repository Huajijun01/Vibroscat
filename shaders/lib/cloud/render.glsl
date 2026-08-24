#ifndef LIB_CLOUD_RENDER_GLSL
#define LIB_CLOUD_RENDER_GLSL

// High-level cloud compositor: final sky color with volumetric clouds +
// cirrus. Each layer fades toward the sky by the atmospheric transmittance
// to its surface position (linear RGB).

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/cloud/volumetric.glsl"
#include "/lib/cloud/cirrus.glsl"
#include "/lib/atmosphere/core.glsl"

// Atmospheric transmittance along the camera→cloud-surface ray (UE
// GetTransmittance scheme; (r, mu) camera, (r_d, mu_d) surface, same ray):
//   ground miss:  T = T_lut(r, mu)      / T_lut(r_d, mu_d)
//   ground hit:   T = T_lut(r_d, -mu_d) / T_lut(r, -mu)   (reciprocity)
// The baked LUT stores the full chord for non-ground directions (incl.
// slightly negative cosines), so the first branch is valid for dir.y < 0.
vec3 CloudSurfaceTransmittance(vec3 surface_pos, vec3 view_dir) {
    if (any(notEqual(surface_pos, vec3(0.0)))) {
        vec3 camera_pos = AtmosphereCameraPosition();
        float r = length(camera_pos);
        float r2 = r * r;
        float mu = dot(camera_pos, view_dir) / r;
        float d = length(surface_pos - camera_pos);
        float r_d = sqrt(d * d + 2.0 * r * mu * d + r * r);
        float r_d2 = r_d * r_d;
        float mu_d = (r * mu + d) / r_d;

        vec4 numerator;
        vec4 denominator;
        if (CloudLightBlockedByEarth(camera_pos, r2, view_dir)) {
            // The ray hits the ground: upward LUT samples via reciprocity.
            numerator = SampleTransmittance(TRANSMITTANCE_LUT, r_d, r_d2, -mu_d);
            denominator = SampleTransmittance(TRANSMITTANCE_LUT, r, r2, -mu);
        } else {
            // Upward ray exiting through the top, or a shallow downward ray
            // that misses the ground: both LUT cosines are valid.
            numerator = SampleTransmittance(TRANSMITTANCE_LUT, r, r2, mu);
            denominator = SampleTransmittance(TRANSMITTANCE_LUT, r_d, r_d2, mu_d);
        }
        // LUT has exact zeros near the horizon: guard the denominator (UE
        // divides unguarded).
        vec4 segment_transmittance = min(numerator / max(denominator, vec4(1.0e-5)), vec4(1.0));
        return TransmittanceToLinearSRGB(segment_transmittance, vec4(1.0));
    }
    return vec3(1.0);
}

// Re-light unlit cloud radiance with the current sun/moon; the consumer
// adds skyColor · cloudData.z afterwards.
const float MOON_DARKEN = 0.4;
vec3 RelightClouds(vec3 cloud_data, vec3 surface_position) {
    vec3 sun_dir = normalize(u_world_sun_dir);
    vec3 moon_dir = -sun_dir;
    float surface_r = length(surface_position);
    float surface_r2 = surface_r * surface_r;
    float sun_mu = dot(surface_position, sun_dir) / surface_r;
    float moon_mu = dot(surface_position, moon_dir) / surface_r;
    vec3 sun_color = SpectralToLinearSRGB(
        SampleTransmittance(TRANSMITTANCE_LUT, surface_r, surface_r2, sun_mu) * ATM_SOLAR) * ATM_EXPOSURE;
    vec3 moon_color = SpectralToLinearSRGB(
        SampleTransmittance(TRANSMITTANCE_LUT, surface_r, surface_r2, moon_mu) * ATM_MOON_IRR) * ATM_EXPOSURE * MOON_DARKEN;
    // Ambient evaluated once at the shared surface position, scaled by the
    // absorbed fraction (1 - T).
    vec3 ambient_cloud_radiance = GetAmbientColor(surface_position, sun_dir)
        * (1.0 - cloud_data.z)
        * CLOUD_SKY_LIGHT_STRENGTH;
    float direct_sun_radiance = cloud_data.x;
    float direct_moon_radiance = cloud_data.y;
    return direct_sun_radiance * sun_color + direct_moon_radiance * moon_color + ambient_cloud_radiance;
}

// Compose volumetric + cirrus over the sky. Layer order follows the ray:
// the first-entered layer draws in front (correct occlusion from below,
// between layers, above the cirrus shell).
vec3 RenderCloudLayers(vec3 view_dir, vec3 sky_color,
    vec3 volumetric_radiance,   // packed march output: x = sun, y = moon, z = T
    vec3 volumetric_surface_pos, // km planet-centered volumetric cloud surface
    float volumetric_entry_km,   // ray entry distance into the volumetric shell
    out vec3 cloud_transmittance // combined REAL transmittance of the cloud layers
) {
    // Volumetric layer composite over pure sky.
    vec3 volumetric_scattering = vec3(0.0);
    float volumetric_transmittance = 1.0;
    if (volumetric_radiance.z < 0.99999) {
        volumetric_scattering = RelightClouds(volumetric_radiance, volumetric_surface_pos);
        volumetric_transmittance = volumetric_radiance.z;
    }
    vec3 volumetric_composite = volumetric_scattering + sky_color * volumetric_transmittance;

    // Cirrus layer composite over pure sky.
    vec3 cirrus_surface_pos;
    vec3 cirrus_transmittance;
    vec3 cirrus_composite = RenderCirrusClouds(view_dir, sky_color, cirrus_surface_pos, cirrus_transmittance);

    // Atmospheric fades blend each composite toward the sky but must NOT
    // touch the true transmittance (a faded far cloud would otherwise let
    // the layer behind show through).
    vec3 volumetric_fade = CloudSurfaceTransmittance(volumetric_surface_pos, view_dir);
    vec3 cirrus_fade = CloudSurfaceTransmittance(cirrus_surface_pos, view_dir);
    vec3 volumetric_faded = mix(sky_color, volumetric_composite, volumetric_fade);
    vec3 cirrus_faded = mix(sky_color, cirrus_composite, cirrus_fade);

    // Celestial discs attenuated by the combined REAL transmittance of every
    // cloud layer in front.
    cloud_transmittance = vec3(volumetric_transmittance) * cirrus_transmittance;

    // Depth sort by ray entry: nearer layer drawn last (from the ground the
    // volumetric layer occludes cirrus behind; from above the order flips).
    float cirrus_entry_km = any(notEqual(cirrus_surface_pos, vec3(0.0)))
        ? length(cirrus_surface_pos - AtmosphereCameraPosition()) : 1.0e9;
    bool volumetric_in_front = volumetric_transmittance < 0.99999 && volumetric_entry_km < cirrus_entry_km;
    if (volumetric_in_front) {
        return volumetric_faded + (cirrus_faded - sky_color) * volumetric_transmittance;
    }
    return cirrus_faded + (volumetric_faded - sky_color) * cirrus_transmittance;
}

#endif
