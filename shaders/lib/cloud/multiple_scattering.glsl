#ifndef LIB_CLOUD_MULTIPLE_SCATTERING_GLSL
#define LIB_CLOUD_MULTIPLE_SCATTERING_GLSL

#include "/lib/scattering/phase.glsl"

// Every scattering order past the first, isotropized:
// fms = omega_sat * (1 - exp2(-reference_optical_depth)); orders = fms / (1 - fms).
// reference_optical_depth is dimensionless (extinction times the owning layer's
// reference length). omega_sat < 1 keeps the series finite in half-float.

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
