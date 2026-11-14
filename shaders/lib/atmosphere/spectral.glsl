#ifndef LIB_ATMOSPHERE_SPECTRAL_GLSL
#define LIB_ATMOSPHERE_SPECTRAL_GLSL

#include "/lib/core/math_scalar.glsl"

// Spectral -> linear sRGB over quadrature nodes 450/510/580/650 nm;
// weights refitted for the pack's display fit.
vec3 SpectralToLinearSRGB(vec4 spectral_radiance) {
    return vec3(dot(spectral_radiance, vec4(7.75104809, -60.9972992, 88.8918533, 53.3156281)),
        dot(spectral_radiance, vec4(-9.50318718, 69.8496323, 40.5499535, -5.23501587)),
        dot(spectral_radiance, vec4(98.9764709, 4.83470011, -6.79986143, -0.428102016)));
}

// Display white balance: each channel gained by Y(solar) / S(solar) (Rec.709 luminance), not a
// Bradford adaptation; normalizing to Y = 175.79 keeps the ATM_EXPOSURE lighting calibration.
const vec3 SRGB_WHITE_BALANCE = vec3(1.19774342, 0.963369071, 0.901317656);

vec3 SpectralToLinearSRGBWhiteBalanced(vec4 spectral_radiance) {
    return SpectralToLinearSRGB(spectral_radiance) * SRGB_WHITE_BALANCE;
}

// T = 1 maps to white under the incident light spectrum; pass equal-energy for unknown light.
vec3 TransmittanceToLinearSRGB(vec4 t, vec4 light) {
    vec4 safe_light = max(light, vec4(1.0e-4));
    vec3 white = SpectralToLinearSRGB(safe_light);
    return saturate(SpectralToLinearSRGB(saturate(t) * safe_light)
        / max(white, vec3(1.0e-4)));
}

// Neutral spectrum maps to white (same convention as TransmittanceToLinearSRGB); the matrix white
// point is folded into per-channel reciprocal multiplies (~1e-6 relative deviation).
vec3 SpectralFractionToLinearSRGB(vec4 x) {
    return SpectralToLinearSRGB(saturate(x))
        * vec3(0.0112408511, 0.010453539, 0.0103537673);
}

#endif // LIB_ATMOSPHERE_SPECTRAL_GLSL
