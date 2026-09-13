#ifndef LIB_COLOR_TONEMAP_REINHARD_GLSL
#define LIB_COLOR_TONEMAP_REINHARD_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/spaces.glsl"


// --- Reinhard-Gamut (mode 3, the dispatcher fallback): virtual-gamut Reinhard ---

vec3 DRTGamutExpand(vec3 color, float expansion) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return mix(color, vec3(neutral), expansion);
}

vec3 DRTGamutContract(vec3 color, float expansion) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return (color - expansion * vec3(neutral)) / (1.0 - expansion);
}

vec3 DRTReinhardCurve(vec3 color, float middle_gray, float curve_peak) {
    float linear_slope = middle_gray / 0.18;
    float shoulder_extent = curve_peak - middle_gray;
    vec3 gray_offset = color - vec3(0.18);
    vec3 tangent_distance = linear_slope * gray_offset;
    vec3 linear = linear_slope * color;
    vec3 shoulder = middle_gray + tangent_distance / (vec3(1.0) + tangent_distance / shoulder_extent);
    // Per-channel branch: linear below the 18% kink, hyperbolic shoulder above.
    return mix(shoulder, linear, vec3(lessThanEqual(color, vec3(0.18))));
}

vec3 DRTProtectHue(vec3 original_linear, vec3 mapped_display, float retention) {
    if (retention <= 0.0) return mapped_display;
    vec3 original_hsv = RGBToHSV(FromLinear(original_linear));
    vec3 mapped_hsv = RGBToHSV(mapped_display);
    if (original_hsv.y <= 1.0e-7 || mapped_hsv.y <= 1.0e-7)
        return mapped_display;

    float hue_offset = original_hsv.x - mapped_hsv.x;
    hue_offset -= floor(hue_offset + 0.5);
    mapped_hsv.x = fract(mapped_hsv.x + retention * hue_offset);
    return HSVToRGB(mapped_hsv);
}

vec3 TonemapReinhardGamut(vec3 linear_rgb) {
    // Curve as DRT Bench's curve_for_headroom (headroom = 1.0); reach
    // clamped to keep the shoulder well-conditioned.
    const float middle_gray = (0.18 * TONEMAP_RG_INPUT_SCALE) / (1.0 + 0.18 * TONEMAP_RG_INPUT_SCALE);
    const float minimum_reach = log2(1.0 / middle_gray) + 0.1;
    const float reach_ev = max(TONEMAP_RG_HIGHLIGHT_REACH_EV, minimum_reach);
    const float reach_ratio = exp2(reach_ev);
    const float tangent_distance = middle_gray * (reach_ratio - 1.0);
    const float output_distance = 1.0 - middle_gray;
    const float shoulder_extent = output_distance * tangent_distance / (tangent_distance - output_distance);
    const float curve_peak = middle_gray + shoulder_extent;

    vec3 linear_rec709 = max(linear_rgb, 0.0);
    vec3 working = DRTGamutExpand(linear_rec709, TONEMAP_RG_GAMUT_EXPANSION);
    vec3 mapped_linear = DRTGamutContract(
        DRTReinhardCurve(working, middle_gray, curve_peak), TONEMAP_RG_GAMUT_EXPANSION);
    vec3 mapped_display = FromLinear(mapped_linear);
    mapped_display = DRTProtectHue(linear_rec709, mapped_display, TONEMAP_RG_HUE_RETENTION);
    return ToLinear(clamp(mapped_display, 0.0, 1.0));
}


// --- Reinhard-AgX (mode 5): linear shadows into an AgX log shoulder ---

// ln(1 + x). The series branch keeps the tangent at the segment join
// from cancelling into noise for the small values the join produces.
float Log1p(float x) {
    if (x < 0.001)
        return x * (1.0 + x * (-0.5 + x / 3.0));
    return 0.6931471805599453 * log2(1.0 + x);
}

// Solved curve parameters (DRT Bench: ReinhardAgxCurveParameters). The tool
// solves them on the CPU per headroom; here every input is a TONEMAP_RA_*
// option and the output peak is SDR white, so the block folds to constants.
struct DRTReinhardAgxShape {
    float compression_start;
    float linear_slope;
    float shoulder_extent;
    float shoulder_power;
    float shoulder_coefficient;
};

DRTReinhardAgxShape DRTReinhardAgxShapeFromOptions() {
    float middle_gray = (0.18 * TONEMAP_RA_INPUT_SCALE) / (1.0 + 0.18 * TONEMAP_RA_INPUT_SCALE);
    float linear_slope = middle_gray / 0.18;
    // DRT maximum_compression_start: keep output room for a positive shoulder
    // at every input scale, so the linear segment cannot swallow the peak.
    float compression_start = min(TONEMAP_RA_COMPRESSION_START, 0.99 * 0.18 / middle_gray);
    // DRT minimum_highlight_reach_ev: ln(1 + distance) has to exceed one at
    // the requested reach or the AgX coefficient turns negative.
    float minimum_reach_ev = log2((2.718281828459045 - 1.0) / middle_gray) + 0.1;
    float reach = 0.18 * exp2(max(TONEMAP_RA_HIGHLIGHT_REACH_EV, minimum_reach_ev));
    float shoulder_extent = 1.0 - linear_slope * compression_start;
    float join_distance = linear_slope * (reach - compression_start) / shoulder_extent;

    DRTReinhardAgxShape shape;
    shape.compression_start = compression_start;
    shape.linear_slope = linear_slope;
    shape.shoulder_extent = shoulder_extent;
    shape.shoulder_power = TONEMAP_RA_SHOULDER_POWER;
    shape.shoulder_coefficient =
        1.0 - pow(Log1p(join_distance), -TONEMAP_RA_SHOULDER_POWER);
    return shape;
}

// Linear below the compression start, then the normalized AgX shoulder
// z / (1 + a*z^p)^(1/p) on z = ln(1 + slope*(x - start)/extent). Value and
// tangent are continuous at the join, and a is solved so the curve reaches
// display white exactly at the requested reach.
float DRTReinhardAgxComponent(float value, DRTReinhardAgxShape shape) {
    if (value <= shape.compression_start)
        return shape.linear_slope * value;
    float log_distance = Log1p(
        shape.linear_slope * (value - shape.compression_start) / shape.shoulder_extent);
    return shape.linear_slope * shape.compression_start
        + shape.shoulder_extent * log_distance
            * pow(1.0 + shape.shoulder_coefficient * pow(log_distance, shape.shoulder_power),
                -1.0 / shape.shoulder_power);
}

vec3 TonemapReinhardAgx(vec3 linear_rgb) {
    DRTReinhardAgxShape shape = DRTReinhardAgxShapeFromOptions();

    vec3 linear_rec709 = max(linear_rgb, 0.0);
    vec3 working = DRTGamutExpand(linear_rec709, TONEMAP_RA_GAMUT_EXPANSION);
    vec3 curved = vec3(
        DRTReinhardAgxComponent(working.x, shape),
        DRTReinhardAgxComponent(working.y, shape),
        DRTReinhardAgxComponent(working.z, shape));
    vec3 mapped_linear = DRTGamutContract(curved, TONEMAP_RA_GAMUT_EXPANSION);
    vec3 mapped_display = FromLinear(mapped_linear);
    mapped_display = DRTProtectHue(linear_rec709, mapped_display, TONEMAP_RA_HUE_RETENTION);
    return ToLinear(clamp(mapped_display, 0.0, 1.0));
}

#endif // LIB_COLOR_TONEMAP_REINHARD_GLSL
