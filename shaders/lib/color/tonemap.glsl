#ifndef LIB_COLOR_TONEMAP_GLSL
#define LIB_COLOR_TONEMAP_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/tonemap_aces2.glsl"
#include "/lib/color/tonemap_agx.glsl"
#include "/lib/color/tonemap_blender_agx.glsl"
#include "/lib/color/tonemap_gt7.glsl"
#include "/lib/color/tonemap_lpm.glsl"
#include "/lib/color/tonemap_opendrt.glsl"


vec3 Tonemap(vec3 linear_rgb) {
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
#else
    return TonemapGT7(linear_rgb);
#endif
}

// Rational compression for temporal HDR history; this is not a display DRT.
vec3 FastTonemap(vec3 x) {
    return x / (0.903453 * x + 0.427205);
}

vec3 FastInvtonemap(vec3 y) {
    return 0.427205 * y / (1.0 - 0.903453 * y);
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
