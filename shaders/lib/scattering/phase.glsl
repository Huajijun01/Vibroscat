#ifndef LIB_SCATTERING_PHASE_GLSL
#define LIB_SCATTERING_PHASE_GLSL

#include "/lib/core/math_scalar.glsl"

// Normalized phase functions: the sphere integral of p dOmega is 1. The
// surface-normalized variant uses a projected hemisphere integral. Tuned
// parameters stay with the effect that owns them.

const float PHASE_ISOTROPIC = 1.0 / (4.0 * PI);

float PhaseRayleigh(float cos_theta) {
    return (cos_theta * cos_theta + 1.0) * (3.0 / (16.0 * PI));
}

// Henyey-Greenstein phase (Henyey & Greenstein 1941). One eccentricity g:
// g > 0 forward-peaked, g < 0 backward-peaked, g = 0 isotropic.
float PhaseHenyeyGreenstein(float cos_theta, float eccentricity) {
    float eccentricity2 = eccentricity * eccentricity;
    float denominator = max(1.0 + eccentricity2 - 2.0 * eccentricity * cos_theta, 1.0e-4);
    // d^(-3/2) as one inversesqrt of the cube: the guard keeps the cube in
    // range, and the SFU call replaces the sqrt-plus-divide pair. inversesqrt
    // precision is implementation-defined (~1e-6 relative), far inside the
    // scattering budget.
    float denominator3 = denominator * denominator * denominator;
    return PHASE_ISOTROPIC * (1.0 - eccentricity2) * inversesqrt(denominator3);
}

// Equal-weight forward and mirrored backward HG lobes. The sphere integral
// is one; volumetric-cloud octave contributions apply their own weights.
// backward_g is a positive magnitude, evaluated as -backward_g.
float PhaseHenyeyGreensteinDualLobe(float cos_theta, float forward_g, float backward_g) {
    return PhaseHenyeyGreenstein(cos_theta, forward_g) * 0.5 + PhaseHenyeyGreenstein(cos_theta, -backward_g) * 0.5;
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

// Normalized unpolarized Klein-Nishina shape (Klein & Nishina 1929), the
// Compton differential cross-section expressed through
// q = 1 / (1 + epsilon * (1 - cos_theta)):
// F = q^2 * (q + 1/q - (1 - cos_theta^2)).
// epsilon is an artistic forward-spike shape parameter, not a Compton energy
// fit. normalization is the caller's 1 / sphere integral of F, evaluated in
// double precision offline for the chosen epsilon; F itself is shaped so the
// forward value stays representable in fp32 down to the backward horizon.
float PhaseKleinNishina(float cos_theta, float epsilon, float normalization) {
    float t = 1.0 + epsilon * (1.0 - cos_theta);
    // q + 1/q with q = 1 / t collapses to t + 1/t, keeping a single divide.
    float shape = (t + 1.0 / t - (1.0 - cos_theta * cos_theta)) / (t * t);
    return normalization * shape;
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
