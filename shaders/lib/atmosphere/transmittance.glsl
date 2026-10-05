#ifndef LIB_ATMOSPHERE_TRANSMITTANCE_GLSL
#define LIB_ATMOSPHERE_TRANSMITTANCE_GLSL

#include "/lib/atmosphere/atmosphere_geometry.glsl"

// -- Custom Texture bindings (registered in shaders.properties) --
//
// MS LUT: raw 4-wave radiance in RGBA16F (32x32), no per-channel
// normalization - sampled values are absolute spectral radiance. The u axis
// is horizon-concentrated; see GetMultiScatterLUTUV below.

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
    float x_r  = rho * ATM_RCP_H;
    x_mu = x_mu * x_mu;  // square remap -> more resolution near horizon
    return vec2(x_mu, x_r);
}

// Paired horizon UVs for one radius and mirrored musines (sun and moon share
// the extinction path): rho and the discriminant sqrt only depend on mu^2, so
// the pair computes them once. Each output is bit-identical to
// GetTransmittanceLUTUV with the matching sign: (-mu)^2 == mu^2 exactly and
// -r * (-mu) is the exact sign flip of r * mu.
void GetTransmittanceLUTUVPair(float r, float r2, float mu, out vec2 uv_pos, out vec2 uv_neg) {
    float rho = sqrt(r2 - ATM_PLANET_R2);
    float mu2 = mu * mu;
    float sq = sqrt(max(r2 * (mu2 - 1.0) + ATM_ATMO_R2, 0.0));
    float d_min = ATM_ATMO_R - r;
    float d_max = rho + ATM_H;
    float x_r  = rho * ATM_RCP_H;
    // One shared reciprocal keeps the mirrored outputs bit-identical.
    float inv_range = 1.0 / max(d_max - d_min, 1.0e-5);

    float d_pos = max(0.0, -r * mu + sq);
    float x_mu_pos = (d_pos - d_min) * inv_range;
    uv_pos = vec2(x_mu_pos * x_mu_pos, x_r);

    float d_neg = max(0.0, r * mu + sq);
    float x_mu_neg = (d_neg - d_min) * inv_range;
    uv_neg = vec2(x_mu_neg * x_mu_neg, x_r);
}

// The MS LUT's u axis is the bake's sign(s)*s^3 sun-elevation ladder: the 32
// knots are horizon-dense instead of uniform in mu. Addressing works in the
// elevation fraction g = 2*asin(mu)/pi and inverts the cube. Keep this map in
// lockstep with the finalize pass of the sky-tracer pack bake.
vec2 GetMultiScatterLUTUV(float r, float mu) {
    float g = asin(clamp(mu, -1.0, 1.0)) * 0.6366197723675814;
    float s = sign(g) * pow(abs(g), 1.0 / 3.0);
    return vec2(s * 0.5 + 0.5, (r - ATM_PLANET_R) * ATM_RCP_ATMO_MINUS_P);
}

// ===============================================================
// LUT Sampling
// ===============================================================

vec4 SampleTransmittance(sampler2D lut_tex, float r, float r2, float mu) {
    vec2 uv = GetTransmittanceLUTUV(r, r2, mu);
    if(uv.x > 1.0) {
        return vec4(0.0);
    }
    return textureLod(lut_tex, uv, 0.0);
}

vec4 SampleMultiScatter(sampler2D lut_tex, float r, float mu) {
    return textureLod(lut_tex, GetMultiScatterLUTUV(r, mu), 0.0);
}

#endif // LIB_ATMOSPHERE_TRANSMITTANCE_GLSL
