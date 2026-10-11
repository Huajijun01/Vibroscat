#ifndef LIB_COLOR_TONEMAP_OPENDRT_GLSL
#define LIB_COLOR_TONEMAP_OPENDRT_GLSL

#include "/lib/contract/settings.glsl"


// ===========================================================================
// OpenDRT (mode 7)
//
// Ported from Jed Smith's OpenDRT (Open Display Rendering Transform),
// github.com/jedypod/open-display-transform, display-transforms/opendrt/
// OpenDRT.dctl, GPL-3.0; licenses/THIRD_PARTY_NOTICES.md section 23. The
// DCTL's parameter presets are collapsed to its "Standard" look preset
// (look_preset = 0, tonescale_preset = 0), which is what the port
// reproduces; the tone-scale and color-volume parameters that preset drives
// are exposed as TONEMAP_ODT_* options with the preset's own values as
// defaults.
//
// The operator is a picture-formation chain, not a curve:
//   1. input Rec.709 linear -> P3D65, which is the tool's rendering space;
//   2. a "render space" desaturation that fixes how much of the color volume
//      the RGB ratios below span;
//   3. a scalar tone-scale driver with the color carried as RGB ratios;
//   4. hue-angle windows, hue contrast and the two hue-shift stages, which
//      are what give OpenDRT its filmic primary/secondary paths;
//   5. purity compression (a lerp to the achromatic axis driven by the
//      tone-scaled value), the mid-range purity trims that keep midtones
//      colorful without chalky highlights, and brilliance, which scales the
//      intensity of pure stimuli before the curve so darkening a primary
//      also softens its compression;
//   6. inverse render space, P3D65 -> Rec.709, and the final toe.
//
// Deviations from the reference, all recorded in the notices section:
//   - SDR only: the peak luminance is fixed at 100 nits, so the display
//     scale ts_dsc is 1, the HDR grey-boost term is log2(1) = 0, and the
//     HDR purity lerp that would blend ts_s1 towards s_Lp100 has weight zero
//     - which collapses the reference's tsn_pt and tsn_const curves into one
//     and removes pt_hdr, tn_gb and tn_Lp as parameters.
//   - The output transfer is this pack's sRGB OETF in post/final.fragment, so
//     the port returns display-linear and omits the reference's inverse
//     display EOTF, and it uses the tool's "sRGB Display" preset surround
//     (tn_su = 2, bright surround) instead of its default Rec.1886 preset.
//   - Default TONEMAP_ODT_GREY_LUMINANCE re-anchors the display grey: the
//     tool's own default of 10 nits on a 100-nit peak puts scene 18% grey on
//     0.124 display-linear, while every other mode in this pack shares a
//     0.18 anchor. 15.1306824 is the solved value that places scene 18% grey
//     on exactly 18% display-linear with the default tone-scale parameters.
//   - Input and display gamut are fixed to Rec.709, so the reference's
//     two-step conversions (Rec.709 -> XYZ D65 -> P3D65 and its inverse)
//     fold into one matrix each, and the creative-white stage is a
//     no-op at its Standard preset value D65 and is omitted.
// ===========================================================================

// Rec.709 <-> P3D65, folded from the reference's XYZ D65 intermediate
// matrices. Each vec3 is one column, so the GLSL mat3 holds the transpose of
// the row-major products of the DCTL's matrix pair.
const mat3 ODT_SRGB_TO_P3D65 = mat3(
    vec3(0.8224619687, 0.0331941989, 0.0170826307),
    vec3(0.1775380313, 0.9668058011, 0.0723974407),
    vec3(0.0000000000, 0.0000000000, 0.9105199286));
const mat3 ODT_P3D65_TO_SRGB = mat3(
    vec3(1.2249401763, -0.0420569547, -0.0196375546),
    vec3(-0.2249401763, 1.0420569547, -0.0786360456),
    vec3(0.0000000000, 0.0000000000, 1.0982736001));

