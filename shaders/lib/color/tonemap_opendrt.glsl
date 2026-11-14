#ifndef LIB_COLOR_TONEMAP_OPENDRT_GLSL
#define LIB_COLOR_TONEMAP_OPENDRT_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"

#if TONEMAP_MODE == 3


// OpenDRT (mode 3), ported from github.com/jedypod/open-display-transform,
// display-transforms/opendrt/OpenDRT.dctl (GPL-3.0, modified;
// licenses/THIRD_PARTY_NOTICES.md section 4).

// Rec.709 <-> P3D65; each vec3 is one column, so the mat3 holds the row-major product transposed.
const mat3 ODT_SRGB_TO_P3D65 = mat3(
    vec3(0.8224619687, 0.0331941989, 0.0170826307),
    vec3(0.1775380313, 0.9668058011, 0.0723974407),
    vec3(0.0000000000, 0.0000000000, 0.9105199286));
const mat3 ODT_P3D65_TO_SRGB = mat3(
    vec3(1.2249401763, -0.0420569547, -0.0196375546),
    vec3(-0.2249401763, 1.0420569547, -0.0786360456),
    vec3(0.0000000000, 0.0000000000, 1.0982736001));

// The official Standard look preset of OpenDRT v1.1.0.
const float ODT_CONTRAST = 1.66;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.003;
const float ODT_OFFSET = 0.005;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 0;
const float ODT_LOW_CONTRAST = 0.0;
const float ODT_LOW_CONTRAST_WIDTH = 0.5;
const float ODT_CREATIVE_WHITE_RANGE = 0.25;
const float ODT_RENDER_SATURATION = 0.35;
const float ODT_RENDER_WEIGHT_R = 0.25;
const float ODT_RENDER_WEIGHT_B = 0.55;
const float ODT_PURITY_LOW = 0.25;
const float ODT_PURITY_LOW_R = 0.5;
const float ODT_PURITY_LOW_G = 0.0;
const float ODT_PURITY_LOW_B = 0.1;
const float ODT_PURITY_HIGH = 0.25;
const float ODT_PURITY_HIGH_R = 0.5;
const float ODT_PURITY_HIGH_B = 0.0;
const float ODT_PURITY_SOFTCLIP_C = 0.06;
const float ODT_PURITY_SOFTCLIP_M = 0.08;
const float ODT_PURITY_SOFTCLIP_Y = 0.06;
const float ODT_MID_PURITY_LOW = 0.4;
const float ODT_MID_PURITY_LOW_RANGE = 0.25;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.5;
const float ODT_MID_PURITY_HIGH = -0.8;
const float ODT_MID_PURITY_HIGH_RANGE = 0.35;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.4;
const float ODT_BRILLIANCE = 0.0;
const float ODT_BRILLIANCE_R = -2.5;
const float ODT_BRILLIANCE_G = -1.5;
const float ODT_BRILLIANCE_B = -1.5;
const float ODT_BRILLIANCE_RANGE = 0.5;
const float ODT_BRILLIANCE_STRENGTH = 0.35;
const float ODT_POST_BRILLIANCE = -0.5;
const float ODT_POST_BRILLIANCE_R = -1.25;
const float ODT_POST_BRILLIANCE_G = -1.25;
const float ODT_POST_BRILLIANCE_B = -0.25;
const float ODT_HUE_CONTRAST_R = 1.0;
const float ODT_HUE_CONTRAST_RANGE = 0.3;
const float ODT_HUE_SHIFT_R = 0.6;
const float ODT_HUE_SHIFT_R_RANGE = 0.6;
const float ODT_HUE_SHIFT_G = 0.35;
const float ODT_HUE_SHIFT_G_RANGE = 1.0;
const float ODT_HUE_SHIFT_B = 0.66;
const float ODT_HUE_SHIFT_B_RANGE = 1.0;
const float ODT_HUE_SHIFT_C = 0.25;
const float ODT_HUE_SHIFT_C_RANGE = 1.0;
const float ODT_HUE_SHIFT_M = 0.0;
const float ODT_HUE_SHIFT_M_RANGE = 1.0;
const float ODT_HUE_SHIFT_Y = 0.0;
const float ODT_HUE_SHIFT_Y_RANGE = 1.0;
const mat3 ODT_CREATIVE_WHITE_MATRIX = mat3(
    vec3(1.224940176280561, -0.042056954709688, -0.019637554590334),
    vec3(-0.224940176280560, 1.042056954709688, -0.078636045550632),
    vec3(0.000000000000000, -0.000000000000000, 1.098273600140966));
