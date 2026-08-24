#ifndef LIB_LIGHTING_BRDF_GLSL
#define LIB_LIGHTING_BRDF_GLSL

#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/material/core.glsl"

vec3 FresnelSchlick(float vdoth, vec3 f0) {
    return f0 + (vec3(1.0) - f0) * Pow5(1.0 - vdoth);
}

// Isotropic Trowbridge-Reitz GGX. Alpha is the squared perceptual roughness.
float DistributionGGX(float ndot_h, float alpha) {
    float alpha2 = alpha * alpha;
    float denominator = max(ndot_h * ndot_h * (alpha2 - 1.0) + 1.0, alpha2);
    return alpha2 / (PI * denominator * denominator);
}

// Height-correlated Smith visibility, including the 1 / (4 NdotL NdotV) term.
float VisibilitySmithGGXCorrelated(float ndot_v, float ndot_l, float alpha) {
    float alpha2 = alpha * alpha;
    float lambda_v = ndot_l * sqrt(ndot_v * ndot_v * (1.0 - alpha2) + alpha2);
    float lambda_l = ndot_v * sqrt(ndot_l * ndot_l * (1.0 - alpha2) + alpha2);
    return 0.5 / max(lambda_v + lambda_l, 1e-5);
}

float DiffuseBurley(float ndot_v, float ndot_l, float ldot_h, float roughness) {
    float fd90 = 0.5 + 2.0 * roughness * ldot_h * ldot_h;
    float light_scatter = 1.0 + (fd90 - 1.0) * Pow5(1.0 - ndot_l);
    float view_scatter = 1.0 + (fd90 - 1.0) * Pow5(1.0 - ndot_v);
    return light_scatter * view_scatter * (1.0 / PI);
}

vec3 BRDFF0(vec3 albedo, float metalness) {
    return mix(vec3(0.04), albedo, metalness);
}

vec3 EvaluateDiffuseReflectance(vec3 albedo, vec3 f0, float diffuse_weight) {
    return albedo * (vec3(1.0) - f0) * diffuse_weight;
}

vec3 EvaluateDiffuseReflectance(vec3 albedo, float metalness) {
    vec3 f0 = BRDFF0(albedo, metalness);
    return EvaluateDiffuseReflectance(albedo, f0, 1.0 - metalness);
}

vec3 EvaluateLambertBRDF(vec3 albedo, vec3 f0, float diffuse_weight) {
    return EvaluateDiffuseReflectance(albedo, f0, diffuse_weight)
        * (1.0 / PI);
}

vec3 EvaluateLambertBRDF(vec3 albedo, float metalness) {
    return EvaluateDiffuseReflectance(albedo, metalness) * (1.0 / PI);
}

vec3 EvaluateDirectBRDF(vec3 albedo, vec3 f0, float diffuse_weight,
        float roughness, float ndotv, float ndotl, float ndoth,
        float vdoth, float ldoth) {
    float alpha = max(roughness * roughness, 0.002);
    vec3 F = FresnelSchlick(vdoth, f0);
    vec3 diffuse = albedo * (vec3(1.0) - F) * diffuse_weight
        * DiffuseBurley(ndotv, ndotl, ldoth, roughness);
    return diffuse + F * DistributionGGX(ndoth, alpha)
        * VisibilitySmithGGXCorrelated(ndotv, ndotl, alpha)
        * step(1e-5, ndotv);
}

vec3 EvaluateDirectBRDF(vec3 albedo, float roughness, float metalness,
        float ndotv, float ndotl, float ndoth, float vdoth, float ldoth) {
    return EvaluateDirectBRDF(
        albedo, BRDFF0(albedo, metalness), 1.0 - metalness,
        roughness, ndotv, ndotl, ndoth, vdoth, ldoth);
}

float SmithGGXLambda(float ndotx, float alpha) {
    float a2 = alpha * alpha;
    return 0.5 * (-1.0 + sqrt(1.0 + a2
        * (1.0 - ndotx * ndotx) / max(ndotx * ndotx, 1e-6)));
}

float SmithGGXG1(float ndotv, float alpha) {
    return 1.0 / (1.0 + SmithGGXLambda(ndotv, alpha));
}

float SmithGGXG2Correlated(float ndotv, float ndotl, float alpha) {
    return 1.0 / (1.0 + SmithGGXLambda(ndotv, alpha)
        + SmithGGXLambda(ndotl, alpha));
}

float SpecularOcclusion(float ndotv, float ao, float roughness) {
    float exponent = exp2(-16.0 * roughness - 1.0);
    return clamp(pow(ndotv + ao, exponent) - 1.0 + ao, 0.0, 1.0);
}

vec3 VisibleGGXThroughput(vec3 f0, float vdoth, float ndotv,
        float ndotl, float alpha) {
    if (ndotv <= 0.0 || ndotl <= 0.0 || vdoth <= 0.0) {
        return vec3(0.0);
    }
    float ratio = clamp(SmithGGXG2Correlated(ndotv, ndotl, alpha)
        / max(SmithGGXG1(ndotv, alpha), 1e-5), 0.0, 1.0);
    return FresnelSchlick(vdoth, f0) * ratio;
}

// ---------------------------------------------------------------------------
// GGX spherical area light approximation (Guerrilla's Decima Engine, SIGGRAPH
// 2017 "Advances in Lighting and AA" — Johan Andersson [DEC17]):
//   https://www.realtimerendering.com/advances/s2017/DecimaSiggraph2017.pdf
// Bent-light Newton iteration from the presentation; implements its getNoH().
// ---------------------------------------------------------------------------

