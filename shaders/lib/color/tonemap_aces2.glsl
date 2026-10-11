#ifndef LIB_COLOR_TONEMAP_ACES2_GLSL
#define LIB_COLOR_TONEMAP_ACES2_GLSL

#include "/lib/contract/settings.glsl"


// ===========================================================================
// ACES 2.0 output transform (mode 1)
//
// Ported from the ACES 2.0 reference CTL (Apache-2.0, Copyright Contributors
// to the ACES Project; licenses/THIRD_PARTY_NOTICES.md section 22):
//   aces-core/lib/Lib.Academy.OutputTransform.ctl  (CAM + chroma + gamut)
//   aces-core/lib/Lib.Academy.Tonescale.ctl        (MM tonescale)
//   aces-core/lib/Lib.Academy.ColorSpaces.ctl      (Rec.709 -> AP0)
//
// Chain: linear sRGB -> ACES2065-1 (AP0, Bradford-adapted from D65) -> clamp
// to AP1 -> Hellwig-2022 JMh -> MM tonescale on J -> hue-dependent chroma
// compression -> JMh -> display-linear Rec.709.
//
// No lookup table of any kind, and no baked curve. The reference precomputes
// three 360-entry hue tables as a "compute once" optimisation of analytic
// solves; the one this port needs is the reach limit, and it is solved per
// pixel instead: the reference bisects `any(RGB < 0)` at J = limit_J_max in
// the AP1 reach gamut (its table spans 72.5 .. 194.4 over the hue circle),
// and ACES2ReachLimit does the same with a bounded 8-step bisection inside
// that observed bracket. Against the reference core this moves the output by
// at most 0.0096 display-linear (mean 0.0003) over 3000 sampled colors.
//
// Two reference stages are deliberately not ported, which is why this file is
// ~200 lines instead of the CTL's 1700:
//   - The display-cusp gamut compressor. It needs a second and a third hue
//     table (per-hue cusp and upper-hull gamma) built from nested solvers
//     (`find_display_cusp_for_hue`, `make_upper_hull_gamma_table`), and it
//     only reshapes colors the chroma compression already pushed outside the
//     limiting gamut. This port clamps instead, so extremely saturated
//     highlights clip per channel instead of being mapped inside.
//   - The inverse transform (`outputTransform_inv` and its helpers), which a
//     display transform does not need.
//
// Deviation in anchoring: the reference maps scene 18% grey to its own
// display grey, c_d = 10.013 nits = 0.100 display-linear. Every mode in this
// pack shares a 0.18 anchor, so TONEMAP_ACES2_INPUT_SCALE pre-scales the
// scene; its default 1.7133450 is the solved value that puts scene 18% grey
// on 18% display-linear, and 1.0 is the reference's own scale.
//
// Viewing conditions are the reference's fixed SDR set: dim surround
// (F_s = 0.9 / 0.59 / 0.9), L_A = 100, Y_b = 20, 100-nit peak, model gamma
// cz = 0.59 * (1.48 + sqrt(Y_b / L_A)) = 1.1370560.
// ===========================================================================

// Rec.709 (D65) -> ACES2065-1 (AP0, D60) with the Bradford chromatic
// adaptation the reference's `calculate_rgb_to_rgb_matrix` uses by default.
const mat3 ACES2_SRGB_TO_AP0 = mat3(
    vec3(0.4396329819, 0.0897764430, 0.0175411704),
    vec3(0.3829886982, 0.8134394287, 0.1115465533),
    vec3(0.1773783199, 0.0967841283, 0.8709122763));
// AP0 <-> AP1, for the reference's input clamp to the AP1 gamut.
const mat3 ACES2_AP0_TO_AP1 = mat3(
    vec3(1.4514393161, -0.0765537734, 0.0083161484),
    vec3(-0.2365107469, 1.1762296998, -0.0060324498),
    vec3(-0.2149285693, -0.0996759264, 0.9977163014));
const mat3 ACES2_AP1_TO_AP0 = mat3(
    vec3(0.6954522414, 0.0447945634, -0.0055258826),
    vec3(0.1406786965, 0.8596711185, 0.0040252103),
    vec3(0.1638690622, 0.0955343182, 1.0015006723));

// CAM16_c matrices. The Aab <-> cone-response pair depends only on the
// viewing conditions, so the input, reach and limit sets share it.
const mat3 ACES2_IN_RGB_TO_CAM16C = mat3(
    vec3(0.4451810084, 0.1237341065, 0.0117007255),
    vec3(0.3496492545, 0.6136436165, 0.0280607916),
    vec3(-0.0011297353, 0.0563228045, 0.7539390104));
const mat3 ACES2_CONE_TO_AAB = mat3(
    vec3(20.2588103403, 15480.0000000000, 1720.0000000000),
    vec3(10.1294051702, -16887.2727272727, 1720.0000000000),
    vec3(0.5064702585, 1407.2727272727, -3440.0000000000));
const mat3 ACES2_AAB_TO_CONE = mat3(
    vec3(0.0323680263, 0.0323680263, 0.0323680263),
    vec3(0.0000207658, -0.0000410250, -0.0000101296),
    vec3(0.0000132606, -0.0000120174, -0.0002900761));
