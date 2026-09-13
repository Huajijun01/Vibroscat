#ifndef LIB_COLOR_TONEMAP_AGX_GLSL
#define LIB_COLOR_TONEMAP_AGX_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/spaces.glsl"

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

#endif // LIB_COLOR_TONEMAP_AGX_GLSL
