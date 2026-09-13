#ifndef LIB_COLOR_COLOR_GLSL
#define LIB_COLOR_COLOR_GLSL

#include "/lib/contract/settings.glsl"



// sRGB <-> Linear conversion (BT.709 OETF)
vec3 ToLinear(vec3 srgb) {
    bvec3 cutoff = lessThan(srgb, vec3(0.04045));
    vec3 higher = pow((srgb + vec3(0.055)) / vec3(1.055), vec3(2.4));
    vec3 lower = srgb / vec3(12.92);
    return mix(higher, lower, cutoff);
}

vec3 FromLinear(vec3 linear_rgb) {
    bvec3 cutoff = lessThan(linear_rgb, vec3(0.0031308));
    vec3 higher = vec3(1.055) * pow(linear_rgb, vec3(1.0 / 2.4)) - vec3(0.055);
    vec3 lower = linear_rgb * vec3(12.92);
    return mix(higher, lower, cutoff);
}

// Rec.709 linear luminance, shared by lighting, fog and temporal blending.
float Luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Linear sRGB (D65) -> CIE XYZ, shared by colorimetric models (scotopic
// luminance, white point math).
const mat3 SRGB_TO_XYZ = mat3(
    vec3(0.4124564, 0.2126729, 0.0193339),
    vec3(0.3575761, 0.7151522, 0.1191920),
    vec3(0.1804375, 0.0721750, 0.9503041));

// OKLAB
// l/m/s are the LMS cone responses, l_/m_/s_ their cube roots (Ottosson's
// reference notation).
vec3 RGBToOKLAB(vec3 c) {
    float l = 0.4121656120 * c.r + 0.5362752080 * c.g + 0.0514575653 * c.b;
    float m = 0.2118591070 * c.r + 0.6807189584 * c.g + 0.1074065790 * c.b;
    float s = 0.0883097947 * c.r + 0.2818474174 * c.g + 0.6302613616 * c.b;

    float l_ = pow(l, 1.0 / 3.0);
    float m_ = pow(m, 1.0 / 3.0);
    float s_ = pow(s, 1.0 / 3.0);

    vec3 lab;
    lab.x = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    lab.y = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    lab.z = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
    return lab;
}

vec3 OKLABToRGB(vec3 c) {
    float l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;

    float l = l_ * l_ * l_;
    float m = m_ * m_ * m_;
    float s = s_ * s_ * s_;

    vec3 rgb;
    rgb.r =  4.0767245293 * l - 3.3072168827 * m + 0.2307590544 * s;
    rgb.g = -1.2681437731 * l + 2.6093323231 * m - 0.3411344290 * s;
    rgb.b = -0.0041119885 * l - 0.7034763098 * m + 1.7068625689 * s;
    return rgb;
}

// AgX display rendering transform.
// Concept: [SOB22] Sobotka, Troy. AgX. 2022. https://github.com/sobotka/AgX
// Curve: AgX-S2O3 analytical implementation, [LIN24] linlin, AgX. 2024, MIT
// - ported from the upstream AgX-S2O3 Slang shader (
// github.com/bWFuanVzYWth/AgX @ 0796e1b4). Linear sRGB in/out, 0.18 anchor.
vec3 AgXInset(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return mix(color, vec3(neutral), TONEMAP_AGX_GAMUT_COMPRESSION);
}

vec3 AgXOutset(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return (color - TONEMAP_AGX_GAMUT_COMPRESSION * vec3(neutral))
        / (1.0 - TONEMAP_AGX_GAMUT_COMPRESSION);
}

float AgXCurveComponent(float value) {
    bool toe = value <= AGX_INPUT_PIVOT;
    float power = toe ? TONEMAP_AGX_TOE_POWER : TONEMAP_AGX_SHOULDER_POWER;
    float coefficient = toe ? AGX_TOE_A : AGX_SHOULDER_A;
    float pivot_offset = value - AGX_INPUT_PIVOT;
    return AGX_OUTPUT_PIVOT + AGX_PIVOT_SLOPE * pivot_offset
        * pow(1.0 + coefficient * pow(abs(pivot_offset), power), -1.0 / power);
}

vec3 TonemapAGX(vec3 linear_rgb) {
    // Inset: gamut compression toward the AgX neutral axis.
    vec3 working = AgXInset(max(linear_rgb, 2e-10));

    // Normalized log2 shaper (min EV -12.474 .. max EV +4.026).
    const float min_log2 = -12.473931188332412333;   // log2(0.18) - 10
    const float dynamic_range = 16.5;
    working = (log2(working) - min_log2) / dynamic_range;
    working = clamp(working, 0.0, 1.0);

    // User contrast around the mid-grey pivot (AgX log domain).
    working = AGX_INPUT_PIVOT + (working - AGX_INPUT_PIVOT) * TONEMAP_AGX_CONTRAST;
    working = clamp(working, 0.0, 1.0);

    // S2O3 per-channel toe/shoulder power curve.
    working = vec3(AgXCurveComponent(working.x), AgXCurveComponent(working.y), AgXCurveComponent(working.z));

    // AgX looks and user adjustments in the display-referred AgX Base domain.
    float look_gamma = 1.0;
    float look_saturation = 1.0;
#if TONEMAP_AGX_LOOK == 1
    look_gamma = 1.3;
    look_saturation = 1.2;
#elif TONEMAP_AGX_LOOK == 2
    look_saturation = 0.0;
#endif
    look_gamma *= TONEMAP_AGX_GAMMA;
    look_saturation *= TONEMAP_AGX_SATURATION;

    float working_luma = Luminance(working);
    working = mix(vec3(working_luma), working, look_saturation);
    working = pow(max(working, 0.0), vec3(look_gamma));

    // Linearize the 2.4-encoded AgX Base image, then outset back to sRGB.
    working = pow(working, vec3(2.4));
    working = AgXOutset(working);

#if TONEMAP_AGX_LOOK == 2
    working = vec3(dot(working, vec3(0.2627, 0.6780, 0.0593)));
#endif
    return working;
}

// ===========================================================================
// DRT family - display rendering transforms ported from the DRT Bench tool
// (github.com/bWFuanVzYWth/DRT).
// Provenance:
//   - Oklab DRT: Björn Ottosson "A display rendering transform" (2021); the
//     DRT Bench port (linlin's permission; licenses/THIRD_PARTY_NOTICES.md
//     section 4).
//   - Reinhard-Gamut (mode 3): DRT Bench experiment (linlin's permission,
//     2026-08).
//   - Reinhard-AgX (mode 5): DRT Bench linear-shadow / AgX-shoulder hybrid
//     (DRT Bench is GPL-3.0-only since 2026-09).
// All of them take and return linear sRGB (the DRT tool's AP0 input is already
// Rec.709/sRGB primaries here, so the AP0->Rec.709 matrix is omitted). The
// DRT tool encodes sRGB internally; these ports return linear and let the
// final pass (final.fragment) apply the OETF.
// ===========================================================================

const float DRT_OKLAB_MIDDLE_GRAY = 0.18;
const float DRT_OKLAB_RGB_HEADROOM = 0.99999;
const vec3 DRT_OKLAB_RED_ROW = vec3(4.0767416621, -3.3077115913, 0.2309699292);
const vec3 DRT_OKLAB_GREEN_ROW = vec3(-1.2684380046, 2.6097574011, -0.3413193965);
const vec3 DRT_OKLAB_BLUE_ROW = vec3(-0.0041960863, -0.7034186147, 1.7076147010);

// --- Oklab DRT (mode 1): shoulder curve + gamut cusp + saturation cap ---

float DRTShoulderCoefficient(float overexposure) {
    float scale = overexposure / (overexposure - DRT_OKLAB_MIDDLE_GRAY);
    return (scale * scale - 1.0) / DRT_OKLAB_MIDDLE_GRAY;
}

float DRTMapLightness(float lightness, float overexposure) {
    float brightness = lightness * lightness * lightness;
    float x = DRTShoulderCoefficient(overexposure) * brightness;
    float inverse_root = inversesqrt(1.0 + x);
    float mapped_brightness = overexposure * x * inverse_root * inverse_root / (1.0 + inverse_root);
    return pow(mapped_brightness, 1.0 / 3.0);
}

vec3 DRTRootDirection(vec2 hue) {
    return vec3(
        0.3963377774 * hue.x + 0.2158037573 * hue.y,
        -0.1055613458 * hue.x - 0.0638541728 * hue.y,
        -0.0894841775 * hue.x - 1.2914855480 * hue.y);
}

float DRTMaxSaturation(vec2 hue, vec3 direction) {
    float k0;
    float k1;
    float k2;
    float k3;
    float k4;
    vec3 rgb_row;
    if (-1.88170328 * hue.x - 0.80936493 * hue.y > 1.0) {
        k0 = 1.19086277; k1 = 1.76576728; k2 = 0.59662641; k3 = 0.75515197; k4 = 0.56771245;
        rgb_row = DRT_OKLAB_RED_ROW;
    } else if (1.81444104 * hue.x - 1.19445276 * hue.y > 1.0) {
        k0 = 0.73956515; k1 = -0.45954404; k2 = 0.08285427; k3 = 0.12541070; k4 = 0.14503204;
        rgb_row = DRT_OKLAB_GREEN_ROW;
    } else {
        k0 = 1.35733652; k1 = -0.00915799; k2 = -1.15130210; k3 = -0.50559606; k4 = 0.00692167;
        rgb_row = DRT_OKLAB_BLUE_ROW;
    }

    float saturation = k0 + k1 * hue.x + k2 * hue.y + k3 * hue.x * hue.x + k4 * hue.x * hue.y;
    vec3 roots = vec3(1.0) + saturation * direction;
    vec3 lms = roots * roots * roots;
    vec3 first_lms = 3.0 * direction * roots * roots;
    vec3 second_lms = 6.0 * direction * direction * roots;
    float f = dot(rgb_row, lms);
    float f1 = dot(rgb_row, first_lms);
    float f2 = dot(rgb_row, second_lms);
    return saturation - f * f1 / (f1 * f1 - 0.5 * f * f2);
}

float DRTConnectedSaturation(vec2 hue, float saturation) {
    const vec2 blue_notch_axis = vec2(-0.10362546, -0.99461639);
    float alignment = max(dot(hue, blue_notch_axis), 0.0);
    float alignment2 = alignment * alignment;
    float alignment4 = alignment2 * alignment2;
    float alignment8 = alignment4 * alignment4;
    float alignment16 = alignment8 * alignment8;
    float alignment32 = alignment16 * alignment16;
    float alignment64 = alignment32 * alignment32;
    float alignment128 = alignment64 * alignment64;
    float alignment256 = alignment128 * alignment128;
    return min(saturation, 0.57 + (1.0 - alignment256));
}

float DRTCuspLightness(float saturation, vec3 direction) {
    vec3 roots = vec3(1.0) + saturation * direction;
    vec3 lms = roots * roots * roots;
    vec3 rgb = vec3(
        dot(DRT_OKLAB_RED_ROW, lms),
        dot(DRT_OKLAB_GREEN_ROW, lms),
        dot(DRT_OKLAB_BLUE_ROW, lms));
    return pow(1.0 / max(rgb.r, max(rgb.g, rgb.b)), 1.0 / 3.0);
}

float DRTRefineUpperChroma(float chroma, float lightness, vec3 direction) {
    vec3 roots = lightness + chroma * direction;
    vec3 lms = roots * roots * roots;
    vec3 first_lms = 3.0 * direction * roots * roots;
    vec3 second_lms = 6.0 * direction * direction * roots;
    vec3 rgb = vec3(dot(DRT_OKLAB_RED_ROW, lms), dot(DRT_OKLAB_GREEN_ROW, lms), dot(DRT_OKLAB_BLUE_ROW, lms));
    vec3 first_rgb = vec3(dot(DRT_OKLAB_RED_ROW, first_lms), dot(DRT_OKLAB_GREEN_ROW, first_lms), dot(DRT_OKLAB_BLUE_ROW, first_lms));
    vec3 second_rgb = vec3(dot(DRT_OKLAB_RED_ROW, second_lms), dot(DRT_OKLAB_GREEN_ROW, second_lms), dot(DRT_OKLAB_BLUE_ROW, second_lms));
    vec3 f = rgb - 1.0;
    vec3 denominator = first_rgb * first_rgb - 0.5 * f * second_rgb;
    vec3 reciprocal_step = first_rgb / denominator;
    vec3 newton_step = -f * reciprocal_step;
    newton_step = vec3(
        reciprocal_step.x >= 0.0 ? newton_step.x : 1.0e20,
        reciprocal_step.y >= 0.0 ? newton_step.y : 1.0e20,
        reciprocal_step.z >= 0.0 ? newton_step.z : 1.0e20);
    return chroma + min(newton_step.r, min(newton_step.g, newton_step.b));
}

float SoftMin(float value, float limit, float power) {
    if (value <= 0.0 || limit <= 0.0) return 0.0;
    float lower = min(value, limit);
    float higher = max(value, limit);
    float ratio = lower / higher;
    return lower * pow(1.0 + pow(ratio, power), -1.0 / power);
}

float SoftMin4(float value, float limit) {
    if (value <= 0.0 || limit <= 0.0) return 0.0;
    float lower = min(value, limit);
    float higher = max(value, limit);
    float ratio = lower / higher;
    float ratio2 = ratio * ratio;
    float root = sqrt(1.0 + ratio2 * ratio2);
    return lower * inversesqrt(root);
}

float DRTSaturationCap(float lightness, float maximum_saturation, vec3 direction) {
    if (lightness <= 0.0) return maximum_saturation;
    if (lightness >= 1.0) return 0.0;
    float cusp = DRTCuspLightness(maximum_saturation, direction);
    float black_chroma = lightness * maximum_saturation;
    float white_chroma = cusp * maximum_saturation * (1.0 - lightness) / (1.0 - cusp);
    white_chroma = DRTRefineUpperChroma(white_chroma, lightness, direction);
    float t = clamp((lightness - cusp) / (1.0 - cusp), 0.0, 1.0);
    float shoulder = t * (1.0 - t);
    white_chroma *= 1.0 - 0.0035 * 16.0 * shoulder * shoulder;
    float rounded_chroma = SoftMin4(black_chroma, white_chroma);
    return max(rounded_chroma / lightness, 0.0);
}

float DRTChromaRetention(float lightness) {
    float lightness2 = lightness * lightness;
    float lightness4 = lightness2 * lightness2;
    float lightness8 = lightness4 * lightness4;
    return 1.0 - lightness8 * lightness4;
}

float DRTRoundingPower(float lightness) {
    float endpoint_distance = lightness * (1.0 - lightness);
    return 32.0 - 256.0 * endpoint_distance * endpoint_distance;
}

vec3 DRTMapLinearRgb(vec3 color, float overexposure) {
    vec3 oklab = RGBToOKLAB(color);
    if (oklab.x <= 0.0) return vec3(0.0);
    float output_lightness = DRTMapLightness(oklab.x, overexposure);
    float input_chroma = length(oklab.yz);
    if (input_chroma <= 1.0e-8)
        return DRT_OKLAB_RGB_HEADROOM * OKLABToRGB(vec3(output_lightness, 0.0, 0.0));

    vec2 hue = oklab.yz / input_chroma;
    vec3 direction = DRTRootDirection(hue);
    float input_saturation = input_chroma / oklab.x;
    float maximum_saturation = DRTConnectedSaturation(hue, DRTMaxSaturation(hue, direction));
    float desired_saturation = input_saturation * DRTChromaRetention(output_lightness);
    float cap = DRTSaturationCap(output_lightness, maximum_saturation, direction);
    float output_saturation = SoftMin(desired_saturation, cap, DRTRoundingPower(output_lightness));
    return DRT_OKLAB_RGB_HEADROOM * OKLABToRGB(vec3(
        output_lightness, output_lightness * output_saturation * hue));
}

vec3 TonemapOklabDRT(vec3 linear_rgb) {
    return DRTMapLinearRgb(max(linear_rgb, 0.0), TONEMAP_OKLAB_OVEREXPOSURE);
}


// --- HSV helpers (shared by the Reinhard-Gamut hue protection) ---

vec3 RGBToHSV(vec3 color) {
    float maximum = max(color.r, max(color.g, color.b));
    float minimum = min(color.r, min(color.g, color.b));
    float chroma = maximum - minimum;
    float hue = 0.0;
    if (chroma > 1.0e-7) {
        if (maximum == color.r)
            hue = (color.g - color.b) / chroma;
        else if (maximum == color.g)
            hue = (color.b - color.r) / chroma + 2.0;
        else
            hue = (color.r - color.g) / chroma + 4.0;
        hue = fract(hue / 6.0);
    }
    float saturation = maximum > 1.0e-7 ? chroma / maximum : 0.0;
    return vec3(hue, saturation, maximum);
}

vec3 HSVToRGB(vec3 hsv) {
    vec3 primary = clamp(abs(fract(hsv.x + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return hsv.z * mix(vec3(1.0), primary, hsv.y);
}


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


// ===========================================================================
// GT7 Tone Mapping (mode 4): Polyphony Digital's color-volume mapping
// operator, "Driving Toward Reality: Physically Based Tone Mapping and
// Perceptual Fidelity in Gran Turismo 7" [PDI25], SIGGRAPH 2025 courses.
// Ported from the official sample implementation shipped with the course
// material (gt7_tone_mapping.cpp, MIT; licenses/THIRD_PARTY_NOTICES.md
// section 18). A per-channel pass of the GT Tone Mapping Curve V2 (linear
// midtones, contrast toe, converging shoulder) is blended with an ICtCp
// path that keeps the original chroma but fades it toward white across the
// highlight, so saturated highlights roll off without the per-channel hue
// twist. The sample's frame-buffer domain (1.0 = 100 nits, linear
// Rec.2020, SDR paper white 250 nits) is entered and left through the
// BT.709 <-> BT.2020 matrices below; GT7_MID_GREY_SCALE re-anchors scene
// 18% grey at 18% display-linear, the anchor shared with the other modes
// (same role as ACES_MID_GREY_SCALE, solved from 0.4*curve(scale*0.18)=0.18).
// ===========================================================================

const mat3 SRGB_TO_BT2020 = mat3(
    vec3(0.6274039, 0.0690973, 0.0163914),
    vec3(0.3292830, 0.9195404, 0.0880133),
    vec3(0.0433131, 0.0113623, 0.8955953));
const mat3 BT2020_TO_SRGB = mat3(
    vec3(1.6604910, -0.1245505, -0.0181508),
    vec3(-0.5876411, 1.1328999, -0.1005789),
    vec3(-0.0728499, -0.0083494, 1.1187297));

// ICtCp (ITU-R BT.2124) on Rec.2020 primaries; the GLSL columns hold the
// transposed ITU rows, so M * v matches the reference row-major multiply.
const mat3 GT7_BT2020_TO_LMS = mat3(
    vec3(1688.0, 683.0, 99.0),
    vec3(2146.0, 2951.0, 309.0),
    vec3(262.0, 462.0, 3688.0)) / 4096.0;
const mat3 GT7_LMS_TO_BT2020 = mat3(
    vec3(3.4366066943, -0.7913295556, -0.0259498997),
    vec3(-2.5064521187, 1.9836004518, -0.0989137147),
    vec3(0.0698454243, -0.1922708962, 1.1248636144));
const mat3 GT7_LMS_TO_ICTCP = mat3(
    vec3(2048.0, 6610.0, 17933.0),
    vec3(2048.0, -13613.0, -17390.0),
    vec3(2048.0, 7003.0, -543.0)) / 4096.0;
const mat3 GT7_ICTCP_TO_LMS = mat3(
    vec3(0.6666666667, 0.6666666667, 0.6666666667),
    vec3(-0.1780680749, -0.1952861489, 0.3733542238),
    vec3(0.2179053500, -0.0041539000, -0.2137514500));

// ST 2084 transfer on the sample's frame-buffer scale (1.0 = 100 nits).
float InverseEotfST2084(float framebuffer) {
    float shaped = pow(max(framebuffer, 0.0) * 0.01, 0.1593017578125);
    return pow((0.8359375 + 18.8515625 * shaped) / (1.0 + 18.6875 * shaped), 78.84375);
}

float EotfST2084(float pq) {
    float shaped = pow(max(pq, 0.0), 1.0 / 78.84375);
    return 100.0 * pow(max(shaped - 0.8359375, 0.0) / (18.8515625 - 18.6875 * shaped), 6.277394636015);
}

vec3 RgbToICtCp(vec3 rgb) {
    vec3 lms = GT7_BT2020_TO_LMS * rgb;
    lms = vec3(InverseEotfST2084(lms.r), InverseEotfST2084(lms.g), InverseEotfST2084(lms.b));
    return GT7_LMS_TO_ICTCP * lms;
}

vec3 ICtCpToRgb(vec3 ictcp) {
    vec3 lms = GT7_ICTCP_TO_LMS * ictcp;
    lms = vec3(EotfST2084(lms.r), EotfST2084(lms.g), EotfST2084(lms.b));
    return max(GT7_LMS_TO_BT2020 * lms, 0.0);
}

// GT Tone Mapping Curve V2. Official SDR preset (peak 2.5, gray point
// 0.538, linear section 0.444, toe strength 1.28) with one deliberate
// deviation: alpha 0 instead of the sample's 0.25, so the shoulder
// asymptote is exactly paper white. The sample's engine normalizes scene
// exposure before the curve and can output HDR, which hides its
// overshooting shoulder; this pack feeds un-normalized scene values into
// an SDR target, where the 0.25 shoulder crossed white at ~1.45x scene
// white and the official min() hard-clipped everything brighter.
// Perfectly linear below 0.444 * peak, contrast toe toward black,
// converging exponential shoulder above the linear section.
const float GT7_PEAK = 2.5;             // paper white, frame-buffer scale
const float GT7_SDR_CORRECTION = 0.4;   // 1 / paper-white frame-buffer value
const float GT7_GRAY_POINT = 0.538;
const float GT7_LINEAR_SECTION = 0.444;
const float GT7_TOE_STRENGTH = 1.280;
// Shoulder terms kA + kB*exp(kC*x) with k = (0.444 - 1) / (0 - 1);
// kA = peak * (0.444 + k) = peak for alpha 0.
const float GT7_SHOULDER_A = 2.5;
const float GT7_SHOULDER_B = -3.089054009429425;
const float GT7_SHOULDER_C = -0.719424460431655;
// UCS luma of the paper-white grey (2.5, 2.5, 2.5): chroma-fade pivot.
const float GT7_TARGET_LUMA_UCS = 0.903838732486;
// Input prescale re-anchoring 18% grey: 0.4*curve(scale*0.18) = 0.18.
const float GT7_MID_GREY_SCALE = 2.508318700610;

float GT7Curve(float x) {
    if (x <= 0.0) return 0.0;
    if (x >= GT7_LINEAR_SECTION * GT7_PEAK) {
        return GT7_SHOULDER_A + GT7_SHOULDER_B * exp(x * GT7_SHOULDER_C);
    }
    float weight_linear = smoothstep(0.0, GT7_GRAY_POINT, x);
    float weight_toe = 1.0 - weight_linear;
    float toe_mapped = GT7_GRAY_POINT * pow(x / GT7_GRAY_POINT, GT7_TOE_STRENGTH);
    return weight_toe * toe_mapped + weight_linear * x;
}

vec3 TonemapGT7(vec3 linear_rgb) {
    vec3 rgb = SRGB_TO_BT2020 * (GT7_MID_GREY_SCALE * max(linear_rgb, 0.0));
    vec3 ucs = RgbToICtCp(rgb);

    // Step 1: per-channel curve pass (color-accurate midtones, hue twist
    // in the shoulder).
    vec3 skewed = vec3(GT7Curve(rgb.r), GT7Curve(rgb.g), GT7Curve(rgb.b));

    // Step 2: UCS pass - twisted luma, original chroma faded toward white
    // as the scene luminance approaches paper white.
    vec3 skewed_ucs = RgbToICtCp(skewed);
    // Ordered edges: the two sliders may be set either way round, and
    // smoothstep is undefined when edge0 >= edge1.
    float chroma_scale = 1.0 - smoothstep(
        min(TONEMAP_GT7_CHROMA_FADE_START, TONEMAP_GT7_CHROMA_FADE_END),
        max(TONEMAP_GT7_CHROMA_FADE_START, TONEMAP_GT7_CHROMA_FADE_END),
        ucs.x / GT7_TARGET_LUMA_UCS);
    vec3 faded = ICtCpToRgb(vec3(skewed_ucs.x, ucs.y * chroma_scale, ucs.z * chroma_scale));

    // Step 3: blend the paths and apply the SDR paper-white correction.
    vec3 blended = mix(skewed, faded, TONEMAP_GT7_BLEND);
    return BT2020_TO_SRGB * (min(blended, vec3(GT7_PEAK)) * GT7_SDR_CORRECTION);
}


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

// LogLuv32 -> linear sRGB, per [ERI07] Ericson, Christer. "Converting RGB to
// LogLuv in a fragment shader". 2007. R = u', G = v', B = int(Le),
// A = frac(Le), Le = 2*log2(Y) + 127. Decodes LogLuv32 RGBA8 HDR textures
// (e.g. the night star map).
const mat3 LOGLUV32_INVERSE_M = mat3(6.0014, -2.7008, -1.7996, -1.3320, 3.1029, -5.7721, 0.3008, -1.0882, 5.6268);

vec3 LogLuv32ToLinear(vec4 v_log_luv) {
    if (all(lessThanEqual(v_log_luv, vec4(0.0)))) return vec3(0.0);
    float le = v_log_luv.z * 255.0 + v_log_luv.w;
    vec3 xyz_prime;
    xyz_prime.y = exp2((le - 127.0) * 0.5);
    xyz_prime.z = xyz_prime.y / max(v_log_luv.y, 1.0e-6);
    xyz_prime.x = v_log_luv.x * xyz_prime.z;
    return max(LOGLUV32_INVERSE_M * xyz_prime, vec3(0.0));
}

#endif // COLOR_GLSL
