#ifndef LIB_COLOR_TONEMAP_GT7_GLSL
#define LIB_COLOR_TONEMAP_GT7_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"


// GT7 tone mapping (mode 5), ported from the SIGGRAPH 2025 course sample
// gt7_tone_mapping.cpp (MIT; licenses/THIRD_PARTY_NOTICES.md section 3).
// Per-channel GT Tone Mapping Curve V2 pass blended with an ICtCp path whose
// chroma fades toward white across the highlight. The frame-buffer domain
// (1.0 = 100 nits, linear Rec.2020, SDR paper white 250 nits) is entered and
// left through the BT.709 <-> BT.2020 matrices below.

const mat3 SRGB_TO_BT2020 = mat3(
    vec3(0.6274039, 0.0690973, 0.0163914),
    vec3(0.3292830, 0.9195404, 0.0880133),
    vec3(0.0433131, 0.0113623, 0.8955953));
const mat3 BT2020_TO_SRGB = mat3(
    vec3(1.6604910, -0.1245505, -0.0181508),
    vec3(-0.5876411, 1.1328999, -0.1005789),
    vec3(-0.0728499, -0.0083494, 1.1187297));

// ICtCp (ITU-R BT.2124) on Rec.2020 primaries; the GLSL columns hold the
// transposed ITU rows, so M * v matches the ITU row-major form.
const mat3 GT7_BT2020_TO_LMS = mat3(
    vec3(1688.0, 683.0, 99.0),
    vec3(2146.0, 2951.0, 309.0),
    vec3(262.0, 462.0, 3688.0)) / 4096.0;
const mat3 GT7_LMS_TO_BT2020 = mat3(
    vec3(3.4366066943, -0.7913295556, -0.0259498997),
    vec3(-2.5064521187, 1.9836004518, -0.0989137147),
    vec3(0.0698454243, -0.1922708962, 1.1248636144));
// Each vec3 below is one COLUMN, so these arrays read as the transpose of the
// ITU row-major formulas:
//   I  = 0.5*L + 0.5*M          Ct = (6610L - 13613M + 7003S) / 4096
//   Cp = (17933L - 17390M - 543S) / 4096
// and its exact inverse (round-trips within 2e-16) is
//   L = I + 0.0086090370*Ct + 0.1110296250*Cp
//   M = I - 0.0086090370*Ct - 0.1110296250*Cp
//   S = I + 0.5600313357*Ct - 0.3206271750*Cp
// The forward constant keeps S out of I: I is luma, and both the chroma-fade
// pivot and the faded path's luminance read it.
const mat3 GT7_LMS_TO_ICTCP = mat3(
    vec3(2048.0, 6610.0, 17933.0),
    vec3(2048.0, -13613.0, -17390.0),
    vec3(0.0, 7003.0, -543.0)) / 4096.0;
const mat3 GT7_ICTCP_TO_LMS = mat3(
    vec3(1.0, 1.0, 1.0),
    vec3(0.0086090370, -0.0086090370, 0.5600313357),
    vec3(0.1110296250, -0.1110296250, -0.3206271750));

// ST 2084 approximations on the frame-buffer scale (1.0 = 100 nits).
// The encoder is a degree-4/4 rational fit in the fourth root of [0, 200000].
// The decoder fits sqrt(luminance) over PQ [0, 1] and squares the result.
float InverseEotfST2084(float framebuffer) {
    float t = sqrt(sqrt(max(framebuffer, 0.0)));
    float numerator = (((2.3004936807 * t + 19.578484656) * t + 2.3376490862) * t
        - 0.035154822768) * t + 0.00013389250855;
    float denominator = (((1.2172895108 * t + 15.544603934) * t + 23.932019724) * t
        + 5.9143226671) * t + 1.0;
    return numerator / denominator;
}

float EotfST2084(float pq) {
    float t = saturate(pq);
    float numerator = ((-0.5306719001 * t + 0.6658327258) * t + 0.39794461679) * t
        + 0.00065304196493;
    float denominator = ((-0.30650758822 * t + 1.3182563834) * t - 1.9583739718) * t + 1.0;
    float root = numerator / denominator;
    return root * root;
}

