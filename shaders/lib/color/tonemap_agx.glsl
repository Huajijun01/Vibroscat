#ifndef LIB_COLOR_TONEMAP_AGX_GLSL
#define LIB_COLOR_TONEMAP_AGX_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/color/spaces.glsl"


// ===========================================================================
// AgX (mode 0): the HSV hue-repair variant of AgX, "AgX-HSV".
//
// Ported from DRT Bench (github.com/bWFuanVzYWth/DRT, GPL-3.0-only), file
// shaders/agx_hsv.wgsl, with its `AgxParameters::hsv_default()` curve;
// licenses/THIRD_PARTY_NOTICES.md section 1. The inset/outset pair,
// the log2 shaper and the toe/shoulder power curve are the family the S2O3
// variant also uses; what makes this variant "HSV" is the final hue repair,
// which compares the hue of the tone-scaled result with the hue of the
// original scene color and pulls it back by a retention that falls from the
// shadows to the highlights (1.0 at black -> AGX_WHITE_HUE_RETENTION).
//
// Domain: the reference's display value is sRGB-OETF encoded, anchored so
// that its output pivot is OETF(0.18) = 0.46135613. This port therefore
// decodes with the pack's exact sRGB EOTF (`ToLinear`) and returns
// display-linear color, which keeps the shared "scene 18% gray -> 18%
// display-linear" anchor exactly: 0.18 scene in gives 0.18 out.
// The hue comparison itself stays in the reference's pure-2.2 domain.
//
// Degree-six polynomials approximate the reference's toe and shoulder;
// the hue repair retains the reference's signal-domain calculation.
// ===========================================================================

// AgX-HSV curve parameters (DRT Bench `AgxParameters::hsv_default()`).
const float AGX_GAMUT_COMPRESSION = 0.05;
const float AGX_MIN_LOG2 = -12.473931188332412333;    // log2(0.18) - 10 EV
const float AGX_INVERSE_DYNAMIC_RANGE = 0.060606060606060606; // 1 / 16.5 EV
const float AGX_INPUT_PIVOT = 0.6060606060606061;     // 10 / 16.5 EV
const float AGX_OUTPUT_PIVOT = 0.4613561300;          // sRGB OETF(0.18)
const vec3 AGX_NEUTRAL_WEIGHTS = vec3(0.2120053547549465, 0.3921825078090138, 0.3958121374360396);

const float AGX_WHITE_HUE_RETENTION = 0.5;
// Reference `AgxParameters` hue retention at black; the highlight end is the
// fixed AGX_WHITE_HUE_RETENTION constant.
const float AGX_BLACK_HUE_RETENTION = 1.0;

// Inset: compress the working gamut toward the AgX neutral axis.
vec3 AgXInset(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return mix(color, vec3(neutral), AGX_GAMUT_COMPRESSION);
}

// Outset: its exact inverse, applied after the curve.
vec3 AgXOutset(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return (color - AGX_GAMUT_COMPRESSION * vec3(neutral))
        / (1.0 - AGX_GAMUT_COMPRESSION);
}

// Piecewise degree-six fits over the normalized log shaper [0, 1].
// Both segments preserve the pivot and their outer endpoint values.
float AgXCurveComponent(float value) {
    bool toe = value <= AGX_INPUT_PIVOT;
    float t = (value - AGX_INPUT_PIVOT) * (toe ? -1.65 : 2.5384615384615385);
    float toe_value = (((((-1.0720958708 * t + 3.1268145866) * t - 2.7914172515) * t
        - 0.27643456832) * t + 2.1409202513) * t - 1.5891432771) * t + AGX_OUTPUT_PIVOT;
    float shoulder_value = (((((-4.8885598032 * t + 14.96519738) * t - 15.989722099) * t
        + 6.5648895721) * t - 1.1605649624) * t + 1.0474037825) * t + AGX_OUTPUT_PIVOT;
    return toe ? toe_value : shoulder_value;
}

// Hue repair: keep the original hue, faded by how bright the pixel became.
// `original_linear` is the scene color and `mapped` the tone-scaled display
// value; the comparison runs in the reference's pure-2.2 signal domain.
vec3 AgXRepairHue(vec3 original_linear, vec3 mapped) {
    vec3 original_hsv = RGBToHSV(pow(max(original_linear, 0.0), vec3(1.0 / 2.2)));
    vec3 mapped_hsv = RGBToHSV(mapped);
    float normalized_value = saturate(mapped_hsv.z);

    if (original_hsv.y > 1.0e-7 && mapped_hsv.y > 1.0e-7) {
        float retention = mix(AGX_BLACK_HUE_RETENTION, AGX_WHITE_HUE_RETENTION, normalized_value);
        float hue_offset = original_hsv.x - mapped_hsv.x;
        hue_offset -= floor(hue_offset + 0.5);
        mapped_hsv.x = fract(mapped_hsv.x + retention * hue_offset);
    }

    return HSVToRGB(vec3(mapped_hsv.x, saturate(mapped_hsv.y), mapped_hsv.z));
}

vec3 TonemapAGX(vec3 linear_rgb) {
    vec3 original = max(linear_rgb, 0.0);

    // Inset and the normalized log2 shaper (min EV -12.4739 .. max EV +4.0261).
    vec3 working = AgXInset(original);
    working = (log2(max(working, 2e-10)) - AGX_MIN_LOG2) * AGX_INVERSE_DYNAMIC_RANGE;
    working = saturate(working);

    // Toe/shoulder curve, then back out of the working gamut.
    working = vec3(AgXCurveComponent(working.x), AgXCurveComponent(working.y),
        AgXCurveComponent(working.z));
    working = AgXOutset(working);

    // The variant's hue repair, in the display-referred AgX Base domain.
    working = AgXRepairHue(original, working);

    // The reference clamps its final display signal, then the pack decodes
    // it for the shared display-linear sharpening / final sRGB output.
    return ToLinear(saturate(working));
}

#endif // LIB_COLOR_TONEMAP_AGX_GLSL
