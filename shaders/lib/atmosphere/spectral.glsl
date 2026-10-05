#ifndef LIB_ATMOSPHERE_SPECTRAL_GLSL
#define LIB_ATMOSPHERE_SPECTRAL_GLSL

// ===============================================================
// Spectral -> linear sRGB  (4x3 manually expanded, FMA-friendly)
// Quadrature nodes 450/510/580/650 nm (sky-tracer realtime bands,
// weights refitted from sky-tracer's display fit); chain validated
// against the previous 410/480/560/630 constants (see
// research/sky-tracer/scripts/pack_glsl_constants.py).
// ===============================================================

vec3 SpectralToLinearSRGB(vec4 spectral_radiance) {
    return vec3(dot(spectral_radiance, vec4(7.75104809, -60.9972992, 88.8918533, 53.3156281)),
        dot(spectral_radiance, vec4(-9.50318718, 69.8496323, 40.5499535, -5.23501587)),
        dot(spectral_radiance, vec4(98.9764709, 4.83470011, -6.79986143, -0.428102016)));
}

// ===============================================================
// Spectral -> linear Rec.2020  (4x3, solar-white-balanced to D65)
//
// Linear Rec.2020 working space (smaller CMF negative weights); columns
// pre-multiplied by a Bradford solar-white->D65 adaptation. Convert back
// with Rec2020ToSRGB() at the scene boundary.
// ===============================================================

vec3 SpectralToLinearRec2020(vec4 spectral_radiance) {
    return vec3(dot(spectral_radiance, vec4(5.94900179, -13.560091, 74.1413651, 33.3429909)),
        dot(spectral_radiance, vec4(-6.80702496, 58.4251175, 42.3308372, -1.03582621)),
        dot(spectral_radiance, vec4(80.0665054, 8.67134762, -1.00728083, -0.000367216242)));
}

vec3 Rec2020ToSRGB(vec3 rgb) {
    // GLSL mat3 is column-major: pass columns of the row-major matrix.
    return mat3(1.660226750, -0.124553300, -0.018155170,
                -0.587547610, 1.132926080, -0.100603050,
                -0.072838260, -0.008349570, 1.118998170) * rgb;
}

// Spectral transmittance -> linear sRGB, normalized so T = 1 maps to white
// under the incident light spectrum; pass equal-energy for unknown light.
vec3 TransmittanceToLinearSRGB(vec4 t, vec4 light) {
    vec4 safe_light = max(light, vec4(1.0e-4));
    vec3 white = SpectralToLinearSRGB(safe_light);
    return clamp(SpectralToLinearSRGB(clamp(t, vec4(0.0), vec4(1.0)) * safe_light)
        / max(white, vec3(1.0e-4)), vec3(0.0), vec3(1.0));
}

// Rec.2020 variant; convert back with Rec2020ToSRGB at the scene boundary.
vec3 TransmittanceToLinearRec2020(vec4 t, vec4 light) {
    vec4 safe_light = max(light, vec4(1.0e-4));
    vec3 white = SpectralToLinearRec2020(safe_light);
    return clamp(SpectralToLinearRec2020(clamp(t, vec4(0.0), vec4(1.0)) * safe_light)
        / max(white, vec3(1.0e-4)), vec3(0.0), vec3(1.0));
}

// Unitless spectral fraction -> linear sRGB, normalized so a neutral
// spectrum maps to white (same convention as TransmittanceToLinearSRGB).
// The white point of the coefficient matrix above is (88.961235, 95.661385,
// 96.583206) at float32, folded here as per-channel reciprocal multiplies
// (relative deviation from the division form is ~1e-6).
vec3 SpectralFractionToLinearSRGB(vec4 x) {
    return SpectralToLinearSRGB(clamp(x, vec4(0.0), vec4(1.0)))
        * vec3(0.0112408511, 0.010453539, 0.0103537673);
}

#endif // LIB_ATMOSPHERE_SPECTRAL_GLSL
