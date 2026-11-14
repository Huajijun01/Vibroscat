#ifndef LIB_COLOR_TONEMAP_GLSL
#define LIB_COLOR_TONEMAP_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/tonemap_aces_filmic.glsl"
#include "/lib/color/tonemap_aces_fitted.glsl"
#include "/lib/color/tonemap_agx.glsl"
#include "/lib/color/tonemap_gt7.glsl"
#include "/lib/color/tonemap_hable.glsl"
#include "/lib/color/tonemap_hejl2015.glsl"
#include "/lib/color/tonemap_opendrt.glsl"


// Modes 6-8 and 10 key scene 0.18 gray near 0.14-0.18 display-linear.
vec3 Tonemap(vec3 linear_rgb) {
#if TONEMAP_MODE == 0
    return TonemapAGX(linear_rgb);
#elif TONEMAP_MODE == 3
    return TonemapOpenDRT(linear_rgb);
#elif TONEMAP_MODE == 6
    return TonemapACESFitted(linear_rgb * 1.25);
#elif TONEMAP_MODE == 7
    return TonemapHable(linear_rgb * 1.25);
#elif TONEMAP_MODE == 8
    return TonemapACESFilmic(linear_rgb * 0.6);
#elif TONEMAP_MODE == 10
    return TonemapHejl2015(linear_rgb * 0.7);
#else
    return TonemapGT7(linear_rgb);
#endif
}

// History-space compression, not a display DRT; fitted to the GT7 gray response.
// FastTonemap and FastInvTonemap must keep identical constants to stay exact inverses.
vec3 FastTonemap(vec3 x) {
    return x / (0.951067 * x + 0.344568);
}

vec3 FastInvTonemap(vec3 y) {
    return 0.344568 * y / (1.0 - 0.951067 * y);
}

// TAA history round-trip; HDRDecompress is its exact inverse.
vec3 HDRCompress(vec3 x) {
    return sqrt(FastTonemap(x));
}

vec3 HDRDecompress(vec3 y) {
    return FastInvTonemap(y * y);
}

#endif // LIB_COLOR_TONEMAP_GLSL
