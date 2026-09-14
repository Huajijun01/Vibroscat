#ifndef LIB_COLOR_TONEMAP_GT7_GLSL
#define LIB_COLOR_TONEMAP_GT7_GLSL

#include "/lib/contract/settings.glsl"


// ===========================================================================
// GT7 Tone Mapping (mode 4): Polyphony Digital's color-volume mapping
// operator, "Driving Toward Reality: Physically Based Tone Mapping and
// Perceptual Fidelity in Gran Turismo 7" [PDI25], SIGGRAPH 2025 courses.
// Ported from the official sample implementation shipped with the course
// material (gt7_tone_mapping.cpp, MIT; licenses/THIRD_PARTY_NOTICES.md
// section 17). A per-channel pass of the GT Tone Mapping Curve V2 (linear
// midtones, contrast toe, converging shoulder) is blended with an ICtCp
// path that keeps the original chroma but fades it toward white across the
// highlight, so saturated highlights roll off without the per-channel hue
// twist. The sample's frame-buffer domain (1.0 = 100 nits, linear
// Rec.2020, SDR paper white 250 nits) is entered and left through the
// BT.709 <-> BT.2020 matrices below; GT7_MID_GREY_SCALE re-anchors scene
// 18% grey at 18% display-linear, the anchor shared with the other modes
// (same role as ACES_MID_GREY_SCALE, solved from 0.4*curve(scale*0.18)=0.18).
// ===========================================================================

const mat3 SRGB_TO_BT2020 = mat3(
    vec3(0.6274039, 0.0690973, 0.0163914),
    vec3(0.3292830, 0.9195404, 0.0880133),
    vec3(0.0433131, 0.0113623, 0.8955953));
const mat3 BT2020_TO_SRGB = mat3(
    vec3(1.6604910, -0.1245505, -0.0181508),
    vec3(-0.5876411, 1.1328999, -0.1005789),
    vec3(-0.0728499, -0.0083494, 1.1187297));

// ICtCp (ITU-R BT.2124) on Rec.2020 primaries; the GLSL columns hold the
// transposed ITU rows, so M * v matches the reference row-major multiply.
const mat3 GT7_BT2020_TO_LMS = mat3(
    vec3(1688.0, 683.0, 99.0),
    vec3(2146.0, 2951.0, 309.0),
    vec3(262.0, 462.0, 3688.0)) / 4096.0;
const mat3 GT7_LMS_TO_BT2020 = mat3(
    vec3(3.4366066943, -0.7913295556, -0.0259498997),
    vec3(-2.5064521187, 1.9836004518, -0.0989137147),
    vec3(0.0698454243, -0.1922708962, 1.1248636144));
const mat3 GT7_LMS_TO_ICTCP = mat3(
    vec3(2048.0, 6610.0, 17933.0),
    vec3(2048.0, -13613.0, -17390.0),
    vec3(2048.0, 7003.0, -543.0)) / 4096.0;
const mat3 GT7_ICTCP_TO_LMS = mat3(
    vec3(0.6666666667, 0.6666666667, 0.6666666667),
    vec3(-0.1780680749, -0.1952861489, 0.3733542238),
    vec3(0.2179053500, -0.0041539000, -0.2137514500));

// ST 2084 transfer on the sample's frame-buffer scale (1.0 = 100 nits).
float InverseEotfST2084(float framebuffer) {
    float shaped = pow(max(framebuffer, 0.0) * 0.01, 0.1593017578125);
    return pow((0.8359375 + 18.8515625 * shaped) / (1.0 + 18.6875 * shaped), 78.84375);
}

float EotfST2084(float pq) {
    float shaped = pow(max(pq, 0.0), 1.0 / 78.84375);
    return 100.0 * pow(max(shaped - 0.8359375, 0.0) / (18.8515625 - 18.6875 * shaped), 6.277394636015);
}

