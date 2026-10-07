#ifndef LIB_LIGHTING_TEMPORAL_AO_GLSL
#define LIB_LIGHTING_TEMPORAL_AO_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/raytrace/ssr_depth.glsl"

// ============================================================================
// AO temporal accumulation helpers (used by deferred1).
// ============================================================================
// History in the merged colortex8 (R = AO, G = age, B = encoded view depth
// via the EncodeSSRDepth squared curve, A = NaN "not cloud"); this module
// provides per-pixel math only. Generation
// is half-res, bilinear upsample, one sample/pixel/frame (full convergence).
// Rejection trusts the history only within the distance limit and the normal
// dot floor (AOHistoryWeight); both ramp smoothly to zero.

// Reproject a camera-relative world position into the previous jittered scene UV.
// Also outputs the receiver in the previous frame's view space for
// AOHistoryWeight (the forward push the reprojection already computed).
// Returns false when the point is behind the previous camera or off-screen.
bool AOReprojectToPrevious(vec3 world_pos, out vec2 previous_uv, out vec3 receiver_prev_view) {
    vec3 camera_delta = cameraPosition - previousCameraPosition;
    vec4 previous_view = gbufferPreviousModelView * vec4(world_pos + camera_delta, 1.0);
    receiver_prev_view = previous_view.xyz;
    vec4 previous_clip = gbufferPreviousProjection * previous_view;
    vec3 previous_ndc = previous_clip.xyz / previous_clip.w;
    previous_uv = previous_ndc.xy * 0.5 + 0.5;
#ifdef TAA
    previous_uv += u_taa_offset_previous * 0.5;
#endif
    return previous_clip.w > 0.0 && all(greaterThanEqual(previous_uv, vec2(0.0)))
        && all(lessThanEqual(previous_uv, vec2(1.0)));
}

// Decode the stored history depth (EncodeSSRDepth curve) back to linear view
// depth in meters. The clip-depth reference is projection-depth-row derived
// and therefore FOV-independent; it only moves when near/far change, which
// reloads the world and reseeds the history anyway.
float AOHistoryViewDepth(float encoded) {
    float inverse_clip_depth = gbufferProjectionInverse[2][3] + gbufferProjectionInverse[3][3];
    return sqrt(max(encoded, 0.0)) * (SSR_DEPTH_HALF_RCP_SQRT / inverse_clip_depth);
}

// Linear view depth to previous-frame screen depth: inverts the depth row of
// PreviousScreenToView (view_depth = P[3].z / (ndc_z + P[2].z)).
float ViewDepthToPreviousScreenDepth(float view_depth) {
    float ndc_z = gbufferPreviousProjection[3].z / max(view_depth, 1.0e-6)
        - gbufferPreviousProjection[2].z;
    return clamp(ndc_z * 0.5 + 0.5, 0.0, 1.0);
}

// History trust in [0, 1], product of two checks:
//  - distance: static geometry = zero displacement (full trust); beyond
//    AO_HISTORY_DISTANCE_LIMIT -> smooth 0.
//  - normal: current-frame normal at the reprojected position stands in for
//    the previous (no previous-normal buffer); disagreement beyond
//    AO_HISTORY_NORMAL_DOT_FLOOR -> 0. Both normals come from the same frame in
//    the stored world space, so the dot product is space-agnostic.
float AOHistoryWeight(vec3 receiver_prev_view, vec3 normal_world, vec2 history_uv, vec4 history) {
    // Distance consistency. Both points live in the previous frame's view
    // space: the history surface from PreviousScreenToView and the receiver
    // pushed forward by AOReprojectToPrevious. The view transform is rigid,
    // so this equals the world-space displacement the limit is expressed in,
    // without inverting the previous modelview per pixel.
    vec2 projection_uv = history_uv;
#ifdef TAA
    projection_uv -= u_taa_offset_previous * 0.5;
#endif
    vec3 previous_view = PreviousScreenToView(vec3(projection_uv,
        ViewDepthToPreviousScreenDepth(AOHistoryViewDepth(history.b))));
    float displacement = length(previous_view - receiver_prev_view);
    float distance_weight = 1.0 - smoothstep(0.0, AO_HISTORY_DISTANCE_LIMIT, displacement);

    // Normal consistency (current-frame normal at the reprojected position).
    vec2 normal_uv = projection_uv;
#ifdef TAA
    normal_uv += u_taa_offset * 0.5;
#endif
    ivec2 history_texel = clamp(
        ivec2(normal_uv * u_render_res),
        ivec2(0),
        ivec2(u_render_res) - 1);
    vec3 history_normal = DecodeOctahedralNormal(texelFetch(colortex4, history_texel, 0).xy);
    float normal_weight = smoothstep(
        AO_HISTORY_NORMAL_DOT_FLOOR, 1.0, dot(history_normal, normal_world));

    return distance_weight * normal_weight;
}

// One accumulation per frame (age = sample count). Fresh weight is the
// capped running average 1/(age+1): it decays with the accumulated age and
// settles at 1/AO_HISTORY_FRAMES, so that setting owns the denoising depth
// (same law as the cloud scheme, CloudAccumulate). Rejection lifts it
// toward 1 (untrusted history replaced quickly). Full rejection -> fresh
// sample, age reset.
float AOAccumulate(float fresh_ao, float hist_ao, float hist_age,
                     float rejection, out float next_age) {
    float pixel_age = min(hist_age, AO_HISTORY_FRAMES) * rejection;
    float base_alpha = 1.0 / min(pixel_age + 1.0, float(AO_HISTORY_FRAMES));
    float alpha = 1.0 - (1.0 - base_alpha) * rejection;
    next_age = pixel_age + 1.0;
    return mix(hist_ao, fresh_ao, alpha);
}

#endif // LIB_LIGHTING_TEMPORAL_AO_GLSL
