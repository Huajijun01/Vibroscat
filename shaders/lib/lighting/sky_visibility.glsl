#ifndef LIB_LIGHTING_SKY_VISIBILITY_GLSL
#define LIB_LIGHTING_SKY_VISIBILITY_GLSL

#include "/lib/contract/sky_light_data.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/sky_light.glsl"

// Directional sky visibility for the RSM ambient fallback.
//
// Math contract. The receiver's visible sky irradiance is
//   E_visible(n) = integral V(omega) * L(omega) * max(dot(n, omega), 0) domega
// with V the screen-space horizon visibility and L the raw sky radiance SH
// from SkyLightData. On one GTAO half-slice the directions are
//   omega(theta) = v * cos(theta) + t * sin(theta), theta in [0, pi],
// with v the world toward-camera axis and t the world slice tangent; the
// opposite side of the slice uses -t. With n.v = a and n.t = b the cosine
// weight is a*cos + b*sin and the spherical Jacobian is sin(theta), so the
// arc integrand is a trigonometric polynomial in (cos, sin) whose
// antiderivative is closed-form. The cosine is part of the transport
// integral: the result is irradiance and needs no further SH_A convolution.
//
// The arc evaluates only the L0/L1 bands of the raw SH field. The five L2
// terms are intentionally excluded: three RGB polynomial terms per slice keep
// the fused GTAO loop within its register budget, and the L2 share of the
// blocked energy stays in the fallback as a bounded under-occlusion. The
// unoccluded control variate remains the full EvalSkyLight, so an open
// surface reduces exactly to the existing ambient path.
//
// Both sides of a slice are integrated in one call. The interval algebra
// never evaluates sin or cos of an angle: with R = length(vec2(a, b)),
//   beta = atan(b, a) wrapped to [-pi/2, 3*pi/2),
// the positive-cosine band [beta - pi/2, beta + pi/2] either lies inside
// [0, pi] (exactly when a >= 0), giving sin(beta +/- pi/2) = +/-b/R and
// cos(beta +/- pi/2) = a/R, or wraps past pi (a < 0), where the upper end
// is pi and the lower end is the horizon or beta - pi/2 (compared through
// h <= sin(beta) = b/R because cos decreases on [0, pi]). Only beta itself
// is transcendental: it enters the Jss primitive linearly. Side -t reuses
// the same atan (atan is odd in its first argument), and its six RGB
// coefficient products are sign flips of side +t's, with sin*b unchanged by
// the double negation.
//
// Sky coefficients are world-axis (+Y up). Callers rotate the view basis
// into world space with mat3(gbufferModelViewInverse); directions are
// camera-relative and never take cameraPosition.
//
// Reference for the SH diffuse transport factors: Ramamoorthi & Hanrahan,
// "An Efficient Representation for Irradiance Environment Maps", SIGGRAPH
// 2001 (cited at the constants in atmosphere/sky_light.glsl).

struct SkyArcPolynomial {
    vec3 constant_term;
    vec3 cos_term;
    vec3 sin_term;
};

// Loop-invariant field for one receiver and its slice orbit: the constant
// and cos terms plus the sin terms along the two world-space slice axes, so
// each slice assembles its polynomial from the already-rotated orbit cos/sin
// instead of re-rotating its tangent.
struct SkyLinearField {
    vec3 constant_term;
    vec3 cos_term;
    vec3 sin_term_t;
    vec3 sin_term_b;
};

SkyLinearField BuildSkyLinearField(vec3 view_axis_world, vec3 slice_t_world,
        vec3 slice_b_world) {
    vec3 l0 = vec3(sky_sh_r0.x, sky_sh_g0.x, sky_sh_b0.x);
    vec3 l1y = SH_Y1 * vec3(sky_sh_r0.y, sky_sh_g0.y, sky_sh_b0.y);
    vec3 l1z = SH_Y1 * vec3(sky_sh_r0.z, sky_sh_g0.z, sky_sh_b0.z);
    vec3 l1x = SH_Y1 * vec3(sky_sh_r0.w, sky_sh_g0.w, sky_sh_b0.w);
    SkyLinearField field;
    field.constant_term = SH_Y0 * l0;
    field.cos_term = l1y * view_axis_world.y
        + l1z * view_axis_world.z
        + l1x * view_axis_world.x;
    field.sin_term_t = l1y * slice_t_world.y
        + l1z * slice_t_world.z
        + l1x * slice_t_world.x;
    field.sin_term_b = l1y * slice_b_world.y
        + l1z * slice_b_world.z
        + l1x * slice_b_world.x;
    return field;
}

