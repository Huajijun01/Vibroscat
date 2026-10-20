#ifndef LIB_LIGHTING_TEMPORAL_AO_GLSL
#define LIB_LIGHTING_TEMPORAL_AO_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/lighting/ao_history.glsl"
#include "/lib/raytrace/ssr_depth.glsl"

// ============================================================================
// AO temporal accumulation and missing-surface history helpers.
// ============================================================================
// History in the merged colortex8 (R = EncodeAOHistory(AO), G = age, B = view depth
// via the EncodeSSRDepth squared curve, A = NaN "not cloud"); this module
// provides per-pixel math only. Half-res generation accumulates before the
// depth/normal-guided full-res reconstruction on the current sample lattice.
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

// Decode the stored history depth (EncodeSSRDepth curve) back to linear view
// depth in meters. The clip-depth reference is projection-depth-row derived
// and therefore FOV-independent; it only moves when near/far change, which
// reloads the world and reseeds the history anyway.
float AOHistoryViewDepth(float encoded) {
    return sqrt(max(encoded, 0.0)) * u_ssr_depth_decode;
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
    // Use the stored linear depth directly: depth -> screen -> view would
    // introduce two reciprocal operations that cancel algebraically.
    vec2 previous_ray = (projection_uv * 2.0 - 1.0 + gbufferPreviousProjection[2].xy)
        / vec2(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y);
    vec3 previous_view = vec3(previous_ray, -1.0) * AOHistoryViewDepth(history.b);
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

// R=AO, G=age, B=total trust. Validate individual history texels before
// interpolation: a blended depth or normal cannot identify a foreign tap.
vec3 SampleAOHistory(vec3 receiver_prev_view, vec3 normal_world, vec2 history_uv) {
    vec2 filter_position = history_uv * u_render_res - 0.5;
    ivec2 base_texel = ivec2(floor(filter_position));
    vec2 fraction = fract(filter_position);
    vec2 history_sum = vec2(0.0);
    float weight_sum = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            vec2 weights = mix(vec2(1.0) - fraction, fraction, bvec2(x != 0, y != 0));
            float weight = weights.x * weights.y;
            if (weight <= 0.0) continue;
            ivec2 sample_texel = base_texel + ivec2(x, y);
            if (any(lessThan(sample_texel, ivec2(0)))
                    || any(greaterThanEqual(sample_texel, ivec2(u_render_res)))) continue;
            vec4 history = texelFetch(colortex8, sample_texel, 0);
            if (!isnan(history.a) || history.g < 1.0 || history.b <= 0.0
                    || any(isnan(history.rgb)) || any(isinf(history.rgb))) continue;
            vec2 sample_uv = (vec2(sample_texel) + 0.5) * u_render_pixel_size;
            weight *= AOHistoryWeight(receiver_prev_view, normal_world, sample_uv, history);
            history_sum += history.rg * weight;
            weight_sum += weight;
        }
    }
    return weight_sum > 1.0e-5 ? vec3(DecodeAOHistory(history_sum.x / weight_sum),
        history_sum.y / weight_sum, weight_sum) : vec3(1.0, 0.0, 0.0);
}

// Hole filling copies one validated estimate; it does not perform another
// temporal blend. Keeping this discrete avoids filtering a second neighborhood.
vec3 SampleAOHistoryNearest(vec3 receiver_prev_view, vec3 normal_world, vec2 history_uv) {
    ivec2 sample_texel = clamp(ivec2(history_uv * u_render_res), ivec2(0), ivec2(u_render_res) - 1);
    vec4 history = texelFetch(colortex8, sample_texel, 0);
    if (!isnan(history.a) || history.g < 1.0 || history.b <= 0.0
            || any(isnan(history.rgb)) || any(isinf(history.rgb))) return vec3(1.0, 0.0, 0.0);
    vec2 sample_uv = (vec2(sample_texel) + 0.5) * u_render_pixel_size;
    float trust = AOHistoryWeight(receiver_prev_view, normal_world, sample_uv, history);
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

// Both AO stages read the previous full-res history, before deferred1 publishes
// this frame. Missing lattice support reuses this history without aging it.
vec3 ReprojectAOHistory(ivec2 texel, float scene_depth, vec2 normal_oct, bool interpolate) {
#if defined(AO_TEMPORAL_ENABLED)
    if (scene_depth < 1.0 && frameCounter > 0) {
        vec2 uv = (vec2(texel) + 0.5) * u_render_pixel_size;
#ifdef TAA
        uv -= u_taa_offset * 0.5;
#endif
        vec3 world_pos = DepthToWorldPos(uv, scene_depth);
        vec2 history_uv;
        vec3 receiver_prev_view;
        if (AOReprojectToPrevious(world_pos, history_uv, receiver_prev_view)) {
            vec3 normal_world = DecodeOctahedralNormal(normal_oct);
            return interpolate ? SampleAOHistory(receiver_prev_view, normal_world, history_uv)
                : SampleAOHistoryNearest(receiver_prev_view, normal_world, history_uv);
        }
    }
#endif
    return vec3(1.0, 0.0, 0.0);
}

vec2 ResolveTemporalAO(ivec2 texel, float scene_depth, vec2 normal_oct, float fresh_ao) {
    float next_age = 1.0;
#if defined(AO_TEMPORAL_ENABLED)
    vec3 history = ReprojectAOHistory(texel, scene_depth, normal_oct, true);
    fresh_ao = AOAccumulate(fresh_ao, history.r, history.g, history.b, next_age);
#endif
    return vec2(fresh_ao, next_age);
}

#endif // LIB_LIGHTING_TEMPORAL_AO_GLSL
