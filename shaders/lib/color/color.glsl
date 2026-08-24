#include "/lib/contract/settings.glsl"
#ifndef LIB_COLOR_COLOR_GLSL
#define LIB_COLOR_COLOR_GLSL




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

// OKLAB
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
// — ported from the upstream AgX-S2O3 Slang shader (
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
    float distance = value - AGX_INPUT_PIVOT;
    return AGX_OUTPUT_PIVOT + AGX_PIVOT_SLOPE * distance
        * pow(1.0 + coefficient * pow(abs(distance), power), -1.0 / power);
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

    float formed_luma = dot(working, vec3(0.2126, 0.7152, 0.0722));
    working = mix(vec3(formed_luma), working, look_saturation);
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
// DRT family — display rendering transforms ported from the DRT Bench tool
// (github.com/bWFuanVzYWth/DRT).
// Provenance:
//   - Oklab DRT: Björn Ottosson "A display rendering transform" (2021); the
//     DRT Bench Slang port (linlin's permission; licenses/THIRD_PARTY_NOTICES.md
//     section 4).
//   - Reinhard-Gamut: DRT Bench experiment (linlin's permission, 2026-08).
// Both take and return linear sRGB (the DRT tool's AP0 input is already
// Rec.709/sRGB primaries here, so the AP0->Rec.709 matrix is omitted). The
// DRT tool encodes sRGB internally; these ports return linear and let the
// final pass (final.fragment) apply the OETF.
// ===========================================================================

const float DRT_OKLAB_MIDDLE_GRAY = 0.18;
const float DRT_OKLAB_RGB_HEADROOM = 0.99999;
const vec3 DRT_OKLAB_RED_ROW = vec3(4.0767416621, -3.3077115913, 0.2309699292);
const vec3 DRT_OKLAB_GREEN_ROW = vec3(-1.2684380046, 2.6097574011, -0.3413193965);
const vec3 DRT_OKLAB_BLUE_ROW = vec3(-0.0041960863, -0.7034186147, 1.7076147010);
const vec3 DRT_AGX_NEUTRAL_WEIGHTS = vec3(0.2120053547549465, 0.3921825078090138, 0.3958121374360396);

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
    vec3 step = -f * reciprocal_step;
    step = vec3(
        reciprocal_step.x >= 0.0 ? step.x : 1.0e20,
        reciprocal_step.y >= 0.0 ? step.y : 1.0e20,
        reciprocal_step.z >= 0.0 ? step.z : 1.0e20);
    return chroma + min(step.r, min(step.g, step.b));
}

float DRTSoftMin(float value, float limit, float power) {
    if (value <= 0.0 || limit <= 0.0) return 0.0;
    float lower = min(value, limit);
    float higher = max(value, limit);
    float ratio = lower / higher;
    return lower * pow(1.0 + pow(ratio, power), -1.0 / power);
}

float DRTSoftMin4(float value, float limit) {
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
    float rounded_chroma = DRTSoftMin4(black_chroma, white_chroma);
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
    float output_saturation = DRTSoftMin(desired_saturation, cap, DRTRoundingPower(output_lightness));
    return DRT_OKLAB_RGB_HEADROOM * OKLABToRGB(vec3(
        output_lightness, output_lightness * output_saturation * hue));
}

vec3 TonemapOklabDRT(vec3 linear_rgb) {
    return DRTMapLinearRgb(max(linear_rgb, 0.0), TONEMAP_OKLAB_OVEREXPOSURE);
}


// --- HSV helpers (shared by the Reinhard-Gamut hue protection) ---

