#ifndef LIB_MATERIAL_OPAQUE_SURFACE_GLSL
#define LIB_MATERIAL_OPAQUE_SURFACE_GLSL

#include "/lib/core/math_scalar.glsl"

// RGBA16 UNORM: oct8 shading normal in RG, rough8/selector8 in B,
// emission8/AO8 in A. materialID remains in colortex1.a.
vec4 PackOpaqueSurface(vec2 normal_oct, vec4 material_data) {
    vec4 codes = floor(saturate(material_data) * 255.0);
    vec2 normal_codes = floor(normal_oct * 255.0 + 0.5);
    return vec4(normal_codes * (1.0 / 255.0),
        (codes.r + 256.0 * codes.g) * (1.0 / 65535.0),
        (codes.b + 256.0 * codes.a) * (1.0 / 65535.0));
}

vec2 UnpackOpaqueReflectance(vec4 surface) {
    uint code = uint(round(surface.b * 65535.0));
    return vec2(code & 255u, code >> 8) * (1.0 / 255.0);
}

vec4 UnpackOpaqueMaterial(vec4 surface) {
    uvec2 codes = uvec2(round(surface.ba * 65535.0));
    return unpackUnorm4x8(codes.x | (codes.y << 16));
}

#endif // LIB_MATERIAL_OPAQUE_SURFACE_GLSL
