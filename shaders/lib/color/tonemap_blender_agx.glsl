#ifndef LIB_COLOR_TONEMAP_BLENDER_AGX_GLSL
#define LIB_COLOR_TONEMAP_BLENDER_AGX_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/spaces.glsl"

#if TONEMAP_MODE == 2
#if TONEMAP_BLENDER_AGX_LOOK != 0
#include "/lib/third_party/opencolorio/blender_agx_looks.glsl"
#endif

// ===========================================================================
// Blender AgX (mode 2): the AgX view transform Blender 4.0 made the default
// for new files (Blender 4.0 color management release notes, "AgX View
// Transform"; blender/blender!106355, GPL-2.0-or-later). AgX itself is Troy
// Sobotka's display rendering transform; the configuration Blender ships is
// EaryChow's, and the sigmoid is Jed Smith's tunable toe/shoulder curve.
//
// Blender bakes the formation into the 57^3 `AgX_Base_sRGB.cube` LUT that its
// `AgX_LUT_Gen/AgXBasesRGB.py` generator writes. This port evaluates that
// generator's chain instead, in closed form:
//
//   linear sRGB (Rec.709, D65)
//     -> Rec.2020 -> lower input guard rail -> AgX inset
//     -> normalized log2 shaper over Blender's -10 .. +6.5 EV range
//     -> toe/shoulder contrast sigmoid, slope 2.4 / power 1.5
//     -> power 2.4 linearization out of the AgX Base encoding
//     -> 40% interpolation from original to formed working-space hue
//     -> [AgX outset] * [Rec.2020 -> Rec.709]                (one matrix)
//     -> lower display guard rail
//     -> display-linear Rec.709, clamped to [0,1]
//
// No lookup table, no baked curve, no table of curve samples: every stage is
// closed-form arithmetic on the pixel.
//
// Formation includes the generator's 40% interpolation from the original
// working-space hue toward the formed hue, and both lower guard rails.
// The guard rails below are independent algebraic reconstructions: for
// unit-sum luminance weights the opponent compensation reduces to 2*Y-min.
// No generator Python source is distributed. The upper guard rail remains
// disabled, matching the generator itself.
// Blender v4.0.0's nine official AgX looks are selected in their 25-stop
// AgX Log process space before the view formation. Punchy uses the official
// OCIO grading-tone and CDL operations; it is not a display-gamma shortcut.
// The Base Contrast look is identity and bypasses that conversion.
//
// Anchor: the shaper maps scene 0.18 to 10/16.5 EV, which is the curve's own
// x pivot, and the curve is built so that curve(x_pivot) = y_pivot and
// y_pivot^2.4 = 0.18. Both matrices keep neutrals fixed (the rows of the
// matrix as used sum to 1 within 1e-15). Scene 18% grey therefore lands on
// 18% display-linear with no pre-scale, which is why this mode has no
// input-scale option: unlike ACES 2.0 or OpenDRT, the reference's own
// calibration already is this pack's anchor.
// ===========================================================================

// Matrices derived from the generator's color spaces and working-space
// construction in `AgX_LUT_Gen/working_space.py`. The outset deliberately
// differs from the inverse inset, matching the generator's formation (the
// equivalent Rec.2020-generated parameters are rotate [2.13976149,
// -1.22827335, -3.05174246] and inset [0.32965205, 0.28051336, 0.12475368]).
// Each vec3 is one COLUMN; output primaries conversion is folded into the
// outset, while the input conversion precedes the Rec.2020 guard rail.
const mat3 BAGX_AGX_WORKING_TO_SRGB = mat3(
    vec3(1.964894002918574, -0.299309067235188, -0.164356434385884),
    vec3(-0.856007892438453, 1.326391871960617, -0.238207395344333),
    vec3(-0.108886110480121, -0.0270828047254282, 1.402563829730217));
const mat3 BAGX_SRGB_TO_REC2020 = mat3(
    vec3(0.627401924722236, 0.0690954897392609, 0.0163937090881632),
    vec3(0.329291971755002, 0.919544281267395, 0.0880281623979006),
    vec3(0.0433061035227624, 0.0113602289933443, 0.895578128513936));
