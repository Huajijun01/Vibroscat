#ifndef LIB_SCATTERING_PHASE_GLSL
#define LIB_SCATTERING_PHASE_GLSL

#include "/lib/core/math_scalar.glsl"

// Normalized phase functions: the sphere integral of p dOmega is 1.

const float PHASE_ISOTROPIC = 1.0 / (4.0 * PI);

float PhaseRayleigh(float cos_theta) {
    return (cos_theta * cos_theta + 1.0) * (3.0 / (16.0 * PI));
}

// Henyey-Greenstein 1941; g > 0 forward-peaked, g < 0 backward-peaked.
float PhaseHenyeyGreenstein(float cos_theta, float eccentricity) {
    float eccentricity2 = eccentricity * eccentricity;
    float denominator = max(1.0 + eccentricity2 - 2.0 * eccentricity * cos_theta, 1.0e-4);
    float denominator3 = denominator * denominator * denominator;
    return PHASE_ISOTROPIC * (1.0 - eccentricity2) * inversesqrt(denominator3);
}

// backward_g is a positive magnitude, evaluated at -backward_g; equal weights keep the phase normalized.
float PhaseHenyeyGreensteinDualLobe(float cos_theta, float forward_g, float backward_g) {
    return PhaseHenyeyGreenstein(cos_theta, forward_g) * 0.5 + PhaseHenyeyGreenstein(cos_theta, -backward_g) * 0.5;
}

// Weights sum to 1, so the blend stays a normalized phase; back_g is a magnitude, evaluated at -back_g.
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

// Normalized unpolarized Klein-Nishina shape (Klein & Nishina 1929, the Compton differential
// cross-section). epsilon is an artistic forward-spike parameter, not a Compton energy fit;
// normalization is the caller's 1 / sphere integral of the shape, evaluated offline in
// double precision for the chosen epsilon.
float PhaseKleinNishina(float cos_theta, float epsilon, float normalization) {
    float t = 1.0 + epsilon * (1.0 - cos_theta);
    float shape = (t + 1.0 / t - (1.0 - cos_theta * cos_theta)) / (t * t);
    return normalization * shape;
}

// Cornette-Shanks 1992: normalized single-lobe Mie fit; g = 0 reduces to the Rayleigh phase.
float PhaseCornetteShanks(float cos_theta, float eccentricity) {
    float p = 1.0 + eccentricity * eccentricity - 2.0 * eccentricity * cos_theta;
    return (3.0 / (8.0 * PI)) * ((1.0 - eccentricity * eccentricity) * (1.0 + cos_theta * cos_theta)) / ((2.0 + eccentricity * eccentricity) * p * sqrt(p));
}

// HG divided by its cosine-weighted hemisphere integral (surface normal along the lobe axis);
// valid at g = 0 too, where the surface response is 1/PI. A surface transmission lobe, not a volume phase.
float PhaseHenyeyGreensteinSurfaceNormalized(float cos_theta, float eccentricity) {
    float g = clamp(eccentricity, 0.0, 0.9);
    float g2 = g * g;
    float projected_integral = (1.0 + g) / (2.0 * (1.0 - g + g2
        + (1.0 - g) * sqrt(1.0 + g2)));
    return PhaseHenyeyGreenstein(clamp(cos_theta, -1.0, 1.0), g) / projected_integral;
}

#endif // LIB_SCATTERING_PHASE_GLSL
