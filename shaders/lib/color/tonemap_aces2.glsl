#ifndef LIB_COLOR_TONEMAP_ACES2_GLSL
#define LIB_COLOR_TONEMAP_ACES2_GLSL

#include "/lib/contract/settings.glsl"

#if TONEMAP_MODE == 1
#include "/lib/third_party/opencolorio/aces2_output.glsl"

// ACES 2.0 SDR approximation with a rational achromatic tonescale, analytic
// hue boundaries and an interior gamut-compression bypass. The OpenColorIO-
// derived transform retains the AP1 clamp, Hellwig-2022 responses and chroma
// compression; saturated colors use the display-cusp intersection model.
// Input is scene-linear Rec.709/D65; output is display-linear Rec.709/D65.
// The pack's shared sRGB OETF is applied once, in post/final.fragment.
// Uses the reference exposure without a middle-gray prescale.
// The Academy ACES 2.0 reference transform is Copyright Contributors to the
// ACES Project, Apache-2.0; see licenses/THIRD_PARTY_NOTICES.md section 3.
const mat3 ACES2_SRGB_TO_AP0 = mat3(
    vec3(0.4396329819, 0.0897764430, 0.0175411704),
    vec3(0.3829886982, 0.8134394287, 0.1115465533),
    vec3(0.1773783199, 0.0967841283, 0.8709122763));

vec3 TonemapACES2(vec3 linear_rgb) {
    // Clamp in AP1 inside the output transform, after converting the
    // signed source RGB; clipping Rec.709 first changes out-of-gamut hues.
    vec3 aces = ACES2_SRGB_TO_AP0 * linear_rgb;
    return ACES2Output(vec4(aces, 1.0)).rgb;
}
#endif

#endif // LIB_COLOR_TONEMAP_ACES2_GLSL