vec3 RGBToICtCp(vec3 rgb) {
    vec3 lms = GT7_BT2020_TO_LMS * rgb;
    lms = vec3(InverseEotfST2084(lms.r), InverseEotfST2084(lms.g), InverseEotfST2084(lms.b));
    return GT7_LMS_TO_ICTCP * lms;
}

vec3 ICtCpToRGB(vec3 ictcp) {
    vec3 lms = GT7_ICTCP_TO_LMS * ictcp;
    lms = vec3(EotfST2084(lms.r), EotfST2084(lms.g), EotfST2084(lms.b));
    return max(GT7_LMS_TO_BT2020 * lms, 0.0);
}

// GT Tone Mapping Curve V2: SDR toe and linear section, with the pack's
// alpha = 0 shoulder.
// Its asymptote is paper white, preserving highlight gradation in SDR
// instead of overshooting white and relying on the final hard clamp.
const float GT7_PEAK = 2.5;
const float GT7_SDR_CORRECTION = 0.4;
const float GT7_GRAY_POINT = 0.538;
const float GT7_LINEAR_SECTION = 0.444;
const float GT7_TOE_STRENGTH = 1.280;
// Precomputed shoulder coefficients for alpha = 0.
const float GT7_SHOULDER_A = 2.5;
const float GT7_SHOULDER_B = -3.089054009429425;
const float GT7_SHOULDER_C = -0.719424460431655;
const float GT7_BLEND = 0.6;
const float GT7_CHROMA_FADE_START = 0.98;
const float GT7_CHROMA_FADE_END = 1.16;
// UCS luma I of the paper-white gray (2.5, 2.5, 2.5): chroma-fade pivot.
// I is luma, so it is 0.5 * (L + M) and excludes S.
const float GT7_TARGET_LUMA_UCS = 0.6025591550;
// Scene exposure key: folds the input scale into the primaries matrix, so
// scene 18% gray enters the curve at 0.36 and keys at
// 0.4 * GT7Curve(0.36) ~= 0.14 display-linear.
const float GT7_MID_GREY_SCALE = 2.0;
const mat3 SRGB_TO_BT2020_SCALED = SRGB_TO_BT2020 * GT7_MID_GREY_SCALE;

float GT7Curve(float x) {
    if (x <= 0.0) return 0.0;
    if (x >= GT7_LINEAR_SECTION * GT7_PEAK) {
        return GT7_SHOULDER_A + GT7_SHOULDER_B * exp(x * GT7_SHOULDER_C);
    }
    float weight_linear = smoothstep(0.0, GT7_GRAY_POINT, x);
    float weight_toe = 1.0 - weight_linear;
    float toe_mapped = GT7_GRAY_POINT * pow(x / GT7_GRAY_POINT, GT7_TOE_STRENGTH);
    return weight_toe * toe_mapped + weight_linear * x;
}

vec3 TonemapGT7(vec3 linear_rgb) {
    vec3 rgb = SRGB_TO_BT2020_SCALED * max(linear_rgb, 0.0);
    vec3 ucs = RGBToICtCp(rgb);

    // Step 1: per-channel curve pass (color-accurate midtones, hue twist
    // in the shoulder).
    vec3 skewed = vec3(GT7Curve(rgb.r), GT7Curve(rgb.g), GT7Curve(rgb.b));

    // Step 2: UCS pass - twisted luma, original chroma faded toward white
    // as the scene luminance approaches paper white.
    vec3 skewed_ucs = RGBToICtCp(skewed);
    // The thresholds are fixed and strictly ordered.
    float relative_luma = ucs.x / GT7_TARGET_LUMA_UCS;
    float chroma_scale = 1.0 - smoothstep(GT7_CHROMA_FADE_START, GT7_CHROMA_FADE_END, relative_luma);
    vec3 faded = ICtCpToRGB(vec3(skewed_ucs.x, ucs.y * chroma_scale, ucs.z * chroma_scale));

    // Step 3: blend the paths and apply the SDR paper-white correction.
    vec3 blended = mix(skewed, faded, GT7_BLEND);
    // Rec.2020's SDR cube is larger than Rec.709's. Apply the display clamp
    // after converting primaries, before the pack's sharpening and OETF.
    return saturate(BT2020_TO_SRGB * (min(blended, vec3(GT7_PEAK)) * GT7_SDR_CORRECTION));
}

#endif // LIB_COLOR_TONEMAP_GT7_GLSL
