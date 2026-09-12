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
float VisibilitySmithGGXCorrelated(float ndotv, float ndotl, float alpha) {
    float alpha2 = alpha * alpha;
    float lambda_v = ndotl * sqrt(ndotv * ndotv * (1.0 - alpha2) + alpha2);
    float lambda_l = ndotv * sqrt(ndotl * ndotl * (1.0 - alpha2) + alpha2);
    return 0.5 / max(lambda_v + lambda_l, 1e-5);
}

float DiffuseBurley(float ndotv, float ndotl, float ldoth, float roughness) {
    float fd90 = 0.5 + 2.0 * roughness * ldoth * ldoth;
    float light_scatter = 1.0 + (fd90 - 1.0) * Pow5(1.0 - ndotl);
    float view_scatter = 1.0 + (fd90 - 1.0) * Pow5(1.0 - ndotv);
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
    vec3 fresnel = FresnelSchlick(vdoth, f0);
    vec3 diffuse = albedo * (vec3(1.0) - fresnel) * diffuse_weight
        * DiffuseBurley(ndotv, ndotl, ldoth, roughness);
    return diffuse + fresnel * DistributionGGX(ndoth, alpha)
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

float VisibleGGXVisibility(float ndotv, float ndotl, float alpha) {
    if (ndotv <= 0.0 || ndotl <= 0.0) {
        return 0.0;
    }
    return clamp(SmithGGXG2Correlated(ndotv, ndotl, alpha)
        / max(SmithGGXG1(ndotv, alpha), 1e-5), 0.0, 1.0);
}

vec3 VisibleGGXThroughput(vec3 f0, float vdoth, float ndotv,
        float ndotl, float alpha) {
    return FresnelSchlick(vdoth, f0)
        * VisibleGGXVisibility(ndotv, ndotl, alpha);
}

// ---------------------------------------------------------------------------
// GGX spherical area light approximation (Guerrilla's Decima Engine, SIGGRAPH
// 2017 "Advances in Lighting and AA" - Johan Andersson [DEC17]):
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
    float rdotl = 2.0 * ndotl * ndotv - ldotv;
    if (rdotl >= cos_radius) return 1.0;

    float scaled = cos_radius * tan_radius * inversesqrt(1.0 - rdotl * rdotl);
    float ndott = scaled * (ndotv - rdotl * ndotl);
    float vdott = scaled * (2.0 * ndotv * ndotv - 1.0 - rdotl * ldotv);

    // Triple product dot(cross(N, L), V).
    float triple = sqrt(max(1.0 - ndotl * ndotl - ndotv * ndotv - ldotv * ldotv + 2.0 * ndotl * ndotv * ldotv, 0.0));
    float ndotb = scaled * triple;
    float vdotb = scaled * (2.0 * triple * ndotv);

    // One Newton iteration to improve the bent light direction.
    float nl_rot = ndotl * cos_radius + ndotv + ndott;
    float lv_rot = ldotv * cos_radius + 1.0 + vdott;
    float p = ndotb * lv_rot;
    float q = nl_rot * lv_rot;
    float s = vdotb * nl_rot;
    float x_num = q * (-0.5 * p + 0.25 * vdotb * nl_rot);
    float x_den = p * p + s * (s - 2.0 * p) + nl_rot * ((ndotl * cos_radius + ndotv) * lv_rot * lv_rot
            + q * (-0.5 * (lv_rot + ldotv * cos_radius) - 0.5));
    // two_x is twice the Newton step; (sin_theta, cos_theta) rotate the
    // bent direction by that step's angle.
    float two_x = 2.0 * x_num / (x_den * x_den + x_num * x_num);
    float sin_theta = two_x * x_den;
    float cos_theta = 1.0 - two_x * x_num;
    ndott = cos_theta * ndott + sin_theta * ndotb;
    vdott = cos_theta * vdott + sin_theta * vdotb;

    // (N.H)^2 from the bent light direction.
    float new_ndotl = ndotl * cos_radius + ndott;
    float new_ldotv = ldotv * cos_radius + vdott;
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
void EvaluateBRDF(vec3 albedo, vec2 texcoord, vec3 normal_view, vec3 view_direction, vec3 light_direction, out vec3 direct_lighting,
    out vec3 lambert_brdf, out vec3 diffuse_reflectance
) {
    vec4 spec_tex = vec4(0.0);
    if (any(notEqual(textureSize(specular, 0), ivec2(1)))) spec_tex = texture(specular, texcoord);
    Material mat = MaterialDefaults(spec_tex);

    vec3 half_direction = normalize(view_direction + light_direction);
    float ndotv = Max0(dot(normal_view, view_direction));
    float ndotl = Max0(dot(normal_view, light_direction));
    float ndoth = Max0(dot(normal_view, half_direction));
    float vdoth = Max0(dot(view_direction, half_direction));
    float ldoth = Max0(dot(light_direction, half_direction));

    direct_lighting = EvaluateDirectBRDF(albedo, mat.roughness, mat.metalness, ndotv, ndotl, ndoth, vdoth, ldoth) * ndotl;
    lambert_brdf = EvaluateLambertBRDF(albedo, mat.metalness);
    diffuse_reflectance = EvaluateDiffuseReflectance(albedo, mat.metalness);
}

#endif