// CAM16_c -> RGB per parameter set: AP1 for the reach solve, Rec.709 for the
// display output.
const mat3 ACES2_REACH_CAM16C_TO_RGB = mat3(
    vec3(4.0024029431, -0.8322729849, 0.0040119560),
    vec3(-2.6622907515, 2.4053381483, -0.0728795802),
    vec3(-0.0801911441, -0.3131441159, 1.3287886716));
const mat3 ACES2_LIMIT_CAM16C_TO_RGB = mat3(
    vec3(7.4504851642, -1.4750670894, 0.0106288727),
    vec3(-6.1301832888, 3.1183571979, -0.3185728276),
    vec3(-0.0603808280, -0.3833690610, 1.5678650023));

const float ACES2_CAM_OFFSET = 27.13;
const float ACES2_CAM_POWER = 0.42;
const float ACES2_CAM_POWER_INV = 2.380952380952381;   // 1 / 0.42
const float ACES2_CZ = 1.137056021344975;              // model gamma
const float ACES2_INV_CZ = 0.8794641435671241;         // 1 / cz
const float ACES2_F_L_N = 0.007937005275461673;
const float ACES2_A_W_J = 0.03236802625138552;         // compression_fwd(F_L)
const float ACES2_INV_A_W_J = 30.89468576902167;       // 1 / A_w_J
const float ACES2_J_SCALE = 100.0;
const float ACES2_FORWARD_LIMIT = 1024.0;              // 8 * r_hit at 100 nits
const float ACES2_LIMIT_J_MAX = 100.0;                 // Y_to_J(100 nits)

// MM tonescale at the fixed 100-nit SDR peak (Lib.Academy.Tonescale init).
const float ACES2_TS_M_2 = 1.047103762443455;
const float ACES2_TS_S_2 = 0.9198582541782887;
const float ACES2_TS_G = 1.15;
const float ACES2_TS_T_1 = 0.04;

// Chroma compression: the peak-independent ratios and the 100-nit normaliser.
const float ACES2_SAT = 1.3;
const float ACES2_COMPR = 2.4;
const float ACES2_SAT_THR = 0.005;
const float ACES2_CHROMA_SCALE = 1.0000530626;         // pow(0.03379*100, 0.30596) - 0.45135

// Bracket for the reach limit solve; the reference's table stays inside it.
const float ACES2_REACH_LOW = 50.0;
const float ACES2_REACH_HIGH = 250.0;
const int ACES2_REACH_STEPS = 8;

// Post-adaptation cone-response compression and its inverse (the reference
// clamps the inverse's input at 0.99).
float ACES2CompressCone(float v) {
    float compressed = pow(abs(v), ACES2_CAM_POWER);
    return sign(v) * compressed / (ACES2_CAM_OFFSET + compressed);
}

float ACES2ExpandCone(float v) {
    float limited = min(abs(v), 0.99);
    return sign(v) * pow(ACES2_CAM_OFFSET * limited / (1.0 - limited), ACES2_CAM_POWER_INV);
}

// Aab -> JMh: J is the achromatic response, M the colorfulness, h the hue.
vec3 ACES2AabToJMh(vec3 aab) {
    if (aab.x <= 0.0) return vec3(0.0);
    float hue = degrees(atan(aab.z, aab.y));
    return vec3(ACES2_J_SCALE * pow(aab.x, ACES2_CZ), length(aab.yz),
        mod(hue + 360.0, 360.0));
}

vec3 ACES2RGBToJMh(vec3 aces) {
    vec3 cone = ACES2_IN_RGB_TO_CAM16C * aces;
    vec3 aab = ACES2_CONE_TO_AAB * vec3(
        ACES2CompressCone(cone.x), ACES2CompressCone(cone.y), ACES2CompressCone(cone.z));
    return ACES2AabToJMh(aab);
}

vec3 ACES2JMhToRGB(vec3 jmh, mat3 cam16c_to_rgb) {
    float hue = radians(jmh.z);
    vec3 aab = vec3(pow(max(jmh.x, 0.0) / ACES2_J_SCALE, ACES2_INV_CZ),
        jmh.y * cos(hue), jmh.y * sin(hue));
    vec3 cone = ACES2_AAB_TO_CONE * aab;
    return cam16c_to_rgb * vec3(
        ACES2ExpandCone(cone.x), ACES2ExpandCone(cone.y), ACES2ExpandCone(cone.z));
}

// J <-> luminance in nits, through the achromatic response. The forward
// direction divides by the white's achromatic response A_w_J, the inverse
// multiplies by it.
float ACES2JToY(float j) {
    float normalized = pow(max(j, 0.0) / ACES2_J_SCALE, ACES2_INV_CZ);
    return ACES2ExpandCone(ACES2_A_W_J * normalized) / ACES2_F_L_N;
}

float ACES2YToJ(float y) {
    float response = ACES2CompressCone(y * ACES2_F_L_N);
    return ACES2_J_SCALE * pow(max(response * ACES2_INV_A_W_J, 0.0), ACES2_CZ);
}

