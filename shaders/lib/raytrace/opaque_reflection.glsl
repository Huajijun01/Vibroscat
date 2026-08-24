#ifndef LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL
#define LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL

#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"

vec2 OpaqueSSRRandom2(ivec2 tx) {
    ivec3 size = textureSize(utex_stbn_scalar, 0);
    ivec2 p0 = ivec2(
        (tx.x % size.x + size.x) % size.x,
        (tx.y % size.y + size.y) % size.y);
    int z = (frameCounter % size.z + size.z) % size.z;
    ivec2 p1 = (p0 + ivec2(47, 83)) % size.xy;
    float u0 = texelFetch(utex_stbn_scalar, ivec3(p0, z), 0).r;
    float u1 = texelFetch(
        utex_stbn_scalar, ivec3(p1, (z + 29) % size.z), 0).r;
    return clamp(vec2(u0, u1), vec2(1e-6), vec2(1.0 - 1e-6));
}

mat3 BuildOrthonormalBasis(vec3 N) {
    vec3 up = abs(N.z) < 0.999
        ? vec3(0.0, 0.0, 1.0)
        : vec3(1.0, 0.0, 0.0);
    vec3 T = normalize(cross(up, N));
    return mat3(T, cross(N, T), N);
}

vec3 SampleVisibleGGX(vec3 local_v, float alpha, vec2 u) {
    vec3 wi_std = normalize(vec3(local_v.xy * alpha, local_v.z));
    float phi = 2.0 * PI * u.x;
    float z = (1.0 - u.y) * (1.0 + wi_std.z) - wi_std.z;
    float sin_theta = sqrt(clamp(1.0 - z * z, 0.0, 1.0));
    vec3 cap = vec3(sin_theta * cos(phi), sin_theta * sin(phi), z);
    vec3 wm_std = cap + wi_std;
    return normalize(vec3(wm_std.xy * alpha, wm_std.z));
}

vec3 OpaqueReflectionDirection(vec3 N, vec3 V,
        float perceptual_roughness, ivec2 tx, out vec3 H) {
    float alpha = max(perceptual_roughness * perceptual_roughness, 0.002);
    mat3 frame = BuildOrthonormalBasis(N);
    vec3 local_v = transpose(frame) * V;
    vec3 local_h = SampleVisibleGGX(
        local_v, alpha, OpaqueSSRRandom2(tx));
    H = normalize(frame * local_h);
    vec3 L = normalize(reflect(-V, H));
    return dot(N, L) > 1e-5 ? L : vec3(0.0);
}

#endif
