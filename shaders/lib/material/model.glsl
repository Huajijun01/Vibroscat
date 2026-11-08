#ifndef LIB_MATERIAL_MODEL_GLSL
#define LIB_MATERIAL_MODEL_GLSL

#include "/lib/core/math_scalar.glsl"

// ============================================================================
// Material model - oldPBR/seusPBR-style specular map convention
// ============================================================================
//
// Specular map channels used by this shader pack:
//   R = smoothness  (0=dull, 1=polished)
//   G = metalness   (stored without thresholding)
//   B = emission    (0=dark, 1=self-illuminated)
//   A = reserved
//
// oldPBR convention above; under MC_TEXTURE_FORMAT_LAB_PBR the atlas is
// LabPBR instead: B = auxiliary, A = emission (see DecodeOpaqueMaterial).
//
// materialID ranges (see block.properties for per-block assignment):
//   80-95   water
//   96-111  metal   (iron, gold, anvil, etc.)
//   112-127 emissive (glowstone, torch, lava, beacon, etc.)
//   128-137 vegetation; 135 is rigid opaque, other classes are thin tissue
//   160-191 translucent (glass, ice, slime, stained glass)

struct OpaqueMaterial {
    float perceptual_roughness;
    float specular_selector;
    float emission;
    float auxiliary;
};

struct PBRMaterial {
    float perceptual_roughness;
    float alpha;
    vec3 f0;
    float diffuse_weight;
    float emission;
    float auxiliary;
};

float LabPBREmission(float encoded) {
    float value = floor(encoded * 255.0 + 0.5);
    return value >= 255.0 ? 0.0 : value / 254.0;
}

OpaqueMaterial DecodeOpaqueMaterial(vec4 spec) {
    OpaqueMaterial m;
    m.perceptual_roughness = 1.0 - spec.r;
    m.specular_selector = spec.g;
#ifdef MC_TEXTURE_FORMAT_LAB_PBR
    m.emission = LabPBREmission(spec.a);
    m.auxiliary = spec.b;
#else
    m.emission = spec.b;
    m.auxiliary = spec.a;
#endif
    return m;
}

PBRMaterial ResolveOpaquePBR(vec3 albedo, float roughness, float selector,
        float emission, float auxiliary) {
    PBRMaterial m;
    float selector_byte = floor(selector * 255.0 + 0.5);
    m.perceptual_roughness = roughness;
    m.alpha = max(roughness * roughness, 0.002);
#ifdef MC_TEXTURE_FORMAT_LAB_PBR
    bool metal = selector_byte >= 230.0;
    m.f0 = metal ? albedo : vec3(selector_byte / 255.0);
    m.diffuse_weight = metal ? 0.0 : 1.0;
#else
    m.f0 = mix(vec3(0.04), albedo, selector);
    m.diffuse_weight = 1.0 - selector;
#endif
    m.emission = emission;
    m.auxiliary = auxiliary;
    return m;
}

// Empirical SSS class amounts; LOW uses them as thin-layer transmission priors.
float PlantTransmissionPrior(int id) {
    if (id == 128) return 0.35;
    if (id == 129 || id == 130) return 0.30;
    if (id == 131) return 0.25;
    if (id == 132) return 0.10;
    if (id == 133) return 0.20;
    if (id == 134 || id == 137) return 0.03;
    if (id == 136) return 0.06;
    return 0.0;
}

// Geometric cutout averaging footprint, independent of optical transport.
float PlantShadowFootprint(int id) {
    if (id == 129) return 0.040;
    if (id == 128 || id == 130 || id == 131 || id == 133) return 0.020;
    if (id == 132 || id == 134 || id == 136 || id == 137) return 0.010;
    return 0.0;
}

bool PlantUsesTiltedSheets(int id) {
    return id == 128 || id == 130 || id == 131 || id == 133 || id == 134 || id == 137;
}

// -- Normal-map decoding --
// LabPBR format (default since MC 1.14): X and Y channels store the 2D
// tangent-space normal (Z reconstructed). Compatible with OptiFine / Iris
// LabPBR normal maps (normal.xy remapped from [0,1] to [-1,1]).
vec3 DecodeLabPBR(vec3 packed_normal) {
    vec2 xy = packed_normal.xy * 2.0 - 1.0;
    return vec3(xy, sqrt(saturate(1.0 - dot(xy, xy))));
}

#endif // LIB_MATERIAL_MODEL_GLSL
