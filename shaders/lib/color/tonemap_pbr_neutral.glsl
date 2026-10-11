#ifndef LIB_COLOR_TONEMAP_PBR_NEUTRAL_GLSL
#define LIB_COLOR_TONEMAP_PBR_NEUTRAL_GLSL

#include "/lib/contract/settings.glsl"


// ===========================================================================
// Khronos PBR Neutral (mode 6)
//
// Ported from the Khronos Group reference implementation
// (github.com/KhronosGroup/ToneMapping, PBR_Neutral/pbrNeutral.glsl,
// Copyright 2024 The Khronos Group Inc., Apache-2.0;
// licenses/THIRD_PARTY_NOTICES.md section 22). The operator is the published
// PBR Neutral specification, without the sample's inline constants folded
// away:
//
//   x = min(R,G,B)                       f = x - x^2/(4*F90)   for x <= 2*F90
//   p = max(R-f, G-f, B-f)               f = F90               for x >  2*F90
//   pn = 1 - (1-Ks)^2 / (p + 1 - 2Ks)    g = 1/(Kd*(p-pn) + 1)
//   out = (c - f)                        for p <= Ks
//   out = (c - f)*pn/p*g + pn*(1-g)      for p >  Ks
//
// with F90 = 0.04 (dielectric Fresnel reflectance at normal incidence,
// IoR 1.5), Ks = 0.8 - F90 (highlight compression start) and Kd = 0.15
// (desaturation speed). Input and output are linear Rec.709: the operator
// performs no gamut mapping because the PBR input is assumed to be inside
// that gamut already.
//
// Properties kept from the specification: no hue shift for any input (the
// only changes are inside the plane spanned by the color and the white
// axis), continuous partial derivatives, a 1:1 invertible mapping, and an
// output bounded by paper white.
//
// Deviation from the reference: the specification's own scale is "1.0 is
// the brightest scene value", so its F90 subtraction lands scene 18% grey on
// 0.14 display-linear, 0.36 EV below the anchor every other mode in this
// pack shares. TONEMAP_PBRN_INPUT_SCALE pre-scales the scene so that its
// default (0.18 + F90)/0.18 puts scene 18% grey back on 18% display-linear;
// the value 1.0 reproduces the reference's own scale exactly. The scale is
// applied before the offset, so it shifts both the exact-reproduction range
// and the start of highlight compression: with the default scale the base
// colors between 0.065 and 0.655 scene-linear come through unchanged apart
// from the F90 subtraction, and anything above 0.655 is compressed.
//
// Headroom note: the reference targets a well-exposed scene whose values
// above 1.0 are small specular highlights. This pack feeds it a scene with
// sun, sky and emissive radiance far above that, which the operator maps
// into the last 20% of the display range. That hard highlight roll-off is
// the operator's designed behavior, not a port defect; lower
// TONEMAP_PBRN_INPUT_SCALE to pull the compression knee upwards.
// ===========================================================================

const float PBRN_F90 = 0.04;
const float PBRN_START_COMPRESSION = 0.8 - PBRN_F90;
const float PBRN_DESATURATION = 0.15;
// 1 / (4 * F90), the quadratic low-end fade coefficient.
const float PBRN_LOW_END_SCALE = 1.0 / (4.0 * PBRN_F90);
const float PBRN_TWO_F90 = 2.0 * PBRN_F90;

vec3 TonemapPBRNeutral(vec3 linear_rgb) {
    vec3 color = max(linear_rgb, vec3(0.0)) * TONEMAP_PBRN_INPUT_SCALE;

    // F90 is removed from every channel so a lit dielectric reflects its base
    // color unchanged. Below 2*F90 the removal fades out quadratically, which
    // is what keeps black at black.
    float low_end = min(color.r, min(color.g, color.b));
    float offset = low_end < PBRN_TWO_F90
        ? low_end - PBRN_LOW_END_SCALE * low_end * low_end
        : PBRN_F90;
    color -= offset;

    float peak = max(color.r, max(color.g, color.b));
    if (peak < PBRN_START_COMPRESSION) return color;

    // Converging shoulder to paper white plus the desaturation that removes
    // the per-channel hue twist a plain per-channel knee would leave behind.
    float shoulder = 1.0 - PBRN_START_COMPRESSION;
    float compressed_peak = 1.0 - shoulder * shoulder / (peak + shoulder - PBRN_START_COMPRESSION);
    color *= compressed_peak / peak;
    float desaturation = 1.0 - 1.0 / (PBRN_DESATURATION * (peak - compressed_peak) + 1.0);
    return mix(color, vec3(compressed_peak), desaturation);
}

#endif // LIB_COLOR_TONEMAP_PBR_NEUTRAL_GLSL
