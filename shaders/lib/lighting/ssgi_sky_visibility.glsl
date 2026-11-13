#ifndef LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL
#define LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL

#include "/lib/contract/settings.glsl"
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
// SSGI_SKY_MOMENT_DEBUG 1 replaces the shared curves with independent per-mode
// fits as an A/B reference.
// Full visibility uses the conditional slice mean, not a hemisphere mean.
// The returned moment is not a unit vector and must not be normalized.
// D_view = view_dir*result.x + ray_direction*result.y.
vec2 SSGISkySliceMoment(uint occupied, float m, float angle_normal) {
    uint missing = ~occupied;
    if (missing == 0u) return vec2(0.0);
    float h = 1.5707963267948966 - angle_normal;
    float h2 = h * h;
    float x = h2 * 0.20264236728467555 - 1.0;
#if SSGI_SKY_MOMENT_DEBUG == 1
    // Independent fits: one degree-3 polynomial per even mode and one
    // degree-4 polynomial per odd mode, each weighted by its own q_i.
    float a = m * (1.0 + h2 * (((0.00029860737030241058 * x
        + (0.00092418337571893553)) * x + (0.0045278051508929771)) * x
        + (-0.021105192775338691)));
    float b = 0.0;
    if (occupied != 0u) {
        {
            float q = float(bitCount(missing & 0x0F0F0F0Fu)) * (1.0 / 16.0) - m;
            b += q * h * ((((0.00013259441377800522 * x
                + (0.00026181269758173217)) * x + (-0.000286334949233293)) * x
                + (0.008332865359183525)) * x + (-0.045727671499450881));
        }
        {
            float q = float(bitCount(missing & 0x00FF00FFu)) * (1.0 / 16.0) - m;
            b += q * h * ((((0.00022727548256930749 * x
                + (0.00058356698189654084)) * x + (9.6121830402205139e-05)) * x
                + (0.014786775771094357)) * x + (-0.087444141181568069));
        }
        {
            float q = float(bitCount(missing & 0xF00FF00Fu)) * (1.0 / 16.0) - m;
            a += q * h2 * (((0.00020169026693017501 * x
                + (0.00034343720154822276)) * x + (0.0010322981835843967)) * x
                + (-0.0070512761000404616));
        }
        {
            float q = float(bitCount(missing & 0x0000FFFFu)) * (1.0 / 16.0) - m;
            b += q * h * ((((0.00031034055464604344 * x
                + (0.001023382830666578)) * x + (0.0019821844636409322)) * x
                + (0.025166524405302024)) * x + (-0.16359872301187312));
        }
        {
            float q = float(bitCount(missing & 0xF0F00F0Fu)) * (1.0 / 16.0) - m;
            a += q * h2 * (((0.00021558895793419189 * x
                + (0.00046058762571679184)) * x + (0.0018113356322097176)) * x
                + (-0.010062109383315721));
        }
        {
            float q = float(bitCount(missing & 0xFF0000FFu)) * (1.0 / 16.0) - m;
            a += q * h2 * (((0.00028170275001789354 * x
                + (0.00077191460434905817)) * x + (0.0034964547579222666)) * x
                + (-0.017144002448219151));
        }
        {
            float q = float(bitCount(missing & 0x0FF0F00Fu)) * (1.0 / 16.0) - m;
            b += q * h * ((((8.5513429762442043e-05 * x
                + (2.7198091324035014e-05)) * x + (-0.0011663357781413958)) * x
                + (0.0030027828176576034)) * x + (-0.0072232615536940948));
        }
    }
#else
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
#endif
    float c = cos(0.5 * h);
    float s = sin(0.5 * h);
    return vec2(c * a - s * b, s * a + c * b);
}

// moment_world uses the normalized cosine measure and must not be normalized.
// l2_band is EvalSkyLightL2(fallback_normal), hoisted ahead of the march; the
// band depends only on the receiver normal and its SSBO reads are
// placement-sensitive in the epilogue (same rule as sky_l2_blocked in gtao).
// The ignored L2/visibility correlation is a model approximation.
// The caller clamps the composed RGB once to >= 0 (per-band clamping would
// break the signed L2 lobes) and adds no open-sky upper bound; the single
// random slice's positive swings average out over frames.
// No second AO multiplication; the ambient floor joins after, scaled by m.
vec3 EvalSSGISkyFromMoment(float m, vec3 moment_world, vec3 l2_band) {
    vec4 basis = vec4(SH_Y0 * m, SH_Y1 * moment_world.yzx);
    vec3 visible_l01 = PI * vec3(dot(sky_sh_r0, basis), dot(sky_sh_g0, basis),
        dot(sky_sh_b0, basis));
    return visible_l01 + m * l2_band;
}

#endif // LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL
