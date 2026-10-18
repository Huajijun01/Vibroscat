#ifndef LIB_COLOR_TONEMAP_REINHARD_AGX_GLSL
#define LIB_COLOR_TONEMAP_REINHARD_AGX_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/spaces.glsl"
#include "/lib/color/tonemap_agx.glsl"


// ===========================================================================
// Reinhard-AgX (mode 6): Reinhard-Gamut's virtual gamut around a tone curve
// whose shadows are linear and whose highlights join an AgX logarithmic
// shoulder with the same value and tangent at the join.
//
// Ported from DRT Bench (github.com/bWFuanVzYWth/DRT, GPL-3.0-only since
// 2026-09), shaders/reinhard_agx.wgsl; licenses/THIRD_PARTY_NOTICES.md
// section 3. The tool feeds an AP0 scene-linear image through a Rec.709
// linear working space; this pack's scene color is already that space, so
// the reference's AP0 -> Rec.709 matrix has no counterpart here.
//
// The reference solves the curve and the shoulder coefficient on the CPU for
// the current output headroom. This pack is SDR only (display peak 1.0), so
// both fold to the constants below at the tool's default parameters.
//
// Domain: scene-linear Rec.709 in; display-linear out, after the reference's
// sRGB encode, HSV hue repair and display-signal clamp are undone with the
// pack's exact sRGB EOTF.
// ===========================================================================

// DRT Bench `ReinhardParameters::default()` as embedded in
// `ReinhardAgxParameters::default()`. Its input_scale = 1 / (1 - 0.18) makes
// linear_middle_gray = 0.18, so the linear segment has slope 1 and scene 18%
// gray lands on display 0.18; compression starts at that same 18%.
const float RA_GAMUT_EXPANSION = 0.04;
const float RA_COMPRESSION_START = 0.18;
const float RA_LINEAR_SLOPE = 1.0;
const float RA_OUTPUT_PEAK = 1.0;
const float RA_SHOULDER_POWER = 5.0;
const float RA_HUE_RETENTION = 0.5;
// 1 - ln(1 + d)^-5, with the shoulder distance d at the default 8 EV
// highlight reach: (0.18 * 2^8 - 0.18) / 0.82 = 55.9756097561. The solved
// coefficient places the curve's peak on display white (1.000152) there.
const float RA_SHOULDER_COEFFICIENT = 0.9990738451;

// Moving the virtual primaries outward makes the coordinates of an unchanged
// Rec.709 color contract toward the neutral axis.
vec3 ReinhardGamutExpand(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return mix(color, vec3(neutral), RA_GAMUT_EXPANSION);
}

// The neutral projection is invariant, so this is the exact inverse of the
// expansion before the intervening nonlinear curve.
vec3 ReinhardGamutContract(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return (color - RA_GAMUT_EXPANSION * vec3(neutral)) / (1.0 - RA_GAMUT_EXPANSION);
}

float ReinhardAgxLog1p(float distance) {
    // ln(1 + x) = ln(2) * log2(1 + x). The series branch keeps the tangent at
    // the segment join from cancelling into noise where the distance is small.
    if (distance < 0.001) {
        return distance * (1.0 + distance * (-0.5 + distance / 3.0));
    }
    return 0.6931471805599453 * log2(1.0 + distance);
}

// One channel: linear below the compression start, then the normalized AgX
// shoulder z / (1 + a * z^p)^(1/p) on z = ln(1 + slope * (x - start) / extent).
// Value and tangent are continuous at the join by construction, and a sets
// where the asymptote sits relative to display white.
float ReinhardAgxCurve(float value) {
    if (value <= RA_COMPRESSION_START) {
        return RA_LINEAR_SLOPE * value;
    }
    float extent = RA_OUTPUT_PEAK - RA_LINEAR_SLOPE * RA_COMPRESSION_START;
    float log_distance = ReinhardAgxLog1p(
        RA_LINEAR_SLOPE * (value - RA_COMPRESSION_START) / extent);
    return RA_LINEAR_SLOPE * RA_COMPRESSION_START
        + extent * log_distance
            * pow(1.0 + RA_SHOULDER_COEFFICIENT * pow(log_distance, RA_SHOULDER_POWER),
                -1.0 / RA_SHOULDER_POWER);
}

// Hue repair (reference protectHsvHue): pull the tone-scaled hue back toward
// the scene hue by a fixed retention. The comparison runs on the display
// signal, as in the reference, and leaves neutrals untouched.
vec3 ReinhardAgxProtectHue(vec3 original_linear, vec3 mapped_display) {
    vec3 original_hsv = RGBToHSV(FromLinear(original_linear));
    vec3 mapped_hsv = RGBToHSV(mapped_display);
    if (original_hsv.y <= 1.0e-7 || mapped_hsv.y <= 1.0e-7) {
        return mapped_display;
    }
    float hue_offset = original_hsv.x - mapped_hsv.x;
    hue_offset -= floor(hue_offset + 0.5);
    mapped_hsv.x = fract(mapped_hsv.x + RA_HUE_RETENTION * hue_offset);
    return HSVToRGB(mapped_hsv);
}

vec3 TonemapReinhardAGX(vec3 linear_rgb) {
    vec3 original = max(linear_rgb, 0.0);
    vec3 working = ReinhardGamutExpand(original);
    vec3 curved = vec3(ReinhardAgxCurve(working.x), ReinhardAgxCurve(working.y),
        ReinhardAgxCurve(working.z));

    // The reference clamps its encoded display signal into [0, display white];
    // bounding the linear value first is the same clamp and keeps the
    // non-negative argument the pack's sRGB encode requires.
    vec3 mapped_linear = max(ReinhardGamutContract(curved), 0.0);
    vec3 mapped_display = FromLinear(mapped_linear);
    mapped_display = ReinhardAgxProtectHue(original, mapped_display);
    return ToLinear(clamp(mapped_display, 0.0, 1.0));
}

#endif // LIB_COLOR_TONEMAP_REINHARD_AGX_GLSL
