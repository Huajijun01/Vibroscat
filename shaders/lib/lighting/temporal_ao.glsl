#ifndef LIB_LIGHTING_TEMPORAL_AO_GLSL
#define LIB_LIGHTING_TEMPORAL_AO_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/core/render_scale.glsl"
#include "/lib/lighting/ao_history.glsl"
#include "/lib/raytrace/ssr_depth.glsl"

// History uses the merged colortex8 encoding documented in ao.compute.

// receiver_prev_view: reuse the forward push the caller computed for
// AOHistoryWeight.
bool AOReprojectToPrevious(vec3 world_pos, out vec2 previous_uv, out vec3 receiver_prev_view) {
    vec4 previous_view = gbufferPreviousModelView * vec4(world_pos + u_camera_delta, 1.0);
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

// Decodes the EncodeSquaredDepth curve to linear view depth (m). The decode
// constant is FOV-independent; it only changes when near/far change.
float AOHistoryViewDepth(float encoded) {
    return sqrt(max(encoded, 0.0)) * u_squared_depth_decode;
}

// Reconstruct the history tap at its actual previous jittered pixel center.
vec3 AOHistoryViewPosition(vec2 history_uv, vec4 history) {
    vec2 projection_uv = history_uv;
#ifdef TAA
    projection_uv -= u_taa_offset_previous * 0.5;
#endif
    vec2 previous_ray = (projection_uv * 2.0 - 1.0 + gbufferPreviousProjection[2].xy)
        / vec2(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y);
    return vec3(previous_ray, -1.0) * AOHistoryViewDepth(history.b);
}

float AOHistoryWeight(vec3 sample_prev_view, vec3 receiver_prev_view, vec3 receiver_view,
        vec3 normal_world) {
    vec3 delta_world = transpose(mat3(gbufferPreviousModelView))
        * (sample_prev_view - receiver_prev_view);
    // Only displacement off the receiver plane is a depth mismatch; same-surface
    // separation is valid, even on a grazing plane.
    float displacement = abs(dot(delta_world, normal_world));
    float distance_weight = 1.0 - smoothstep(0.0, AO_HISTORY_DISTANCE_LIMIT, displacement);
    if (distance_weight <= 0.0) return 0.0;

    // No previous-normal buffer: project the previous tap's surface into this
    // frame before reading the current normal; jitter substitution is wrong in motion.
    vec3 sample_view = receiver_view + mat3(gbufferModelView) * delta_world;
    if (sample_view.z >= -1.0e-4) return 0.0;
    vec2 normal_uv = ViewToNDC(sample_view).xy * 0.5 + 0.5;
#ifdef TAA
    normal_uv += u_taa_offset * 0.5;
#endif
    if (any(lessThan(normal_uv, vec2(0.0))) || any(greaterThanEqual(normal_uv, vec2(1.0)))) return 0.0;
    ivec2 history_texel = clamp(
        ivec2(normal_uv * u_render_res),
        ivec2(0),
        ivec2(u_render_res) - 1);
    vec3 history_normal = DecodeOctahedralNormal(texelFetch(colortex4, history_texel, 0).xy);
    float normal_weight = smoothstep(
        AO_HISTORY_NORMAL_DOT_FLOOR, 1.0, dot(history_normal, normal_world));

    return distance_weight * normal_weight;
}

// colortex8 tap: R=AO, G=age, B=trust. Do not round history_uv to any texel
// lattice; snapping causes jumps and biased feedback.
vec3 SampleAOHistory(vec3 receiver_prev_view, vec3 receiver_view, vec3 normal_world, vec2 history_uv) {
    vec2 sample_uv = clamp(history_uv, 0.5 * u_render_pixel_size, 1.0 - 0.5 * u_render_pixel_size);
#if defined(TAAU_ACTIVE)
    vec4 history = textureLod(colortex8, SceneTextureUV(sample_uv), 0.0);
#else
    vec4 history = textureLod(colortex8, sample_uv, 0.0);
#endif
    if (!isnan(history.a) || history.g < 1.0 || history.b <= 0.0
            || any(isnan(history.rgb)) || any(isinf(history.rgb))) return vec3(1.0, 0.0, 0.0);
    vec3 sample_prev_view = AOHistoryViewPosition(sample_uv, history);
    float trust = AOHistoryWeight(sample_prev_view, receiver_prev_view, receiver_view,
        normal_world);
    return vec3(DecodeAOHistory(history.r), history.g, trust);
}

// Fresh weight is the capped running average 1/(age+1), settling at
// 1/AO_HISTORY_FRAMES (same law as CloudAccumulate); rejection lifts it toward 1.
float AOAccumulate(float fresh_ao, float hist_ao, float hist_age,
                     float rejection, out float next_age) {
    float pixel_age = min(hist_age, AO_HISTORY_FRAMES) * rejection;
    float base_alpha = 1.0 / min(pixel_age + 1.0, float(AO_HISTORY_FRAMES));
    float alpha = 1.0 - (1.0 - base_alpha) * rejection;
    next_age = pixel_age + 1.0;
    return mix(hist_ao, fresh_ao, alpha);
}

// Only generation reads AO history; reconstruction publishes the full-res
// result without another reprojection.
vec3 ReprojectAOHistory(ivec2 texel, float scene_depth, vec2 normal_oct) {
#if defined(AO_TEMPORAL_ENABLED)
    if (scene_depth < 1.0 && frameCounter > 0) {
        vec2 uv = (vec2(texel) + 0.5) * u_render_pixel_size;
#ifdef TAA
        uv -= u_taa_offset * 0.5;
#endif
        vec3 receiver_view;
        vec3 world_pos = DepthToWorldPosView(uv, scene_depth, receiver_view);
        vec2 history_uv;
        vec3 receiver_prev_view;
        if (AOReprojectToPrevious(world_pos, history_uv, receiver_prev_view)) {
            vec3 normal_world = DecodeOctahedralNormal(normal_oct);
            return SampleAOHistory(receiver_prev_view, receiver_view, normal_world, history_uv);
        }
    }
#endif
    return vec3(1.0, 0.0, 0.0);
}

// Caller issues ReprojectAOHistory before its AO kernel and hands the fetched
// history in here.
vec2 ResolveTemporalAO(vec3 history, float fresh_ao) {
    float next_age = 1.0;
#if defined(AO_TEMPORAL_ENABLED)
    fresh_ao = AOAccumulate(fresh_ao, history.r, history.g, history.b, next_age);
#endif
    return vec2(fresh_ao, next_age);
}

#endif // LIB_LIGHTING_TEMPORAL_AO_GLSL
