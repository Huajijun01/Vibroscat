#ifndef LIB_COLOR_PURKINJE_GLSL
#define LIB_COLOR_PURKINJE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/spaces.glsl"

// ============================================================================
// Rod-mediated night vision (Purkinje shift).
// ============================================================================
//
// Below the cone threshold the visual response collapses to a single
// achromatic rod channel with peak sensitivity near 507 nm: scene colors
// lose chroma and read blue-gray, and red content (V' ~ 0) dims fastest.
// Scotopic luminance is estimated from CIE XYZ with the empirical
// mesopic-photometry relation V' = Y * (1.33 * (1 + (Y + Z) / X) - 1.68).
// The estimator is positive across the sRGB gamut (factor >= 0.398) and
// reproduces the D65 scotopic/photopic ratio V'/Y = 2.57. The replacement
// keeps that rod luminance on a unit-luminance blue-gray tint, so displayed
// brightness tracks rod sensitivity while chroma is removed.
//
// Applied in the tonemap pass on the exposure-scaled image. The only gate
// input is the exposure state (requires AE):
//   adaptation_luma: an equivalent scene key reconstructed from the exposure
//     pass's persistent EV state. It models the partially adapted eye level.
//     The rod share ramps log-linearly across the mesopic band between
//     PURKINJE_SCOTOPIC_KEY and PURKINJE_PHOTOPIC_KEY.
// Per pixel, cone color vision retakes over above PURKINJE_CONE_LUMINANCE
// (post-exposure units): bright emitters keep their hue while the dark
// surroundings collapse onto the rod gray.

vec3 ApplyPurkinjeEffect(vec3 color, float adaptation_luma) {
    float key = max(adaptation_luma, 1.0e-6);
    float rod_weight = clamp(
        (log2(PURKINJE_PHOTOPIC_KEY) - log2(key))
            / (log2(PURKINJE_PHOTOPIC_KEY) - log2(PURKINJE_SCOTOPIC_KEY)),
        0.0, 1.0);
    rod_weight *= PURKINJE_STRENGTH;
    if (rod_weight <= 0.0) {
        return color;
    }

    vec3 xyz = SRGB_TO_XYZ * max(color, vec3(0.0));
    float scotopic_factor = 1.33
        * (1.0 + (xyz.y + xyz.z) / max(xyz.x, 1.0e-6)) - 1.68;
    float scotopic_luminance = xyz.y * max(scotopic_factor, 0.0);
    vec3 rod_color = scotopic_luminance
        * (PURKINJE_TINT / Luminance(PURKINJE_TINT));

    float cone_takeover = exp2(-Luminance(color) / PURKINJE_CONE_LUMINANCE);
    return mix(color, rod_color, rod_weight * cone_takeover);
}

#endif // LIB_COLOR_PURKINJE_GLSL
