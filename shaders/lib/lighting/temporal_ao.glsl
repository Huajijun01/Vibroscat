#ifndef LIB_LIGHTING_TEMPORAL_AO_GLSL
#define LIB_LIGHTING_TEMPORAL_AO_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/packing.glsl"

// ============================================================================
// AO temporal accumulation helpers (used by deferred1).
// ============================================================================
// History in the merged colortex8 (R = AO, G = age, B = 1 - depth,
// A = NaN "not cloud"); this module provides per-pixel math only. Generation
// is half-res, bilinear upsample, one sample/pixel/frame (full convergence).
// Rejection trusts the history only within the distance limit and the normal
// dot floor (GTAOHistoryWeight); both ramp smoothly to zero.

// Reproject a camera-relative world position into the previous frame's UV.
// Also outputs the receiver in the previous frame's view space for
// GTAOHistoryWeight (the forward push the reprojection already computed).
// Returns false when the point is behind the previous camera or off-screen.
bool GTAOReprojectToPrevious(vec3 world_pos, out vec2 previous_uv, out vec3 receiver_prev_view) {
    vec3 camera_delta = cameraPosition - previousCameraPosition;
    vec4 previous_view = gbufferPreviousModelView * vec4(world_pos + camera_delta, 1.0);
    receiver_prev_view = previous_view.xyz;
    vec4 previous_clip = gbufferPreviousProjection * previous_view;
    vec3 previous_ndc = previous_clip.xyz / previous_clip.w;
    previous_uv = previous_ndc.xy * 0.5 + 0.5;
    return previous_clip.w > 0.0 && all(greaterThanEqual(previous_uv, vec2(0.0)))
        && all(lessThanEqual(previous_uv, vec2(1.0)));
}

// History trust in [0, 1], product of two checks:
//  - distance: static geometry = zero displacement (full trust); beyond
//    AO_HISTORY_DISTANCE_LIMIT -> smooth 0.
//  - normal: current-frame normal at the reprojected position stands in for
//    the previous (no previous-normal buffer); disagreement beyond
//    AO_HISTORY_NORMAL_DOT_MIN -> 0.
float GTAOHistoryWeight(vec3 receiver_prev_view, vec3 view_normal, vec2 history_uv, vec4 history) {
    // Distance consistency. Both points live in the previous frame's view
    // space: the history surface from PreviousScreenToView and the receiver
    // pushed forward by GTAOReprojectToPrevious. The view transform is rigid,
    // so this equals the world-space displacement the limit is expressed in,
    // without inverting the previous modelview per pixel.
    vec3 previous_view = PreviousScreenToView(vec3(history_uv, 1.0 - history.b));
    float displacement = length(previous_view - receiver_prev_view);
    float distance_weight = 1.0 - smoothstep(0.0, AO_HISTORY_DISTANCE_LIMIT, displacement);

    // Normal consistency (current-frame normal at the reprojected position).
    ivec2 history_texel = clamp(
        ivec2(history_uv * vec2(viewWidth, viewHeight)),
        ivec2(0),
        ivec2(viewWidth, viewHeight) - 1);
    vec3 history_normal = DecodeOctahedralNormal(texelFetch(colortex4, history_texel, 0).xy);
    float normal_weight = smoothstep(
        AO_HISTORY_NORMAL_DOT_MIN, 1.0, dot(history_normal, view_normal));

    return distance_weight * normal_weight;
}

// One accumulation per frame (age = sample count). Fresh weight: box
// average 1/(samples+1) over the first AO_ACCUMULATION_BOX_SAMPLES, then
// steady-state AO_ACCUMULATION_ALPHA; rejection lifts it toward 1 (untrusted
// history replaced quickly). Full rejection -> fresh sample, age reset.
float GTAOAccumulate(float fresh_ao, float hist_ao, float hist_age,
                     float rejection, out float next_age) {
    float pixel_age = min(hist_age, AO_AGE_LIMIT) * rejection;
    float samples = pixel_age;
    float base_alpha = samples < float(AO_ACCUMULATION_BOX_SAMPLES)
        ? 1.0 / (samples + 1.0)
        : AO_ACCUMULATION_ALPHA;
    float alpha = 1.0 - (1.0 - base_alpha) * rejection;
    // Darkening slowdown: fresh < hist scales the fresh weight by
    // AO_DARKEN_SLOWDOWN. The condition is the darkening STATE (not the
    // per-frame rejection): the slow rate is carried by the age, so the
    // fade-in continues after rejection clears; brightening stays fast.
    if (fresh_ao < hist_ao) {
        alpha *= AO_DARKEN_SLOWDOWN;
    }
    next_age = pixel_age + 1.0;
    return mix(hist_ao, fresh_ao, alpha);
}

#endif
