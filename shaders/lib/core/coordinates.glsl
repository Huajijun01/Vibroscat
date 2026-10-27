#ifndef LIB_CORE_COORDINATES_GLSL
#define LIB_CORE_COORDINATES_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"

// View space <-> camera-relative world (player) space.
vec3 ViewToWorldSpace(vec3 view_pos) {
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

// Eye position in camera-relative world (feet-player) space. Depth
// reconstruction (ViewToWorldSpace / DepthToWorldPos) lands in feet-player
// space whose origin sits at the player's head; the eye is offset by
// gbufferModelViewInverse[3] (head-to-camera translation, ~1.62 m up
// standing, bobbing/swimming included). Close-range direction and distance
// math must subtract this offset.
vec3 EyePositionWorldSpace() {
    return u_eye_world_pos;
}

vec3 WorldToViewSpace(vec3 sp) {
    return (gbufferModelView * vec4(sp, 1.0)).xyz;
}

// NDCToView specialized to the symmetric perspective projection the game
// builds: rows 0/1 of the inverse carry only their diagonal entries (clip
// x/y never mix in eye z), and rows 2/3 only their z/w entries; the four
// dropped products per component are exact zeros, so this is bit-identical
// to the full mat4 product. The same structure is already load-bearing in
// LinearDepthFromScreenDepth and PreviousScreenToView. This pack's TAA
// jitter reaches the matrix-free gl_Position offset, never the matrix.
vec3 NDCToViewSparse(vec2 ndc_xy, float ndc_z) {
    vec3 view_h = vec3(
        gbufferProjectionInverse[0][0] * ndc_xy.x,
        gbufferProjectionInverse[1][1] * ndc_xy.y,
        gbufferProjectionInverse[2][2] * ndc_z + gbufferProjectionInverse[3][2]);
    return view_h / (gbufferProjectionInverse[2][3] * ndc_z + gbufferProjectionInverse[3][3]);
}

// NDC ([-1,1]^3) to camera-relative view space.
vec3 NDCToView(vec3 ndc) {
    return NDCToViewSparse(ndc.xy, ndc.z);
}

// Camera-relative view space to NDC ([-1,1]^3). Sparse forward form of the
// full mat4 product under the same symmetric-perspective structure documented
// above: rows 0/1 of the projection carry only their diagonal entries and
// row 2 only its z/w entries, so the dropped products are exact zeros.
vec3 ViewToNDC(vec3 view_pos) {
    vec3 clip = vec3(
        gbufferProjection[0][0] * view_pos.x,
        gbufferProjection[1][1] * view_pos.y,
        gbufferProjection[2][2] * view_pos.z + gbufferProjection[3][2]);
    return clip / -view_pos.z;
}

// View space to clip space for positions (homogeneous w = 1). Sparse forward
// form of the full mat4 product under the symmetric-perspective structure
// documented above: rows 0/1 carry only their diagonal entries, row 2 only
// its z/w entries, and the w row is exactly [0, 0, -1, 0]. Callers pass the
// pass-local matrix explicitly: gl_ProjectionMatrix carries the MC_HAND_DEPTH
// clip-Z scale in gbuffers_hand(_water), which Iris applies as a
// left-multiplied row scale that leaves the w row untouched, while
// gbufferProjection always holds the unscaled world projection.
vec4 ViewToClip(mat4 projection, vec3 view_pos) {
    return vec4(projection[0].x * view_pos.x,
        projection[1].y * view_pos.y,
        projection[2].z * view_pos.z + projection[3].z,
        -view_pos.z);
}

// Reconstructs a camera-relative player-space position from screen UV and depth.
vec3 DepthToWorldPos(vec2 uv, float depth) {
    vec3 view_pos = NDCToView(vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0));
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

// Same reconstruction that also yields the intermediate view-space position,
// so callers needing both frames skip a WorldToViewSpace round trip through
// the world matrix.
vec3 DepthToWorldPosView(vec2 uv, float depth, out vec3 view_pos) {
    view_pos = NDCToView(vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0));
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

// Reprojects a closest-to-camera point (screen xy + screen depth z) into the
// previous frame's UV space. Camera-relative world positions apply the camera
// delta; view-model positions such as the first-person hand do not.
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

// Legacy callers without material classification retain the foreground
// heuristic. Hand-aware callers must use the explicit overload above.
vec3 ToPrevious(vec3 closest_to_camera) {
    return ToPrevious(closest_to_camera, closest_to_camera.z >= 0.56);
}

// Previous-frame screen coordinates [0,1]3 to previous view space.
vec3 PreviousScreenToView(vec3 screen_position) {
    vec3 projected = screen_position * 2.0 - 1.0;
    projected.xy += gbufferPreviousProjection[2].xy;
    projected.x /= gbufferPreviousProjection[0].x;
    projected.y /= gbufferPreviousProjection[1].y;
    float view_depth = gbufferPreviousProjection[3].z
        / (projected.z + gbufferPreviousProjection[2].z);
    return vec3(projected.xy * view_depth, -view_depth);
}

// Screen depth [0,1] to linear depth (|view z|), via the analytic inverse of
// the perspective projection (sparse-matrix form of NDCToView).
float LinearDepthFromScreenDepth(float screen_depth) {
    screen_depth = screen_depth * 2.0 - 1.0;
    return 1.0 / (screen_depth * gbufferProjectionInverse[2][3] + gbufferProjectionInverse[3][3]);
}

// -- Screen-rect ray exit (screen-space marches) --

// Forward exit parameter t where a perspective ray leaves the [-1,1]^2 NDC
// rect. The ray arrives in homogeneous clip form: the screen position
// (origin_clip.xy / origin_clip.w) travels along
// (origin_clip.xy + t * direction_clip.xy)
//     / (origin_clip.w + t * direction_clip.w),
// so t keeps the caller's own ray parametrization. Per axis the solver
// intersects x = +-1 and y = +-1; a zero denominator is a ray parallel to
// that edge pair and is skipped. Returns fallback_t when no edge is crossed
// forward, so callers keep one min() chain for their remaining extent
// limits (far plane, max distance).
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

// Per-axis clip-ray parameter where the projected NDC coordinate crosses
// target_coord, from (o.xy + d.xy * t) / (o.w + d.w * t) = target_coord.
// Unlike ClipRayScreenExitT this keeps the ray's true clip w (the
// perspective NDC z is rational in t), so the solve stays exact for a
// projected ray instead of a flat w=1/w=0 chord. Non-positive crossings
// return fallback_t, letting a componentwise minimum over the four screen
// edges pick the forward-facing exit.
vec2 ClipRayScreenCoordT(vec4 origin_clip, vec4 direction_clip,
        float target_coord, float fallback_t) {
    vec2 t = (target_coord * origin_clip.ww - origin_clip.xy)
        / (direction_clip.xy - target_coord * direction_clip.ww);
    return mix(t, vec2(fallback_t), step(t, vec2(0.0)));
}

// -- Shadow-space transforms (world -> shadow clip / NDC, distortion, bias) --

// Analytic shadow distortion: compresses clip-space XY toward center.
#define DISTORT_FACTOR 0.9

vec2 GetDistortFactor(vec2 clip_pos) {
    // Compress XY toward center (linear blend of uniform and |clip|).
    return mix(vec2(1.0), abs(clip_pos), DISTORT_FACTOR);
}

// Remap shadow NDC depth into the protected range (SHADOW_DEPTH_SCALE);
// inverse: ndc = 0.5 + (protected - 0.5)/SCALE.
float ProtectShadowDepth(float ndc_depth) {
    return 0.5 + SHADOW_DEPTH_SCALE * (ndc_depth - 0.5);
}

// Convert a depth gap measured in protected shadow depth (e.g. PCSS blocker
// gap or SSS thickness) into world meters along the light direction.
float ShadowDepthGapToWorld(float protected_gap) {
    return 2.0 * protected_gap / (SHADOW_DEPTH_SCALE * max(abs(shadowProjection[2].z), 1e-6));
}

// Inverse of ShadowDepthGapToWorld: world meters -> protected shadow depth.
float ShadowDepthGapFromWorld(float world_gap) {
    return 0.5 * SHADOW_DEPTH_SCALE * abs(shadowProjection[2].z) * world_gap;
}

// Undistorted shadow clip space [-1,1]^3. PCSS offset math works in clip
// space; the distortion is re-applied per sample via DistortShadowClip().
vec3 ProjectToShadowClip(vec3 world_pos) {
    vec3 view_pos = mat3(shadowModelView) * world_pos + shadowModelView[3].xyz;

    vec3 clip_pos;
    clip_pos.x = shadowProjection[0].x * view_pos.x + shadowProjection[3].x;
    clip_pos.y = shadowProjection[1].y * view_pos.y + shadowProjection[3].y;
    clip_pos.z = shadowProjection[2].z * view_pos.z + shadowProjection[3].z;
    return clip_pos;
}

// Both shadow projections for one world position in a single sweep. The view
// transform and diagonal clip projection are shared verbatim, so the clip
// output is bit-identical to ProjectToShadowClip.
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

// Shadow clip space -> shadow map UV [0,1], re-applying the analytic distortion.
vec2 DistortShadowClip(vec2 clip_pos) {
    return clip_pos / GetDistortFactor(clip_pos) * 0.5 + 0.5;
}

#endif // LIB_CORE_COORDINATES_GLSL