// Invert the dielectric Fresnel equation at normal incidence to recover the
// effective IOR from f0 (Blender EEVEE approach, GPL-2.0-or-later).
float F0ToIOR(float f0) {
    float sqrt_f0 = sqrt(f0) * 0.99999;
    return (1.0 + sqrt_f0) / (1.0 - sqrt_f0);
}

// Exact unpolarized dielectric Fresnel (standard optics). Returns 1.0 when g
// is imaginary (total internal reflection).
vec3 FresnelDielectric(float cos_theta, float f0) {
    float n = F0ToIOR(f0);
    float g_sq = n * n + cos_theta * cos_theta - 1.0;

    if (g_sq < 0.0) return vec3(1.0);

    float g = sqrt(g_sq);
    float a = g - cos_theta;
    float b = g + cos_theta;
    float a_over_b = a / b;
    float b_cos_minus1 = b * cos_theta - 1.0;
    float a_cos_plus1 = a * cos_theta + 1.0;

    return vec3(0.5 * a_over_b * a_over_b * (1.0 + b_cos_minus1 * b_cos_minus1 / (a_cos_plus1 * a_cos_plus1)));
}

// Decima [DEC17] getNoH(): returns (N.H)^2 for the bent light direction
// over the source disc of angular radius light_radius (radians).
float GetNdotHSquared(float ndotl, float ndotv, float ldotv, float light_radius) {
    float cos_radius = cos(light_radius);
    float tan_radius = tan(light_radius);

    // Early out when the reflection ray already falls within the disc.
    float r_dot_l = 2.0 * ndotl * ndotv - ldotv;
    if (r_dot_l >= cos_radius) return 1.0;

    float scaled = cos_radius * tan_radius * inversesqrt(1.0 - r_dot_l * r_dot_l);
    float n_dot_t = scaled * (ndotv - r_dot_l * ndotl);
    float v_dot_t = scaled * (2.0 * ndotv * ndotv - 1.0 - r_dot_l * ldotv);

    // Triple product dot(cross(N, L), V).
    float triple = sqrt(max(1.0 - ndotl * ndotl - ndotv * ndotv - ldotv * ldotv + 2.0 * ndotl * ndotv * ldotv, 0.0));
    float n_dot_b = scaled * triple;
    float v_dot_b = scaled * (2.0 * triple * ndotv);

    // One Newton iteration to improve the bent light direction.
    float nl_rot = ndotl * cos_radius + ndotv + n_dot_t;
    float lv_rot = ldotv * cos_radius + 1.0 + v_dot_t;
    float p = n_dot_b * lv_rot;
    float q = nl_rot * lv_rot;
    float s = v_dot_b * nl_rot;
    float x_num = q * (-0.5 * p + 0.25 * v_dot_b * nl_rot);
    float x_den = p * p + s * (s - 2.0 * p) + nl_rot * ((ndotl * cos_radius + ndotv) * lv_rot * lv_rot
            + q * (-0.5 * (lv_rot + ldotv * cos_radius) - 0.5));
    float two_x = 2.0 * x_num / (x_den * x_den + x_num * x_num);
    float sin_theta = two_x * x_den;
    float cos_theta = 1.0 - two_x * x_num;
    n_dot_t = cos_theta * n_dot_t + sin_theta * n_dot_b;
    v_dot_t = cos_theta * v_dot_t + sin_theta * v_dot_b;

    // (N.H)^2 from the bent light direction.
    float new_ndotl = ndotl * cos_radius + n_dot_t;
    float new_ldotv = ldotv * cos_radius + v_dot_t;
    float ndoth = ndotv + new_ndotl;
    float hdoth = 2.0 * new_ldotv + 2.0;

    return clamp(ndoth * ndoth / hdoth, 0.0, 1.0);
}

// Same distribution as DistributionGGX, but takes (N.H)^2 directly so the
// area-light path avoids a sqrt() round trip.
float DistributionGGXNdotH2(float ndoth2, float alpha) {
    float alpha2 = alpha * alpha;
    float denominator = max(ndoth2 * (alpha2 - 1.0) + 1.0, alpha2);
    return alpha2 / (PI * denominator * denominator);
}

// Forward translucent lighting retains the legacy scalar-metalness material
// path. Its overloads delegate to the same F0-explicit BRDF implementation;
// N, V and L must use the same space (view space in the gbuffer passes).
void EvaluateBRDF(vec3 albedo, vec2 texcoord, vec3 N, vec3 V, vec3 L, out vec3 direct_lighting,
    out vec3 lambert_brdf, out vec3 diffuse_reflectance
) {
    vec4 spec_tex = vec4(0.0);
    if (any(notEqual(textureSize(specular, 0), ivec2(1)))) spec_tex = texture(specular, texcoord);
    Material mat = MaterialDefaults(0, spec_tex);

    vec3 H = normalize(V + L);
    float ndotv = Max0(dot(N, V));
    float ndotl = Max0(dot(N, L));
    float ndoth = Max0(dot(N, H));
    float vdoth = Max0(dot(V, H));
    float ldoth = Max0(dot(L, H));

    direct_lighting = EvaluateDirectBRDF(albedo, mat.roughness, mat.metalness, ndotv, ndotl, ndoth, vdoth, ldoth) * ndotl;
    lambert_brdf = EvaluateLambertBRDF(albedo, mat.metalness);
    diffuse_reflectance = EvaluateDiffuseReflectance(albedo, mat.metalness);
}

#endif
