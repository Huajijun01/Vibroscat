#ifndef LIB_COLOR_TONEMAP_ACES_GLSL
#define LIB_COLOR_TONEMAP_ACES_GLSL


// ACES 1.0 RRT+ODT fitted curve (rrtAndODTFit, Narkowicz 2016), linear
// sRGB -> ACEScg -> fit -> sRGB.
const mat3 SRGB_TO_ACESCG = mat3(
    vec3(0.613097, 0.070194, 0.020616),
    vec3(0.339523, 0.916154, 0.109570),
    vec3(0.047371, 0.013653, 0.869815));
const mat3 ACESCG_TO_SRGB = mat3(
    vec3(1.705052, -0.130257, -0.024003),
    vec3(-0.621793, 1.140803, -0.128969),
    vec3(-0.083258, -0.010549, 1.152972));

// Pre-scale: f(k*0.18) = 0.18 (mid-grey anchor shared with the other
// tonemap modes).
const float ACES_MID_GREY_SCALE = 0.72317081;

vec3 TonemapACES(vec3 linear_rgb) {
    vec3 acescg = SRGB_TO_ACESCG * max(linear_rgb, 0.0);
    vec3 fitted = ACES_MID_GREY_SCALE * acescg;
    fitted = fitted * (2.51 * fitted + 0.03) / (fitted * (2.43 * fitted + 0.59) + 0.14);
    return ACESCG_TO_SRGB * fitted;
}

#endif // LIB_COLOR_TONEMAP_ACES_GLSL
