#ifndef LIB_COLOR_TONEMAP_AGX_GLSL
#define LIB_COLOR_TONEMAP_AGX_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/spaces.glsl"


// ===========================================================================
// AgX (mode 0): the HSV hue-repair variant of AgX, "AgX-HSV".
//
// Ported from DRT Bench (github.com/bWFuanVzYWth/DRT, GPL-3.0-only since
// 2026-09), shaders/agx_hsv.wgsl, with its `AgxParameters::hsv_default()`
// curve; licenses/THIRD_PARTY_NOTICES.md section 3. The inset/outset pair,
// the log2 shaper and the toe/shoulder power curve are the family the S2O3
// variant also uses; what makes this variant "HSV" is the final hue repair,
// which compares the hue of the tone-scaled result with the hue of the
// original scene color and pulls it back by a retention that falls from the
// shadows to the highlights (1.0 at black -> TONEMAP_AGX_HIGHLIGHT_HUE).
//
// Domain: the reference's display value is sRGB-OETF encoded, anchored so
// that its output pivot is OETF(0.18) = 0.46135613. This port therefore
// decodes with the pack's exact sRGB EOTF (`ToLinear`) and returns
// display-linear color, which keeps the shared "scene 18% grey -> 18%
// display-linear" anchor exactly: 0.18 scene in gives 0.18 out.
// The hue comparison itself stays in the reference's pure-2.2 domain.
//
// No lookup table: the curve is the reference's closed-form power form and
// the hue repair is a handful of scalar operations.
// ===========================================================================

const float AGX_MAXIMUM_LOG_COORDINATE = 1.0;
// Reference `AgxParameters` hue retention at black; the highlight end is the
// TONEMAP_AGX_HIGHLIGHT_HUE setting.
const float AGX_BLACK_HUE_RETENTION = 1.0;

// Inset: compress the working gamut toward the AgX neutral axis.
vec3 AgXInset(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return mix(color, vec3(neutral), TONEMAP_AGX_GAMUT_COMPRESSION);
}

// Outset: its exact inverse, applied after the curve.
vec3 AgXOutset(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return (color - TONEMAP_AGX_GAMUT_COMPRESSION * vec3(neutral))
        / (1.0 - TONEMAP_AGX_GAMUT_COMPRESSION);
}

// One channel of the toe/shoulder power curve: continuous at the pivot with
// the slope the reference's `curve_coefficient` solves for.
float AgXCurveComponent(float value) {
    bool toe = value <= AGX_INPUT_PIVOT;
    float power = toe ? TONEMAP_AGX_TOE_POWER : TONEMAP_AGX_SHOULDER_POWER;
    float coefficient = toe ? AGX_TOE_A : AGX_SHOULDER_A;
    // Both exponents are setting literals, so select the negated reciprocal
    // of each constant instead of dividing the runtime-selected power.
    float inverse_power = toe ? -1.0 / TONEMAP_AGX_TOE_POWER
                              : -1.0 / TONEMAP_AGX_SHOULDER_POWER;
    float pivot_offset = value - AGX_INPUT_PIVOT;
    return AGX_OUTPUT_PIVOT + AGX_PIVOT_SLOPE * pivot_offset
        * pow(1.0 + coefficient * pow(abs(pivot_offset), power), inverse_power);
}

// Hue repair: keep the original hue, faded by how bright the pixel became.
// `original_linear` is the scene color and `mapped` the tone-scaled display
// value; the comparison runs in the reference's pure-2.2 signal domain.
vec3 AgXRepairHue(vec3 original_linear, vec3 mapped) {
    vec3 original_hsv = RGBToHSV(pow(max(original_linear, 0.0), vec3(1.0 / 2.2)));
    vec3 mapped_hsv = RGBToHSV(mapped);
    float normalized_value = clamp(mapped_hsv.z, 0.0, 1.0);

    if (original_hsv.y > 1.0e-7 && mapped_hsv.y > 1.0e-7) {
        float retention = mix(AGX_BLACK_HUE_RETENTION, TONEMAP_AGX_HIGHLIGHT_HUE, normalized_value);
        float hue_offset = original_hsv.x - mapped_hsv.x;
        hue_offset -= floor(hue_offset + 0.5);
        mapped_hsv.x = fract(mapped_hsv.x + retention * hue_offset);
    }

    return HSVToRGB(vec3(mapped_hsv.x, clamp(mapped_hsv.y, 0.0, 1.0), mapped_hsv.z));
}

vec3 TonemapAGX(vec3 linear_rgb) {
    vec3 original = max(linear_rgb, 0.0);

    // Inset and the normalized log2 shaper (min EV -12.4739 .. max EV +4.0261).
    vec3 working = AgXInset(original);
    working = (log2(max(working, 2e-10)) - AGX_MIN_LOG2) * AGX_INVERSE_DYNAMIC_RANGE;
    working = clamp(working, 0.0, AGX_MAXIMUM_LOG_COORDINATE);

    // User contrast around the mid-grey pivot (AgX log domain).
    working = AGX_INPUT_PIVOT + (working - AGX_INPUT_PIVOT) * TONEMAP_AGX_CONTRAST;
    working = clamp(working, 0.0, AGX_MAXIMUM_LOG_COORDINATE);

    // Toe/shoulder power curve, then back out of the working gamut.
    working = vec3(AgXCurveComponent(working.x), AgXCurveComponent(working.y),
        AgXCurveComponent(working.z));
    working = AgXOutset(working);

    // The variant's hue repair, in the display-referred AgX Base domain.
    working = AgXRepairHue(original, working);

    // Pack looks on top of the reference operator, then the anchor decode.
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

    working = mix(vec3(Luminance(working)), working, look_saturation);
    working = pow(max(working, 0.0), vec3(look_gamma));
    return ToLinear(working);
}

#endif // LIB_COLOR_TONEMAP_AGX_GLSL