vec3 RgbToICtCp(vec3 rgb) {
    vec3 lms = GT7_BT2020_TO_LMS * rgb;
    lms = vec3(InverseEotfST2084(lms.r), InverseEotfST2084(lms.g), InverseEotfST2084(lms.b));
    return GT7_LMS_TO_ICTCP * lms;
}

vec3 ICtCpToRgb(vec3 ictcp) {
    vec3 lms = GT7_ICTCP_TO_LMS * ictcp;
    lms = vec3(EotfST2084(lms.r), EotfST2084(lms.g), EotfST2084(lms.b));
    return max(GT7_LMS_TO_BT2020 * lms, 0.0);
}

// GT Tone Mapping Curve V2. Official SDR preset (peak 2.5, gray point
// 0.538, linear section 0.444, toe strength 1.28) with one deliberate
// deviation: alpha 0 instead of the sample's 0.25, so the shoulder
// asymptote is exactly paper white. The sample's engine normalizes scene
// exposure before the curve and can output HDR, which hides its
// overshooting shoulder; this pack feeds un-normalized scene values into
// an SDR target, where the 0.25 shoulder crossed white at ~1.45x scene
// white and the official min() hard-clipped everything brighter.
// Perfectly linear below 0.444 * peak, contrast toe toward black,
// converging exponential shoulder above the linear section.
const float GT7_PEAK = 2.5;             // paper white, frame-buffer scale
const float GT7_SDR_CORRECTION = 0.4;   // 1 / paper-white frame-buffer value
const float GT7_GRAY_POINT = 0.538;
const float GT7_LINEAR_SECTION = 0.444;
const float GT7_TOE_STRENGTH = 1.280;
// Shoulder terms kA + kB*exp(kC*x) with k = (0.444 - 1) / (0 - 1);
// kA = peak * (0.444 + k) = peak for alpha 0.
const float GT7_SHOULDER_A = 2.5;
const float GT7_SHOULDER_B = -3.089054009429425;
const float GT7_SHOULDER_C = -0.719424460431655;
// UCS luma of the paper-white grey (2.5, 2.5, 2.5): chroma-fade pivot.
const float GT7_TARGET_LUMA_UCS = 0.903838732486;
// Input prescale re-anchoring 18% grey: 0.4*curve(scale*0.18) = 0.18.
const float GT7_MID_GREY_SCALE = 2.508318700610;

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
    vec3 rgb = SRGB_TO_BT2020 * (GT7_MID_GREY_SCALE * max(linear_rgb, 0.0));
    vec3 ucs = RgbToICtCp(rgb);

    // Step 1: per-channel curve pass (color-accurate midtones, hue twist
    // in the shoulder).
    vec3 skewed = vec3(GT7Curve(rgb.r), GT7Curve(rgb.g), GT7Curve(rgb.b));

    // Step 2: UCS pass - twisted luma, original chroma faded toward white
    // as the scene luminance approaches paper white.
    vec3 skewed_ucs = RgbToICtCp(skewed);
    // Ordered edges: the two sliders may be set either way round, and
    // smoothstep is undefined when edge0 >= edge1.
    float chroma_scale = 1.0 - smoothstep(
        min(TONEMAP_GT7_CHROMA_FADE_START, TONEMAP_GT7_CHROMA_FADE_END),
        max(TONEMAP_GT7_CHROMA_FADE_START, TONEMAP_GT7_CHROMA_FADE_END),
        ucs.x / GT7_TARGET_LUMA_UCS);
    vec3 faded = ICtCpToRgb(vec3(skewed_ucs.x, ucs.y * chroma_scale, ucs.z * chroma_scale));

    // Step 3: blend the paths and apply the SDR paper-white correction.
    vec3 blended = mix(skewed, faded, TONEMAP_GT7_BLEND);
    return BT2020_TO_SRGB * (min(blended, vec3(GT7_PEAK)) * GT7_SDR_CORRECTION);
}

#endif // LIB_COLOR_TONEMAP_GT7_GLSL
