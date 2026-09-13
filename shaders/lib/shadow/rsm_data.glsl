#ifndef LIB_SHADOW_RSM_DATA_GLSL
#define LIB_SHADOW_RSM_DATA_GLSL

#include "/lib/core/packing.glsl"
#include "/lib/color/spaces.glsl"

// RGBA8, nearest-only: two RGB565 bytes and two octahedral normal bytes.
// Companding reflectance preserves dark colors without widening shadowcolor0.
vec4 EncodeRSMSource(vec3 diffuse_reflectance, vec3 normal_shadow) {
    uvec3 rgb = uvec3(round(clamp(FromLinear(diffuse_reflectance), 0.0, 1.0) * vec3(31.0, 63.0, 31.0)));
    uint packed_rgb = (rgb.r << 11u) | (rgb.g << 5u) | rgb.b;
    vec2 encoded_normal = EncodeOctahedralNormal(normal_shadow);
    // Reserve all-zero RGBA8 for absent/translucent sources, including when
    // a black surface's normal quantizes to the octahedron's (0, 0) corner.
    if (all(lessThan(encoded_normal, vec2(0.5 / 255.0)))) encoded_normal.x = 1.0 / 255.0;
    return vec4(vec2(packed_rgb & 255u, packed_rgb >> 8u) / 255.0, encoded_normal);
}

vec3 DecodeRSMSource(vec4 source_data) {
    uvec2 bytes = uvec2(round(source_data.rg * 255.0));
    uint packed_rgb = bytes.x | (bytes.y << 8u);
    return ToLinear(vec3(packed_rgb >> 11u, (packed_rgb >> 5u) & 63u, packed_rgb & 31u)
        / vec3(31.0, 63.0, 31.0));
}

#endif // LIB_SHADOW_RSM_DATA_GLSL
