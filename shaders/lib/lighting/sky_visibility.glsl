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

// Loop-invariant part of the arc polynomial for one receiver: the constant
// term and the coefficient of cos(theta) depend only on the toward-camera
// axis; only the sin(theta) term varies per slice tangent. The L1 vectors
// are pre-scaled by SH_Y1 so a slice assembly costs three multiply-adds.
struct SkyLinearField {
    vec3 constant_term;
    vec3 view_axis_term;
    vec3 l1y;
    vec3 l1z;
    vec3 l1x;
};

SkyLinearField BuildSkyLinearField(vec3 view_axis_world) {
    vec3 l0 = vec3(sky_sh_r0.x, sky_sh_g0.x, sky_sh_b0.x);
    SkyLinearField field;
    field.constant_term = SH_Y0 * l0;
    field.l1y = SH_Y1 * vec3(sky_sh_r0.y, sky_sh_g0.y, sky_sh_b0.y);
    field.l1z = SH_Y1 * vec3(sky_sh_r0.z, sky_sh_g0.z, sky_sh_b0.z);
    field.l1x = SH_Y1 * vec3(sky_sh_r0.w, sky_sh_g0.w, sky_sh_b0.w);
    field.view_axis_term = field.l1y * view_axis_world.y
        + field.l1z * view_axis_world.z
        + field.l1x * view_axis_world.x;
    return field;
}

SkyArcPolynomial BuildSkyArcPolynomial(SkyLinearField sky_field,
        vec3 tangent_world) {
    SkyArcPolynomial arc;
    arc.constant_term = sky_field.constant_term;
    arc.cos_term = sky_field.view_axis_term;
    arc.sin_term = sky_field.l1y * tangent_world.y
        + sky_field.l1z * tangent_world.z
        + sky_field.l1x * tangent_world.x;
    return arc;
}

// Antiderivative F(theta) of the arc integrand
// L(theta) * (a*cos + b*sin) * sin(theta), where L expands to the three
// polynomial terms. The scalar primitives are
//   Jcs = s^2/2, Jss = theta/2 - sin(2*theta)/4, Jccs = -c^3/3,
//   Jcss = s^3/3, Jsss = -c + c^3/3.
vec3 SkyArcPrimitive(SkyArcPolynomial sky_arc, float a, float b, float theta) {
    float s = sin(theta);
    float c = cos(theta);
    float s2 = s * s;
    float c2 = c * c;
    float sin2th = 2.0 * s * c;
    float j_cs = 0.5 * s2;
    float j_ss = 0.5 * theta - 0.25 * sin2th;
    float j_ccs = -c * c2 * (1.0 / 3.0);
    float j_css = s * s2 * (1.0 / 3.0);
    float j_sss = -c + c * c2 * (1.0 / 3.0);
    return sky_arc.constant_term * (a * j_cs + b * j_ss)
        + sky_arc.cos_term * (a * j_ccs + b * j_css)
        + sky_arc.sin_term * (a * j_css + b * j_sss);
}

// Integral of the arc integrand over the blocked arc [acos(horizon_cos), pi]
// intersected with the positive-cosine interval. horizon_cos is the GTAO
// horizon cosine from SearchHorizons (-1 fully open). beta = atan(b, a)
// centers the positive-cosine band; the wrap past -pi/2 keeps the
// intersection with [0, pi] correct for back-facing and grazing normals.
// The result may be negative where the raw SH has negative lobes; it is not
// clamped here so separate arcs stay linear under the slice sum. Callers
// accumulate both sides of each slice and multiply by PI / GTAO_SLICES to
// turn the arc sum into irradiance.
vec3 IntegrateSkyBlockedArc(SkyArcPolynomial sky_arc,
        float ndotv, float ndott, float horizon_cos) {
    float a = ndotv;
    float b = ndott;
    float projected_length2 = a * a + b * b;
    if (projected_length2 < 1.0e-8) {
        return vec3(0.0);  // normal perpendicular to the slice plane
    }
    float beta = atan(b, a);
    if (beta < -0.5 * PI) beta += TAU;
    float theta_lo = max(acos(clamp(horizon_cos, -1.0, 1.0)),
        max(beta - 0.5 * PI, 0.0));
    float theta_hi = min(beta + 0.5 * PI, PI);
    if (theta_hi <= theta_lo) {
        return vec3(0.0);
    }
    return SkyArcPrimitive(sky_arc, a, b, theta_hi)
        - SkyArcPrimitive(sky_arc, a, b, theta_lo);
}

#endif // LIB_LIGHTING_SKY_VISIBILITY_GLSL
