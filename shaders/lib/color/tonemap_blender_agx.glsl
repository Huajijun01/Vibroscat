#ifndef LIB_COLOR_TONEMAP_BLENDER_AGX_GLSL
#define LIB_COLOR_TONEMAP_BLENDER_AGX_GLSL


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
//     -> [Rec.709 -> Rec.2020] * [AgX inset]                 (one matrix)
//     -> normalized log2 shaper over Blender's -10 .. +6.5 EV range
//     -> toe/shoulder contrast sigmoid, slope 2.4 / power 1.5
//     -> power 2.4 linearization out of the AgX Base encoding
//     -> [AgX outset] * [Rec.2020 -> Rec.709]                (one matrix)
//     -> display-linear Rec.709, clamped to [0,1]
//
// No lookup table, no baked curve, no table of curve samples: every stage is
// closed-form arithmetic on the pixel.
//
// Reference stages deliberately not ported:
//   - The per-channel chroma-angle mixing (40% in `AgXBasesRGB.py`) and the
//     sRGB guard rails (`compensate_low_side`; the generator itself has the
//     upper guard rail commented out because it flips the figure-ground
//     luminance relation above +8 EV). Both are a second per-channel pass
//     over an already formed image; Blender's own realtime GLSL port of this
//     configuration drops them for the same reason.
//   - The AgX contrast looks, including Punchy. Blender's own documentation
//     places them in the 25-stop "AgX Log" space with the pivot at 0.18 middle
//     grey, and describes Punchy as a look that darkens the image; the look's
//     definition also moved between AgX revisions. This port therefore ships
//     the Base Contrast view transform exactly as the generator writes it and
//     exposes no look option.
//
// Anchor: the shaper maps scene 0.18 to 10/16.5 EV, which is the curve's own
// x pivot, and the curve is built so that curve(x_pivot) = y_pivot and
// y_pivot^2.4 = 0.18. Both matrices keep neutrals fixed (the rows of the
// matrix as used sum to 1 within 1e-15). Scene 18% grey therefore lands on
// 18% display-linear with no pre-scale, which is why this mode has no
// input-scale option: unlike ACES 2.0 or OpenDRT, the reference's own
// calibration already is this pack's anchor.
// ===========================================================================

// Combined [Rec.709 -> Rec.2020] * [AgX inset], and its inverse combined with
// [Rec.2020 -> Rec.709]. Derived in the AgX port's Mathematica worksheet from
// the standard BT.709 -> BT.2020 matrix and the AgX working space of
// `AgX_LUT_Gen/working_space.py` (Rec.2020 primaries rotated and inset; the
// equivalent Rec.2020-generated parameters are rotate [2.13976149,
// -1.22827335, -3.05174246] and inset [0.32965205, 0.28051336, 0.12475368]).
// Each vec3 is one COLUMN, so the listing reads as the transpose of the
// worksheet's row-major result.
const mat3 BAGX_SRGB_TO_AGX_WORKING = mat3(
    vec3(0.544814746488245, 0.140416948464053, 0.0888104196149096),
    vec3(0.373787398372697, 0.754137554567394, 0.178871756420858),
    vec3(0.0813978551390581, 0.105445496968552, 0.732317823964232));
const mat3 BAGX_AGX_WORKING_TO_SRGB = mat3(
    vec3(1.96488741169489, -0.299313364904742, -0.164352742528393),
    vec3(-0.855988495690215, 1.32639796461980, -0.238183969428088),
    vec3(-0.108898916004672, -0.0270845997150571, 1.40253671195648));

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
    // The generator clamps the linear input in the source space, before the
    // combined inset, and uses a small positive floor only to keep log2()
    // away from zero; nothing below survives the shaper's own 0 clamp.
    vec3 working = BAGX_SRGB_TO_AGX_WORKING * max(linear_rgb, 2e-10);

    // Normalized log2 shaper (min EV -10 .. max EV +6.5 around 0.18).
    working = (log2(working) - BAGX_MIN_LOG2) * BAGX_INVERSE_DYNAMIC_RANGE;
    working = max(working, 0.0);

    // Per-channel contrast sigmoid, still inside the AgX working gamut.
    working = vec3(BlenderAgXSigmoid(working.x), BlenderAgXSigmoid(working.y),
        BlenderAgXSigmoid(working.z));

    // Out of the AgX Base 2.4 encoding, then out of the working gamut. The
    // reference leaves the result unclamped for later grading; this pack's
    // tonemap modes all return display-linear color in [0,1].
    working = pow(max(working, 0.0), vec3(2.4));
    return clamp(BAGX_AGX_WORKING_TO_SRGB * working, 0.0, 1.0);
}

#endif // LIB_COLOR_TONEMAP_BLENDER_AGX_GLSL
