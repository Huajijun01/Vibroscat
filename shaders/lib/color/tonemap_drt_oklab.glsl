#ifndef LIB_COLOR_TONEMAP_DRT_OKLAB_GLSL
#define LIB_COLOR_TONEMAP_DRT_OKLAB_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/spaces.glsl"

// ===========================================================================
// DRT family - display rendering transforms ported from the DRT Bench tool
// (github.com/bWFuanVzYWth/DRT).
// Provenance:
//   - Oklab DRT: Björn Ottosson "A display rendering transform" (2021); the
//     DRT Bench port (linlin's permission; licenses/THIRD_PARTY_NOTICES.md
//     section 3).
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

#endif // LIB_COLOR_TONEMAP_DRT_OKLAB_GLSL