const mat3 BAGX_REC2020_TO_WORKING = mat3(
    vec3(0.856627156288779, 0.137318972283552, 0.111898208045180),
    vec3(0.0951212454025349, 0.761241987009081, 0.0767994145625176),
    vec3(0.0482515983086858, 0.101439040707367, 0.811302377392303));
// Inverse of the official AgX Log inset, not the formation's outset.
const mat3 BAGX_LOG_WORKING_TO_REC2020 = mat3(
    vec3(1.197441076887705, -0.196474626321346, -0.146557417106601),
    vec3(-0.144261512698001, 1.354095131469730, -0.108284058788469),
    vec3(-0.053179564189704, -0.157620505148385, 1.254841475895071));
const float BAGX_LOOK_MIN_LOG2 = -12.47393;
const float BAGX_LOOK_LOG_RANGE = 24.9999988117;

// CIE 2015 / 6504 K weights used to generate Blender 4.0's shipped cube.
// The generator's June 2025 D65 revision uses different guard-rail weights.
const vec3 BAGX_REC2020_LUMINANCE = vec3(0.2658180370250449, 0.59846986045365, 0.1357121025213052);
const vec3 BAGX_SRGB_LUMINANCE = vec3(0.210352433792270, 0.649791053871429, 0.139856512336301);

// Translate a negative RGB minimum to zero, conserving the generator's
// compensated opponent luminance. An in-gamut input is unchanged.
vec3 BlenderAgXInputGuard(vec3 rgb) {
    float minimum = min(rgb.r, min(rgb.g, rgb.b));
    float offset = max(-minimum, 0.0);
    if (offset == 0.0) return rgb;
    float compensated_luma = max(2.0 * dot(rgb, BAGX_REC2020_LUMINANCE) - minimum, 0.0);
    return (rgb + offset) * compensated_luma / (compensated_luma + offset);
}

// The sRGB lower guard uses the same opponent luminance with an intensity
// dependent blend. Adding the common offset changes Y and the compensated
// Y by exactly offset, so the reference's two RGB passes reduce to this solve.
vec3 BlenderAgXOutputGuard(vec3 rgb) {
    float minimum = min(rgb.r, min(rgb.g, rgb.b));
    float offset = max(-minimum, 0.0);
    if (offset == 0.0) return rgb;
    float luma = max(dot(rgb, BAGX_SRGB_LUMINANCE), 0.0);
    float difference = luma - minimum;
    float before = luma + (1.0 - clamp(pow(luma, 0.08), 0.0, 1.0)) * difference;
    float shifted_luma = luma + offset;
    float after = shifted_luma
        + (1.0 - clamp(pow(shifted_luma, 0.08), 0.0, 1.0)) * difference;
    return (rgb + offset) * min(before / after, 1.0);
}

// Log2 shaper: Blender forms the image over -10 .. +6.5 EV around 0.18, which
// in absolute log2 is log2(0.18) - 10 to log2(0.18) + 6.5, a 16.5 EV range.
const float BAGX_MIN_LOG2 = -12.473931188332412333;             // log2(0.18) - 10
const float BAGX_INVERSE_DYNAMIC_RANGE = 0.060606060606060606;   // 1 / 16.5

// The sigmoid's six parameters. The pivots are fixed by the shaper: its input
// 0.18 sits at 10/16.5 EV, and the curve's output pivot is 0.18 raised to the
// 1/2.4 that the AgX Base encoding will take back off.
const float BAGX_X_PIVOT = 0.6060606060606061;      // 10 / 16.5, the shaper's 0.18
const float BAGX_Y_PIVOT = 0.48943708957387834;     // 0.18 ^ (1 / 2.4)
const float BAGX_CURVE_SLOPE = 2.4;                 // AgX's contrast
const float BAGX_CURVE_POWER = 1.5;                 // toe and shoulder power
const float BAGX_CURVE_INVERSE_POWER = 0.6666666666666666;   // 1 / 1.5
// Toe and shoulder scales, `equationScale` of `AgX_LUT_Gen/sigmoid.py`:
//   f(t, u) = ((slope*t)^-power * ((slope*t/u)^power - 1))^(-1/power)
// evaluated at the toe transition (t, u) = (1 - x_pivot, 1 - y_pivot), whose
// result the toe uses negated, and at the shoulder transition
// (t, u) = (x_pivot, y_pivot). `sigmoid.py`'s linear segment between the two
// transitions has zero width here - both transitions are the pivot - so the
// curve is exactly these two branches.
const float BAGX_TOE_SCALE = -0.5656756066543746;
const float BAGX_SHOULDER_SCALE = 0.7151982862790444;

