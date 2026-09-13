#ifndef LIB_CLOUD_MULTIPLE_SCATTERING_GLSL
#define LIB_CLOUD_MULTIPLE_SCATTERING_GLSL

#include "/lib/scattering/phase.glsl"

// ===============================================================
// Cloud multiple scattering - the shared form, owned once.
//
// The approximation is the one published at
//   https://zhuanlan.zhihu.com/p/457997155
// It splits a cloud sample's in-scattering into the single-scattering phase
// and a geometric series standing for every order past the first:
//
//   fms    = omega_sat * (1 - exp2(-reference_optical_depth))
//   orders = fms / (1 - fms)                    orders >= 1, isotropic
//
// reference_optical_depth is DIMENSIONLESS: the medium's extinction times the
// reference length of the layer that owns it. The knee sits at one optical
// depth over that length, which is the same statement for any medium only
// because the length is supplied per layer.
//
// TWO of the model's inputs are per-layer and are therefore arguments, not
// constants of this file.
//
// reference_optical_depth: a knee expressed in sigma_t alone carries a length
// in its units, and a length calibrated for one medium lands somewhere else
// entirely for another. This pack's volumetric layer runs at 100 km^-1 and a
// cirrus shell at 3 km^-1, a factor of 33 apart. One knee cannot put both at
// the same place on the curve, and a layer that never reaches the knee gets no
// series at all. Each layer therefore owns the length and states it next to
// its own extinction.
//
// saturation_albedo: this is the medium's single-scattering albedo, which the
// source writes as the leading omega of fms. Water and ice are different
// media, and this pack already gives them different albedos, so they cannot
// share this. It is passed in rather than read from a user-facing control
// because the series converges to omega / (1 - omega) and would swing by orders
// of magnitude across one march step; each layer pins its own value and lets
// its strength control scale the result linearly.
//
// This is the model that lets a layer return more radiance than single
// scattering with a single-scattering albedo of at most 1. A constant gain on
// the scattering term instead raises the effective albedo above 1 and creates
// energy; the series adds it from the medium's own optical depth.
// ===============================================================

// Extinction in m^-1 for an extinction authored per kilometer.
const float CLOUD_EXTINCTION_PER_KM_TO_PER_M = 0.001;
// 1 - fms only needs a guard against an albedo of exactly 1. At a saturation
// albedo of 0.99 the ratio peaks at 999 and never reaches this floor.
const float CLOUD_MS_FLOOR = 1.0e-4;

// fms / (1 - fms): every scattering order past the first, isotropized.
// saturation_albedo is the layer's own, not a shared constant; see the header.
float CloudMultipleScatteringOrders(float reference_optical_depth, float saturation_albedo) {
    float fms = saturation_albedo
        * (1.0 - exp2(-max(reference_optical_depth, 0.0)));
    return fms / max(1.0 - fms, CLOUD_MS_FLOOR);
}

// The added orders enter as an isotropic source, so they carry the isotropic
// phase and sum directly with the single-scattering phase. strength is the
// layer's own linear weight on those orders.
float CloudIsotropicOrders(float reference_optical_depth, float saturation_albedo, float strength) {
    return strength * PHASE_ISOTROPIC
        * CloudMultipleScatteringOrders(reference_optical_depth, saturation_albedo);
}

#endif // LIB_CLOUD_MULTIPLE_SCATTERING_GLSL
