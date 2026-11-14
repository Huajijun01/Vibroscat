#ifndef LIB_RAYTRACE_SSR_DEPTH_GLSL
#define LIB_RAYTRACE_SSR_DEPTH_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/render_scale.glsl"

// Squared depth halves FP16 relative distance error; scaled to the largest
// finite half (65504) so near surfaces stay out of subnormals. Sky encodes to
// the clipping-depth endpoint and passes ordinary depth comparisons without a separate rejection.
const float SQUARED_DEPTH_HALF_MAX = 65504.0;
const float SQUARED_DEPTH_HALF_MIN = 5.960464477539063e-8;
const float SQUARED_DEPTH_HALF_RCP_SQRT = 0.0039072041399776936;  // inversesqrt(65504)

float EncodeSquaredDepth(float screen_depth) {
    // Iris 'far' is render distance, not the clipping plane; the inverse
    // projection at screen depth 1 never truncates visible geometry.
    float normalized_depth = saturate(LinearDepthFromScreenDepth(screen_depth) * u_inv_clip_depth);
    return max(SQUARED_DEPTH_HALF_MIN,
        SQUARED_DEPTH_HALF_MAX * normalized_depth * normalized_depth);
}

float ReadDepthSample(vec2 uv) {
#if defined(SSR_QUARTER_DEPTH_ACTIVE)
    // Explicit base level: the single-level image alias makes LOD 0 the only
    // defined result across the march loops' divergent prefetch exits.
#if defined(TAAU_ACTIVE)
    float encoded_depth = textureLod(usam_ssr_depth, SceneImageUV(uv, vec2(textureSize(usam_ssr_depth, 0)), 0.25), 0.0).r;
#else
    float encoded_depth = textureLod(usam_ssr_depth, uv, 0.0).r;
#endif
    // The CPU folds the inverse-depth row-sum divide into u_squared_depth_decode.
    return sqrt(encoded_depth) * u_squared_depth_decode;
#else
#if defined(TAAU_ACTIVE)
    return textureLod(depthtex1, SceneTextureUV(uv), 0.0).r;
#else
    return textureLod(depthtex1, uv, 0.0).r;
#endif
#endif
}

bool DepthSampleIsSky(float depth_sample) {
#if defined(SSR_QUARTER_DEPTH_ACTIVE)
    // Same positive-domain product form as DepthSampleBeforeRay below.
    return depth_sample * u_inv_clip_depth >= 1.0;
#else
    return depth_sample >= 1.0;
#endif
}

float RayDepthFromScreen(float screen_depth) {
#if defined(SSR_QUARTER_DEPTH_ACTIVE)
    // Reciprocal view depth stays affine even when the jittered final step
    // extends beyond the far plane; linear depth would cross its pole.
    return (screen_depth * 2.0 - 1.0) * gbufferProjectionInverse[2][3]
        + gbufferProjectionInverse[3][3];
#else
    return screen_depth;
#endif
}

bool DepthSampleBeforeRay(float surface_depth, float ray_depth) {
#if defined(SSR_QUARTER_DEPTH_ACTIVE)
    // Encoded depths carry a strictly positive floor, so 1/d > r and r*d < 1
    // select identically; the product form trades the divide for a multiply
    // (boundaries may flip within 1 ulp).
    return ray_depth * surface_depth < 1.0;
#else
    return surface_depth < ray_depth;
#endif
}

#endif // LIB_RAYTRACE_SSR_DEPTH_GLSL