const float ODT_PI = 3.14159265358979323846;
const float ODT_TWO_PI = 6.28318530717958647692;
const float ODT_SQRT3_INVERSE = 0.57735026918962576;
// SDR paper white in nits, the reference's fixed SDR peak luminance.
const float ODT_PEAK_LUMINANCE = 100.0;
// Reference "sRGB Display" display-encoding preset: bright surround, which
// flattens the curve exponent by 2 * 5%.
const float ODT_SURROUND = 2.0;
// Scene-linear middle grey, fixed by the reference.
const float ODT_SCENE_GREY = 0.18;
// Render-space neutral axis weights (red, blue; green takes the remainder)
// and the achromatic-distance toe that smooths the purity response.
const float ODT_RENDER_WEIGHT_R = 0.25;
const float ODT_RENDER_WEIGHT_B = 0.55;
const float ODT_ACHROMATIC_TOE = 0.25;

// Hue angles, rotated so that red sits at 0. The RGB windows are wider than
// the CMY ones; the hue-shift variants move red towards orange and blue
// towards cyan, and the secondary angles are the reference's creative
// offsets from the exact cyan/magenta/yellow positions.
const float ODT_HUE_ORIGIN = 1.10714931;
const float ODT_HUE_ANGLE_R = 0.1;
const float ODT_HUE_ANGLE_G = 4.3;
const float ODT_HUE_ANGLE_B = 2.3;
const float ODT_HUE_ANGLE_SHIFT_R = -0.4;
const float ODT_HUE_ANGLE_SHIFT_B = 2.5;
const float ODT_HUE_ANGLE_C = 3.3;
const float ODT_HUE_ANGLE_M = 1.3;
const float ODT_HUE_ANGLE_Y = -1.15;
const float ODT_HUE_WINDOW_RGB = 0.66;
const float ODT_HUE_WINDOW_CMY = 0.5;

// Hue contrast (red only in the reference) and the two hue-shift stages.
// The G/B and CMY ranges are 1.0 in the Standard preset, whose 1/range
// exponent is a no-op, so those terms carry no power function here.
const float ODT_HUE_CONTRAST_R = 1.0;
const float ODT_HUE_CONTRAST_RANGE = 0.3;
const float ODT_HUE_SHIFT_R = 0.6;
const float ODT_HUE_SHIFT_R_RANGE = 0.6;
const float ODT_HUE_SHIFT_G = 0.35;
const float ODT_HUE_SHIFT_B = 0.66;
const float ODT_HUE_SHIFT_C = 0.25;
const float ODT_HUE_SHIFT_M = 0.0;
const float ODT_HUE_SHIFT_Y = 0.0;

// Per-channel purity-compression weights, mid-range purity trims and
// brilliance. The brilliance and post-brilliance sets darken pure red,
// green and blue, the mid-range terms lift low-purity midtones and pull down
// upper midtones, and the softclip constants are per-secondary.
const float ODT_PURITY_LOW_R = 0.5;
const float ODT_PURITY_LOW_G = 0.0;
const float ODT_PURITY_LOW_B = 0.1;
const float ODT_PURITY_HIGH_R = 0.5;
const float ODT_PURITY_HIGH_B = 0.0;
const float ODT_MID_PURITY_LOW = 0.4;
const float ODT_MID_PURITY_LOW_RANGE = 0.25;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.5;
const float ODT_MID_PURITY_HIGH = -0.8;
const float ODT_MID_PURITY_HIGH_RANGE = 0.35;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.4;
const float ODT_BRILLIANCE_RANGE = 0.5;
const float ODT_BRILLIANCE_STRENGTH = 0.35;
const float ODT_BRILLIANCE_R = -2.5;
const float ODT_BRILLIANCE_G = -1.5;
const float ODT_BRILLIANCE_B = -1.5;
const float ODT_POST_BRILLIANCE = -0.5;
const float ODT_POST_BRILLIANCE_R = -1.25;
const float ODT_POST_BRILLIANCE_G = -1.25;
const float ODT_POST_BRILLIANCE_B = -0.25;
const float ODT_PURITY_SOFTCLIP_C = 0.06;
const float ODT_PURITY_SOFTCLIP_M = 0.08;
const float ODT_PURITY_SOFTCLIP_Y = 0.06;

// Quadratic toe compression (reference compress_toe_quadratic); the inverse
// solves the same curve for its input and is only used by the tone-scale
// constraint solve below.
float ODTToeQuadratic(float x, float toe) {
    return toe == 0.0 ? x : x * x / (x + toe);
}

