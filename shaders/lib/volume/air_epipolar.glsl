#ifndef LIB_VOLUME_AIR_EPIPOLAR_GLSL
#define LIB_VOLUME_AIR_EPIPOLAR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/atmosphere/air_fog.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/scattering/phase.glsl"
#include "/lib/volume/epipolar_core.glsl"

#ifdef AIR_EPIPOLAR_ACTIVE

// E = shadowed direct source integral / unshadowed direct source integral.
// It remains a dimensionless RGB visibility, without incident light color or
// radiance. Each bin integrates the same spectral Rayleigh/Mie sources as the
// composite; phase affects their relative weights when rain and clear air mix.
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
    float cos_theta = dot(delta / length_m, u_world_light_dir);
    float phase_ray = PhaseRayleigh(cos_theta);
    float phase_mie = PhaseHenyeyGreensteinTripleLobe(cos_theta, ATM_MIE_PHASE);
    vec4 prefix_transmittance = vec4(1.0);
    vec3 numerator = vec3(0.0);
    vec3 denominator = vec3(0.0);
    for (int k = 0; k < AIR_EPIPOLAR_SHADOW_STEPS; ++k) {
        // Stratified, equal-length bins. One jitter offset per ray retains
        // exactly equal spacing and never selects the old inverse-CDF march.
        float u = (float(k) + stbn_jitter) * inv_steps;
        AirFogDensityProfile bin_profile = profile;
        bin_profile.eye_height_m += direction_y * (float(k) * bin_length);
        AirFogIntegral bin_integral = IntegrateAirFogScattering(bin_profile, medium, direction_y, bin_length);
        vec4 source = prefix_transmittance * (bin_integral.scattering_ray * phase_ray
            + bin_integral.scattering_mie * phase_mie);
        // Normalize after the same linear spectral conversion as the composite.
        // Its white normalization and fog intensity cancel in this ratio.
        // Preserve signed color-fit contributions instead of clamping bins.
        vec3 weight = SpectralToLinearSRGB(source);
        numerator += weight * EpipolarShadowVisibility(shadow_start, shadow_end, u);
        denominator += weight;
        prefix_transmittance *= bin_integral.transmittance;
    }
    // No scattering means no shadow contribution; choose neutral E=1.
    return mix(vec3(1.0), numerator / max(denominator, vec3(1e-20)),
        greaterThan(denominator, vec3(1e-20)));
}

#endif // AIR_EPIPOLAR_ACTIVE
#endif // LIB_VOLUME_AIR_EPIPOLAR_GLSL
