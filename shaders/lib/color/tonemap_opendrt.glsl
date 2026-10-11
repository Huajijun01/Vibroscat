#ifndef LIB_COLOR_TONEMAP_OPENDRT_GLSL
#define LIB_COLOR_TONEMAP_OPENDRT_GLSL

#include "/lib/contract/settings.glsl"

#if TONEMAP_MODE == 3
#include "/lib/color/tonemap_opendrt_presets.glsl"


// ===========================================================================
// OpenDRT (mode 3)
//
// Ported from Jed Smith's OpenDRT (Open Display Rendering Transform),
// github.com/jedypod/open-display-transform, display-transforms/opendrt/
// OpenDRT.dctl, GPL-3.0; licenses/THIRD_PARTY_NOTICES.md section 25.
// Official look and tonescale presets select complete parameter sets,
// including contrast-low/high and creative-white stages. All raw parameters
// are fixed in tonemap_opendrt_presets.glsl.
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
//   6. inverse render space, creative-white adaptation, Rec.709 conversion,
//      and the final toe.
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
//   - Display gray stays at the reference's 10 nits; no calibration to
//     another operator is applied. Input and display gamut are Rec.709.
//     Creative-white matrices fold P3D65 -> XYZ -> CAT -> Rec.709.
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
const float ODT_GREY_LUMINANCE = 10.0;
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

// Quadratic toe compression (reference compress_toe_quadratic); the inverse
// solves the same curve for its input and is only used by the tone-scale
// constraint solve below.
float ODTToeQuadratic(float x, float toe) {
    return toe == 0.0 ? x : x * x / (x + toe);
}

float ODTToeQuadraticInverse(float x, float toe) {
    return toe == 0.0 ? x : 0.5 * (x + sqrt(x * (4.0 * toe + x)));
}

// Reference compress_toe_cubic, including its constraint inverse.
float ODTToeCubic(float x, float multiplier, float width, bool inverse_curve) {
    if (multiplier == 1.0) return x;
    float x2 = x * x;
    if (!inverse_curve) return x * (x2 + multiplier * width) / (x2 + width);
    float p0 = x2 - 3.0 * multiplier * width;
    float p1 = 2.0 * x2 + 27.0 * width - 9.0 * multiplier * width;
    float p2 = pow(0.5 * (sqrt(x2 * p1 * p1 - 4.0 * p0 * p0 * p0) + x * p1), 1.0 / 3.0);
    return p0 / (3.0 * p2) + p2 / 3.0 + x / 3.0;
}