const float ODT_CREATIVE_WHITE_NORMALIZATION = 1.000000000000;

const float ODT_PI = 3.14159265358979323846;
const float ODT_SQRT3_INVERSE = 0.57735026918962576;
// SDR paper white in nits.
const float ODT_PEAK_LUMINANCE = 100.0;
// Bright-surround display encoding: flattens the curve exponent by 2 * 5%.
const float ODT_SURROUND = 2.0;
const float ODT_SCENE_GREY = 0.18;
const float ODT_GREY_LUMINANCE = 10.0;
const float ODT_ACHROMATIC_TOE = 0.25;

// Hue angles rotated so red sits at 0; secondary angles offset from exact CMY.
const float ODT_HUE_ORIGIN = 1.10714931;
const float ODT_HUE_ANGLE_R = 0.1;
const float ODT_HUE_ANGLE_G = 4.3;
const float ODT_HUE_ANGLE_B = 2.3;
const float ODT_HUE_ANGLE_SHIFT_R = -0.4;
const float ODT_HUE_ANGLE_SHIFT_B = 2.5;
const float ODT_HUE_ANGLE_C = 3.3;
const float ODT_HUE_ANGLE_M = 1.3;
const float ODT_HUE_ANGLE_Y = -1.15;
const float ODT_HUE_WINDOW_RGB = 0.66;
const float ODT_HUE_WINDOW_CMY = 0.5;

float ODTToeQuadratic(float x, float toe) {
    return toe == 0.0 ? x : x * x / (x + toe);
}

float ODTToeQuadraticInverse(float x, float toe) {
    return toe == 0.0 ? x : 0.5 * (x + sqrt(x * (4.0 * toe + x)));
}

float ODTToeCubic(float x, float multiplier, float width, bool inverse_curve) {
    if (multiplier == 1.0) return x;
    float x2 = x * x;
    if (!inverse_curve) return x * (x2 + multiplier * width) / (x2 + width);
    float p0 = x2 - 3.0 * multiplier * width;
    float p1 = 2.0 * x2 + 27.0 * width - 9.0 * multiplier * width;
    float p2 = pow(0.5 * (sqrt(x2 * p1 * p1 - 4.0 * p0 * p0 * p0) + x * p1), 1.0 / 3.0);
    return p0 / (3.0 * p2) + p2 / 3.0 + x / 3.0;
}

float ODTHighContrast(float x) {
    float power = exp2(ODT_HIGH_CONTRAST);
    float pivot = 0.18 * exp2(ODT_HIGH_CONTRAST_PIVOT);
    if (x < pivot || power == 1.0) return x;
    float offset = pivot - pivot / power;
    float scale = pow(pivot, 1.0 - power) / power;
    float extension = pivot * exp2(ODT_HIGH_CONTRAST_EXTENSION);
    float extension_power = pow(extension, power);
    float slope = power * scale * extension_power / extension;
    float intercept = scale * extension_power + offset;
    return x > extension ? slope * (x - extension) + intercept : scale * pow(x, power) + offset;
}

float ODTHyperbolicCompression(float x, float scale, float power) {
    return pow(x / (x + scale), power);
}

// Cyan-yellow / green-magenta opponent axes.
vec2 ODTOpponent(vec3 rgb) {
    return vec2(rgb.r - rgb.b, rgb.g - (rgb.r + rgb.b) * 0.5);
}

