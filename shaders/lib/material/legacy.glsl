#ifndef LIB_MATERIAL_LEGACY_GLSL
#define LIB_MATERIAL_LEGACY_GLSL

// Legacy scalar-metalness path; opaque geometry uses the PBR resolve in lib/material/model.glsl.
struct Material {
    float roughness;
    float metalness;
    float emission;
    float reserved;
};

Material MaterialDefaults(vec4 spec) {
    Material m;
    m.roughness  = 1.0 - spec.r;
    m.metalness  = spec.g;
    m.emission   = spec.b;
    m.reserved    = spec.a;

    return m;
}

#endif // LIB_MATERIAL_LEGACY_GLSL