// Reference contrast_high forward curve and its linear extension.
float ODTHighContrast(float x) {
    float power = exp2(ODT_HIGH_CONTRAST);
    float pivot = 0.18 * exp2(ODT_HIGH_CONTRAST_PIVOT);
    if (x < pivot || power == 1.0) return x;
    float offset = pivot - pivot / power;
    float scale = pow(pivot, 1.0 - power) / power;
    float extension = pivot * exp2(ODT_HIGH_CONTRAST_EXTENSION);
    float extension_power = pow(extension, power);
    float slope = power * scale * extension_power / extension;
    float intercept = scale * extension_power + offset;
    return x > extension ? slope * (x - extension) + intercept : scale * pow(x, power) + offset;
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
    float ts_x0 = ODT_SCENE_GREY + ODT_OFFSET;
    float ts_y0 = ODT_GREY_LUMINANCE * 0.01;
    float ts_p = ODT_CONTRAST / (1.0 + ODT_SURROUND * 0.05);
    float ts_x1 = exp2(6.0 * ODT_SHOULDER_CLIP + 4.0);
    float ts_s0 = ODTToeQuadraticInverse(ts_y0, ODT_TOE);
    float ts_s10 = ts_x0 * (pow(ts_s0, -1.0 / ODT_CONTRAST) - 1.0);
    float ts_m1 = ts_y1 / pow(ts_x1 / (ts_x1 + ts_s10), ODT_CONTRAST);
    float ts_m2 = ODTToeQuadraticInverse(ts_m1, ODT_TOE);
    float ts_s = ts_x0 * (pow(ts_s0 / ts_m2, -1.0 / ODT_CONTRAST) - 1.0);
    // The SDR purity lerp has zero weight at the fixed 100-nit peak, so the
    // reference's s_Lp100 scale is used for both of its tone-scale reads.
    float ts_s1 = ts_x0 * (pow(ts_y0, -1.0 / ODT_CONTRAST) - 1.0);

    // --- Rendering space ---
    vec3 render_weights = vec3(ODT_RENDER_WEIGHT_R,
        1.0 - ODT_RENDER_WEIGHT_R - ODT_RENDER_WEIGHT_B, ODT_RENDER_WEIGHT_B);
    // The reference carries signed scene RGB through the rendering space;
    // clipping before conversion distorts signed out-of-gamut hues.
    vec3 rgb = ODT_SRGB_TO_P3D65 * linear_rgb;
    float render_level = dot(rgb, render_weights);
    rgb = render_level * ODT_RENDER_SATURATION + rgb * (1.0 - ODT_RENDER_SATURATION);
    rgb += ODT_OFFSET;

    // --- Tone-scale driver, RGB ratios, achromatic distance and hue ---
    float tsn = length(rgb) * ODT_SQRT3_INVERSE;
    rgb = tsn > 0.0 ? rgb / tsn : vec3(0.0);

    vec2 opponent = ODTOpponent(rgb);
    float ach_d = 1.25 * ODTToeQuadratic(0.5 * length(opponent), ODT_ACHROMATIC_TOE);
    // DCTL atan2(0, 0) selects zero for neutrals; GLSL atan(0, 0) is undefined.
    float opponent_angle = all(equal(opponent, vec2(0.0))) ? 0.0 : atan(opponent.x, opponent.y);
    float hue = ODTTruncatedRemainder(opponent_angle + ODT_PI + ODT_HUE_ORIGIN,
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
    float brilliance = (ODT_BRILLIANCE + ODT_BRILLIANCE_R * hue_rgb.r
        + ODT_BRILLIANCE_G * hue_rgb.g + ODT_BRILLIANCE_B * hue_rgb.b)
        * pow(ach_d, 1.0 / ODT_BRILLIANCE_STRENGTH);
    tsn *= exp2(brilliance * (brilliance < 0.0 ? brilliance_ramp : 1.0 - brilliance_ramp));

    // --- Official low/high contrast modules, before hyperbolic compression ---
    if (ODT_LOW_CONTRAST_ENABLE != 0) {
        float multiplier = exp2(-ODT_LOW_CONTRAST);
        float width = ODT_LOW_CONTRAST_WIDTH * 0.25;
        width *= width;
        float constraint = ODTToeCubic(ts_x0, multiplier, width, true) / ts_x0;
        tsn = ODTToeCubic(tsn * constraint, multiplier, width, false);
    }
    if (ODT_HIGH_CONTRAST_ENABLE != 0) tsn = ODTHighContrast(tsn);

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
        hue_rgb_shift.g * ach_d * pow(tsn_purity, 1.0 / ODT_HUE_SHIFT_G_RANGE),
        hue_rgb_shift.b * ach_d * pow(tsn_purity, 1.0 / ODT_HUE_SHIFT_B_RANGE));
    vec3 hue_shift_rgb = vec3(hue_shift.r * ODT_HUE_SHIFT_R,
        hue_shift.g * -ODT_HUE_SHIFT_G, hue_shift.b * -ODT_HUE_SHIFT_B);
    rgb += vec3(hue_shift_rgb.b - hue_shift_rgb.g,
        hue_shift_rgb.r - hue_shift_rgb.b, hue_shift_rgb.g - hue_shift_rgb.r);

    vec3 hue_shift_cmy = ach_d * hue_cmy * pow(vec3(1.0 - tsn_purity),
        vec3(1.0 / ODT_HUE_SHIFT_C_RANGE, 1.0 / ODT_HUE_SHIFT_M_RANGE, 1.0 / ODT_HUE_SHIFT_Y_RANGE));
    vec3 hue_shift_cmy_rgb = vec3(hue_shift_cmy.r * -ODT_HUE_SHIFT_C,
        hue_shift_cmy.g * ODT_HUE_SHIFT_M, hue_shift_cmy.b * ODT_HUE_SHIFT_Y);
    rgb += vec3(hue_shift_cmy_rgb.b - hue_shift_cmy_rgb.g,
        hue_shift_cmy_rgb.r - hue_shift_cmy_rgb.b, hue_shift_cmy_rgb.g - hue_shift_cmy_rgb.r);

    // --- Purity compression and mid-range purity ---
    // The low/high limits shape how much purity survives at each end of the
    // intensity range; the achromatic distance gates both.
    float purity = 1.0 - pow(tsn_purity, 1.0 + 4.0 * (1.0 - tsn_purity)
        * (ODT_PURITY_LOW + ODT_PURITY_LOW_R * hue_rgb_shift.r
            + ODT_PURITY_LOW_G * hue_rgb_shift.g + ODT_PURITY_LOW_B * hue_rgb_shift.b));
    purity = pow(purity, (1.0 - ach_d * (ODT_PURITY_HIGH_R * hue_rgb_shift.r
        + ODT_PURITY_HIGH_B * hue_rgb_shift.b)) * (1.0 - ODT_PURITY_HIGH * ach_d));
    purity *= 1.0 + ODT_MID_PURITY_LOW * exp(-2.0 * ach_d * ach_d / ODT_MID_PURITY_LOW_STRENGTH)
        * pow(1.0 - tsn_purity, 1.0 / ODT_MID_PURITY_LOW_RANGE);
    purity *= 1.0 + ODT_MID_PURITY_HIGH * exp(-2.0 * ach_d * ach_d / ODT_MID_PURITY_HIGH_STRENGTH)
        * pow(tsn_purity, 1.0 / (4.0 * ODT_MID_PURITY_HIGH_RANGE));
    rgb = rgb * purity + 1.0 - purity;

    // --- Inverse rendering space and display gamut ---
    float purity_level = dot(rgb, render_weights);
    rgb = (purity_level * ODT_RENDER_SATURATION - rgb)
        / (ODT_RENDER_SATURATION - 1.0);
    float white_weight = pow(tsn_purity, 2.0 * ODT_CREATIVE_WHITE_RANGE);
    rgb = mix(ODT_P3D65_TO_SRGB * rgb, ODT_CREATIVE_WHITE_MATRIX * rgb, white_weight);
    rgb *= ODT_CREATIVE_WHITE_NORMALIZATION * white_weight + 1.0 - white_weight;

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
    tsn = ODTToeQuadratic(tsn * ts_m2, ODT_TOE);
    return clamp(rgb * tsn, 0.0, 1.0);
}

#endif // TONEMAP_MODE == 3

#endif // LIB_COLOR_TONEMAP_OPENDRT_GLSL
