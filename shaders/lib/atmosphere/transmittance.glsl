#ifndef LIB_ATMOSPHERE_TRANSMITTANCE_GLSL
#define LIB_ATMOSPHERE_TRANSMITTANCE_GLSL

#include "/lib/atmosphere/atmosphere_geometry.glsl"

// -- Custom Texture bindings (registered in shaders.properties) --
//
// MS LUT: raw 4-wave radiance in RGBA16F (32x32), no per-channel
// normalization - sampled values are absolute spectral radiance.

// ===============================================================
// LUT UV mapping
// ===============================================================

vec2 GetTransmittanceLUTUV(float r, float r2, float mu) {
    float rho = sqrt(r2 - ATM_PLANET_R2);
    float discriminant = r2 * (mu * mu - 1.0) + ATM_ATMO_R2;
    float d = max(0.0, (-r * mu + sqrt(max(discriminant, 0.0))));
    float d_min = ATM_ATMO_R - r;
    float d_max = rho + ATM_H;
    float x_mu = (d - d_min) / max(d_max - d_min, 1.0e-5);
    float x_r  = rho / max(ATM_H, 1.0e-5);
    x_mu = x_mu * x_mu;  // square remap -> more resolution near horizon
    return vec2(x_mu, x_r);
}

vec2 GetMultiScatterLUTUV(float r, float mu) {
    return vec2(mu * 0.5 + 0.5, (r - ATM_PLANET_R) * ATM_RCP_ATMO_MINUS_P);
}

// ===============================================================
// LUT Sampling
// ===============================================================

vec4 SampleTransmittance(sampler2D lut_tex, float r, float r2, float mu) {
    vec2 uv = GetTransmittanceLUTUV(r, r2, mu);
    return textureLod(lut_tex, uv, 0.0);
}

vec4 SampleMultiScatter(sampler2D lut_tex, float r, float mu) {
    return textureLod(lut_tex, GetMultiScatterLUTUV(r, mu), 0.0);
}

#endif // LIB_ATMOSPHERE_TRANSMITTANCE_GLSL
