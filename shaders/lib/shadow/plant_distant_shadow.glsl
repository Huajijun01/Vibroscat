#ifndef LIB_SHADOW_PLANT_DISTANT_SHADOW_GLSL
#define LIB_SHADOW_PLANT_DISTANT_SHADOW_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"

#if SHADOW_SSS_DEBUG >= 11
#define PLANT_SHADOW_DIAGNOSTICS
#endif

// Strict per-ray budget: ten coarse depth reads, at most two candidate slots,
// and one changed-texel validation per slot. Packet reads are ID or geometric
// normal fetches; at most eight per ray. Misses supply no evidence of light.
struct PlantShadowEstimate {
    float blocking_confidence;
#if defined(PLANT_SHADOW_DIAGNOSTICS)
    int depth_reads;
    int packet_reads;
    int coarse_reads;
    int validation_reads;
    int candidate_count;
    bool valid_projected_extent;
    bool rejected_candidate;
#endif
};

float PlantPixelWorld(float view_depth) {
    return 2.0 * view_depth / u_pixel_world_scale;
}

float PlantDepthQuantum(float view_depth) {
    return 2.0 * abs(gbufferProjectionInverse[2][3]) * view_depth * view_depth
        * 0.000000059604644775390625;
}

float PlantBorderPixels(vec2 scene_uv) {
    vec2 border = min(scene_uv, vec2(1.0) - scene_uv) * u_render_res;
    return min(border.x, border.y);
}

void PlantClipEnd(float origin_plane, float direction_plane, inout float ray_end_m) {
    if (direction_plane < 0.0) ray_end_m = min(ray_end_m, origin_plane / -direction_plane);
}

vec3 PlantRayPosition(vec3 q0, vec3 q1, float k0, float k1, float fraction) {
    return mix(q0, q1, fraction) / mix(k0, k1, fraction);
}

bool PlantFetchDepth(ivec2 texel, out float screen_depth) {
    if (any(lessThan(texel, ivec2(0))) || any(greaterThanEqual(texel, ivec2(u_render_res)))) {
        screen_depth = 1.0;
        return false;
    }
    screen_depth = texelFetch(depthtex0, texel, 0).r;
    return true;
}

bool PlantLocalReceiver(vec3 point_view, vec3 normal_view, int hit_id,
        vec3 receiver_view, vec3 receiver_normal_view, int receiver_id,
        float self_radius_m, float plane_epsilon_m) {
    vec3 separation = point_view - receiver_view;
    return hit_id == receiver_id
        && abs(dot(normal_view, receiver_normal_view)) >= 0.95
        && dot(separation, separation) <= self_radius_m * self_radius_m
        && abs(dot(separation, receiver_normal_view)) <= plane_epsilon_m;
}

float PlantMapConfidence(vec3 shadow_clip, vec3 view_pos) {
    float clip_edge = max(abs(shadow_clip.x), abs(shadow_clip.y));
    float xy = 1.0 - smoothstep(SHADOW_SSS_FADE_START, 1.0, clip_edge);
    float z = 1.0 - smoothstep(SHADOW_SSS_FADE_START, 1.0, abs(shadow_clip.z));
    float radius = 1.0 - smoothstep(SHADOW_SSS_FADE_START, 1.0,
        length(view_pos) / min(shadowDistance, far));
    return xy * z * radius;
}

float PlantDistantPrior(float skylight) {
    float sky = saturate(skylight);
    return sky * sky;
}

