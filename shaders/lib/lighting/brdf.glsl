#ifndef LIB_LIGHTING_BRDF_GLSL
#define LIB_LIGHTING_BRDF_GLSL

#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/material/legacy.glsl"

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

vec3 EvaluateDirectSpecularBRDF(vec3 f0, float roughness,
        float ndotv, float ndotl, float ndoth, float vdoth) {
    float alpha = max(roughness * roughness, 0.002);
    return FresnelSchlick(vdoth, f0) * DistributionGGX(ndoth, alpha)
        * VisibilitySmithGGXCorrelated(ndotv, ndotl, alpha)
        * step(1e-5, ndotv);
}

vec3 EvaluateDirectBRDF(vec3 albedo, vec3 f0, float diffuse_weight,
        float roughness, float ndotv, float ndotl, float ndoth,
        float vdoth, float ldoth, out vec3 diffuse_brdf) {
    vec3 fresnel = FresnelSchlick(vdoth, f0);
    vec3 diffuse = albedo * (vec3(1.0) - fresnel) * diffuse_weight
        * DiffuseBurley(ndotv, ndotl, ldoth, roughness);
    diffuse_brdf = diffuse;
    return diffuse + EvaluateDirectSpecularBRDF(f0, roughness,
        ndotv, ndotl, ndoth, vdoth);
}

vec3 EvaluateDirectBRDF(vec3 albedo, float roughness, float metalness,
        float ndotv, float ndotl, float ndoth, float vdoth, float ldoth) {
    vec3 unused_diffuse_brdf;
    return EvaluateDirectBRDF(
        albedo, BRDFF0(albedo, metalness), 1.0 - metalness,
        roughness, ndotv, ndotl, ndoth, vdoth, ldoth, unused_diffuse_brdf);
}

float SmithGGXLambda(float ndotx, float alpha) {
    float a2 = alpha * alpha;
    return 0.5 * (-1.0 + sqrt(1.0 + a2
        * (1.0 - ndotx * ndotx) / max(ndotx * ndotx, 1e-6)));
}

// Specular occlusion curve (Jimenez et al. 2016).
float SpecularOcclusion(float ndotv, float ao, float roughness) {
    float exponent = exp2(-16.0 * roughness - 1.0);
    return saturate(pow(ndotv + ao, exponent) - 1.0 + ao);
}

float VisibleGGXVisibility(float ndotv, float ndotl, float alpha) {
    if (ndotv <= 0.0 || ndotl <= 0.0) {
        return 0.0;
    }
    // G2/G1 cancels into (1 + lambda_v) / (1 + lambda_v + lambda_l);
    // one quotient instead of the three the factored forms carry.
    float lambda_v = SmithGGXLambda(ndotv, alpha);
    float lambda_l = SmithGGXLambda(ndotl, alpha);
    return saturate((1.0 + lambda_v) / (1.0 + lambda_v + lambda_l));
}

vec3 VisibleGGXThroughput(vec3 f0, float vdoth, float ndotv,
        float ndotl, float alpha) {
    return FresnelSchlick(vdoth, f0)
        * VisibleGGXVisibility(ndotv, ndotl, alpha);
}

// Small-disc approximation: shrink sin(angle(N,H)) by the fraction of the
// reflection-to-light chord outside the light disc. Radius is in radians;
// the sun/moon use r <= 0.005.
float GetNdotHSquared(float ndotl, float ndotv, float ldotv, float light_radius) {
    float ndoth = ndotl + ndotv;
    // Opposing light/view directions make H undefined at the grazing horizon.
    float ndoth2 = saturate(ndoth * ndoth / max(2.0 + 2.0 * ldotv, 1e-6));
    float rdotl = 2.0 * ndotl * ndotv - ldotv;
    float edge = 1.0 - light_radius * inversesqrt(max(2.0 - 2.0 * rdotl, light_radius * light_radius));
    return 1.0 - (1.0 - ndoth2) * edge * edge;
}

// Same distribution as DistributionGGX, but takes (N.H)^2 directly so the
// area-light path avoids a sqrt() round trip.
float DistributionGGXNdotH2(float ndoth2, float alpha) {
    float alpha2 = alpha * alpha;
    float denominator = max(ndoth2 * (alpha2 - 1.0) + 1.0, alpha2);
    return alpha2 / (PI * denominator * denominator);
}

// Forward-pass lighting over the legacy scalar-metalness material. The caller
// owns the material read: it fetches the spec texel (or passes the zero
// default where no PBR data exists) and decodes it with MaterialDefaults
// before calling, so this stays pure BRDF math. N, V and L must arrive unit
// and use the same space (view space in the gbuffer passes).
void EvaluateBRDF(vec3 albedo, Material mat, vec3 normal_view, vec3 view_dir, vec3 light_dir, out vec3 direct_lighting,
    out vec3 lambert_brdf, out vec3 diffuse_reflectance
) {
    vec3 half_dir = normalize(view_dir + light_dir);
    // N, V and L reach here unit and H is their normalized sum, so each cosine
    // is at most 1: the [0,1] clamp is exact, and saturate() folds into the
    // producing dot as .SAT where max(x, 0.0) costs a separate instruction.
    float ndotv = saturate(dot(normal_view, view_dir));
    float ndotl = saturate(dot(normal_view, light_dir));
    float ndoth = saturate(dot(normal_view, half_dir));
    float vdoth = saturate(dot(view_dir, half_dir));
    // V and L are unit and H is their normalized sum, so V.H and L.H both
    // equal (1 + V.L)/|V + L|: the ldoth argument reuses vdoth.
    direct_lighting = EvaluateDirectBRDF(albedo, mat.roughness, mat.metalness, ndotv, ndotl, ndoth, vdoth, vdoth) * ndotl;
    lambert_brdf = EvaluateLambertBRDF(albedo, mat.metalness);
    diffuse_reflectance = EvaluateDiffuseReflectance(albedo, mat.metalness);
}

#endif // LIB_LIGHTING_BRDF_GLSL
