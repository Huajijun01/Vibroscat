#ifndef LIB_VOLUME_AIR_EPIPOLAR_GLSL
#define LIB_VOLUME_AIR_EPIPOLAR_GLSL

// Air-fog epipolar helpers: air column key + air shadow ratio. Depends on
// epipolar_core.glsl; functions only (uniforms from the includer).

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/volume/epipolar_core.glsl"

#ifdef EPIPOLAR_VOLUMETRICS

// Air-fog depth key for the epipolar filter: nearest visible surface
// (depthtex0), because air fog composites over the final water surface too.
// Underwater the air fog is disabled, so the key is invalid (0). Linear
// viewZ, same space as the water key (see EpipolarWaterColumnKey).
float EpipolarAirColumnKey(vec2 uv01) {
    ivec2 texel = EpipolarScreenTexel(uv01);
    if (isEyeInWater == 1) return 0.0;
    return LinearDepthFromScreenDepth(texelFetch(depthtex0, texel, 0).r);
}

// Air shadow ratio: no light-direction OD, view-path transmittance only
// (groundLight approximates the active light).
// stbn_jitter is the STBN dither sampled by the integrate pass main.
vec3 EpipolarAirShadowRatio(vec3 start_scene, vec3 end_scene, float extinction,
                            float stbn_jitter) {
    vec3 s = ProjectToShadowClip(start_scene);
    vec3 e = ProjectToShadowClip(end_scene);
    vec3 diff = end_scene - start_scene;
    float segment_length = length(diff);
    float seg_optical = segment_length;
    float t_end = exp(-extinction * seg_optical);
    float tau = -log(max(t_end, 1e-6));
    bool uniform_steps = abs(seg_optical) < 1e-3 || abs(tau) < 1e-3;
    vec3 numerator = vec3(0.0);
    vec3 denominator = vec3(0.0);
    for (int k = 0; k < AIR_EPIPOLAR_SHADOW_STEPS; ++k) {
        float p = (float(k) + stbn_jitter) / float(AIR_EPIPOLAR_SHADOW_STEPS);
        float u;
        vec3 weight;
        if (uniform_steps) {
            u = p;
            weight = vec3(exp(-extinction * (u * segment_length)));
        } else {
            // t_sample decays arithmetically in p, so u = -log(t_sample)/tau is
            // the inverse CDF of the view-path transmittance: every step
            // already carries an equal share of the transmittance mass and its
            // estimator weight is 1. Weighting it by t_sample as well squares
            // the sampling density, which biases the ratio toward the far end
            // of the column (int(T^2*V)/int(T^2) instead of int(T*V)/int(T))
            // and does not vanish with more steps. The identity degrades
            // gracefully once t_end saturates at 1e-6 (~11.5 km of continuous
            // sea-level air, unreachable inside the fog slab).
            float t_sample = 1.0 + p * (t_end - 1.0);
            u = clamp(-log(max(t_sample, 1e-6)) / tau, 0.0, 1.0);
            weight = vec3(1.0);
        }
        float shadow = EpipolarShadowVisibility(s, e, u);
        numerator += weight * shadow;
        denominator += weight;
    }
    return Saturate(numerator / max(denominator, vec3(1e-6)));
}

#endif // EPIPOLAR_VOLUMETRICS
#endif // LIB_VOLUME_AIR_EPIPOLAR_GLSL
