#ifndef LIB_CLOUD_MULTIPLE_SCATTERING_GLSL
#define LIB_CLOUD_MULTIPLE_SCATTERING_GLSL

#include "/lib/scattering/phase.glsl"

// Every scattering order past the first, isotropized: fms / (1 - fms). reference_optical_depth
// is dimensionless (extinction * the owning layer's reference length); omega_sat < 1 keeps the series finite.
float MultipleScatteringOrders(float reference_optical_depth, float saturation_albedo) {
    float unscattered = exp2(-max(reference_optical_depth, 0.0));
    float fms = saturation_albedo * (1.0 - unscattered);
    // (1 - a) + a * unscattered, not 1 - fms: subtracting rounded fms from one loses its high-tau contribution.
    float remaining = (1.0 - saturation_albedo) + saturation_albedo * unscattered;
    return fms / remaining;
}

// strength is the layer's own linear weight on the isotropic orders, which sum with the single-scattering phase.
float IsotropicOrders(float reference_optical_depth, float saturation_albedo, float strength) {
    return strength * PHASE_ISOTROPIC
        * MultipleScatteringOrders(reference_optical_depth, saturation_albedo);
}

#endif // LIB_CLOUD_MULTIPLE_SCATTERING_GLSL