// Forward MM tone scale: relative scene-linear in, display nits out.
float ACES2Tonescale(float x) {
    float f = ACES2_TS_M_2 * pow(max(x, 0.0) / (x + ACES2_TS_S_2), ACES2_TS_G);
    return max(0.0, f * f / (f + ACES2_TS_T_1)) * ACES2_J_SCALE;
}

// The reference's soft toe. `x > limit` passes through, which is what leaves
// near-neutral pixels untouched.
float ACES2Toe(float x, float limit, float k1_in, float k2_in) {
    if (x > limit) return x;
    float k2 = max(k2_in, 0.001);
    float k1 = sqrt(k1_in * k1_in + k2 * k2);
    float k3 = (limit + k1) / (limit + k2);
    float minus_b = k3 * x - k1;
    float minus_c = k2 * k3 * x;
    return 0.5 * (minus_b + sqrt(minus_b * minus_b + 4.0 * minus_c));
}

// Hue-dependent normaliser, the reference's own 3-harmonic series in degrees.
float ACES2ChromaNorm(float hue) {
    float hr = radians(hue);
    float a = cos(hr);
    float b = sin(hr);
    float cos2 = a * a - b * b;
    float sin2 = 2.0 * a * b;
    float cos3 = 4.0 * a * a * a - 3.0 * a;
    float sin3 = 3.0 * b - 4.0 * b * b * b;
    return (11.34072 * a + 16.46899 * cos2 + 7.88380 * cos3 + 14.66441 * b
        - 6.37224 * sin2 + 9.19364 * sin3 + 77.12896) * ACES2_CHROMA_SCALE;
}

// Largest M that stays inside the AP1 reach gamut at J = limit_J_max, solved
// with the reference's own test (`any(RGB < 0)`) in a bounded bisection.
float ACES2ReachLimit(float hue) {
    vec3 high_probe = vec3(ACES2_LIMIT_J_MAX, ACES2_REACH_HIGH, hue);
    if (!any(lessThan(ACES2JMhToRGB(high_probe, ACES2_REACH_CAM16C_TO_RGB), vec3(0.0))))
        return ACES2_REACH_HIGH;

    float low = ACES2_REACH_LOW;
    float high = ACES2_REACH_HIGH;
    vec3 low_probe = vec3(ACES2_LIMIT_J_MAX, low, hue);
    if (any(lessThan(ACES2JMhToRGB(low_probe, ACES2_REACH_CAM16C_TO_RGB), vec3(0.0))))
        return low;

    for (int i = 0; i < ACES2_REACH_STEPS; ++i) {
        float mid = 0.5 * (low + high);
        vec3 mid_probe = vec3(ACES2_LIMIT_J_MAX, mid, hue);
        if (any(lessThan(ACES2JMhToRGB(mid_probe, ACES2_REACH_CAM16C_TO_RGB), vec3(0.0))))
            high = mid;
        else
            low = mid;
    }
    return high;
}

// Rescale M with the tone-scaled J, expand then compress it against the reach
// limit. The expansion lifts shadows and midtones, the compression rolls
// highlights off while keeping pure colors.
vec3 ACES2ChromaCompress(vec3 jmh, float tonemapped_j) {
    if (jmh.y == 0.0 || jmh.x <= 0.0 || tonemapped_j <= 0.0)
        return vec3(tonemapped_j, jmh.y, jmh.z);

    float normalized_j = tonemapped_j / ACES2_LIMIT_J_MAX;
    float remaining = max(0.0, 1.0 - normalized_j);
    float norm = ACES2ChromaNorm(jmh.z);
    float limit = pow(normalized_j, ACES2_INV_CZ) * ACES2ReachLimit(jmh.z) / norm;

    float m = jmh.y * pow(tonemapped_j / jmh.x, ACES2_INV_CZ) / norm;
    m = limit - ACES2Toe(limit - m, limit - 0.001, remaining * ACES2_SAT,
        sqrt(normalized_j * normalized_j + ACES2_SAT_THR));
    m = ACES2Toe(m, limit, normalized_j * ACES2_COMPR, remaining);
    return vec3(tonemapped_j, m * norm, jmh.z);
}

vec3 TonemapACES2(vec3 linear_rgb) {
    vec3 aces = ACES2_SRGB_TO_AP0 * (max(linear_rgb, vec3(0.0)) * TONEMAP_ACES2_INPUT_SCALE);
    aces = ACES2_AP1_TO_AP0 * clamp(ACES2_AP0_TO_AP1 * aces, 0.0, ACES2_FORWARD_LIMIT);

    vec3 jmh = ACES2RGBToJMh(aces);
    float scene_y = ACES2JToY(jmh.x) / ACES2_J_SCALE;
    float tonemapped_j = ACES2YToJ(ACES2Tonescale(scene_y));

    return clamp(ACES2JMhToRGB(ACES2ChromaCompress(jmh, tonemapped_j),
        ACES2_LIMIT_CAM16C_TO_RGB), 0.0, 1.0);
}

#endif // LIB_COLOR_TONEMAP_ACES2_GLSL
