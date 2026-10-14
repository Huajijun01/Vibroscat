#ifndef LIB_VOLUME_AIR_EPIPOLAR_GLSL
#define LIB_VOLUME_AIR_EPIPOLAR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/atmosphere/air_fog.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/scattering/phase.glsl"
#include "/lib/volume/epipolar_core.glsl"

#if defined(AIR_EPIPOLAR_ACTIVE)
// E = shadowed direct source integral / unshadowed direct source integral.
// It remains a dimensionless RGB visibility, without incident light color or
// radiance. Each bin uses the composite's closed-form transmittance loss
// across its equal-distance interval.
// In channel-wise RGB transport the constant whole-ray source cancels from
// this ratio. The remaining weight is T(start)-T(end), never T alone.
vec3 EpipolarAirShadowRatio(vec3 start_scene, vec3 end_scene, AirFogDensityProfile profile,
        AirFogMedium medium, float stbn_jitter) {
    vec3 delta = end_scene - start_scene;
    float length_m = length(delta);
    if (length_m <= 1e-6) return vec3(1.0);
    float direction_y = delta.y / length_m;
    vec3 shadow_start = ProjectToShadowClip(start_scene);
    vec3 shadow_end = ProjectToShadowClip(end_scene);
    float inv_steps = 1.0 / float(AIR_EPIPOLAR_SHADOW_STEPS);
    float bin_length = length_m * inv_steps;
    vec3 prefix_transmittance = vec3(1.0);
    vec3 numerator = vec3(0.0);
    vec3 denominator = vec3(0.0);
    for (int k = 0; k < AIR_EPIPOLAR_SHADOW_STEPS; ++k) {
        // Stratified, equal-length bins. One jitter offset per ray retains
        // exactly equal spacing and never selects the old inverse-CDF march.
        float u = (float(k) + stbn_jitter) * inv_steps;
        AirFogDensityProfile bin_profile = profile;
        bin_profile.eye_height_m += direction_y * (float(k) * bin_length);
        vec3 bin_tau = AirFogOpticalDepth(bin_profile, medium, direction_y, bin_length);
        vec3 bin_transmittance = exp(-bin_tau);
        vec3 weight = prefix_transmittance * AirFogRemovedFraction(bin_tau, bin_transmittance);
        numerator += weight * EpipolarShadowVisibility(shadow_start, shadow_end, u);
        denominator += weight;
        prefix_transmittance *= bin_transmittance;
    }
    // No scattering means no shadow contribution; choose neutral E=1.
    return mix(vec3(1.0), numerator / max(denominator, vec3(1e-20)),
        greaterThan(denominator, vec3(1e-20)));
}

#endif // AIR_EPIPOLAR_ACTIVE
#endif // LIB_VOLUME_AIR_EPIPOLAR_GLSL
