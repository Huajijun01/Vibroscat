#ifndef LIB_COLOR_TONEMAP_AGX_GLSL
#define LIB_COLOR_TONEMAP_AGX_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/color/spaces.glsl"


// AgX-HSV (mode 0), ported from DRT Bench agx_hsv.wgsl, AgxParameters::hsv_default()
// (GPL-3.0-only, modified; licenses/THIRD_PARTY_NOTICES.md section 1).
// Scene-linear in, display-linear out (0.18 scene -> 0.18).

const float AGX_GAMUT_COMPRESSION = 0.05;
const float AGX_MIN_LOG2 = -12.473931188332412333;    // log2(0.18) - 10 EV
const float AGX_INVERSE_DYNAMIC_RANGE = 0.060606060606060606; // 1 / 16.5 EV
const float AGX_INPUT_PIVOT = 0.6060606060606061;     // 10 / 16.5 EV
const float AGX_OUTPUT_PIVOT = 0.4613561300;          // sRGB OETF(0.18)
const vec3 AGX_NEUTRAL_WEIGHTS = vec3(0.2120053547549465, 0.3921825078090138, 0.3958121374360396);

const float AGX_WHITE_HUE_RETENTION = 0.5;
const float AGX_BLACK_HUE_RETENTION = 1.0;

vec3 AgXInset(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return mix(color, vec3(neutral), AGX_GAMUT_COMPRESSION);
}

vec3 AgXOutset(vec3 color) {
    float neutral = dot(color, AGX_NEUTRAL_WEIGHTS);
    return (color - AGX_GAMUT_COMPRESSION * vec3(neutral))
        / (1.0 - AGX_GAMUT_COMPRESSION);
}

// Degree-6 toe/shoulder fits; both segments preserve the pivot and outer endpoint values.
float AgXCurveComponent(float value) {
    bool toe = value <= AGX_INPUT_PIVOT;
    float t = (value - AGX_INPUT_PIVOT) * (toe ? -1.65 : 2.5384615384615385);
    float toe_value = (((((-1.0720958708 * t + 3.1268145866) * t - 2.7914172515) * t
        - 0.27643456832) * t + 2.1409202513) * t - 1.5891432771) * t + AGX_OUTPUT_PIVOT;
    float shoulder_value = (((((-4.8885598032 * t + 14.96519738) * t - 15.989722099) * t
        + 6.5648895721) * t - 1.1605649624) * t + 1.0474037825) * t + AGX_OUTPUT_PIVOT;
    return toe ? toe_value : shoulder_value;
}

// Hue repair in a pure-2.2 domain: original_linear is scene color, mapped the tone-scaled display value.
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

    vec3 working = AgXInset(original);
    working = (log2(max(working, 2e-10)) - AGX_MIN_LOG2) * AGX_INVERSE_DYNAMIC_RANGE;
    working = saturate(working);

    working = vec3(AgXCurveComponent(working.x), AgXCurveComponent(working.y),
        AgXCurveComponent(working.z));
    working = AgXOutset(working);

    working = AgXRepairHue(original, working);

    return ToLinear(saturate(working));
}

#endif // LIB_COLOR_TONEMAP_AGX_GLSL
