#ifndef LIB_VOLUME_AIR_EPIPOLAR_GLSL
#define LIB_VOLUME_AIR_EPIPOLAR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/air_fog.glsl"
#include "/lib/volume/epipolar_core.glsl"

#ifdef AIR_EPIPOLAR_ACTIVE

// Preserve historical E = integral(T(s)*V(s) ds) / integral(T(s) ds).
// E is a normalized scalar shadow visibility, replicated in RGB; it contains
// neither light color nor density/scattering gain. Only T changes with height.
vec3 EpipolarAirShadowRatio(vec3 start_scene, vec3 end_scene, AirFogDensityProfile profile,
        float extinction, float stbn_jitter) {
    vec3 delta = end_scene - start_scene;
    float length_m = length(delta);
    if (length_m <= 1e-6) return vec3(1.0);
    float direction_y = delta.y / length_m;
    vec3 shadow_start = ProjectToShadowClip(start_scene);
    vec3 shadow_end = ProjectToShadowClip(end_scene);
    float inv_steps = 1.0 / float(AIR_EPIPOLAR_SHADOW_STEPS);
    float first_mass = AirFogColumnDensity(profile, direction_y, stbn_jitter * inv_steps * length_m);
    float numerator = 0.0;
    float denominator = 0.0;
    for (int k = 0; k < AIR_EPIPOLAR_SHADOW_STEPS; ++k) {
        // Stratified, equal-length bins. One jitter offset per ray retains
        // exactly equal spacing and never selects the old inverse-CDF march.
        float u = (float(k) + stbn_jitter) * inv_steps;
        float mass = AirFogColumnDensity(profile, direction_y, u * length_m);
        // A common exp(+tau_first) cancels in the ratio, preventing both sums
        // from underflowing on optically thick rays. The first weight is 1.
        float weight = exp(-extinction * max(mass - first_mass, 0.0));
        numerator += weight * EpipolarShadowVisibility(shadow_start, shadow_end, u);
        denominator += weight;
    }
    return vec3(saturate(numerator / denominator));
}

#endif // AIR_EPIPOLAR_ACTIVE
#endif // LIB_VOLUME_AIR_EPIPOLAR_GLSL
