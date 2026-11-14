#ifndef LIB_VOLUME_AIR_EPIPOLAR_GLSL
#define LIB_VOLUME_AIR_EPIPOLAR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/atmosphere/air_fog.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/scattering/phase.glsl"
#include "/lib/volume/epipolar_core.glsl"

// Dimensionless RGB visibility (shadowed / unshadowed direct-source integral
// ratio); no incident light color or radiance.
vec3 AirShadowRatio(vec3 start_world, vec3 end_world, AirFogDensityProfile profile,
        AirFogMedium medium, float stbn_jitter) {
    vec3 delta = end_world - start_world;
    float length_m = length(delta);
    if (length_m <= 1e-6) return vec3(1.0);
    float direction_y = delta.y / length_m;
    vec3 shadow_start = ProjectToShadowClip(start_world);
    vec3 shadow_end = ProjectToShadowClip(end_world);
    float inv_steps = 1.0 / float(AIR_EPIPOLAR_SHADOW_STEPS);
    float bin_length = length_m * inv_steps;
    vec3 prefix_transmittance = vec3(1.0);
    vec3 numerator = vec3(0.0);
    vec3 denominator = vec3(0.0);
    for (int k = 0; k < AIR_EPIPOLAR_SHADOW_STEPS; ++k) {
        // One jitter offset per ray keeps the bin spacing exactly stratified.
        float u = (float(k) + stbn_jitter) * inv_steps;
        AirFogDensityProfile bin_profile = profile;
        bin_profile.eye_height_m += direction_y * (float(k) * bin_length);
        vec3 bin_tau = AirFogOpticalDepth(bin_profile, medium, direction_y, bin_length);
        vec3 bin_transmittance = exp(-bin_tau);
        vec3 weight = prefix_transmittance * (1.0 - bin_transmittance);
        numerator += weight * ShadowVisibility(shadow_start, shadow_end, u);
        denominator += weight;
        prefix_transmittance *= bin_transmittance;
    }
    // No in-scattering weight means no shadowing; return neutral E=1.
    return mix(vec3(1.0), numerator / max(denominator, vec3(1e-20)),
        greaterThan(denominator, vec3(1e-20)));
}

#endif // LIB_VOLUME_AIR_EPIPOLAR_GLSL
