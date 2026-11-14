// ACES filmic approximation, Krzysztof Narkowicz, "ACES Filmic Tone Mapping
// Curve" (2016): https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/

#ifndef LIB_COLOR_TONEMAP_ACES_FILMIC_GLSL
#define LIB_COLOR_TONEMAP_ACES_FILMIC_GLSL

#include "/lib/core/math_scalar.glsl"

vec3 TonemapACESFilmic(vec3 linear_rgb) {
    return saturate((linear_rgb * (2.51 * linear_rgb + 0.03))
        / (linear_rgb * (2.43 * linear_rgb + 0.59) + 0.14));
}

#endif // LIB_COLOR_TONEMAP_ACES_FILMIC_GLSL
