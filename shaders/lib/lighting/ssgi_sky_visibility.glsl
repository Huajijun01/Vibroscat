#ifndef LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL
#define LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL

#include "/lib/contract/sky_light_data.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/sky_light.glsl"

// The trace's 32 equal-mass CDF sectors form eight four-bit direction groups.
// On its visible arc, psi in [0, h], h = PI/2 - angle_normal, the density is
// proportional to sin(psi)*sin(h-psi). The group conditional means use the
// midpoint frame e0 = v*cos(h/2)+t*sin(h/2), e1 = -v*sin(h/2)+t*cos(h/2).
// Walsh statistics q_i = bitCount(missing & mask_i)/16 - m are exact for
// these group masses. Only the L1 reconstruction is approximated below:
// three even modes share h^2*P1(x), four odd modes share h*Q2(x), where
// x = 2*h^2/PI^2-1. Their weighted counts are collapsed before evaluation.
// The constant mode keeps its original cubic; L0 mass m is unchanged.
// Full visibility uses the conditional slice mean, not a hemisphere mean.
// The returned moment is not a unit vector and must not be normalized.
// D_view = view_dir*result.x + ray_direction*result.y.
vec2 SSGISkySliceMoment(uint occupied, float m, float angle_normal) {
    uint missing = ~occupied;
    if (missing == 0u) return vec2(0.0);
    float h = 1.5707963267948966 - angle_normal;
    float h2 = h * h;
    float x = h2 * 0.20264236728467555 - 1.0;
    float cosine_weight = m * (((0.00029860737030241058 * x
        + 0.00092418337571893553) * x + 0.0045278051508929771) * x
        - 0.021105192775338691);
    float sine_weight = 0.0;
    if (occupied != 0u) {
        {
            float even_stat = float(bitCount(missing & 0xF00FF00Fu)) * 0.026220046
                + float(bitCount(missing & 0xF0F00F0Fu)) * 0.0369987749
                + float(bitCount(missing & 0xFF0000FFu)) * 0.0625
                - m * 2.01150107;
            cosine_weight += even_stat * (0.00391483493 * x - 0.0169771966);
        }
        {
            float odd_stat = float(bitCount(missing & 0x0F0F0F0Fu)) * 0.0174889546
                + float(bitCount(missing & 0x00FF00FFu)) * 0.033435069
                + float(bitCount(missing & 0x0000FFFFu)) * 0.0625
                + float(bitCount(missing & 0x0FF0F00Fu)) * 0.00279046991
                - m * 1.85943198;
            sine_weight = odd_stat * ((0.00192118355 * x + 0.0265562404) * x - 0.16364044);
        }
    }
    float a = m + h2 * cosine_weight;
    float b = h * sine_weight;
    float c = cos(0.5 * h);
    float s = sin(0.5 * h);
    return vec2(c * a - s * b, s * a + c * b);
}

// Visible sky irradiance from the raw radiance SH, the visible mass m, and
// the directional moment. m and moment_world use the normalized cosine
// measure; moment_world must not be normalized. l2_band is the receiver's
// EvalSkyLightL2(fallback_normal), hoisted by the caller ahead of its march:
// the band depends only on the receiver normal, and evaluating it after the
// march left its SSBO reads exposed in the epilogue (backend placement
// cliff; same rule as the sky_l2_blocked hoist in gtao.glsl). The L0/L1
// bands take the moment directly as
// PI*[Y0*L0*m + Y1*(L1 . D)]; EvalSkyLightL2 already carries the SH_A2
// convolution and keeps its sign, so the L2 share is simply scaled by m and
// the ignored L2/visibility correlation stays a model approximation of the
// hybrid, not a numeric failure. The caller clamps the composed RGB once to
// >= 0 - clamping a band separately would break the signed L2 lobes - and
// adds no open-sky upper bound: the single random slice's positive swings
// are part of the estimator and average out over frames, so truncating them
// per frame would bias the result down. No second AO/multiplication on the
// returned value; the ambient floor joins after, scaled by m.
vec3 EvalSSGISkyFromMoment(float m, vec3 moment_world, vec3 l2_band) {
    vec4 basis = vec4(SH_Y0 * m, SH_Y1 * moment_world.yzx);
    vec3 visible_l01 = PI * vec3(dot(sky_sh_r0, basis), dot(sky_sh_g0, basis),
        dot(sky_sh_b0, basis));
    return visible_l01 + m * l2_band;
}

#endif // LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL
