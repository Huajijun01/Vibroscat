#ifndef LIB_CORE_COORDINATES_GLSL
#define LIB_CORE_COORDINATES_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// View space <-> camera-relative player space.
vec3 ViewToSceneSpace(vec3 view_pos) {
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

// Eye position in camera-relative scene (feet-player) space. Depth
// reconstruction (ViewToSceneSpace / DepthToWorldPos) lands in feet-player
// space whose origin sits at the player's head; the eye is offset by
// gbufferModelViewInverse[3] (head-to-camera translation, ~1.62 m up
// standing, bobbing/swimming included). Close-range direction and distance
// math must subtract this offset.
vec3 EyePositionSceneSpace() {
    return gbufferModelViewInverse[3].xyz;
}

vec3 SceneToViewSpace(vec3 sp) {
    return (gbufferModelView * vec4(sp, 1.0)).xyz;
}

// NDC ([-1,1]^3) to camera-relative view space.
vec3 NDCToView(vec3 ndc) {
    vec4 view_h = gbufferProjectionInverse * vec4(ndc, 1.0);
    return view_h.xyz / view_h.w;
}

// Camera-relative view space to NDC ([-1,1]^3).
vec3 ViewToNDC(vec3 view_pos) {
    return (gbufferProjection * vec4(view_pos, 1.0)).xyz / -view_pos.z;
}

// Reconstructs a camera-relative player-space position from screen UV and depth.
vec3 DepthToWorldPos(vec2 texcoord, float depth) {
    vec3 ndc = vec3(texcoord * 2.0 - 1.0, depth * 2.0 - 1.0);
    vec4 view_h = gbufferProjectionInverse * vec4(ndc, 1.0);
    vec3 view_pos = view_h.xyz / view_h.w;
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

// Reprojects a closest-to-camera point (screen xy + screen depth z) into the
// previous frame's UV space. Camera-relative world positions apply the camera
// delta; view-model positions such as the first-person hand do not.
vec3 ToPrevious(vec3 closest_to_camera, bool apply_camera_delta) {
    vec4 pos = vec4(closest_to_camera * 2.0 - 1.0, 1.0);
    pos = gbufferProjectionInverse * pos;
    pos /= pos.w;
    pos = gbufferModelViewInverse * pos;
    if (apply_camera_delta) {
        pos.xyz += cameraPosition - previousCameraPosition;
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

// Inverse of LinearDepthFromScreenDepth: linear depth back to screen [0,1].
float ScreenDepthFromLinearDepth(float linear_depth) {
    linear_depth = (1.0 / linear_depth - gbufferProjectionInverse[3][3]) / gbufferProjectionInverse[2][3];
    return linear_depth * 0.5 + 0.5;
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

// -- Distort-branch shadow bias --
// Texel size from the distortion Jacobian
// (uv = clip/(2*factor)+0.5, so d(uv)/d(clip) = (1-D)/(2*factor^2)),
// then slope-scaled + constant bias -> NDC depth offset.
float AxialDistortShadowBias(float ndotl, vec3 view_pos, float const_bias_texels) {
    float shadow_e = shadowProjection[2].z;
    float shadow_a = shadowProjection[0].x;
    float shadow_b = shadowProjection[1].y;
    float shadow_c = shadowProjection[3].x;
    float shadow_d = shadowProjection[3].y;

    float x = shadow_a * view_pos.x + shadow_c;
    float y = shadow_b * view_pos.y + shadow_d;

    float one_minus_d = 1.0 - DISTORT_FACTOR;
    float fx = one_minus_d + DISTORT_FACTOR * abs(x);
    float fy = one_minus_d + DISTORT_FACTOR * abs(y);

    float dx_view = (2.0 * fx * fx) / (abs(shadow_a) * one_minus_d * float(shadowMapResolution) + 1e-5);
    float dy_view = (2.0 * fy * fy) / (abs(shadow_b) * one_minus_d * float(shadowMapResolution) + 1e-5);
    float texel_world_size = max(dx_view, dy_view);

    float clamped_ndotl = clamp(ndotl, 0.0, 1.0);
    float slope_world = texel_world_size
        * sqrt(max(1.0 - clamped_ndotl * clamped_ndotl, 0.0))
        / max(clamped_ndotl, 1e-4);
    float const_world = texel_world_size * const_bias_texels;

    float depth_scale = 0.5 * abs(shadow_e);    // view-space m -> NDC depth

    return (slope_world + const_world) * depth_scale * smoothstep(0.0, 0.05, ndotl);
}

// World position -> shadow NDC [0,1]3 (orthographic projection uses only the
// diagonal components: 3 mul + 3 add), with the analytic distortion and the
// protected depth remap applied.
vec3 ProjectToShadow(vec3 world_pos) {
    vec3 view_pos = mat3(shadowModelView) * world_pos + shadowModelView[3].xyz;

    vec3 clip_pos;
    clip_pos.x = shadowProjection[0].x * view_pos.x + shadowProjection[3].x;
    clip_pos.y = shadowProjection[1].y * view_pos.y + shadowProjection[3].y;
    clip_pos.z = shadowProjection[2].z * view_pos.z + shadowProjection[3].z;

    clip_pos.xy /= GetDistortFactor(clip_pos.xy);
    return vec3(clip_pos.xy * 0.5 + 0.5, ProtectShadowDepth(clip_pos.z * 0.5 + 0.5));
}

// World position -> shadow NDC [0,1]3 with a slope-scaled depth bias.
vec3 ProjectToShadowWithBias(vec3 world_pos, float ndotl) {
    vec3 view_pos = mat3(shadowModelView) * world_pos + shadowModelView[3].xyz;

    vec3 clip_pos;
    clip_pos.x = shadowProjection[0].x * view_pos.x + shadowProjection[3].x;
    clip_pos.y = shadowProjection[1].y * view_pos.y + shadowProjection[3].y;
    clip_pos.z = shadowProjection[2].z * view_pos.z + shadowProjection[3].z;

    float bias = AxialDistortShadowBias(ndotl, view_pos, 3.0);
    vec2 distort_factor = GetDistortFactor(clip_pos.xy);
    clip_pos.xy /= distort_factor;
    // Bias applied in NDC space, then remapped into the protected range.
    float ndc_z = clip_pos.z * 0.5 + 0.5 - bias;
    return vec3(clip_pos.xy * 0.5 + 0.5, ProtectShadowDepth(ndc_z));
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

// Shadow clip space -> shadow map UV [0,1], re-applying the analytic distortion.
vec2 DistortShadowClip(vec2 clip_pos) {
    return clip_pos / GetDistortFactor(clip_pos) * 0.5 + 0.5;
}

#endif
