#ifndef LIB_COLOR_TONEMAP_GLSL
#define LIB_COLOR_TONEMAP_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/tonemap_aces.glsl"
#include "/lib/color/tonemap_agx.glsl"
#include "/lib/color/tonemap_drt_oklab.glsl"
#include "/lib/color/tonemap_gt7.glsl"
#include "/lib/color/tonemap_reinhard.glsl"


vec3 Tonemap(vec3 linear_rgb) {
#if TONEMAP_MODE == 0
    return TonemapAGX(linear_rgb);
#elif TONEMAP_MODE == 1
    return TonemapOklabDRT(linear_rgb);
#elif TONEMAP_MODE == 2
    return TonemapACES(linear_rgb);
#elif TONEMAP_MODE == 4
    return TonemapGT7(linear_rgb);
#elif TONEMAP_MODE == 5
    return TonemapReinhardAgx(linear_rgb);
#else
    return TonemapReinhardGamut(linear_rgb);
#endif
}

// Rational-only mapping used by the bloom chain (bright-pass transfer).
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
