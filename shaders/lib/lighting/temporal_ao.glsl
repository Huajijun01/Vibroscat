#ifndef LIB_LIGHTING_TEMPORAL_AO_GLSL
#define LIB_LIGHTING_TEMPORAL_AO_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/core/render_scale.glsl"
#include "/lib/lighting/ao_history.glsl"
#include "/lib/raytrace/ssr_depth.glsl"

// ============================================================================
// AO temporal accumulation at the fixed half-resolution receivers.
// ============================================================================
// History in the merged colortex8 (R = EncodeAOHistory(AO), G = age, B = view depth
// via the EncodeSquaredDepth curve, A = NaN "not cloud"); this module
// provides per-pixel math only. Half-res generation accumulates before the
// depth/normal-guided full-res reconstruction on the fixed sample lattice.
// Rejection trusts the history only within the distance limit and the normal
// dot floor (AOHistoryWeight); both ramp smoothly to zero.

// Reproject a camera-relative world position into the previous jittered scene UV.
// Also outputs the receiver in the previous frame's view space for
// AOHistoryWeight (the forward push the reprojection already computed).
// Returns false when the point is behind the previous camera or off-screen.
bool AOReprojectToPrevious(vec3 world_pos, out vec2 previous_uv, out vec3 receiver_prev_view) {
    vec3 camera_delta = u_camera_delta;
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

// Decode the stored history depth (EncodeSquaredDepth curve) back to linear view
// depth in meters. The clip-depth reference is projection-depth-row derived
// and therefore FOV-independent; it only moves when near/far change, which
// reloads the world and reseeds the history anyway.
float AOHistoryViewDepth(float encoded) {
    return sqrt(max(encoded, 0.0)) * u_squared_depth_decode;
}

// Reconstruct the history tap at its actual previous jittered pixel center.
vec3 AOHistoryViewPosition(vec2 history_uv, vec4 history) {
    vec2 projection_uv = history_uv;
#ifdef TAA
    projection_uv -= u_taa_offset_previous * 0.5;
#endif
    // Use the stored linear depth directly: depth -> screen -> view would
    // introduce two reciprocal operations that cancel algebraically.
    vec2 previous_ray = (projection_uv * 2.0 - 1.0 + gbufferPreviousProjection[2].xy)
        / vec2(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y);
    return vec3(previous_ray, -1.0) * AOHistoryViewDepth(history.b);
}

float AOHistoryWeight(vec3 sample_prev_view, vec3 receiver_prev_view, vec3 receiver_view,
        vec3 normal_world) {
    // Reuse the world-space displacement for both checks. Moving the previous
    // rotation across the dot product avoids transforming the normal as well.
    vec3 delta_world = transpose(mat3(gbufferPreviousModelView))
        * (sample_prev_view - receiver_prev_view);
    // The interpolation taps lie on different rays. Their separation along
    // the same surface is valid, especially on a grazing plane; only the
    // displacement away from the receiver plane is a depth mismatch.
    float displacement = abs(dot(delta_world, normal_world));
    float distance_weight = 1.0 - smoothstep(0.0, AO_HISTORY_DISTANCE_LIMIT, displacement);
    if (distance_weight <= 0.0) return 0.0;

    // There is no previous-normal buffer. Project the previous tap's actual
    // surface back into THIS frame before reading the current normal proxy.
    // Merely replacing the jitter at a previous-frame UV is wrong in motion.
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

// R=AO, G=age, B=trust. One hardware bilinear lookup of the reconstructed
// full-res history preserves fractional motion. Do not round history_uv to
// either the full-res or half-res lattice: that causes jumps and biased feedback.
// Geometric validation runs once at this continuous sample position.
vec3 SampleAOHistory(vec3 receiver_prev_view, vec3 receiver_view, vec3 normal_world, vec2 history_uv) {
    vec2 sample_uv = clamp(history_uv, 0.5 * u_render_pixel_size, 1.0 - 0.5 * u_render_pixel_size);
    vec4 history = textureLod(colortex8, SceneTextureUV(sample_uv), 0.0);
    if (!isnan(history.a) || history.g < 1.0 || history.b <= 0.0
            || any(isnan(history.rgb)) || any(isinf(history.rgb))) return vec3(1.0, 0.0, 0.0);
    vec3 sample_prev_view = AOHistoryViewPosition(sample_uv, history);
    float trust = AOHistoryWeight(sample_prev_view, receiver_prev_view, receiver_view,
        normal_world);
    return vec3(DecodeAOHistory(history.r), history.g, trust);
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

// Only generation reads previous AO history; reconstruction publishes this
// frame's full-resolution result without another reprojection or hole fill.
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

vec2 ResolveTemporalAO(ivec2 texel, float scene_depth, vec2 normal_oct, float fresh_ao) {
    float next_age = 1.0;
#if defined(AO_TEMPORAL_ENABLED)
    vec3 history = ReprojectAOHistory(texel, scene_depth, normal_oct);
    fresh_ao = AOAccumulate(fresh_ao, history.r, history.g, history.b, next_age);
#endif
    return vec2(fresh_ao, next_age);
}

#endif // LIB_LIGHTING_TEMPORAL_AO_GLSL