float ODTToeQuadraticInverse(float x, float toe) {
    return toe == 0.0 ? x : 0.5 * (x + sqrt(x * (4.0 * toe + x)));
}

// Hyperbolic compression x/(x + scale) raised to the contrast power: the
// tone-scale driver of the whole operator.
float ODTHyperbolicCompression(float x, float scale, float power) {
    return pow(x / (x + scale), power);
}

// The reference's cyan-yellow / green-magenta opponent pair, used for both
// the achromatic distance and the hue angle.
vec2 ODTOpponent(vec3 rgb) {
    return vec2(rgb.r - rgb.b, rgb.g - (rgb.r + rgb.b) * 0.5);
}

// Truncated remainder, the reference's C `fmod`. GLSL has no `fmod`, and its
// `mod` floors the quotient instead, which folds a negative argument by a
// full turn and would hand the hue windows a different angle than the
// reference computes. The explicit trunc form keeps the port comparable with
// the DCTL:
float ODTTruncatedRemainder(float x, float y) {
    return x - y * trunc(x / y);
}

// Gaussian hue-angle window: the reference's gauss_window over a hue offset
// wrapped into [-PI, PI].
float ODTWindow(float hue, float center, float width) {
    float offset = ODTTruncatedRemainder(hue - center + ODT_PI, ODT_TWO_PI) - ODT_PI;
    return exp(-offset * offset / width);
}

// Softplus with the reference's early-out; the per-channel purity softclip
// that keeps extremely pure primaries inside the display gamut volume.
float ODTSoftplus(float x, float scale) {
    if (x > 10.0 * scale || scale < 1.0e-4) return x;
    return scale * log(max(0.0, 1.0 + exp(x / scale)));
}

