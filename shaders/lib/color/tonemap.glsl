#ifndef LIB_COLOR_TONEMAP_GLSL
#define LIB_COLOR_TONEMAP_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/tonemap_aces2.glsl"
#include "/lib/color/tonemap_agx.glsl"
#include "/lib/color/tonemap_blender_agx.glsl"
#include "/lib/color/tonemap_gt7.glsl"
#include "/lib/color/tonemap_lpm.glsl"
#include "/lib/color/tonemap_opendrt.glsl"
#include "/lib/color/tonemap_reinhard_agx.glsl"
#include "/lib/color/tonemap_calibration.glsl"


// Keep reference evaluation available for validation, without pack grading.
vec3 TonemapReference(vec3 linear_rgb) {
#if TONEMAP_MODE == 0
    return TonemapAGX(linear_rgb);
#elif TONEMAP_MODE == 1
    return TonemapACES2(linear_rgb);
#elif TONEMAP_MODE == 2
    return TonemapBlenderAGX(linear_rgb);
#elif TONEMAP_MODE == 3
    return TonemapOpenDRT(linear_rgb);
#elif TONEMAP_MODE == 4
    return TonemapLPM(linear_rgb);
#elif TONEMAP_MODE == 6
    return TonemapReinhardAGX(linear_rgb);
#else
    return TonemapGT7(linear_rgb);
#endif
}

vec3 Tonemap(vec3 linear_rgb) {
    return CalibrateTonemapOutput(TonemapReference(linear_rgb));
}

// Rational compression for temporal HDR history; this is not a display DRT.
// L2-optimal first-order rational fit of the TonemapGT7 gray response over
// [0, 16] (research/gt7-fast-tonemap); the pair must keep identical
// constants so FastInvtonemap inverts FastTonemap exactly.
vec3 FastTonemap(vec3 x) {
    return x / (0.951067 * x + 0.344568);
}

vec3 FastInvtonemap(vec3 y) {
    return 0.344568 * y / (1.0 - 0.951067 * y);
}

// HDR compression for the TAA history round-trip: HDRCompress =
// sqrt(FastTonemap), inverse = HDRDecompress. Consumer: taa.fragment.
vec3 HDRCompress(vec3 x) {
    return sqrt(FastTonemap(x));
}

vec3 HDRDecompress(vec3 y) {
    return FastInvtonemap(y * y);
}

#endif // LIB_COLOR_TONEMAP_GLSL
