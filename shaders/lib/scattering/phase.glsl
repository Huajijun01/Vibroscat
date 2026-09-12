#ifndef LIB_SCATTERING_PHASE_GLSL
#define LIB_SCATTERING_PHASE_GLSL

#include "/lib/core/math_scalar.glsl"

// ===============================================================
// Scattering phase functions - single canonical owner.
//
// A phase p(cos_theta), with cos_theta = dot(view_dir, light_dir), is
// normalized: the sphere integral of p dOmega = 1. The dual-lobe blend is
// the documented exception. Tuned eccentricities and lobe weights stay with
// the effect that owns them (atmosphere core, cirrus, volumetric clouds,
// water fog, shadow SSS); this file owns the formulas only.
// ===============================================================

// Isotropic phase: equal scattering into every direction.
const float PHASE_ISOTROPIC = 1.0 / (4.0 * PI);

// Rayleigh phase, 3/(16pi) * (1 + cos^2); symmetric front/back.
float PhaseRayleigh(float cos_theta) {
    return (cos_theta * cos_theta + 1.0) * (3.0 / (16.0 * PI));
}

// Henyey-Greenstein phase (Henyey & Greenstein 1941). One eccentricity g:
// g > 0 forward-peaked, g < 0 backward-peaked, g = 0 isotropic.
float PhaseHenyeyGreenstein(float cos_theta, float eccentricity) {
    float eccentricity2 = eccentricity * eccentricity;
    float denominator = max(1.0 + eccentricity2 - 2.0 * eccentricity * cos_theta, 1.0e-4);
    return PHASE_ISOTROPIC * (1.0 - eccentricity2) / (denominator * sqrt(denominator));
}

// Dual-lobe HG: an unweighted forward lobe plus a mirrored backward lobe
// (the volumetric-cloud directional phase, HanPi port). The sum of two
// normalized phases is intentionally not renormalized; callers treat the
// result as a directional weight, matching the upstream formulation.
float PhaseHenyeyGreensteinDualLobe(float cos_theta, float forward_g, float backward_g) {
    return PhaseHenyeyGreenstein(cos_theta, forward_g) + PhaseHenyeyGreenstein(cos_theta, -backward_g);
}

// Triple-lobe HG blend parameters. Weights sum to 1, so the blend stays a
// normalized phase. back_g is a magnitude; the backward lobe is evaluated
// at -back_g.
struct HenyeyGreensteinTripleLobe {
    float peak_g;
    float peak_weight;
    float mid_g;
    float mid_weight;
    float back_g;
    float back_weight;
};

float PhaseHenyeyGreensteinTripleLobe(float cos_theta, HenyeyGreensteinTripleLobe lobes) {
    return lobes.peak_weight * PhaseHenyeyGreenstein(cos_theta, lobes.peak_g)
        + lobes.mid_weight * PhaseHenyeyGreenstein(cos_theta, lobes.mid_g)
        + lobes.back_weight * PhaseHenyeyGreenstein(cos_theta, -lobes.back_g);
}

// Cornette-Shanks phase (Cornette & Shanks 1992): a normalized single-lobe
// fit to Mie scattering. g = 0 reduces to the Rayleigh phase; positive g
// biases scattering toward the forward (sun) direction.
float PhaseCornetteShanks(float cos_theta, float eccentricity) {
    float p = 1.0 + eccentricity * eccentricity - 2.0 * eccentricity * cos_theta;
    return (3.0 / (8.0 * PI)) * ((1.0 - eccentricity * eccentricity) * (1.0 + cos_theta * cos_theta)) / ((2.0 + eccentricity * eccentricity) * p * sqrt(p));
}

// HG normalized as a surface lobe: divided by its largest cosine-weighted
// hemisphere integral, taken with the surface normal along the lobe axis
// (2*PI * integral_0^1 mu*HG(mu,g) dmu). This stable closed form is valid at
// g = 0 as well, where the surface response is 1/PI. A surface transmission
// lobe (through-leaf glow), not a volume phase.
float PhaseHenyeyGreensteinSurfaceNormalized(float cos_theta, float eccentricity) {
    float g = clamp(eccentricity, 0.0, 0.9);
    float g2 = g * g;
    float projected_integral = (1.0 + g) / (2.0 * (1.0 - g + g2
        + (1.0 - g) * sqrt(1.0 + g2)));
    return PhaseHenyeyGreenstein(clamp(cos_theta, -1.0, 1.0), g) / projected_integral;
}

#endif // LIB_SCATTERING_PHASE_GLSL
