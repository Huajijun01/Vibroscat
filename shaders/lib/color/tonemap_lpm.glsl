#ifndef LIB_COLOR_TONEMAP_LPM_GLSL
#define LIB_COLOR_TONEMAP_LPM_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"


// ===========================================================================
// LPM - Luma Preserving Mapper (mode 4)
//
// Ported from AMD's FidelityFX LPM, ffx-lpm/ffx_lpm.h, header tag
// "[LPM] LUMA PRESERVING MAPPER 1.20200225", MIT. That file carries
// "Copyright (c) 2017-2019 Advanced Micro Devices, Inc. All rights reserved."
// and the repository NOTICES.txt records the same MIT code as "Copyright (c)
// 2020 Advanced Micro Devices, Inc. All rights reserved."; see
// licenses/THIRD_PARTY_NOTICES.md section 24. The reference is itself the ALU rewrite of
// the GDC 2019 LUT version ("Switched from using LUTs to doing the full
// mapping in ALU"), so it holds no table and no baked curve to reproduce.
//
// Ported stages, by reference name:
//   LpmSetup  - the toneScaleBias solve for the curve
//               tone(x) = x^contrast / (x^shoulder * bias.x + bias.y), which
//               the reference pins with tone(midIn) = 0.18 and
//               tone(hdrMax) = 1.0. The const block below performs the same
//               solve at compile time, where LpmSetup folds it into its
//               control block.
//   LpmMap    - ratio/luma split, the saturation power on the ratio, the tone
//               curve on the luma of the *original* color (this is what makes
//               the map luma preserving), the ratio re-scale, the crosstalk
//               walk-back-in-gamut pass and the final luma make-up.
//   LPM_CONFIG_709_709 with LPM_COLORS_709_709 - the working, output and
//               container gamut are all Rec.709 at D65, so the reference's
//               `con` and `con2` matrices are both identity and are omitted,
//               lumaW == lumaT, and its `clip` and `scaleOnly` paths are dead.
//
// Omitted stages, and why:
//   - `soft` gamut mapping (softGap): the reference requires `con` alongside
//     it (its prefabs never pair `soft` with a single gamut) and only reaches
//     it when the working and output gamuts differ.
//   - `shoulder`/`shoulderContrast`: the reference's own value is 1.0, where
//     lumaShoulder == luma, and its usage example calls LpmFilter with
//     shoulder = false.
//   - The con2/scaleOnly output transforms (FS2, HDR10, scRGB), the FP16
//     packed path (LpmMapH/LpmFilterH) and the LpmSetupOut control block:
//     this pack returns display-linear Rec.709 and applies its sRGB OETF in
//     post/final.fragment.
//
// Two guards cover inputs that the reference documents as outside its
// contract ({0 to hdrMax}) but can still receive: color == 0 makes its
// 1/max(rgb) a division by zero, and once the tone-mapped luma reaches 1.0
// every crosstalk cap term is exactly 0, so its lumaAdd/dot(cap, lumaT) is
// 0/0. The port returns black in the first case and takes the limit t = 0 in
// the second, which leaves the already-clipped color untouched.
//
// Fixed setup: the header's Rec.709 example uses hdrMax 256, exposure 8,
// contrast 0.25, shoulderContrast 1, saturation 0 and the crosstalk below.
// Its display-format prefabs are output configurations, not artistic looks.
// ===========================================================================

// Luma weights: the Y row of the reference's LpmColRgbToXyz() matrix for the
// Rec.709 primaries (0.64, 0.33) (0.30, 0.60) (0.15, 0.06) and the D65 white
// (0.3127, 0.3290), normalized to sum 1 as LpmSetup does. Working and output
// gamut are the same here, so lumaT == lumaW and this one vector is both.
const vec3 LPM_LUMA_T = vec3(0.21263900587151027, 0.71516867876775590, 0.07219231536073373);
const vec3 LPM_RCP_LUMA_T = 1.0 / LPM_LUMA_T;
// The reference's own crosstalk tuning vector from its "TUNING THE CROSSTALK
// VALUE" section: it shapes how over-exposure desaturates, pulling blue down
// hardest and green next, so the walk to white passes through yellow.
const vec3 LPM_CROSSTALK = vec3(1.0, 0.5, 0.03125);

