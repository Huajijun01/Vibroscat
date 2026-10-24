#ifndef LIB_MATERIAL_TRANSLUCENT_SURFACE_GLSL
#define LIB_MATERIAL_TRANSLUCENT_SURFACE_GLSL

// One RGB UNORM16 surface value split across two RGBA8 targets: colortex2
// carries the low bytes and water flag; colortex1 carries the high
// bytes with framebuffer blending preserving its opaque material-ID alpha.
void PackTranslucentSurface(vec3 encoded_surface, float water_flag,
        out vec4 surface_low, out vec4 surface_high) {
    vec3 unorm16 = floor(clamp(encoded_surface, 0.0, 1.0) * 65535.0 + 0.5);
    vec3 high_bytes = floor(unorm16 * (1.0 / 256.0));
    vec3 low_bytes = unorm16 - high_bytes * 256.0;
    surface_low = vec4(low_bytes * (1.0 / 255.0), water_flag);
    surface_high = vec4(high_bytes * (1.0 / 255.0), 0.0);
}

vec3 UnpackTranslucentSurface(vec3 surface_low, vec3 surface_high) {
    vec3 low_bytes = floor(surface_low * 255.0 + 0.5);
    vec3 high_bytes = floor(surface_high * 255.0 + 0.5);
    return (high_bytes * 256.0 + low_bytes) * (1.0 / 65535.0);
}

#endif // LIB_MATERIAL_TRANSLUCENT_SURFACE_GLSL
