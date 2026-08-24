#ifndef LIB_VOLUME_AIR_EPIPOLAR_GLSL
#define LIB_VOLUME_AIR_EPIPOLAR_GLSL

// Air-fog epipolar helpers: air column key + air shadow ratio. Depends on
// epipolar_core.glsl; functions only (uniforms from the includer).

#include "/lib/contract/settings.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/volume/epipolar_core.glsl"
#include "/lib/core/coordinates.glsl"

#ifdef EPIPOLAR_WATER

// Air-fog depth key for the epipolar filter: nearest visible surface
// (depthtex0), because air fog composites over the final water surface too.
// Underwater the air fog is disabled, so the key is invalid (0). Linear
// viewZ, same space as the water key (see EpipolarColumnKey).
float EpipolarAirColumnKey(vec2 uv01, ivec2 texel) {
    if (isEyeInWater == 1) return 0.0;
    return EpipolarViewZ(uv01, texelFetch(depthtex0, texel, 0).r);
}

// Air shadow ratio: no light-direction OD, view-path transmittance only
// (groundLight approximates the active light).
vec3 EpipolarAirShadowRatio(vec3 start_scene, vec3 end_scene, float extinction,
                            ivec2 rand_coord) {
    vec3 s = ProjectToShadowClip(start_scene);
    vec3 e = ProjectToShadowClip(end_scene);
    vec3 diff = end_scene - start_scene;
    float S = length(diff);
    float seg_optical = S;
    float t_end = exp(-extinction * seg_optical);
    float tau = -log(max(t_end, 1e-6));
    bool uniform_steps = abs(seg_optical) < 1e-3 || abs(tau) < 1e-3;
    // Without TAA, only spatial blue noise dithers the slice, so it would
    // shimmer (no temporal accumulation to hide it).
#ifdef TAA
    float jitter = SampleSTBN(rand_coord, frameCounter);
#else
    float jitter = SampleSTBN(rand_coord, 0);
#endif
    vec3 num = vec3(0.0);
    vec3 den = vec3(0.0);
    for (int k = 0; k < EPIPOLAR_SHADOW_STEPS; ++k) {
        float p = (float(k) + jitter) / float(EPIPOLAR_SHADOW_STEPS);
        float u;
        if (uniform_steps) {
            u = p;
        } else {
            float t_sample = 1.0 + p * (t_end - 1.0);
            u = -log(max(t_sample, 1e-6)) / tau;
            u = clamp(u, 0.0, 1.0);
        }
        vec3 clip = mix(s, e, u);
        vec2 uv = clip.xy / GetDistortFactor(clip.xy) * 0.5 + 0.5;
        float depth = ProtectShadowDepth(clip.z * 0.5 + 0.5);
        float shadow = texture(shadowtex1, vec3(uv, depth));
        vec3 weight = vec3(exp(-extinction * (u * S)));
        num += weight * shadow;
        den += weight;
    }
    return Saturate(num / max(den, vec3(1e-6)));
}

#endif // EPIPOLAR_WATER
#endif // LIB_VOLUME_AIR_EPIPOLAR_GLSL
