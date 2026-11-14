#ifndef LIB_ATMOSPHERE_MEDIA_GLSL
#define LIB_ATMOSPHERE_MEDIA_GLSL

#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/scattering/phase.glsl"

// 4-wave spectral media (450/510/580/650 nm); the Mie fit carries stratospheric sulfate.

// Best tested single-exponential fit to the unclamped exp(-A*sign(h)*|h|^B) reference; defined
// below sea level (2.906x sea level at -8 km). Density functions take the signed radius r = R + h.
const float ATM_RAY_SCALE_H_KM = 7.5;
const float ATM_RAY_INV_H = 1.0 / ATM_RAY_SCALE_H_KM;
const float ATM_RAY_OFFSET = ATM_PLANET_R * ATM_RAY_INV_H;

// Rayleigh scattering base (km^-1 at sea level, per wavelength).
const vec4 ATM_SIGMA_S_RAY = vec4(0.03295005, 0.01997218, 0.01193972, 0.00756925);

// Ozone tent fitted to AFGL ground-view absorption; support [0.5963, 44.5848] km above the surface.
const float ATM_OZONE_TENT_CENTER_KM = 22.5905742141994;
const float ATM_OZONE_TENT_INV_HALF_WIDTH = 0.045466376859396;
const float ATM_OZONE_TENT_PEAK = 1.10522750647986e+19;
const float ATM_OZONE_TENT_CENTER_R = ATM_PLANET_R + ATM_OZONE_TENT_CENTER_KM;
const float ATM_OZONE_TENT_OFFSET = ATM_OZONE_TENT_CENTER_R * ATM_OZONE_TENT_INV_HALF_WIDTH;

// Peak ozone absorption per band (km^-1); 381 * tent peak already merged in.
const vec4 ATM_OZONE_SIGMA = 381.0 * ATM_OZONE_TENT_PEAK
    * vec4(1.70999998e-26, 1.57999997e-25, 4.55000008e-25, 2.41999995e-25);

// Mie aerosol fit: BG is the high-altitude background, NEAR the sea-level increment. Coefficients
// are km^-1 at sea level, ordered [450, 510, 580, 650] nm; the _E extinction fits contain absorption.
const float ATM_MIE_COMPACT_H_KM = 2.3632245061346153;
const float ATM_MIE_COMPACT_INV_H = 1.0 / ATM_MIE_COMPACT_H_KM;
const float ATM_MIE_COMPACT_R_OFFSET = -ATM_PLANET_R * ATM_MIE_COMPACT_INV_H;
const vec4 ATM_MIE_BG_S = vec4(
    0.002946734521953393, 0.0026287289880078763,
    0.002298046456287176, 0.0019252013241666723);
const vec4 ATM_MIE_NEAR_S = vec4(
    0.0739489813045079, 0.06322641877746325,
    0.05277798037467991, 0.04528813435810743);
const vec4 ATM_MIE_BG_E = vec4(
    0.003358190056616399, 0.0031499084273433355,
    0.0030426921054533236, 0.0022406664889633547);
const vec4 ATM_MIE_NEAR_E = vec4(
    0.07826896397622593, 0.06887583434463689,
    0.05860808850252333, 0.05103810940978969);

// Phase weights sum to 1, so the blend stays a normalized phase; formulas in /lib/scattering/phase.glsl.
const float ATM_MIE_KN_E = 200.0;
// 1 / sphere integral of the K-N shape at ATM_MIE_KN_E, double precision.
const float ATM_MIE_KN_NORM = 4.9321931418319;
const float ATM_MIE_KN_WEIGHT = 0.1;
const float ATM_MIE_MID_G = 0.5;
const float ATM_MIE_MID_WEIGHT = 0.7;
const float ATM_MIE_BACK_G = 0.3;
const float ATM_MIE_BACK_WEIGHT = 0.2;

float AtmMiePhase(float cos_theta) {
    return ATM_MIE_KN_WEIGHT * PhaseKleinNishina(cos_theta, ATM_MIE_KN_E, ATM_MIE_KN_NORM)
        + ATM_MIE_MID_WEIGHT * PhaseHenyeyGreenstein(cos_theta, ATM_MIE_MID_G)
        + ATM_MIE_BACK_WEIGHT * PhaseHenyeyGreenstein(cos_theta, -ATM_MIE_BACK_G);
}

// Ocean albedo approximation, ordered [450, 510, 580, 650] nm; the multi-scatter LUT reuses
// this albedo for ground feedback. No specular sun glint.
const vec4 ATM_GROUND_ALBEDO = vec4(0.06, 0.045, 0.025, 0.015);

// r is the real signed radius, down to the bake's -8 km row; clamping must not truncate density.
float DensityRayR(float r) {
    return exp(-ATM_RAY_INV_H * r + ATM_RAY_OFFSET);
}

// Unitless shape in [0, 1]; the peak is baked into ATM_OZONE_SIGMA, no caller peak multiply.
float OzoneTentShape(float r) {
    float q = -ATM_OZONE_TENT_INV_HALF_WIDTH * r + ATM_OZONE_TENT_OFFSET;
    return saturate(1.0 - abs(q));
}

struct AtmosphereMedia {
    vec4 sigma_s_ray;
    vec4 sigma_s_mie;
    vec4 sigma_e_mie;
    vec4 sigma_a_ozone;
    vec4 sigma_t;      // total extinction: Rayleigh + Mie (sca+abs) + ozone
    vec4 sigma_s;      // Rayleigh + Mie scattering
};

AtmosphereMedia AtmosphereMediaAt(float r) {
    AtmosphereMedia media;
    float ray_density = DensityRayR(r);
    float height_ratio = max(ATM_MIE_COMPACT_INV_H * r + ATM_MIE_COMPACT_R_OFFSET, 0.0);
    float mie_weight = saturate(1.0 - height_ratio * height_ratio);
    mie_weight *= mie_weight;

    media.sigma_s_ray = ray_density * ATM_SIGMA_S_RAY;
    media.sigma_s_mie = ray_density * (ATM_MIE_BG_S + ATM_MIE_NEAR_S * mie_weight);
    media.sigma_e_mie = ray_density * (ATM_MIE_BG_E + ATM_MIE_NEAR_E * mie_weight);
    media.sigma_a_ozone = OzoneTentShape(r) * ATM_OZONE_SIGMA;
    // Fixed association (Rayleigh + Mie first, then ozone): one rounding path.
    media.sigma_t = (media.sigma_s_ray + media.sigma_e_mie) + media.sigma_a_ozone;
    media.sigma_s = media.sigma_s_ray + media.sigma_s_mie;
    return media;
}


#endif // LIB_ATMOSPHERE_MEDIA_GLSL
