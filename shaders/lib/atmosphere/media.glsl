#ifndef LIB_ATMOSPHERE_MEDIA_GLSL
#define LIB_ATMOSPHERE_MEDIA_GLSL

#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/scattering/phase.glsl"

// 4-wave spectral media (450/510/580/650 nm). The Mie fit carries the
// stratospheric sulfate contribution, so no separate sulfate layer is evaluated.

// ===============================================================
// Baked Constants
// ===============================================================


// -- Rayleigh density: exp(-h / H), signed altitude --
// H = 7.50 km is the best tested single-exponential fit to the unclamped
// exp(-A * sign(h) * |h|^B) reference over the pack's full training target.
// It removes the per-sample pow and is defined below sea level, where it
// reaches 2.906x sea level at -8 km.
// The density functions take the signed planet-centered radius r = R + h, so
// exp(-h / H) becomes exp(-r / H + R / H), one contracted multiply-add.
const float ATM_RAY_SCALE_H_KM = 7.5;
const float ATM_RAY_INV_H = 1.0 / ATM_RAY_SCALE_H_KM;
const float ATM_RAY_OFFSET = ATM_PLANET_R * ATM_RAY_INV_H;

// -- Rayleigh scattering base (km-^1 at sea level, per wavelength) --
const vec4 ATM_SIGMA_S_RAY = vec4(0.03295005, 0.01997218, 0.01193972, 0.00756925);

// -- Ozone: symmetric triangular tent --
// Symmetric ozone tent fitted to AFGL ground-view absorption/transmission.
// r is the signed planet-centered radius in km; the support is
// [0.596299124, 44.584849304] km above the surface. The function returns the
// unitless tent shape in [0, 1]; the tent peak and the existing 381 factor are
// baked into ATM_OZONE_SIGMA below, so shape * ATM_OZONE_SIGMA = 1000 * n * sigma.
const float ATM_OZONE_TENT_CENTER_KM = 22.5905742141994;
const float ATM_OZONE_TENT_INV_HALF_WIDTH = 0.045466376859396;
const float ATM_OZONE_TENT_PEAK = 1.10522750647986e+19;
// Radius-space center and the multiply-add constant center_radius / half_width.
const float ATM_OZONE_TENT_CENTER_R = ATM_PLANET_R + ATM_OZONE_TENT_CENTER_KM;
const float ATM_OZONE_TENT_OFFSET = ATM_OZONE_TENT_CENTER_R * ATM_OZONE_TENT_INV_HALF_WIDTH;

// -- Ozone cross-section * Dobson * tent peak  (pre-merged) --
// Already includes 381 * ATM_OZONE_TENT_PEAK, so this vec4 is the peak
// absorption per band in km^-1 and needs no further scaling by the peak.
const vec4 ATM_OZONE_SIGMA = 381.0 * ATM_OZONE_TENT_PEAK
    * vec4(1.70999998e-26, 1.57999997e-25, 4.55000008e-25, 2.41999995e-25);

// -- Mie: jointly fitted aerosol + stratospheric sulfate --
// beta(h) = exp(-h / 7.5 km) * (BG + NEAR * q^2), with
// q = max(1 - (max(h, 0) / Hc)^2, 0). The Mie pair reuses the Rayleigh density
// that the same sample already needs, so it evaluates no additional exp, pow,
// smoothstep, or height branch. BG is the background (high-altitude) term and
// NEAR the sea-level increment; _S and _E name the scattering and extinction
// fits, and the extinction fit already contains absorption. The coefficients
// are km^-1 at sea level, ordered [450, 510, 580, 650] nm. The mask is C1 at
// h = 0 and at Hc; negative altitude follows the signed Rayleigh continuation.
// Source: the joint aerosol + sulfate fit.
const float ATM_MIE_COMPACT_H_KM = 2.3632245061346153;
const float ATM_MIE_COMPACT_INV_H = 1.0 / ATM_MIE_COMPACT_H_KM;
// Multiply-add constant -R / Hc for the radius-space height ratio.
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