vec3 DRTRGBToHSV(vec3 color) {
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

vec3 DRTHSVToRGB(vec3 hsv) {
    vec3 primary = clamp(abs(fract(hsv.x + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return hsv.z * mix(vec3(1.0), primary, hsv.y);
}


// --- Reinhard-Gamut (mode 6): virtual-gamut Reinhard ---

vec3 DRTGamutExpand(vec3 color, float expansion) {
    float neutral = dot(color, DRT_AGX_NEUTRAL_WEIGHTS);
    return mix(color, vec3(neutral), expansion);
}

vec3 DRTGamutContract(vec3 color, float expansion) {
    float neutral = dot(color, DRT_AGX_NEUTRAL_WEIGHTS);
    return (color - expansion * vec3(neutral)) / (1.0 - expansion);
}

vec3 DRTReinhardCurve(vec3 color, float middle_gray, float curve_peak) {
    float linear_slope = middle_gray / 0.18;
    float shoulder_extent = curve_peak - middle_gray;
    vec3 distance = color - vec3(0.18);
    vec3 tangent_distance = linear_slope * distance;
    vec3 linear = linear_slope * color;
    vec3 shoulder = middle_gray + tangent_distance / (vec3(1.0) + tangent_distance / shoulder_extent);
    // Per-channel branch: linear below the 18% kink, hyperbolic shoulder above.
    return mix(shoulder, linear, vec3(lessThanEqual(color, vec3(0.18))));
}

vec3 DRTProtectHue(vec3 original_linear, vec3 mapped_display, float retention) {
    if (retention <= 0.0) return mapped_display;
    vec3 original_hsv = DRTRGBToHSV(FromLinear(original_linear));
    vec3 mapped_hsv = DRTRGBToHSV(mapped_display);
    if (original_hsv.y <= 1.0e-7 || mapped_hsv.y <= 1.0e-7)
        return mapped_display;

    float hue_offset = original_hsv.x - mapped_hsv.x;
    hue_offset -= floor(hue_offset + 0.5);
    mapped_hsv.x = fract(mapped_hsv.x + retention * hue_offset);
    return DRTHSVToRGB(mapped_hsv);
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


// ACES 1.0 RRT+ODT fitted curve (rrtAndODTFit, Narkowicz 2016), linear
// sRGB → ACEScg → fit → sRGB.
const mat3 SRGB_TO_ACESCG = mat3(
    vec3(0.613097, 0.070194, 0.020616),
    vec3(0.339523, 0.916154, 0.109570),
    vec3(0.047371, 0.013653, 0.869815));
const mat3 ACESCG_TO_SRGB = mat3(
    vec3(1.705052, -0.130257, -0.024003),
    vec3(-0.621793, 1.140803, -0.128969),
    vec3(-0.083258, -0.010549, 1.152972));

// Pre-scale: f(k·0.18) = 0.18 (mid-grey anchor shared with the other
// tonemap modes).
const float ACES_MID_GREY_SCALE = 0.72317081;

vec3 TonemapACES(vec3 linear_rgb) {
    vec3 acescg = SRGB_TO_ACESCG * max(linear_rgb, 0.0);
    vec3 fitted = ACES_MID_GREY_SCALE * acescg;
    fitted = fitted * (2.51 * fitted + 0.03) / (fitted * (2.43 * fitted + 0.59) + 0.14);
    return ACESCG_TO_SRGB * fitted;
}


vec3 Tonemap(vec3 linear_rgb) {
#if TONEMAP_MODE == 0
    return TonemapAGX(linear_rgb);
#elif TONEMAP_MODE == 1
    return TonemapOklabDRT(linear_rgb);
#elif TONEMAP_MODE == 2
    return TonemapACES(linear_rgb);
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
    x = x / (0.903453 * x + 0.427205);
    return sqrt(x);
}

vec3 HDRDecompress(vec3 y) {
    y = y * y;
    return 0.427205 * y / (1.0 - 0.903453 * y);
}

// LogLuv32 → linear sRGB, per [ERI07] Ericson, Christer. "Converting RGB to
// LogLuv in a fragment shader". 2007; matrices as in Alpha Piscium v1.9.1
// (GPLv3; licenses/THIRD_PARTY_NOTICES.md §10). R = u', G = v', B = int(Le),
// A = frac(Le), Le = 2·log2(Y) + 127. Decodes LogLuv32 RGBA8 HDR textures
// (e.g. the night star map).
const mat3 LOGLUV32_INVERSE_M = mat3(6.0014, -2.7008, -1.7996, -1.3320, 3.1029, -5.7721, 0.3008, -1.0882, 5.6268);

vec3 LogLuv32ToLinear(vec4 v_log_luv) {
    if (all(lessThanEqual(v_log_luv, vec4(0.0)))) return vec3(0.0);
    float le = v_log_luv.z * 255.0 + v_log_luv.w;
    vec3 Xp_Y_XYZp;
    Xp_Y_XYZp.y = exp2((le - 127.0) * 0.5);
    Xp_Y_XYZp.z = Xp_Y_XYZp.y / max(v_log_luv.y, 1.0e-6);
    Xp_Y_XYZp.x = v_log_luv.x * Xp_Y_XYZp.z;
    return max(LOGLUV32_INVERSE_M * Xp_Y_XYZp, vec3(0.0));
}

#endif // COLOR_GLSL