// Degree-6 fits of exp(-acos(cosine)^2 / width) over cosine in [-1, 1].
float ODTWindow(vec2 direction, float center, float width) {
    float angle = center - ODT_PI - ODT_HUE_ORIGIN;
    float cosine = dot(direction, vec2(cos(angle), sin(angle)));
    float rgb_window = (((((0.038401652025 * cosine + 0.11732008925) * cosine + 0.20402394936)
        * cosine + 0.26837042811) * cosine + 0.23376258945) * cosine + 0.11397148313)
        * cosine + 0.024149808674;
    float cmy_window = (((((0.13953249567 * cosine + 0.27290991169) * cosine + 0.22216742163)
        * cosine + 0.1753894888) * cosine + 0.13085745147) * cosine + 0.049597223466)
        * cosine + 0.0095460072666;
    return max(width == ODT_HUE_WINDOW_RGB ? rgb_window : cmy_window, 0.0);
}

// Softplus that keeps extremely pure primaries inside the display gamut.
float ODTSoftplus(float x, float scale) {
    if (x > 10.0 * scale || scale < 1.0e-4) return x;
    return scale * log(max(0.0, 1.0 + exp(x / scale)));
}

vec3 TonemapOpenDRT(vec3 linear_rgb) {
    // Constraint solve: middle gray -> display gray luminance, shoulder clip -> paper white.
    float ts_y1 = ODT_PEAK_LUMINANCE * 0.01;
    float ts_x0 = ODT_SCENE_GREY + ODT_OFFSET;
    float ts_y0 = ODT_GREY_LUMINANCE * 0.01;
    float ts_p = ODT_CONTRAST / (1.0 + ODT_SURROUND * 0.05);
    float ts_x1 = exp2(6.0 * ODT_SHOULDER_CLIP + 4.0);
    float ts_s0 = ODTToeQuadraticInverse(ts_y0, ODT_TOE);
    float ts_s10 = ts_x0 * (pow(ts_s0, -1.0 / ODT_CONTRAST) - 1.0);
    float ts_m1 = ts_y1 / pow(ts_x1 / (ts_x1 + ts_s10), ODT_CONTRAST);
    float ts_m2 = ODTToeQuadraticInverse(ts_m1, ODT_TOE);
    float ts_s = ts_x0 * (pow(ts_s0 / ts_m2, -1.0 / ODT_CONTRAST) - 1.0);
    // SDR purity lerp has zero weight at the fixed 100-nit peak, so ts_s1 serves both reads.
    float ts_s1 = ts_x0 * (pow(ts_y0, -1.0 / ODT_CONTRAST) - 1.0);

    vec3 render_weights = vec3(ODT_RENDER_WEIGHT_R,
        1.0 - ODT_RENDER_WEIGHT_R - ODT_RENDER_WEIGHT_B, ODT_RENDER_WEIGHT_B);
    // Scene RGB passes through unclipped: clipping before conversion distorts out-of-gamut hues.
    vec3 rgb = ODT_SRGB_TO_P3D65 * linear_rgb;
    float render_level = dot(rgb, render_weights);
    rgb = render_level * ODT_RENDER_SATURATION + rgb * (1.0 - ODT_RENDER_SATURATION);
    rgb += ODT_OFFSET;

    float tsn = length(rgb) * ODT_SQRT3_INVERSE;
    rgb = tsn > 0.0 ? rgb / tsn : vec3(0.0);

    vec2 opponent = ODTOpponent(rgb);
    float ach_d = 1.25 * ODTToeQuadratic(0.5 * length(opponent), ODT_ACHROMATIC_TOE);
    // Neutrals give a zero opponent length; hue weights are immaterial (achromatic multiplier is 0).
    vec2 hue_direction = opponent.yx * inversesqrt(max(dot(opponent, opponent), 1.0e-20));

    vec3 hue_rgb = vec3(
        ODTWindow(hue_direction, ODT_HUE_ANGLE_R, ODT_HUE_WINDOW_RGB),
        ODTWindow(hue_direction, ODT_HUE_ANGLE_G, ODT_HUE_WINDOW_RGB),
        ODTWindow(hue_direction, ODT_HUE_ANGLE_B, ODT_HUE_WINDOW_RGB));
    vec3 hue_rgb_shift = vec3(
        ODTWindow(hue_direction, ODT_HUE_ANGLE_SHIFT_R, ODT_HUE_WINDOW_RGB),
        hue_rgb.g,
        ODTWindow(hue_direction, ODT_HUE_ANGLE_SHIFT_B, ODT_HUE_WINDOW_RGB));
    vec3 hue_cmy = vec3(
        ODTWindow(hue_direction, ODT_HUE_ANGLE_C, ODT_HUE_WINDOW_CMY),
        ODTWindow(hue_direction, ODT_HUE_ANGLE_M, ODT_HUE_WINDOW_CMY),
        ODTWindow(hue_direction, ODT_HUE_ANGLE_Y, ODT_HUE_WINDOW_CMY));

    float brilliance_ramp = pow(tsn / (tsn + 1.0), 1.0 - ODT_BRILLIANCE_RANGE);
    float brilliance = (ODT_BRILLIANCE + ODT_BRILLIANCE_R * hue_rgb.r
        + ODT_BRILLIANCE_G * hue_rgb.g + ODT_BRILLIANCE_B * hue_rgb.b)
        * pow(ach_d, 1.0 / ODT_BRILLIANCE_STRENGTH);
    tsn *= exp2(brilliance * (brilliance < 0.0 ? brilliance_ramp : 1.0 - brilliance_ramp));

    if (ODT_LOW_CONTRAST_ENABLE != 0) {
        float multiplier = exp2(-ODT_LOW_CONTRAST);
        float width = ODT_LOW_CONTRAST_WIDTH * 0.25;
        width *= width;
        float constraint = ODTToeCubic(ts_x0, multiplier, width, true) / ts_x0;
        tsn = ODTToeCubic(tsn * constraint, multiplier, width, false);
    }
    if (ODT_HIGH_CONTRAST_ENABLE != 0) tsn = ODTHighContrast(tsn);

    // tsn_purity feeds the color stages below; tsn becomes the final display level.
    float tsn_purity = ODTHyperbolicCompression(tsn, ts_s1, ts_p);
    tsn = ODTHyperbolicCompression(tsn, ts_s, ts_p);

    float hue_contrast_scale = 1.0 - tsn_purity;
    float hue_contrast_center = (hue_contrast_scale * (1.0 - ach_d) + ach_d * (1.0 - hue_contrast_scale))
        * ach_d * hue_rgb.r;
    float hue_contrast = ODT_HUE_CONTRAST_R * (hue_contrast_center - 2.0 * hue_contrast_center
        * pow(hue_contrast_scale, 1.0 / ODT_HUE_CONTRAST_RANGE)) + 1.0;
    rgb = vec3(rgb.r, rgb.g * hue_contrast, rgb.b * hue_contrast);

    vec3 hue_shift = vec3(
        hue_rgb_shift.r * ach_d * pow(tsn_purity, 1.0 / ODT_HUE_SHIFT_R_RANGE),
        hue_rgb_shift.g * ach_d * pow(tsn_purity, 1.0 / ODT_HUE_SHIFT_G_RANGE),
        hue_rgb_shift.b * ach_d * pow(tsn_purity, 1.0 / ODT_HUE_SHIFT_B_RANGE));
    vec3 hue_shift_rgb = vec3(hue_shift.r * ODT_HUE_SHIFT_R,
        hue_shift.g * -ODT_HUE_SHIFT_G, hue_shift.b * -ODT_HUE_SHIFT_B);
    rgb += vec3(hue_shift_rgb.b - hue_shift_rgb.g,
        hue_shift_rgb.r - hue_shift_rgb.b, hue_shift_rgb.g - hue_shift_rgb.r);

    vec3 hue_shift_cmy = ach_d * hue_cmy * pow(vec3(1.0 - tsn_purity),
        vec3(1.0 / ODT_HUE_SHIFT_C_RANGE, 1.0 / ODT_HUE_SHIFT_M_RANGE, 1.0 / ODT_HUE_SHIFT_Y_RANGE));
    vec3 hue_shift_cmy_rgb = vec3(hue_shift_cmy.r * -ODT_HUE_SHIFT_C,
        hue_shift_cmy.g * ODT_HUE_SHIFT_M, hue_shift_cmy.b * ODT_HUE_SHIFT_Y);
    rgb += vec3(hue_shift_cmy_rgb.b - hue_shift_cmy_rgb.g,
        hue_shift_cmy_rgb.r - hue_shift_cmy_rgb.b, hue_shift_cmy_rgb.g - hue_shift_cmy_rgb.r);

    float purity = 1.0 - pow(tsn_purity, 1.0 + 4.0 * (1.0 - tsn_purity)
        * (ODT_PURITY_LOW + ODT_PURITY_LOW_R * hue_rgb_shift.r
            + ODT_PURITY_LOW_G * hue_rgb_shift.g + ODT_PURITY_LOW_B * hue_rgb_shift.b));
    purity = pow(purity, (1.0 - ach_d * (ODT_PURITY_HIGH_R * hue_rgb_shift.r
        + ODT_PURITY_HIGH_B * hue_rgb_shift.b)) * (1.0 - ODT_PURITY_HIGH * ach_d));
    purity *= 1.0 + ODT_MID_PURITY_LOW * exp(-2.0 * ach_d * ach_d / ODT_MID_PURITY_LOW_STRENGTH)
        * pow(1.0 - tsn_purity, 1.0 / ODT_MID_PURITY_LOW_RANGE);
    purity *= 1.0 + ODT_MID_PURITY_HIGH * exp(-2.0 * ach_d * ach_d / ODT_MID_PURITY_HIGH_STRENGTH)
        * pow(tsn_purity, 1.0 / (4.0 * ODT_MID_PURITY_HIGH_RANGE));
    rgb = rgb * purity + 1.0 - purity;

    float purity_level = dot(rgb, render_weights);
    rgb = (purity_level * ODT_RENDER_SATURATION - rgb)
        / (ODT_RENDER_SATURATION - 1.0);
    float white_weight = pow(tsn_purity, 2.0 * ODT_CREATIVE_WHITE_RANGE);
    rgb = mix(ODT_P3D65_TO_SRGB * rgb, ODT_CREATIVE_WHITE_MATRIX * rgb, white_weight);
    rgb *= ODT_CREATIVE_WHITE_NORMALIZATION * white_weight + 1.0 - white_weight;

    // Achromatic distance re-measured on the display gamut: conversion can push a primary out of the compression plane.
    float post_ach_d = 0.25 * length(ODTOpponent(rgb));
    post_ach_d = 1.1 * (post_ach_d * post_ach_d / (post_ach_d + 0.1));
    float post_brilliance = ODT_POST_BRILLIANCE
        + ODT_POST_BRILLIANCE_R * ach_d * hue_rgb.r
        + ODT_POST_BRILLIANCE_G * ach_d * hue_rgb.g
        + ODT_POST_BRILLIANCE_B * ach_d * hue_rgb.b;
    rgb *= exp2(post_brilliance * post_ach_d * tsn);

    rgb = vec3(ODTSoftplus(rgb.r, ODT_PURITY_SOFTCLIP_C),
        ODTSoftplus(rgb.g, ODT_PURITY_SOFTCLIP_M),
        ODTSoftplus(rgb.b, ODT_PURITY_SOFTCLIP_Y));
    // ts_m2 is the inverse-toe gain from the constraint solve.
    tsn = ODTToeQuadratic(tsn * ts_m2, ODT_TOE);
    return saturate(rgb * tsn);
}

#endif // TONEMAP_MODE == 3

#endif // LIB_COLOR_TONEMAP_OPENDRT_GLSL