// -- Phase --
// Atmosphere Mie blend: a Klein-Nishina forward spike keeps the silver
// lining, a broad low-g HG forward lobe adds smooth haze, and a backward HG
// lobe (effective eccentricity -0.3) brightens the anti-solar sky. Weights
// sum to 1, so the blend stays a normalized phase. Formulas live in
// /lib/scattering/phase.glsl.
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

// -- Ground --
// Dark blue ocean approximation for the no-dip Lambertian surface, ordered
// [450, 510, 580, 650] nm. The matching multi-scatter LUT uses the same
// spectral albedo for ground feedback; this model has no specular sun glint.
const vec4 ATM_GROUND_ALBEDO = vec4(0.06, 0.045, 0.025, 0.015);

// ===============================================================
// Density functions (4-wave spectral fit model)
// ===============================================================

// Density profiles in signed planet-centered radius r = ATM_PLANET_R + h, in
// km. Callers hold the real signed radius (the sky march carries r_mid), so
// negative altitude below the ground line thickens the horizon dip instead of
// folding back to sea level. Each height term is a plain a * r + b that the
// compiler contracts to one FMA, and the march never forms h = r - R for
// the medium. Only the transmittance LUT radius is clamped at
// its call site; the multiscatter LUT takes the real signed radius down to
// the bake's -8 km row. That addressing protection must not truncate density.
float DensityRayR(float r) {
    return exp(-ATM_RAY_INV_H * r + ATM_RAY_OFFSET);
}

// Ozone is a symmetric triangular tent over its own support band, so its
// density is zero at negative altitude and above 44.585 km by shape, not by
// clamping altitude to sea level. Returns the unitless shape in [0, 1]: the
// peak is baked into ATM_OZONE_SIGMA, so the caller needs no peak multiply.
// The tent costs one multiply-add, one abs and one saturate, with no log, exp,
// pow, per-sample reciprocal or altitude subtraction. The argument cannot
// exceed one, so the upper clamp is exact and folds into the producing
// instruction.
float OzoneTentShape(float r) {
    float q = -ATM_OZONE_TENT_INV_HALF_WIDTH * r + ATM_OZONE_TENT_OFFSET;
    return saturate(1.0 - abs(q));
}

// ===============================================================
// Scattering & extinction per wavelength  (vec4 = [450,510,580,650])
// ===============================================================

// The per-radius media terms of one integration step, gathered once: the
// sky-radiance integration needs all of them at the same r on each of its
// ATM_NUM_STEPS steps. Rayleigh density is shared by the Rayleigh and Mie
// terms, and Mie scattering and extinction run the same background-plus-mask
// profile, so a step evaluates no Mie exponential and no separate sulfate
// layer.
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
    // The argument cannot exceed one, so saturate's upper clamp is exact.
    float mie_weight = saturate(1.0 - height_ratio * height_ratio);
    mie_weight *= mie_weight;

    media.sigma_s_ray = ray_density * ATM_SIGMA_S_RAY;
    media.sigma_s_mie = ray_density * (ATM_MIE_BG_S + ATM_MIE_NEAR_S * mie_weight);
    media.sigma_e_mie = ray_density * (ATM_MIE_BG_E + ATM_MIE_NEAR_E * mie_weight);
    media.sigma_a_ozone = OzoneTentShape(r) * ATM_OZONE_SIGMA;
    // Fixed association: Rayleigh + Mie first, then ozone, so the totals
    // keep one rounding path.
    media.sigma_t = (media.sigma_s_ray + media.sigma_e_mie) + media.sigma_a_ozone;
    media.sigma_s = media.sigma_s_ray + media.sigma_s_mie;
    return media;
}


#endif // LIB_ATMOSPHERE_MEDIA_GLSL
