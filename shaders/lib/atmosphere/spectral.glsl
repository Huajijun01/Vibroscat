#ifndef LIB_ATMOSPHERE_SPECTRAL_GLSL
#define LIB_ATMOSPHERE_SPECTRAL_GLSL

// ===============================================================
// Spectral -> linear sRGB  (4x3 manually expanded, FMA-friendly)
// ===============================================================

vec3 SpectralToLinearSRGB(vec4 spectral_radiance) {
    return vec3(dot(spectral_radiance, vec4(6.321843624, -26.517091751, 30.142539978, 118.707962036)),
        dot(spectral_radiance, vec4(-5.534153461, 17.321765900, 98.470054626, -8.898775101)),
        dot(spectral_radiance, vec4(39.173206329, 71.765632629, -12.650737762, -1.295249343)));
}

// ===============================================================
// Spectral -> linear Rec.2020  (4x3, solar-white-balanced to D65)
//
// Linear Rec.2020 working space (smaller CMF negative weights); columns
// pre-multiplied by a Bradford solar-white->D65 adaptation. Convert back
// with Rec2020ToSRGB() at the scene boundary.
// ===============================================================

vec3 SpectralToLinearRec2020(vec4 spectral_radiance) {
    return vec3(dot(spectral_radiance, vec4(3.845798926, -7.86893214, 48.567284779, 70.210607852)),
        dot(spectral_radiance, vec4(-4.264385887, 15.066919918, 93.470569559, -0.049300629)),
        dot(spectral_radiance, vec4(35.719363513, 67.276565483, -2.226660272, 0.023773354)));
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
vec3 SpectralFractionToLinearSRGB(vec4 x) {
    vec3 white = SpectralToLinearSRGB(vec4(1.0));
    return SpectralToLinearSRGB(clamp(x, vec4(0.0), vec4(1.0))) / white;
}

#endif // LIB_ATMOSPHERE_SPECTRAL_GLSL