vec3 TonemapOpenDRT(vec3 linear_rgb) {
    // --- Tone-scale constraint solve (reference "Tonescale Constraint
    // Calculations") -- maps scene middle grey onto the display grey
    // luminance and the shoulder-clip scene value onto paper white. The
    // reference solves these per pixel for lack of a constant-folding path
    // in DCTL; they depend only on settings here as well.
    float ts_y1 = ODT_PEAK_LUMINANCE * 0.01;
    float ts_x0 = ODT_SCENE_GREY + TONEMAP_ODT_OFFSET;
    float ts_y0 = TONEMAP_ODT_GREY_LUMINANCE * 0.01;
    float ts_p = TONEMAP_ODT_CONTRAST / (1.0 + ODT_SURROUND * 0.05);
    float ts_x1 = exp2(6.0 * TONEMAP_ODT_SHOULDER_CLIP + 4.0);
    float ts_s0 = ODTToeQuadraticInverse(ts_y0, TONEMAP_ODT_TOE);
    float ts_s10 = ts_x0 * (pow(ts_s0, -1.0 / TONEMAP_ODT_CONTRAST) - 1.0);
    float ts_m1 = ts_y1 / pow(ts_x1 / (ts_x1 + ts_s10), TONEMAP_ODT_CONTRAST);
    float ts_m2 = ODTToeQuadraticInverse(ts_m1, TONEMAP_ODT_TOE);
    float ts_s = ts_x0 * (pow(ts_s0 / ts_m2, -1.0 / TONEMAP_ODT_CONTRAST) - 1.0);
    // The SDR purity lerp has zero weight at the fixed 100-nit peak, so the
    // reference's s_Lp100 scale is used for both of its tone-scale reads.
    float ts_s1 = ts_x0 * (pow(ts_y0, -1.0 / TONEMAP_ODT_CONTRAST) - 1.0);

    // --- Rendering space ---
    vec3 render_weights = vec3(ODT_RENDER_WEIGHT_R,
        1.0 - ODT_RENDER_WEIGHT_R - ODT_RENDER_WEIGHT_B, ODT_RENDER_WEIGHT_B);
    vec3 rgb = ODT_SRGB_TO_P3D65 * max(linear_rgb, vec3(0.0));
    float render_level = dot(rgb, render_weights);
    rgb = render_level * TONEMAP_ODT_RENDER_SATURATION + rgb * (1.0 - TONEMAP_ODT_RENDER_SATURATION);
    rgb += TONEMAP_ODT_OFFSET;

    // --- Tone-scale driver, RGB ratios, achromatic distance and hue ---
    float tsn = length(rgb) * ODT_SQRT3_INVERSE;
    rgb = tsn > 0.0 ? rgb / tsn : vec3(0.0);

    vec2 opponent = ODTOpponent(rgb);
    float ach_d = 1.25 * ODTToeQuadratic(0.5 * length(opponent), ODT_ACHROMATIC_TOE);
    float hue = ODTTruncatedRemainder(atan(opponent.x, opponent.y) + ODT_PI + ODT_HUE_ORIGIN,
        ODT_TWO_PI);

    vec3 hue_rgb = vec3(
        ODTWindow(hue, ODT_HUE_ANGLE_R, ODT_HUE_WINDOW_RGB),
        ODTWindow(hue, ODT_HUE_ANGLE_G, ODT_HUE_WINDOW_RGB),
        ODTWindow(hue, ODT_HUE_ANGLE_B, ODT_HUE_WINDOW_RGB));
    vec3 hue_rgb_shift = vec3(
        ODTWindow(hue, ODT_HUE_ANGLE_SHIFT_R, ODT_HUE_WINDOW_RGB),
        hue_rgb.g,
        ODTWindow(hue, ODT_HUE_ANGLE_SHIFT_B, ODT_HUE_WINDOW_RGB));
    vec3 hue_cmy = vec3(
        ODTWindow(hue, ODT_HUE_ANGLE_C, ODT_HUE_WINDOW_CMY),
        ODTWindow(hue, ODT_HUE_ANGLE_M, ODT_HUE_WINDOW_CMY),
        ODTWindow(hue, ODT_HUE_ANGLE_Y, ODT_HUE_WINDOW_CMY));

    // --- Brilliance ---
    float brilliance_ramp = pow(tsn / (tsn + 1.0), 1.0 - ODT_BRILLIANCE_RANGE);
    float brilliance = (TONEMAP_ODT_BRILLIANCE + ODT_BRILLIANCE_R * hue_rgb.r
        + ODT_BRILLIANCE_G * hue_rgb.g + ODT_BRILLIANCE_B * hue_rgb.b)
        * pow(ach_d, 1.0 / ODT_BRILLIANCE_STRENGTH);
    tsn *= exp2(brilliance * (brilliance < 0.0 ? brilliance_ramp : 1.0 - brilliance_ramp));

    // --- Hyperbolic compression ---
    // tsn_purity is the read the color stages below use; tsn becomes the
    // final display-referred level.
    float tsn_purity = ODTHyperbolicCompression(tsn, ts_s1, ts_p);
    tsn = ODTHyperbolicCompression(tsn, ts_s, ts_p);

    // --- Hue contrast (red angle only, as in the reference) ---
    float hue_contrast_scale = 1.0 - tsn_purity;
    float hue_contrast_center = (hue_contrast_scale * (1.0 - ach_d) + ach_d * (1.0 - hue_contrast_scale))
        * ach_d * hue_rgb.r;
    float hue_contrast = ODT_HUE_CONTRAST_R * (hue_contrast_center - 2.0 * hue_contrast_center
        * pow(hue_contrast_scale, 1.0 / ODT_HUE_CONTRAST_RANGE)) + 1.0;
    rgb = vec3(rgb.r, rgb.g * hue_contrast, rgb.b * hue_contrast);

    // --- Hue shift: primaries as intensity rises, secondaries as it falls ---
    vec3 hue_shift = vec3(
        hue_rgb_shift.r * ach_d * pow(tsn_purity, 1.0 / ODT_HUE_SHIFT_R_RANGE),
        hue_rgb_shift.g * ach_d * tsn_purity,
        hue_rgb_shift.b * ach_d * tsn_purity);
    vec3 hue_shift_rgb = vec3(hue_shift.r * ODT_HUE_SHIFT_R,
        hue_shift.g * -ODT_HUE_SHIFT_G, hue_shift.b * -ODT_HUE_SHIFT_B);
    rgb += vec3(hue_shift_rgb.b - hue_shift_rgb.g,
        hue_shift_rgb.r - hue_shift_rgb.b, hue_shift_rgb.g - hue_shift_rgb.r);

    vec3 hue_shift_cmy = ach_d * (1.0 - tsn_purity)
        * vec3(hue_cmy.r, hue_cmy.g, hue_cmy.b);
    vec3 hue_shift_cmy_rgb = vec3(hue_shift_cmy.r * -ODT_HUE_SHIFT_C,
        hue_shift_cmy.g * ODT_HUE_SHIFT_M, hue_shift_cmy.b * ODT_HUE_SHIFT_Y);
    rgb += vec3(hue_shift_cmy_rgb.b - hue_shift_cmy_rgb.g,
        hue_shift_cmy_rgb.r - hue_shift_cmy_rgb.b, hue_shift_cmy_rgb.g - hue_shift_cmy_rgb.r);

    // --- Purity compression and mid-range purity ---
    // The low/high limits shape how much purity survives at each end of the
    // intensity range; the achromatic distance gates both.
    float purity = 1.0 - pow(tsn_purity, 1.0 + 4.0 * (1.0 - tsn_purity)
        * (TONEMAP_ODT_PURITY_LOW + ODT_PURITY_LOW_R * hue_rgb_shift.r
            + ODT_PURITY_LOW_G * hue_rgb_shift.g + ODT_PURITY_LOW_B * hue_rgb_shift.b));
    purity = pow(purity, (1.0 - ach_d * (ODT_PURITY_HIGH_R * hue_rgb_shift.r
        + ODT_PURITY_HIGH_B * hue_rgb_shift.b)) * (1.0 - TONEMAP_ODT_PURITY_HIGH * ach_d));
    purity *= 1.0 + ODT_MID_PURITY_LOW * exp(-2.0 * ach_d * ach_d / ODT_MID_PURITY_LOW_STRENGTH)
        * pow(1.0 - tsn_purity, 1.0 / ODT_MID_PURITY_LOW_RANGE);
    purity *= 1.0 + ODT_MID_PURITY_HIGH * exp(-2.0 * ach_d * ach_d / ODT_MID_PURITY_HIGH_STRENGTH)
        * pow(tsn_purity, 1.0 / (4.0 * ODT_MID_PURITY_HIGH_RANGE));
    rgb = rgb * purity + 1.0 - purity;

    // --- Inverse rendering space and display gamut ---
    float purity_level = dot(rgb, render_weights);
    rgb = (purity_level * TONEMAP_ODT_RENDER_SATURATION - rgb)
        / (TONEMAP_ODT_RENDER_SATURATION - 1.0);
    rgb = ODT_P3D65_TO_SRGB * rgb;

    // --- Post brilliance ---
    // Re-measures the achromatic distance on the display gamut, because the
    // gamut conversion can push a primary back out of the compression plane.
    float post_ach_d = 0.25 * length(ODTOpponent(rgb));
    post_ach_d = 1.1 * (post_ach_d * post_ach_d / (post_ach_d + 0.1));
    float post_brilliance = ODT_POST_BRILLIANCE
        + ODT_POST_BRILLIANCE_R * ach_d * hue_rgb.r
        + ODT_POST_BRILLIANCE_G * ach_d * hue_rgb.g
        + ODT_POST_BRILLIANCE_B * ach_d * hue_rgb.b;
    rgb *= exp2(post_brilliance * post_ach_d * tsn);

    // --- Purity softclip and final toe ---
    rgb = vec3(ODTSoftplus(rgb.r, ODT_PURITY_SOFTCLIP_C),
        ODTSoftplus(rgb.g, ODT_PURITY_SOFTCLIP_M),
        ODTSoftplus(rgb.b, ODT_PURITY_SOFTCLIP_Y));
    // The display scale ts_dsc is 1 at the fixed SDR peak, so only the
    // inverse-toe gain and the toe itself remain.
    tsn = ODTToeQuadratic(tsn * ts_m2, TONEMAP_ODT_TOE);
    return clamp(rgb * tsn, 0.0, 1.0);
}

#endif // LIB_COLOR_TONEMAP_OPENDRT_GLSL
