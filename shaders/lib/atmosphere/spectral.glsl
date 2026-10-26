#ifndef LIB_ATMOSPHERE_SPECTRAL_GLSL
#define LIB_ATMOSPHERE_SPECTRAL_GLSL

#include "/lib/core/math_scalar.glsl"

// ===============================================================
// Spectral -> linear sRGB  (4x3 manually expanded, FMA-friendly)
// Quadrature nodes 450/510/580/650 nm,
// weights refitted for the pack's display fit.
// ===============================================================

vec3 SpectralToLinearSRGB(vec4 spectral_radiance) {
    return vec3(dot(spectral_radiance, vec4(7.75104809, -60.9972992, 88.8918533, 53.3156281)),
        dot(spectral_radiance, vec4(-9.50318718, 69.8496323, 40.5499535, -5.23501587)),
        dot(spectral_radiance, vec4(98.9764709, 4.83470011, -6.79986143, -0.428102016)));
}

// ===============================================================
// Standard display white balance, in linear sRGB
//
// The scene illuminant is the 4-wave solar spectrum while the display is
// D65, so each linear sRGB channel is gained by the illuminant's own white:
//
//   gain = Y(solar) / S(solar),  Y = Rec.709 luminance
//
// Normalizing to the illuminant's luminance (Y = 175.79) keeps ATM_EXPOSURE
// and the rest of the lighting scale on their current calibration. This is
// a per-channel RGB white balance, not a Bradford chromatic adaptation:
// off-neutral spectra keep their channel ratios and shift with the gain.
// The 4-wave solar white is far from neutral (xy ~ 0.294/0.322), so the red
// gain is ~1.20 and the blue gain ~0.90.
//
// ===============================================================

const vec3 SRGB_WHITE_BALANCE = vec3(1.19774342, 0.963369071, 0.901317656);

vec3 SpectralToLinearSRGBWhiteBalanced(vec4 spectral_radiance) {
    return SpectralToLinearSRGB(spectral_radiance) * SRGB_WHITE_BALANCE;
}

// Spectral transmittance -> linear sRGB, normalized so T = 1 maps to white
// under the incident light spectrum; pass equal-energy for unknown light.
vec3 TransmittanceToLinearSRGB(vec4 t, vec4 light) {
    vec4 safe_light = max(light, vec4(1.0e-4));
    vec3 white = SpectralToLinearSRGB(safe_light);
    return saturate(SpectralToLinearSRGB(saturate(t) * safe_light)
        / max(white, vec3(1.0e-4)));
}

// Unitless spectral fraction -> linear sRGB, normalized so a neutral
// spectrum maps to white (same convention as TransmittanceToLinearSRGB).
// The white point of the coefficient matrix above is (88.961235, 95.661385,
// 96.583206) at float32, folded here as per-channel reciprocal multiplies
// (relative deviation from the division form is ~1e-6).
vec3 SpectralFractionToLinearSRGB(vec4 x) {
    return SpectralToLinearSRGB(saturate(x))
        * vec3(0.0112408511, 0.010453539, 0.0103537673);
}

#endif // LIB_ATMOSPHERE_SPECTRAL_GLSL
