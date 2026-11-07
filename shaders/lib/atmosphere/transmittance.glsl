#ifndef LIB_ATMOSPHERE_TRANSMITTANCE_GLSL
#define LIB_ATMOSPHERE_TRANSMITTANCE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/spectral.glsl"

// Multiscatter LUT bake geometry. The asset's V axis spans its signed bake
// altitude range linearly. Two asset pairs exist, selected by the
// shaders.properties ATM_HORIZON_DIP macro: the below-dip pair spans
// [-(8 km), ATM_ATMO_MINUS_P] with row centers at -6, -2, 2, ..., 118 km,
// and the no-dip pair spans [0, ATM_ATMO_MINUS_P]. The bake depth is a
// property of the asset, not of the user's ATM_HORIZON_DIP_SCALE: that
// setting moves the runtime march bound, while this addressing stays fixed
// per variant.
#ifdef ATM_HORIZON_DIP
const float ATM_MS_BAKE_DIP_KM = 8.0;
#else
const float ATM_MS_BAKE_DIP_KM = 0.0;
#endif
const float ATM_MS_SPAN_KM = ATM_ATMO_MINUS_P + ATM_MS_BAKE_DIP_KM;
const float ATM_MS_RCP_SPAN = 1.0 / ATM_MS_SPAN_KM;

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

// MS bake contract: q = mu * (0.5 + 4 / (1 + 7*abs(mu))),
// u = 0.5 + (31/64)*q. The 32 knots include mu = +/-1 at the edge texel
// centers; no additional half-texel remap. The normalized denominator stays
// in [1/8, 1] for mu in [-1, 1]. V spans the bake's signed altitude range
// (see ATM_MS_BAKE_DIP_KM), so the real radius is passed in, including
// below the ground line for the below-dip asset. The saturate only matters
// for the no-dip asset, where a fp-noise radius under the surface clamps to
// the lowest row instead of smearing the edge texel.
vec2 GetMultiScatterLUTUV(float r, float mu) {
    float den = saturate(0.875 * abs(mu) + 0.125);
    float inv_den = 1.0 / den;
    float gain = 0.2421875 * inv_den + 0.2421875;
    float u = mu * gain + 0.5;
    return vec2(u, saturate((r - ATM_PLANET_R + ATM_MS_BAKE_DIP_KM) * ATM_MS_RCP_SPAN));
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

// Atmospheric transmittance along the camera->cloud-surface ray (UE
// GetTransmittance scheme; (r, mu) camera, (r_d, mu_d) surface, same ray):
//   ground miss:  T = T_lut(r, mu)      / T_lut(r_d, mu_d)
//   ground hit:   T = T_lut(r_d, -mu_d) / T_lut(r, -mu)   (reciprocity)
// The baked LUT stores the full chord for non-ground directions (incl.
// slightly negative cosines), so the first branch is valid for dir.y < 0.
vec3 AtmosphereTransmittanceToSurface(vec3 surface_pos, vec3 view_dir, float surface_r,
    bool ground_hit, vec4 camera_transmittance
) {
    float surface_mu = dot(surface_pos, view_dir) / surface_r;
    vec4 numerator;
    vec4 denominator;
    if (ground_hit) {
        numerator = SampleTransmittance(utex_tslut, surface_r, surface_r * surface_r, -surface_mu);
        denominator = camera_transmittance;
    } else {
        numerator = camera_transmittance;
        denominator = SampleTransmittance(utex_tslut, surface_r, surface_r * surface_r, surface_mu);
    }
    // The caller shares the camera lookup and horizon test across both layers.
    // tslut transmittances decode in [0,1], so the ratio never goes negative.
    vec4 segment_transmittance = saturate(numerator / max(denominator, vec4(1.0e-5)));
    return saturate(SpectralFractionToLinearSRGB(segment_transmittance));
}

#endif // LIB_ATMOSPHERE_TRANSMITTANCE_GLSL