PlantShadowEstimate TracePlantDistantShadow(vec3 receiver_view,
        vec3 receiver_normal_view, int receiver_id, vec3 light_view,
        vec2 jitter_uv, float stbn_dither, float maximum_reach_m) {
    PlantShadowEstimate result;
    result.blocking_confidence = 0.0;
#if defined(PLANT_SHADOW_DIAGNOSTICS)
    result.depth_reads = 0;
    result.packet_reads = 0;
    result.coarse_reads = 0;
    result.validation_reads = 0;
    result.candidate_count = 0;
    result.valid_projected_extent = false;
    result.rejected_candidate = false;
#endif
    float receiver_pixel_m = PlantPixelWorld(-receiver_view.z);
    float origin_bias_m = clamp(0.25 * receiver_pixel_m, 0.002, 0.05);
    vec3 p0 = receiver_view + origin_bias_m * light_view;
    vec4 clip0 = gbufferProjection * vec4(p0, 1.0);
    vec4 clip_direction = gbufferProjection * vec4(light_view, 0.0);
    if (clip0.w <= 0.0 || any(greaterThan(abs(clip0.xyz), vec3(clip0.w)))) return result;
    float ray_end_m = maximum_reach_m - origin_bias_m;
    PlantClipEnd(clip0.w + clip0.x, clip_direction.w + clip_direction.x, ray_end_m);
    PlantClipEnd(clip0.w - clip0.x, clip_direction.w - clip_direction.x, ray_end_m);
    PlantClipEnd(clip0.w + clip0.y, clip_direction.w + clip_direction.y, ray_end_m);
    PlantClipEnd(clip0.w - clip0.y, clip_direction.w - clip_direction.y, ray_end_m);
    PlantClipEnd(clip0.w + clip0.z, clip_direction.w + clip_direction.z, ray_end_m);
    PlantClipEnd(clip0.w - clip0.z, clip_direction.w - clip_direction.z, ray_end_m);
    if (ray_end_m <= 0.0) return result;
    vec3 p1 = p0 + ray_end_m * light_view;
    vec4 clip1 = clip0 + ray_end_m * clip_direction;
    vec2 uv0 = clip0.xy / clip0.w * 0.5 + 0.5;
    vec2 uv1 = clip1.xy / clip1.w * 0.5 + 0.5;
    vec2 span_pixels = abs(uv1 - uv0) * u_render_res;
    float major_pixels = max(span_pixels.x, span_pixels.y);
    if (major_pixels < 2.0) return result;
#if defined(PLANT_SHADOW_DIAGNOSTICS)
    result.valid_projected_extent = true;
#endif
    int steps = min(10, int(ceil(major_pixels)));
    float k0 = 1.0 / clip0.w;
    float k1 = 1.0 / clip1.w;
    vec3 q0 = p0 * k0;
    vec3 q1 = p1 * k1;
    float self_radius_m = clamp(2.0 * receiver_pixel_m, 0.02, 0.25);
    float plane_epsilon_m = clamp(0.25 * receiver_pixel_m, 0.002, 0.03);
    float span_confidence = smoothstep(2.0, 8.0, major_pixels);
    int candidates = 0;
    ivec2 previous_texel = ivec2(-1);
    for (int i = 0; i < 10; ++i) {
        if (i >= steps || candidates >= 2) break;
        float interval0 = float(i) / float(steps);
        float interval1 = float(i + 1) / float(steps);
        float fraction = (float(i) + stbn_dither) / float(steps);
        vec2 sample_uv = mix(uv0, uv1, fraction);
        ivec2 texel = ivec2(floor((sample_uv + jitter_uv) * u_render_res));
        if (all(equal(texel, previous_texel))) continue;
        float screen_depth;
        if (!PlantFetchDepth(texel, screen_depth)) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
            result.rejected_candidate = true;
#endif
            continue;
        }
#if defined(PLANT_SHADOW_DIAGNOSTICS)
        ++result.depth_reads;
        ++result.coarse_reads;
#endif
        previous_texel = texel;
        if (screen_depth >= 1.0) continue;
        float surface_depth_m = LinearDepthFromScreenDepth(screen_depth);
        float quantum_m = PlantDepthQuantum(surface_depth_m);
        float precision_confidence = 1.0 - smoothstep(0.0625, 0.25, quantum_m);
        float slab_m = clamp(max(2.0 * PlantPixelWorld(surface_depth_m),
            2.0 * quantum_m), 0.02, 0.25);
        float depth0_m = -PlantRayPosition(q0, q1, k0, k1, interval0).z;
        float depth1_m = -PlantRayPosition(q0, q1, k0, k1, interval1).z;
        if (surface_depth_m < min(depth0_m, depth1_m) - slab_m
                || surface_depth_m > max(depth0_m, depth1_m) + slab_m) continue;
        if (precision_confidence <= 0.0 || candidates >= 2) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
            result.rejected_candidate = true;
#endif
            continue;
        }
        ++candidates;
#if defined(PLANT_SHADOW_DIAGNOSTICS)
        ++result.candidate_count;
        ++result.packet_reads;
#endif
        int hit_id = int(texelFetch(colortex1, texel, 0).a * 255.0 + 0.5);
        if (hit_id == 64) continue;
