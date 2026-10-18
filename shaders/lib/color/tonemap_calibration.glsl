#ifndef LIB_COLOR_TONEMAP_CALIBRATION_GLSL
#define LIB_COLOR_TONEMAP_CALIBRATION_GLSL

#include "/lib/contract/settings.glsl"

// Pack SDR grading is applied AFTER the reference DRT, so neutral matching
// does not push colored input further into its highlight desaturation.
// A monotone C1 cubic in log2(max RGB) maps the default-look neutral outputs
// at scene 0.01 / 0.18 / 1.0 to GT7's 0.0042891 / 0.18 / 0.796679.
// Black and display white stay fixed. One scalar preserves the reference's
// display-linear RGB ratios and hue without clipping a boosted channel.
// Creative looks keep their grading relative to the calibrated default.
//
// Knots and polynomial coefficients are fitted offline to actual GLSL;
// each vec4 is a cubic in x - knot, highest power first.
#if TONEMAP_MODE == 0
const vec3 TONEMAP_LOG_KNOTS = vec3(-6.6160020828, -2.4739308357, -0.6416906118);
const vec4 TONEMAP_LOG_CUBIC_0 = vec4(0.0007834146, -0.0250582638, 1.3919171644, -7.8651070595);
const vec4 TONEMAP_LOG_CUBIC_1 = vec4(-0.1335633771, 0.2155711399, 1.2246534899, -2.4739325047);
const vec4 TONEMAP_LOG_CUBIC_2 = vec4(-0.0311669159, -0.2268659410, 0.6694511789, -0.3279295266);
const float TONEMAP_HIGHLIGHT_INPUT = 2.43403494;
#elif TONEMAP_MODE == 1
const vec3 TONEMAP_LOG_KNOTS = vec3(-10.4552679062, -3.3219375610, -1.1279499531);
const vec4 TONEMAP_LOG_CUBIC_0 = vec4(-0.0010491110, 0.0313229395, 0.5857189615, -7.8651070595);
const vec4 TONEMAP_LOG_CUBIC_1 = vec4(-0.1371401756, 0.3490548015, 0.8724425534, -2.4739325047);
const vec4 TONEMAP_LOG_CUBIC_2 = vec4(-0.0789562419, -0.0288095897, 0.4236800843, -0.3279295266);
const float TONEMAP_HIGHLIGHT_INPUT = 3.12991751;
#elif TONEMAP_MODE == 2
const vec3 TONEMAP_LOG_KNOTS = vec3(-7.3190670013, -2.4739305973, -0.8468452096);
const vec4 TONEMAP_LOG_CUBIC_0 = vec4(-0.0018234168, 0.0406980149, 0.9583161079, -7.8651070595);
const vec4 TONEMAP_LOG_CUBIC_1 = vec4(-0.3200800235, 0.5789688282, 1.2242749502, -2.4739325047);
const vec4 TONEMAP_LOG_CUBIC_2 = vec4(-0.1951738265, -0.0460382555, 0.5661922420, -0.3279295266);
const float TONEMAP_HIGHLIGHT_INPUT = 3.55171452;
#elif TONEMAP_MODE == 3
const vec3 TONEMAP_LOG_KNOTS = vec3(-8.6448545456, -3.0147109032, -0.9403133988);
const vec4 TONEMAP_LOG_CUBIC_0 = vec4(-0.0004195802, 0.0123516351, 0.9013140111, -7.8651070595);
const vec4 TONEMAP_LOG_CUBIC_1 = vec4(-0.1341886606, 0.2947614955, 1.0004967552, -2.4739325047);
const vec4 TONEMAP_LOG_CUBIC_2 = vec4(-0.0809028464, -0.0753277339, 0.4911100335, -0.3279295266);
const float TONEMAP_HIGHLIGHT_INPUT = 3.26500331;
#elif TONEMAP_MODE == 4
const vec3 TONEMAP_LOG_KNOTS = vec3(-7.4087095261, -2.4739313126, -0.6169700027);
const vec4 TONEMAP_LOG_CUBIC_0 = vec4(-0.0004275920, 0.0114106865, 1.0465892135, -7.8651070595);
const vec4 TONEMAP_LOG_CUBIC_1 = vec4(-0.1442969352, 0.2828618467, 1.1279694195, -2.4739325047);
const vec4 TONEMAP_LOG_CUBIC_2 = vec4(-0.0037092873, -0.2477084132, 0.6857567678, -0.3279295266);
const float TONEMAP_HIGHLIGHT_INPUT = 3.09277974;
#elif TONEMAP_MODE == 6
const vec3 TONEMAP_LOG_KNOTS = vec3(-6.6438565254, -2.4739313126, -0.4505361021);
const vec4 TONEMAP_LOG_CUBIC_0 = vec4(0.0009001979, -0.0412579915, 1.4492606512, -7.8651070595);
const vec4 TONEMAP_LOG_CUBIC_1 = vec4(-0.0338344558, 0.0232202895, 1.1521338430, -2.4739325047);
const vec4 TONEMAP_LOG_CUBIC_2 = vec4(0.2072784635, -0.3212672664, 0.8305336913, -0.3279295266);
const float TONEMAP_HIGHLIGHT_INPUT = 1.84440785;
#else
const float TONEMAP_HIGHLIGHT_INPUT = 1.7773682;
#endif

vec3 CalibrateTonemapOutput(vec3 display_rgb) {
#if TONEMAP_MODE == 5
    return display_rgb;
#else
    float peak = max(display_rgb.r, max(display_rgb.g, display_rgb.b));
    float x = log2(max(peak, 1.0e-20));
    float y;
    if (x < TONEMAP_LOG_KNOTS.x) {
        y = TONEMAP_LOG_CUBIC_0.w
            + (x - TONEMAP_LOG_KNOTS.x) * TONEMAP_LOG_CUBIC_0.z;
    } else {
        vec4 coefficients;
        float knot;
        if (x < TONEMAP_LOG_KNOTS.y) {
            coefficients = TONEMAP_LOG_CUBIC_0;
            knot = TONEMAP_LOG_KNOTS.x;
        } else if (x < TONEMAP_LOG_KNOTS.z) {
            coefficients = TONEMAP_LOG_CUBIC_1;
            knot = TONEMAP_LOG_KNOTS.y;
        } else {
            coefficients = TONEMAP_LOG_CUBIC_2;
            knot = TONEMAP_LOG_KNOTS.z;
        }
        float t = min(x, 0.0) - knot;
        y = ((coefficients.x * t + coefficients.y) * t
            + coefficients.z) * t + coefficients.w;
    }
    float calibrated_peak = exp2(min(y, 0.0));
    return display_rgb * (calibrated_peak / max(peak, 1.0e-20));
#endif
}

#endif // LIB_COLOR_TONEMAP_CALIBRATION_GLSL
