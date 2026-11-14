#ifndef LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL
#define LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/sky_light.glsl"

// occupied = the trace's 32 equal-mass CDF sectors as eight 4-bit direction
// groups; result reconstructs D_view = view_dir*x + ray_direction*y. Not unit.
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

// l2_band: hoisted EvalSkyLightL2(fallback_normal); placement-sensitive in the
// epilogue (same rule as sky_l2_blocked in gtao). Caller: clamp the composed
// RGB once to >= 0, no per-band clamp, no upper bound, no extra AO multiply.
vec3 EvalSSGISkyFromMoment(float m, vec3 moment_world, vec3 l2_band) {
    vec4 basis = vec4(SH_Y0 * m, SH_Y1 * moment_world.yzx);
    vec3 visible_l01 = PI * vec3(dot(sky_sh_r0, basis), dot(sky_sh_g0, basis),
        dot(sky_sh_b0, basis));
    return visible_l01 + m * l2_band;
}

#endif // LIB_LIGHTING_SSGI_SKY_VISIBILITY_GLSL
