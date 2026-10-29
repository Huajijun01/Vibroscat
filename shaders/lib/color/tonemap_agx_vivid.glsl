#ifndef LIB_COLOR_TONEMAP_AGX_VIVID_GLSL
#define LIB_COLOR_TONEMAP_AGX_VIVID_GLSL

#include "/lib/core/math_scalar.glsl"
#include "/lib/color/spaces.glsl"

// AgX Vivid: scene-linear Rec.709 to display-linear Rec.709.
// Linear/log shoulder and virtual gamut adapted from linlin's DRT Bench
// Reinhard-AgX; HSV hue protection follows its AgX-HSV variant (GPL-3.0-only).
// See licenses/THIRD_PARTY_NOTICES.md, section 33.
const vec3 AGX_VIVID_NEUTRAL_WEIGHTS = vec3(0.212005355, 0.392182508, 0.395812137);
const float AGX_VIVID_INSET = 0.06;
const float AGX_VIVID_LINEAR_END = 0.60;
const float AGX_VIVID_SHOULDER_POWER = 6.0;
const float AGX_VIVID_SATURATION_BOOST = 0.08;
const float AGX_VIVID_SHADOW_HUE_RETENTION = 0.95;
const float AGX_VIVID_HIGHLIGHT_HUE_RETENTION = 0.65;

// Unit slope through the low and middle tones, including the 18% gray anchor.
// The logarithmic shoulder joins with the same value and tangent at 0.60.
// Its sixth-power asymptote retains a late, bright shoulder without a finite
// input white clip: gray 1.0 maps to about 0.872, and 2.0 to about 0.995.
vec3 AgXVividToneScale(vec3 color) {
    const float extent = 1.0 - AGX_VIVID_LINEAR_END;
    vec3 shoulder = max(color - AGX_VIVID_LINEAR_END, 0.0) / extent;
    shoulder = log2(1.0 + shoulder) * 0.6931471805599453;
    shoulder /= pow(1.0 + pow(shoulder, vec3(AGX_VIVID_SHOULDER_POWER)),
        vec3(1.0 / AGX_VIVID_SHOULDER_POWER));
    return min(color, AGX_VIVID_LINEAR_END) + extent * shoulder;
}

vec3 TonemapAgXVivid(vec3 linear_rgb) {
    // Temporal reconstruction can overshoot below zero; black is a valid input.
    vec3 original = max(linear_rgb, 0.0);
    float neutral = dot(original, AGX_VIVID_NEUTRAL_WEIGHTS);
    vec3 working = mix(original, vec3(neutral), AGX_VIVID_INSET);
    working = AgXVividToneScale(working);

    // The neutral projection is invariant under the inset, so this is its
    // exact inverse in the linear region. Nonlinear highlights converge to white.
    neutral = dot(working, AGX_VIVID_NEUTRAL_WEIGHTS);
    vec3 formed = (working - AGX_VIVID_INSET * neutral) / (1.0 - AGX_VIVID_INSET);

    // Compare hues in the same sRGB signal domain. The source is not clipped
    // to display white, preserving the hue of bright scene colors.
    vec3 original_hsv = RGBToHSV(FromLinear(original));
    vec3 formed_hsv = RGBToHSV(FromLinear(max(formed, 0.0)));
    float highlight = smoothstep(AGX_VIVID_LINEAR_END, 1.0, max(working.r, max(working.g, working.b)));
    float retention = mix(AGX_VIVID_SHADOW_HUE_RETENTION, AGX_VIVID_HIGHLIGHT_HUE_RETENTION, highlight);
    float hue_offset = original_hsv.x - formed_hsv.x;
    hue_offset -= floor(hue_offset + 0.5);
    formed_hsv.x = fract(formed_hsv.x + retention * hue_offset);

    // Bounded saturation lift: preserve neutral and fully saturated endpoints.
    // Limit HSV value as a unit, avoiding independent RGB clipping after hue repair.
    formed_hsv.y = saturate(formed_hsv.y);
    formed_hsv.y += AGX_VIVID_SATURATION_BOOST * formed_hsv.y * (1.0 - formed_hsv.y);
    formed_hsv.z = saturate(formed_hsv.z);
    return ToLinear(HSVToRGB(formed_hsv));
}

#endif // LIB_COLOR_TONEMAP_AGX_VIVID_GLSL
