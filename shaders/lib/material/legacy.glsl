#ifndef LIB_MATERIAL_LEGACY_GLSL
#define LIB_MATERIAL_LEGACY_GLSL

// Legacy scalar-metalness material path. The forward gbuffer passes fetch a
// block's spec texel in their own main and decode it here; EvaluateBRDF in
// lib/lighting/brdf.glsl consumes the decoded Material. Opaque geometry uses
// the PBR resolve in lib/material/model.glsl, which also documents the spec
// map channels and the materialID ranges.
struct Material {
    float roughness;
    float metalness;
    float emission;
    float reserved;
};

Material MaterialDefaults(vec4 spec) {
    Material m;
    // smoothness inverted to roughness
    m.roughness  = 1.0 - spec.r;
    m.metalness  = spec.g;
    m.emission   = spec.b;
    m.reserved    = spec.a;

    return m;
}

#endif // LIB_MATERIAL_LEGACY_GLSL
