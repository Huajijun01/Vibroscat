#ifndef LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL
#define LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL

#include "/lib/contract/sky_light_data.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/sky_light.glsl"

// Directional sky visibility for the SSGI fallback (SSGI_DIRECTIONAL_SKY).
//
// Math contract. The trace's occupancy bitmask covers the 32 sectors of the
// cosine-weighted CDF arc the march can see, parametrized by the in-plane
// angle psi from the view axis toward the slice direction. With the
// projected normal at signed angle angle_normal, that arc runs from
// view_dir (psi = 0) to view_dir*cos(h) + ray_direction*sin(h) at psi = h =
// PI/2 - angle_normal, and its cosine density is sin(psi)*sin(h - psi) up
// to scale. The 32 sectors form eight consecutive four-bit groups; each
// group is replaced by its precomputed conditional mean direction
//   mu_j(h) = e0 * C_j(h) + e1 * S_j(h)
// in the arc-midpoint frame
//   e0 = v*cos(h/2) + t*sin(h/2), e1 = -v*sin(h/2) + t*cos(h/2),
// with v = view_dir and t = ray_direction. mu_j is a conditional mean, not
// a unit vector: the visible groups' mass-weighted mu_j sum to the
// directional moment D = integral V(omega)*omega dP of the normalized
// cosine measure dP = (n.omega)+ dOmega / PI. Only within-group directional
// resolution is approximated; the 32-bit geometric coverage stays exact and
// the L0 mass m keeps the trace's exact value, so the approximation touches
// the L1 band alone.
//
// An order-8 Walsh transform turns the eight group masses into the total
// mass plus seven masked bitCount statistics, q_i = bitCount(missing &
// positive_mask_i)/16 - m, so no per-group extraction or 32-term dot is
// needed and the transform itself stays exact. The density's mirror
// symmetry about h/2 leaves even modes (even popcount(i)) with cosine-type
// coefficients delta_i0 + h^2*P_i(x) and odd modes with sine-type h*Q_i(x)
// on x = 2*h^2/PI^2 - 1, precomputed as degree-3/4 polynomials evaluated
// in the Horner order below. Full occlusion returns zero; with every
// sector visible each positive mask still counts 16 bits, every non-constant
// q_i is exactly zero, and the estimate reduces to the same conditional
// slice mean rather than a full-hemisphere ambient.
//
// Returns the moment coefficients in the (view_dir, ray_direction) basis:
// D_view = view_dir * result.x + ray_direction * result.y.
vec2 SSGISkySliceMoment(uint occupied, float m, float angle_normal) {
    uint missing = ~occupied;
    if (missing == 0u) return vec2(0.0);
    float h = 1.5707963267948966 - angle_normal;
    float h2 = h * h;
    float x = h2 * 0.20264236728467555 - 1.0;
    float a = m * (1.0 + h2 * (((0.00029860737030241058 * x + (0.00092418337571893553)) * x + (0.0045278051508929771)) * x + (-0.021105192775338691)));
    float b = 0.0;
    if (occupied != 0u) {
        {
            float q = float(bitCount(missing & 0x0F0F0F0Fu)) * (1.0 / 16.0) - m;
            b += q * h * ((((0.00013259441377800522 * x + (0.00026181269758173217)) * x + (-0.000286334949233293)) * x + (0.008332865359183525)) * x + (-0.045727671499450881));
        }
        {
            float q = float(bitCount(missing & 0x00FF00FFu)) * (1.0 / 16.0) - m;
            b += q * h * ((((0.00022727548256930749 * x + (0.00058356698189654084)) * x + (9.6121830402205139e-05)) * x + (0.014786775771094357)) * x + (-0.087444141181568069));
        }
        {
            float q = float(bitCount(missing & 0xF00FF00Fu)) * (1.0 / 16.0) - m;
            a += q * h2 * (((0.00020169026693017501 * x + (0.00034343720154822276)) * x + (0.0010322981835843967)) * x + (-0.0070512761000404616));
        }
        {
            float q = float(bitCount(missing & 0x0000FFFFu)) * (1.0 / 16.0) - m;
            b += q * h * ((((0.00031034055464604344 * x + (0.001023382830666578)) * x + (0.0019821844636409322)) * x + (0.025166524405302024)) * x + (-0.16359872301187312));
        }
        {
            float q = float(bitCount(missing & 0xF0F00F0Fu)) * (1.0 / 16.0) - m;
            a += q * h2 * (((0.00021558895793419189 * x + (0.00046058762571679184)) * x + (0.0018113356322097176)) * x + (-0.010062109383315721));
        }
        {
            float q = float(bitCount(missing & 0xFF0000FFu)) * (1.0 / 16.0) - m;
            a += q * h2 * (((0.00028170275001789354 * x + (0.00077191460434905817)) * x + (0.0034964547579222666)) * x + (-0.017144002448219151));
        }
        {
            float q = float(bitCount(missing & 0x0FF0F00Fu)) * (1.0 / 16.0) - m;
            b += q * h * ((((8.5513429762442043e-05 * x + (2.7198091324035014e-05)) * x + (-0.0011663357781413958)) * x + (0.0030027828176576034)) * x + (-0.0072232615536940948));
        }
    }
    float c = cos(0.5 * h);
    float s = sin(0.5 * h);
    return vec2(c * a - s * b, s * a + c * b);
}

// Visible sky irradiance from the raw radiance SH, the visible mass m, and
// the directional moment. m and moment_world use the normalized cosine
// measure; moment_world must not be normalized. normal_world is the
// receiver's unit geometric world normal - the L2 band is evaluated there,
// never at the moment. The L0/L1 bands take the moment directly as
// PI*[Y0*L0*m + Y1*(L1 . D)]; EvalSkyLightL2 already carries the SH_A2
// convolution and keeps its sign, so the L2 share is simply scaled by m and
// the ignored L2/visibility correlation stays a model approximation of the
// hybrid, not a numeric failure. The caller clamps the composed RGB once to
// >= 0 - clamping a band separately would break the signed L2 lobes - and
// adds no open-sky upper bound: the single random slice's positive swings
// are part of the estimator and average out over frames, so truncating them
// per frame would bias the result down. No second AO/multiplication on the
// returned value; the ambient floor joins after, scaled by m.
vec3 EvalSSGISkyFromMoment(float m, vec3 moment_world, vec3 normal_world) {
    vec4 basis = vec4(SH_Y0 * m, SH_Y1 * moment_world.yzx);
    vec3 visible_l01 = PI * vec3(dot(sky_sh_r0, basis), dot(sky_sh_g0, basis),
        dot(sky_sh_b0, basis));
    return visible_l01 + m * EvalSkyLightL2(normal_world);
}

#endif // LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL
