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
// Each layer supplies its own reference length, saturation albedo and
// strength. The exposed albedo remains below one, bounding the series by
// omega / (1 - omega) and keeping the packed half-float cloud signal finite.
// ===============================================================

// fms / (1 - fms): every scattering order past the first, isotropized.
float MultipleScatteringOrders(float reference_optical_depth, float saturation_albedo) {
    float unscattered = exp2(-max(reference_optical_depth, 0.0));
    float fms = saturation_albedo * (1.0 - unscattered);
    // Keep the exponential in the denominator: subtracting rounded fms
    // from one loses its remaining optical-depth contribution at high tau.
    float remaining = (1.0 - saturation_albedo) + saturation_albedo * unscattered;
    return fms / remaining;
}

// The added orders enter as an isotropic source, so they carry the isotropic
// phase and sum directly with the single-scattering phase. strength is the
// layer's own linear weight on those orders.
float IsotropicOrders(float reference_optical_depth, float saturation_albedo, float strength) {
    return strength * PHASE_ISOTROPIC
        * MultipleScatteringOrders(reference_optical_depth, saturation_albedo);
}

#endif // LIB_CLOUD_MULTIPLE_SCATTERING_GLSL
