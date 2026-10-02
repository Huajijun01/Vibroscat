#ifndef LIB_RAYTRACE_SSR_DEPTH_GLSL
#define LIB_RAYTRACE_SSR_DEPTH_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"

// Squaring normalized view depth halves FP16 relative distance error. Scale
// to the largest finite half (65504), keeping near surfaces out of subnormals
// for normal render distances. Sky uses the clipping-depth endpoint, so it
// participates in ordinary depth comparisons without a separate rejection.
const float SSR_DEPTH_HALF_MAX = 65504.0;
const float SSR_DEPTH_HALF_MIN = 5.960464477539063e-8;

float EncodeSSRDepth(float screen_depth) {
    // Iris 'far' is render distance, not the clipping plane. Use the inverse
    // projection at screen depth 1 so visible geometry is never truncated.
    float inverse_clip_depth = gbufferProjectionInverse[2][3] + gbufferProjectionInverse[3][3];
    float normalized_depth = min(LinearDepthFromScreenDepth(screen_depth) * inverse_clip_depth, 1.0);
    return max(SSR_DEPTH_HALF_MIN,
        SSR_DEPTH_HALF_MAX * normalized_depth * normalized_depth);
}

float ReadSSRDepthSample(vec2 uv) {
#ifdef SSR_QUARTER_DEPTH_ACTIVE
    float encoded_depth = texture(usam_ssr_depth, uv).r;
    float inverse_clip_depth = gbufferProjectionInverse[2][3] + gbufferProjectionInverse[3][3];
    return sqrt(encoded_depth / SSR_DEPTH_HALF_MAX) / inverse_clip_depth;
#else
    return textureLod(depthtex1, uv, 0.0).r;
#endif
}

bool SSRDepthSampleIsSky(float depth_sample) {
#ifdef SSR_QUARTER_DEPTH_ACTIVE
    float inverse_clip_depth = gbufferProjectionInverse[2][3] + gbufferProjectionInverse[3][3];
    return depth_sample >= 1.0 / inverse_clip_depth;
#else
    return depth_sample >= 1.0;
#endif
}

float SSRRayDepthFromScreen(float screen_depth) {
#ifdef SSR_QUARTER_DEPTH_ACTIVE
    return LinearDepthFromScreenDepth(screen_depth);
#else
    return screen_depth;
#endif
}

bool SSRDepthSampleBeforeRay(float surface_depth, float ray_depth) {
    return surface_depth < ray_depth;
}

#endif // LIB_RAYTRACE_SSR_DEPTH_GLSL
