#ifndef LIB_MATERIAL_CORE_GLSL
#define LIB_MATERIAL_CORE_GLSL

// ════════════════════════════════════════════════════════════════════════════
// Material model — oldPBR/seusPBR-style specular map convention
// ════════════════════════════════════════════════════════════════════════════
//
// Specular map channels used by this shader pack:
//   R = smoothness  (0=dull, 1=polished)
//   G = metalness   (stored without thresholding)
//   B = emission    (0=dark, 1=self-illuminated)
//   A = reserved
//
// materialID ranges (see block.properties for per-block assignment):
//   80-95   water
//   96-111  metal   (iron, gold, anvil, etc.)
//   112-127 emissive (glowstone, torch, lava, beacon, etc.)
//   128-134 SSS plants (grass, leaves, vines, crops, flowers, moss, ...)
//   160-191 translucent (glass, ice, slime, stained glass)

struct Material {
    float roughness;
    float metalness;
    float emission;
    float reserved;
};

Material MaterialDefaults(int id, vec4 spec) {
    Material m;
    // smoothness inverted to roughness
    m.roughness  = 1.0 - spec.r;
    m.metalness  = spec.g;
    m.emission   = spec.b;
    m.reserved    = spec.a;

    // class-based overrides disabled; the spec map alone drives the material.
    return m;
}

// Plant subsurface-scattering amount by materialID (see block.properties for
// the 128-134 assignments). 0 = no transmission, 1 = strong translucency.
float SSSAmountForId(int id) {
    if (id == 128) return 0.55;  // grass, ferns, dry grass, seagrass, nether sprouts/roots
    if (id == 129) return 1.0;   // leaves
    if (id == 130) return 0.65;  // vines, crops, stems, kelp
    if (id == 131) return 0.5;   // flowers
    if (id == 132) return 0.45;  // mushrooms & fungi
    if (id == 133) return 0.3;   // bushes, moss, aquatic/other foliage
    if (id == 134) return 0.2;   // dry/dead plants, cactus
    return 0.0;
}

// ── Normal-map decoding ──
// LabPBR format (default since MC 1.14): X and Y channels store the 2D
// tangent-space normal (Z reconstructed). Compatible with OptiFine / Iris
// LabPBR normal maps (normal.xy remapped from [0,1] to [-1,1]).
vec3 DecodeLabPBR(vec3 nm) {
    vec2 xy = nm.xy * 2.0 - 1.0;
    return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

// Full-XYZ normal format: XYZ stored in RGB, remapped from [0,1] to [-1,1].
vec3 DecodeOldPBR(vec3 nm) {
    return normalize(nm * 2.0 - 1.0);
}

#endif
