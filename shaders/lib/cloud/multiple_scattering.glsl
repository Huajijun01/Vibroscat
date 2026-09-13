#ifndef LIB_CLOUD_MULTIPLE_SCATTERING_GLSL
#define LIB_CLOUD_MULTIPLE_SCATTERING_GLSL

#include "/lib/scattering/phase.glsl"

// ===============================================================
// Cloud multiple scattering - single canonical owner for both cloud layers.
//
// The approximation is the one published at
//   https://zhuanlan.zhihu.com/p/457997155
// It splits a cloud sample's in-scattering into the single-scattering phase
// and a geometric series standing for every order past the first:
//
//   fms    = omega_sat * (1 - exp2(-300 * sigma_t))    saturation factor
//   orders = fms / (1 - fms)                           orders >= 1, isotropic
//
// sigma_t is the medium extinction in m^-1, so the knee follows the local
// density instead of a scene-wide constant. Both layers author density per
// kilometer and convert with CLOUD_EXTINCTION_PER_KM_TO_PER_M.
//
// The saturation albedo is a fixed constant rather than the medium albedo: the
// series converges to omega / (1 - omega) and would swing by orders of
// magnitude across one march step if a user-facing albedo drove it. The medium
// albedo stays a separate linear factor at the caller.
//
// This is the model that lets a layer return more radiance than single
// scattering with a single-scattering albedo of at most 1. A constant gain on
// the scattering term instead raises the effective albedo above 1 and creates
// energy; the series adds it from the medium's own extinction.
// ===============================================================

// Extinction in m^-1 for an extinction authored per kilometer.
const float CLOUD_EXTINCTION_PER_KM_TO_PER_M = 0.001;
// Knee of the saturation factor.
const float CLOUD_MS_FMS_SCALE = 300.0;
// Saturation albedo of the geometric series; see the header.
const float CLOUD_MS_FMS_ALBEDO = 0.99;
// 1 - fms only needs a guard against an albedo of exactly 1. At the default
// albedo the ratio peaks at 999 and never reaches this floor.
const float CLOUD_MS_FMS_FLOOR = 1.0e-4;

// fms / (1 - fms): every scattering order past the first, isotropized.
float CloudMultipleScatteringOrders(float sigma_t_per_m) {
    float fms = CLOUD_MS_FMS_ALBEDO
        * (1.0 - exp2(-CLOUD_MS_FMS_SCALE * sigma_t_per_m));
    return fms / max(1.0 - fms, CLOUD_MS_FMS_FLOOR);
}

// The added orders enter as an isotropic source, so they carry the isotropic
// phase and sum directly with the single-scattering phase. strength is the
// layer's own linear weight on those orders.
float CloudIsotropicOrders(float sigma_t_per_m, float strength) {
    return strength * PHASE_ISOTROPIC * CloudMultipleScatteringOrders(sigma_t_per_m);
}

#endif // LIB_CLOUD_MULTIPLE_SCATTERING_GLSL
