// Filmic curve fit, Jim Hejl (2015):
// https://twitter.com/jimhejl/status/633777619998130176

#ifndef LIB_COLOR_TONEMAP_HEJL2015_GLSL
#define LIB_COLOR_TONEMAP_HEJL2015_GLSL

#include "/lib/core/math_scalar.glsl"

const float HEJL2015_WHITE_POINT = 11.2;

// Display-linear output; scene white normalizes to one.
vec3 TonemapHejl2015(vec3 linear_rgb) {
    vec4 working = vec4(linear_rgb, HEJL2015_WHITE_POINT);
    vec4 curve = 1.425 * working + 0.05;
    vec4 mapped = (working * curve + 0.004) / (working * (curve + 0.55) + 0.0491) - 0.0821;
    return saturate(mapped.rgb / mapped.w);
}

#endif // LIB_COLOR_TONEMAP_HEJL2015_GLSL