#if defined(PLANT_SHADOW_DIAGNOSTICS)
        ++result.packet_reads;
#endif
        vec3 hit_normal_view = mat3(gbufferModelView)
            * DecodeOctahedralNormal(texelFetch(colortex4, texel, 0).xy);
        vec2 texel_uv = (vec2(texel) + 0.5) / u_render_res - jitter_uv;
        vec3 surface_view = NDCToView(vec3(texel_uv * 2.0 - 1.0, screen_depth * 2.0 - 1.0));
        if (PlantLocalReceiver(surface_view, hit_normal_view, hit_id, receiver_view,
                receiver_normal_view, receiver_id, self_radius_m, plane_epsilon_m)) continue;
        float denominator = dot(hit_normal_view, light_view);
        if (abs(denominator) < 0.02) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
            result.rejected_candidate = true;
#endif
            continue;
        }
        float hit_t_m = dot(hit_normal_view, surface_view - p0) / denominator;
        if (hit_t_m < 0.0 || hit_t_m > ray_end_m) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
            result.rejected_candidate = true;
#endif
            continue;
        }
        vec3 hit_view = p0 + hit_t_m * light_view;
        vec2 hit_uv = (gbufferProjection * vec4(hit_view, 1.0)).xy / -hit_view.z * 0.5 + 0.5;
        vec2 uv_delta = uv1 - uv0;
        float hit_fraction = abs(uv_delta.x) >= abs(uv_delta.y)
            ? (hit_uv.x - uv0.x) / uv_delta.x : (hit_uv.y - uv0.y) / uv_delta.y;
        if (hit_fraction < interval0 || hit_fraction > interval1) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
            result.rejected_candidate = true;
#endif
            continue;
        }
        ivec2 validation_texel = ivec2(floor((hit_uv + jitter_uv) * u_render_res));
        float validation_depth = screen_depth;
        int validation_id = hit_id;
        vec3 validation_normal_view = hit_normal_view;
        if (any(notEqual(validation_texel, texel))) {
            if (!PlantFetchDepth(validation_texel, validation_depth)) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
                result.rejected_candidate = true;
#endif
                continue;
            }
#if defined(PLANT_SHADOW_DIAGNOSTICS)
            ++result.depth_reads;
            ++result.validation_reads;
#endif
            if (validation_depth >= 1.0) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
                result.rejected_candidate = true;
#endif
                continue;
            }
#if defined(PLANT_SHADOW_DIAGNOSTICS)
            ++result.packet_reads;
#endif
            validation_id = int(texelFetch(colortex1, validation_texel, 0).a * 255.0 + 0.5);
            if (validation_id == 64) continue;
        }
        vec2 validation_uv = (vec2(validation_texel) + 0.5) / u_render_res - jitter_uv;
        vec3 validation_surface_view = NDCToView(vec3(validation_uv * 2.0 - 1.0, validation_depth * 2.0 - 1.0));
        // A changed validation normal is needed only if the inexpensive local
        // receiver predicates could exclude this surface. Keep this before the
        // depth-residual rejection, matching the full packet classifier.
        vec3 separation = validation_surface_view - receiver_view;
        if (validation_id == receiver_id
                && dot(separation, separation) <= self_radius_m * self_radius_m
                && abs(dot(separation, receiver_normal_view)) <= plane_epsilon_m) {
            if (any(notEqual(validation_texel, texel))) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
                ++result.packet_reads;
#endif
                validation_normal_view = mat3(gbufferModelView)
                    * DecodeOctahedralNormal(texelFetch(colortex4, validation_texel, 0).xy);
            }
            if (abs(dot(validation_normal_view, receiver_normal_view)) >= 0.95) continue;
        }
        float error_m = abs(LinearDepthFromScreenDepth(validation_depth) + hit_view.z);
        if (error_m >= slab_m) {
#if defined(PLANT_SHADOW_DIAGNOSTICS)
            result.rejected_candidate = true;
#endif
            continue;
        }
        result.blocking_confidence = span_confidence * smoothstep(0.0, 4.0, PlantBorderPixels(hit_uv))
            * (1.0 - smoothstep(0.5 * slab_m, slab_m, error_m))
            * smoothstep(0.02, 0.08, abs(denominator)) * precision_confidence;
        return result;
    }
    return result;
}

#endif // LIB_SHADOW_PLANT_DISTANT_SHADOW_GLSL
