#ifndef LIB_CORE_COORDINATES_GLSL
#define LIB_CORE_COORDINATES_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"

vec3 ViewToWorldSpace(vec3 view_pos) {
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

// Camera-relative world means feet-player space, whose origin sits at the
// player's head; the eye is offset by gbufferModelViewInverse[3] (~1.62 m
// standing, bobbing/swimming included). Close-range direction and distance
// math against depth-reconstructed positions must subtract this offset.
vec3 EyePositionWorldSpace() {
    return u_eye_world_pos;
}

vec3 WorldToViewSpace(vec3 sp) {
    return (gbufferModelView * vec4(sp, 1.0)).xyz;
}

// Bit-identical to the full mat4 product: the game's symmetric projection
// keeps rows 0/1 diagonal-only and rows 2/3 zw-only, and TAA jitter reaches
// the matrix-free gl_Position offset, never the matrix. The same sparse
// structure is load-bearing in ViewToNDC, LinearDepthFromScreenDepth, and
// PreviousScreenToView.
vec3 NDCToViewSparse(vec2 ndc_xy, float ndc_z) {
    vec3 view_h = vec3(
        gbufferProjectionInverse[0][0] * ndc_xy.x,
        gbufferProjectionInverse[1][1] * ndc_xy.y,
        gbufferProjectionInverse[2][2] * ndc_z + gbufferProjectionInverse[3][2]);
    return view_h / (gbufferProjectionInverse[2][3] * ndc_z + gbufferProjectionInverse[3][3]);
}

vec3 NDCToView(vec3 ndc) {
    return NDCToViewSparse(ndc.xy, ndc.z);
}

vec3 ViewToNDC(vec3 view_pos) {
    vec3 clip = vec3(
        gbufferProjection[0][0] * view_pos.x,
        gbufferProjection[1][1] * view_pos.y,
        gbufferProjection[2][2] * view_pos.z + gbufferProjection[3][2]);
    return clip / -view_pos.z;
}

// Callers pass the pass-local matrix; gbufferProjection is the unscaled world
// projection. gl_ProjectionMatrix's MC_HAND_DEPTH clip-Z scale (gbuffers_hand(_water))
// left-multiplies row scales and leaves w untouched, so the sparse form stays valid.
vec4 ViewToClip(mat4 projection, vec3 view_pos) {
    return vec4(projection[0].x * view_pos.x,
        projection[1].y * view_pos.y,
        projection[2].z * view_pos.z + projection[3].z,
        -view_pos.z);
}

vec3 DepthToWorldPos(vec2 uv, float depth) {
    vec3 view_pos = NDCToView(vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0));
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

vec3 DepthToWorldPosView(vec2 uv, float depth, out vec3 view_pos) {
    view_pos = NDCToView(vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0));
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

// Input is screen xy + screen depth z; world positions apply the camera delta,
// view-model positions such as the first-person hand do not.
vec3 ToPrevious(vec3 closest_to_camera, bool apply_camera_delta) {
    vec3 view_pos = NDCToViewSparse(closest_to_camera.xy * 2.0 - 1.0, closest_to_camera.z * 2.0 - 1.0);
    vec4 pos = vec4((gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz, 1.0);
    if (apply_camera_delta) {
        pos.xyz += u_camera_delta;
    }
    pos = gbufferPreviousModelView * pos;
    pos = gbufferPreviousProjection * pos;
    pos /= pos.w;
    return pos.xyz * 0.5 + 0.5;
}

// Legacy overload without material classification; hand-aware callers must use the explicit overload.
vec3 ToPrevious(vec3 closest_to_camera) {
    return ToPrevious(closest_to_camera, closest_to_camera.z >= 0.56);
}

vec3 PreviousScreenToView(vec3 screen_position) {
    vec3 projected = screen_position * 2.0 - 1.0;
    projected.xy += gbufferPreviousProjection[2].xy;
    projected.x /= gbufferPreviousProjection[0].x;
    projected.y /= gbufferPreviousProjection[1].y;
    float view_depth = gbufferPreviousProjection[3].z
        / (projected.z + gbufferPreviousProjection[2].z);
    return vec3(projected.xy * view_depth, -view_depth);
}

// Returns |view z| (positive distance), via the analytic inverse of the perspective projection.
float LinearDepthFromScreenDepth(float screen_depth) {
    screen_depth = screen_depth * 2.0 - 1.0;
    return 1.0 / (screen_depth * gbufferProjectionInverse[2][3] + gbufferProjectionInverse[3][3]);
}

// Forward exit parameter t where a perspective ray leaves the [-1,1]^2 NDC
// rect. t is in the caller's homogeneous ray parametrization
// (o.xy + t*d.xy)/(o.w + t*d.w); a zero denominator (ray parallel to the
// edge pair) is skipped. Returns fallback_t when no edge is crossed forward,
// so callers keep one min() chain with their remaining extent limits.
float ClipRayScreenExitT(vec4 origin_clip, vec4 direction_clip, float fallback_t) {
    vec2 t1 = (vec2(1.0) * origin_clip.w - origin_clip.xy)
        / (direction_clip.xy - vec2(1.0) * direction_clip.w);
    vec2 t2 = (vec2(-1.0) * origin_clip.w - origin_clip.xy)
        / (direction_clip.xy - vec2(-1.0) * direction_clip.w);
    float exit_t = fallback_t;
    if (t1.x > 0.0) exit_t = min(exit_t, t1.x);
    if (t1.y > 0.0) exit_t = min(exit_t, t1.y);
    if (t2.x > 0.0) exit_t = min(exit_t, t2.x);
    if (t2.y > 0.0) exit_t = min(exit_t, t2.y);
    return exit_t;
}

// Unlike ClipRayScreenExitT this keeps the ray's true clip w (perspective NDC z
// is rational in t), so the crossing solve stays exact for a projected ray
// instead of a flat w=1 chord. Non-positive crossings return fallback_t.
vec2 ClipRayScreenCoordT(vec4 origin_clip, vec4 direction_clip,
        float target_coord, float fallback_t) {
    vec2 t = (target_coord * origin_clip.ww - origin_clip.xy)
        / (direction_clip.xy - target_coord * direction_clip.ww);
    return mix(t, vec2(fallback_t), step(t, vec2(0.0)));
}

#define DISTORT_FACTOR 0.9

vec2 GetDistortFactor(vec2 clip_pos) {
    return mix(vec2(1.0), abs(clip_pos), DISTORT_FACTOR);
}

// Inverse: ndc = 0.5 + (protected - 0.5) / SHADOW_DEPTH_SCALE.
float ProtectShadowDepth(float ndc_depth) {
    return 0.5 + SHADOW_DEPTH_SCALE * (ndc_depth - 0.5);
}

// Protected-depth gap (e.g. PCSS blocker gap or SSS thickness) -> world meters along the light direction.
float ShadowDepthGapToWorld(float protected_gap) {
    return 2.0 * protected_gap / (SHADOW_DEPTH_SCALE * max(abs(shadowProjection[2].z), 1e-6));
}

float ShadowDepthGapFromWorld(float world_gap) {
    return 0.5 * SHADOW_DEPTH_SCALE * abs(shadowProjection[2].z) * world_gap;
}

// Returns undistorted clip space; PCSS offset math re-applies distortion per sample via DistortShadowClip().
vec3 ProjectToShadowClip(vec3 world_pos) {
    vec3 view_pos = mat3(shadowModelView) * world_pos + shadowModelView[3].xyz;

    vec3 clip_pos;
    clip_pos.x = shadowProjection[0].x * view_pos.x + shadowProjection[3].x;
    clip_pos.y = shadowProjection[1].y * view_pos.y + shadowProjection[3].y;
    clip_pos.z = shadowProjection[2].z * view_pos.z + shadowProjection[3].z;
    return clip_pos;
}

// Clip output is bit-identical to ProjectToShadowClip.
void ProjectToShadowPair(vec3 world_pos, out vec3 shadow_proj, out vec3 shadow_clip) {
    vec3 view_pos = mat3(shadowModelView) * world_pos + shadowModelView[3].xyz;

    vec3 clip_pos;
    clip_pos.x = shadowProjection[0].x * view_pos.x + shadowProjection[3].x;
    clip_pos.y = shadowProjection[1].y * view_pos.y + shadowProjection[3].y;
    clip_pos.z = shadowProjection[2].z * view_pos.z + shadowProjection[3].z;
    shadow_clip = clip_pos;

    vec2 distort_factor = GetDistortFactor(clip_pos.xy);
    clip_pos.xy /= distort_factor;
    // The shadow filter owns receiver bias for its actual sampling footprint.
    float ndc_z = clip_pos.z * 0.5 + 0.5;
    shadow_proj = vec3(clip_pos.xy * 0.5 + 0.5, ProtectShadowDepth(ndc_z));
}

vec2 DistortShadowClip(vec2 clip_pos) {
    return clip_pos / GetDistortFactor(clip_pos) * 0.5 + 0.5;
}

#endif // LIB_CORE_COORDINATES_GLSL