// One channel of the AgX contrast sigmoid, in the shaper's [0,1] domain.
// Both branches keep slope*(value - x_pivot)/scale non-negative - the toe
// scale is negative on the negative side of the pivot - so the inner power
// never sees a negative base.
float BlenderAgXSigmoid(float value) {
    bool toe = value < BAGX_X_PIVOT;
    float scale = toe ? BAGX_TOE_SCALE : BAGX_SHOULDER_SCALE;
    float term = BAGX_CURVE_SLOPE * (value - BAGX_X_PIVOT) / scale;
    float shaped = term
        / pow(1.0 + pow(max(term, 0.0), BAGX_CURVE_POWER), BAGX_CURVE_INVERSE_POWER);
    // The reference clips the result for the same reason: rounding can leave
    // a -0 where the exact curve reaches 0.
    return max(BAGX_Y_PIVOT + scale * shaped, 0.0);
}

vec3 TonemapBlenderAGX(vec3 linear_rgb) {
    // The reference protects Rec.2020 after converting primaries; clipping
    // negative source RGB first changes the hue of out-of-gamut inputs.
    vec3 rec2020 = BAGX_SRGB_TO_REC2020 * linear_rgb;
#if TONEMAP_BLENDER_AGX_LOOK != 0
    // Scene -> official AgX Log -> look -> scene. AgX Log's inverse returns
    // through Rec.2020 without undoing the input luminance compensation.
    // The view transform then applies its own guard rail and inset below.
    vec3 log_working = BAGX_REC2020_TO_WORKING * BlenderAgXInputGuard(rec2020);
    log_working = (log2(max(log_working, 1.17549435e-38)) - BAGX_LOOK_MIN_LOG2) / BAGX_LOOK_LOG_RANGE;
    log_working = BlenderAgXOfficialLook(vec4(log_working, 1.0)).rgb;
    rec2020 = BAGX_LOG_WORKING_TO_REC2020 * exp2(log_working * BAGX_LOOK_LOG_RANGE + BAGX_LOOK_MIN_LOG2);
#endif
    vec3 working = BAGX_REC2020_TO_WORKING * BlenderAgXInputGuard(rec2020);
    vec3 original_hsv = RGBToHSV(working);

    // Normalized log2 shaper (min EV -10 .. max EV +6.5 around 0.18).
    working = (log2(max(working, 2e-10)) - BAGX_MIN_LOG2) * BAGX_INVERSE_DYNAMIC_RANGE;
    working = max(working, 0.0);

    // Per-channel contrast sigmoid, still inside the AgX working gamut.
    working = vec3(BlenderAgXSigmoid(working.x), BlenderAgXSigmoid(working.y),
        BlenderAgXSigmoid(working.z));

    // Out of the AgX Base 2.4 encoding, then out of the working gamut. The
    // reference leaves the result unclamped for later grading; this pack's
    // tonemap modes all return display-linear color in [0,1].
    working = pow(max(working, 0.0), vec3(2.4));
    vec3 formed_hsv = RGBToHSV(working);
    float hue_difference = formed_hsv.x - original_hsv.x;
    hue_difference -= floor(hue_difference + 0.5);
    formed_hsv.x = fract(original_hsv.x + 0.4 * hue_difference);
    working = HSVToRGB(formed_hsv);
    return clamp(BlenderAgXOutputGuard(BAGX_AGX_WORKING_TO_SRGB * working), 0.0, 1.0);
}

#endif // TONEMAP_MODE == 2

#endif // LIB_COLOR_TONEMAP_BLENDER_AGX_GLSL
