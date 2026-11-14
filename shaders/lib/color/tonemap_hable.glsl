// Uncharted 2 filmic tone curve, John Hable: "Filmic Tonemapping Operators"
// (filmicgames.com, 2010) and GDC 2010 "Uncharted 2: HDR Lighting".

#ifndef LIB_COLOR_TONEMAP_HABLE_GLSL
#define LIB_COLOR_TONEMAP_HABLE_GLSL

#include "/lib/core/math_scalar.glsl"

const float HABLE_EXPOSURE_BIAS = 2.0;
const float HABLE_WHITE_POINT = 11.2;

// W shares the RGB evaluation for white normalization.
vec3 TonemapHable(vec3 linear_rgb) {
    vec4 working = vec4(linear_rgb * HABLE_EXPOSURE_BIAS, HABLE_WHITE_POINT);
    vec4 mapped = (working * (0.15 * working + 0.05) + 0.004)
        / (working * (0.15 * working + 0.50) + 0.06) - 0.02 / 0.30;
    return saturate(mapped.rgb / mapped.w);
}

#endif // LIB_COLOR_TONEMAP_HABLE_GLSL