// F(hi) - F(lo) of the arc antiderivative
//   F = P0*(a*Jcs + b*Jss) + Pc*(a*Jccs + b*Jcss) + Ps*(a*Jcss + b*Jsss),
// written with the precomputed RGB products p0a = P0*a etc. and the
// primitive differences across the interval:
//   Jcs = s^2/2, Jss = theta/2 - s*c/2, Jccs = -c^3/3, Jcss = s^3/3,
//   Jsss = c^3/3 - c.
vec3 SkySideArc(vec3 p0a, vec3 p0b, vec3 pca, vec3 pcb, vec3 psa, vec3 psb,
        float a, float sin_beta, float cos_beta, float beta,
        float horizon_cos) {
    float theta_lo;
    float sin_lo;
    float cos_lo;
    float theta_hi;
    float sin_hi;
    float cos_hi;
    if (a >= 0.0) {
        // The positive-cosine band lies inside [0, pi]; its upper end is
        // beta + pi/2 and its trigonometry is (a/R, -b/R).
        theta_hi = beta + 0.5 * PI;
        sin_hi = cos_beta;
        cos_hi = -sin_beta;
        theta_lo = acos(horizon_cos);
        sin_lo = sqrt(max(1.0 - horizon_cos * horizon_cos, 0.0));
        cos_lo = horizon_cos;
        if (theta_hi <= theta_lo) return vec3(0.0);
    } else {
        // The band wraps past pi: the upper end is pi and the lower end is
        // the horizon or beta - pi/2, whichever is larger.
        theta_hi = PI;
        sin_hi = 0.0;
        cos_hi = -1.0;
        if (horizon_cos <= sin_beta) {
            theta_lo = acos(horizon_cos);
            sin_lo = sqrt(max(1.0 - horizon_cos * horizon_cos, 0.0));
            cos_lo = horizon_cos;
        } else {
            theta_lo = beta - 0.5 * PI;
            sin_lo = -cos_beta;
            cos_lo = sin_beta;
        }
        if (theta_lo >= PI) return vec3(0.0);
    }
    float sin_hi2 = sin_hi * sin_hi;
    float sin_lo2 = sin_lo * sin_lo;
    float cos_hi3 = cos_hi * cos_hi * cos_hi;
    float cos_lo3 = cos_lo * cos_lo * cos_lo;
    float d_jcs = 0.5 * (sin_hi2 - sin_lo2);
    float d_jss = 0.5 * ((theta_hi - theta_lo)
        - (sin_hi * cos_hi - sin_lo * cos_lo));
    float d_jccs = (cos_lo3 - cos_hi3) * (1.0 / 3.0);
    float d_jcss = (sin_hi2 * sin_hi - sin_lo2 * sin_lo) * (1.0 / 3.0);
    float d_jsss = (cos_hi3 - cos_lo3) * (1.0 / 3.0) - (cos_hi - cos_lo);
    return p0a * d_jcs + pca * d_jccs + psa * d_jcss
        + p0b * d_jss + pcb * d_jcss + psb * d_jsss;
}

// Integral of the L0/L1 sky field over both blocked arcs of one GTAO slice,
// intersected with the positive-cosine band. horizon_cos carries the two
// SearchHorizons cosines (-1 fully open). Arcs stay linear here - raw SH
// negative lobes must cancel across slices - so no per-arc clamp exists;
// callers clamp to [0, open_sky] once per receiver and scale the slice sum
// by PI / GTAO_SLICES to turn it into irradiance.
vec3 IntegrateSkyBlockedArcPair(SkyArcPolynomial sky_arc, float ndotv,
        float ndott, vec2 horizon_cos) {
    if (horizon_cos.x <= -1.0 && horizon_cos.y <= -1.0) {
        return vec3(0.0);
    }
    float projected_length2 = ndotv * ndotv + ndott * ndott;
    if (projected_length2 < 1.0e-8) {
        return vec3(0.0);  // normal perpendicular to the slice plane
    }
    float inv_r = inversesqrt(projected_length2);
    float beta_raw = atan(ndott, ndotv);
    // Wrapped angles in [-pi/2, 3*pi/2): one atan serves both sides.
    float beta = beta_raw < -0.5 * PI ? beta_raw + TAU : beta_raw;
    float beta_neg = -beta_raw;
    if (beta_neg < -0.5 * PI) beta_neg += TAU;
    float sin_beta = ndott * inv_r;
    float cos_beta = ndotv * inv_r;
    vec3 p0a = sky_arc.constant_term * ndotv;
    vec3 p0b = sky_arc.constant_term * ndott;
    vec3 pca = sky_arc.cos_term * ndotv;
    vec3 pcb = sky_arc.cos_term * ndott;
    vec3 psa = sky_arc.sin_term * ndotv;
    vec3 psb = sky_arc.sin_term * ndott;
    return SkySideArc(p0a, p0b, pca, pcb, psa, psb,
               ndotv, sin_beta, cos_beta, beta, horizon_cos.x)
         + SkySideArc(p0a, -p0b, pca, -pcb, -psa, psb,
               ndotv, -sin_beta, cos_beta, beta_neg, horizon_cos.y);
}

#endif // LIB_LIGHTING_SKY_VISIBILITY_GLSL
