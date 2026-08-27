#ifndef LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL
#define LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL

#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/raytrace/ssr.glsl"

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

float OpaqueHistoryMip(float path_length, float perceptual_roughness,
        float origin_view_depth, out float cone_pixels) {
    cone_pixels = max(1.0,
        path_length * perceptual_roughness * perceptual_roughness
            * viewHeight / max(origin_view_depth, 1.0));
    int mip_count = textureQueryLevels(colortex5);
    return clamp(log2(cone_pixels), 0.0, float(max(mip_count - 1, 0)));
}

float OpaqueScreenEdgeWeight(vec2 uv) {
    vec2 edge_distance = min(uv, vec2(1.0) - uv);
    return smoothstep(0.005, 0.04, min(edge_distance.x, edge_distance.y));
}

float OpaqueHistoryConfidence(SSRHit hit, vec3 previous_hit) {
    if (!hit.valid || frameCounter < 2 || !SSRFinite(previous_hit)) {
        return 0.0;
    }
    if (any(lessThanEqual(previous_hit, vec3(0.0)))
            || any(greaterThanEqual(previous_hit, vec3(1.0)))) {
        return 0.0;
    }

    float distance_weight = 1.0 - smoothstep(
        OPAQUE_SSR_MAX_DISTANCE * 0.65,
        OPAQUE_SSR_MAX_DISTANCE, hit.path_length);
    float edge_weight = OpaqueScreenEdgeWeight(hit.screen.xy)
        * OpaqueScreenEdgeWeight(previous_hit.xy);

    vec3 camera_delta = cameraPosition - previousCameraPosition;
    float translation_weight = 1.0 - smoothstep(
        0.25, 1.0, length(camera_delta));
    vec3 current_forward = normalize(vec3(
        gbufferModelView[0][2],
        gbufferModelView[1][2],
        gbufferModelView[2][2]));
    vec3 previous_forward = normalize(vec3(
        gbufferPreviousModelView[0][2],
        gbufferPreviousModelView[1][2],
        gbufferPreviousModelView[2][2]));
    float rotation_weight = smoothstep(
        0.5, 0.95, dot(current_forward, previous_forward));

    return clamp(distance_weight * edge_weight
        * translation_weight * rotation_weight, 0.0, 1.0);
}

vec3 SampleOpaqueHistory(SSRHit hit, float perceptual_roughness,
        float origin_view_depth, out float confidence, out float selected_mip) {
    confidence = 0.0;
    selected_mip = 0.0;
    if (!hit.valid) return vec3(0.0);

    vec3 previous_hit = ToPrevious(hit.screen);
    confidence = OpaqueHistoryConfidence(hit, previous_hit);
    if (confidence <= 0.0) return vec3(0.0);

    float cone_pixels;
    selected_mip = OpaqueHistoryMip(
        hit.path_length, perceptual_roughness,
        origin_view_depth, cone_pixels);
    vec3 history = textureLod(
        colortex5, previous_hit.xy, selected_mip).rgb;
    if (!SSRFinite(history) || any(lessThan(history, vec3(0.0)))) {
        confidence = 0.0;
        return vec3(0.0);
    }
    return max(history, vec3(0.0));
}
#endif