// LpmSetup() tone curve, folded to compile-time constants. LPM_CONTRAST_POWER
// is the reference's contrast after its `contrast += 1.0`, and with
// shoulderContrast 1.0 it is also the shoulder exponent `cs` of the solve.
const float LPM_CONTRAST_POWER = 1.25;
// Reference saturation input is 0, so the ratio exponent equals contrast.
const float LPM_SATURATION_POWER = LPM_CONTRAST_POWER;
// midOut is the reference's fixed display target; midIn is the scene value it
// lands on, which is hdrMax displaced by `exposure` stops.
const float LPM_HDR_MAX = 256.0;
const float LPM_EXPOSURE = 8.0;
const float LPM_MID_OUT = 0.18;
const float LPM_MID_IN = LPM_HDR_MAX * LPM_MID_OUT * exp2(-LPM_EXPOSURE);
// The reference's z0..z4 and w0..w3 solved into toneScaleBias. Its w0..w3
// equal z1..z4 here because cs == contrast at shoulderContrast 1.0.
const float LPM_Z0 = -pow(LPM_MID_IN, LPM_CONTRAST_POWER);
const float LPM_Z1 = pow(LPM_HDR_MAX, LPM_CONTRAST_POWER) * pow(LPM_MID_IN, LPM_CONTRAST_POWER);
const float LPM_Z2 = pow(LPM_HDR_MAX, LPM_CONTRAST_POWER) * pow(LPM_MID_IN, LPM_CONTRAST_POWER) * LPM_MID_OUT;
const float LPM_Z3 = pow(LPM_HDR_MAX, LPM_CONTRAST_POWER) * LPM_MID_OUT;
const float LPM_Z4 = pow(LPM_MID_IN, LPM_CONTRAST_POWER) * LPM_MID_OUT;
const float LPM_TONE_SCALE_A = -((LPM_Z0 + LPM_MID_OUT * (LPM_Z1 - LPM_Z2) / (LPM_Z3 - LPM_Z4)) / LPM_Z4);
const float LPM_TONE_SCALE_B = (LPM_Z1 - LPM_Z2) / (LPM_Z3 - LPM_Z4);

// Input: linear sRGB (Rec.709 primaries, D65), scene-linear, 0.18 = middle
// grey. Output: display-linear Rec.709 in [0,1]; the pack's sRGB OETF runs
// later, so no transfer function is applied here.
vec3 TonemapLPM(vec3 linear_rgb) {
    // LpmMap: the ratio to the channel maximum carries the color, the maximum
    // carries the scale. Zero is the reference's 1/max(rgb) singularity.
    vec3 color = max(linear_rgb, vec3(0.0));
    float max_rgb = max(color.r, max(color.g, color.b));
    if (max_rgb <= 0.0) return vec3(0.0);

    // LpmMap: ratio, then the saturation power (the ratio must not exceed 1
    // for this to hold its meaning).
    vec3 ratio = pow(color / max_rgb, vec3(LPM_SATURATION_POWER));

    // LpmMap: tone map the luma of the *original* color, which is what keeps
    // the operator luma preserving, then re-scale the ratio onto that luma.
    float luma = pow(dot(color, LPM_LUMA_T), LPM_CONTRAST_POWER);
    luma = luma / (luma * LPM_TONE_SCALE_A + LPM_TONE_SCALE_B);
    color = saturate(ratio * saturate(luma / dot(ratio, LPM_LUMA_T)));

    // LpmMap: walk back in gamut. `cap` is how far each channel can still
    // rise, weighted by the crosstalk vector; the luma the clip cost is first
    // spread over those caps and then topped up on the last channel, which
    // keeps the over-exposure ratios and never leaves the gamut.
    vec3 cap = LPM_CROSSTALK * (1.0 - color);
    float cap_luma = dot(cap, LPM_LUMA_T);
    // cap_luma is exactly 0 once the color reaches display white, where the
    // reference divides 0 by 0; t = 0 is the limit and is the identity there.
    float t = cap_luma > 0.0 ? saturate(luma - dot(color, LPM_LUMA_T)) / cap_luma : 0.0;
    color = saturate(t * cap + color);
    return saturate(color + saturate(luma - dot(color, LPM_LUMA_T)) * LPM_RCP_LUMA_T);
}

#endif // LIB_COLOR_TONEMAP_LPM_GLSL
