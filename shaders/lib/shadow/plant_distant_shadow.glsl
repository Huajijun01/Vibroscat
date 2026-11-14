#ifndef LIB_SHADOW_PLANT_DISTANT_SHADOW_GLSL
#define LIB_SHADOW_PLANT_DISTANT_SHADOW_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"

#if defined(SHADOW_PCSS)

struct PlantShadowEstimate {
    float visibility;
    // Negative depth marks a blocker after the receiver's initial segment.
    float sss_depth;
};

float PlantMapConfidence(vec3 shadow_clip, vec3 view_pos) {
    float extent = max(max(abs(shadow_clip.x), abs(shadow_clip.y)),
        length(view_pos) / min(shadowDistance, far));
    return 1.0 - smoothstep(SHADOW_SSS_FADE_START, 1.0, extent);
}

float PlantDistantPrior(float skylight) {
    float sky = saturate(skylight);
    return sky * sky;
}

// Depth-only projected ray: one initial tissue segment, then external shelter.
// Occupancy tolerance 0..20 m view depth; exit distance scales by 0.2 (transport units).
PlantShadowEstimate TracePlantDistantShadow(vec3 receiver_view,
        vec3 light_view, vec2 jitter_uv, float stbn_dither, float maximum_reach_m) {
    PlantShadowEstimate result;
    result.visibility = 1.0;
    result.sss_depth = 0.0;
    vec4 origin_clip = ViewToClip(gbufferProjection, receiver_view);
    vec3 origin_ndc = origin_clip.xyz / origin_clip.w;
    vec4 light_clip = gbufferProjection * vec4(light_view, 0.0);
    vec3 direction = normalize(light_clip.xyz - origin_ndc * light_clip.w);
    vec3 origin_screen = origin_ndc * 0.5 + 0.5;
    vec3 boundary = step(vec3(0.0), direction);
    vec3 boundary_distance = abs(boundary - origin_screen)
        / max(abs(direction), vec3(1.0e-6));
    float ray_length = min(min(boundary_distance.x, boundary_distance.y), boundary_distance.z);
    vec4 end_clip = origin_clip + maximum_reach_m * light_clip;
    if (end_clip.w > 0.0) {
        vec3 end_screen = end_clip.xyz / end_clip.w * 0.5 + 0.5;
        ray_length = min(ray_length, length(end_screen - origin_screen));
    }
    float origin_offset = min(length(u_render_pixel_size), ray_length);
    vec3 ray_position = origin_screen + origin_offset * direction;
    // Twelve geometric intervals with ratio two: sum(2^i, i=0..11)=4095.
    vec3 ray_step = direction * ((ray_length - origin_offset) / 4095.0);
    bool initial_segment = true;
    for (int i = 0; i < 12; ++i) {
        vec3 sample_screen = ray_position + stbn_dither * ray_step;
        ray_position += ray_step;
        ray_step *= 2.0;
        vec2 sample_uv = sample_screen.xy + jitter_uv;
        if (any(lessThan(vec3(sample_uv, sample_screen.z), vec3(0.0)))
                || any(greaterThanEqual(vec3(sample_uv, sample_screen.z), vec3(1.0)))) break;
        float screen_depth = texelFetch(depthtex2, ivec2(sample_uv * u_render_res), 0).r;
        float gap_m = LinearDepthFromScreenDepth(sample_screen.z)
            - LinearDepthFromScreenDepth(screen_depth);
        bool inside = gap_m > 0.0 && gap_m < 20.0;
        if (inside) result.visibility = 0.0;
        if (initial_segment) {
            if (!inside) {
                vec3 exit_view = NDCToView(sample_screen * 2.0 - 1.0);
                result.sss_depth = 0.2 * distance(receiver_view, exit_view);
                initial_segment = false;
            }
        } else if (inside) {
            result.sss_depth = -1.0;
            break;
        }
    }
    return result;
}

#else

// At most twelve point depth reads per ray, no material/normal data;
// misses do not prove light.
struct PlantShadowEstimate {
    float blocking_confidence;
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
        vec3 receiver_normal_view, vec3 light_view, vec2 jitter_uv,
        float stbn_dither, float maximum_reach_m) {
    PlantShadowEstimate result;
    result.blocking_confidence = 0.0;
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
    vec4 clip1 = clip0 + ray_end_m * clip_direction;
    vec2 uv0 = clip0.xy / clip0.w * 0.5 + 0.5;
    vec2 uv1 = clip1.xy / clip1.w * 0.5 + 0.5;
    vec2 span_pixels = abs(uv1 - uv0) * u_render_res;
    float major_pixels = max(span_pixels.x, span_pixels.y);
    if (major_pixels < 2.0) return result;
    int steps = min(12, int(ceil(major_pixels)));
    float inverse_steps = 1.0 / float(steps);
    float k0 = 1.0 / clip0.w;
    float k1 = 1.0 / clip1.w;
    float self_radius_m = clamp(2.0 * receiver_pixel_m, 0.02, 0.25);
    float plane_epsilon_m = clamp(0.25 * receiver_pixel_m, 0.002, 0.03);
    float span_confidence = smoothstep(2.0, 8.0, major_pixels);
    ivec2 previous_texel = ivec2(-1);
    for (int i = 0; i < 12; ++i) {
        if (i >= steps) break;
        float fraction = (float(i) + stbn_dither) * inverse_steps;
        vec2 sample_uv = mix(uv0, uv1, fraction);
        ivec2 texel = ivec2(floor((sample_uv + jitter_uv) * u_render_res));
        if (any(lessThan(texel, ivec2(0))) || any(greaterThanEqual(texel, ivec2(u_render_res)))) continue;
        if (all(equal(texel, previous_texel))) {
            continue;
        }
        previous_texel = texel;
        // Iris copies opaque depth before hand/deferred: this layer excludes
        // hand geometry without ID reads.
        float screen_depth = texelFetch(depthtex2, texel, 0).r;
        if (screen_depth >= 1.0) continue;
        float surface_depth_m = LinearDepthFromScreenDepth(screen_depth);
        // Reciprocal W gives exact point depth (clip W is -view Z).
        float ray_depth_m = 1.0 / mix(k0, k1, fraction);
        float gap_m = ray_depth_m - surface_depth_m;
        float quantum_m = PlantDepthQuantum(surface_depth_m);
        float slab_m = clamp(max(2.0 * PlantPixelWorld(surface_depth_m),
            2.0 * quantum_m), 0.02, 0.25);
        if (gap_m <= origin_bias_m || gap_m >= slab_m) continue;
        // Only near hits need receiver-plane rejection; the normal comes from
        // direct lighting, no texture read.
        if (abs(surface_depth_m + receiver_view.z) <= self_radius_m) {
            vec2 texel_uv = (vec2(texel) + 0.5) / u_render_res - jitter_uv;
            vec3 surface_view = NDCToView(vec3(texel_uv * 2.0 - 1.0, screen_depth * 2.0 - 1.0));
            vec3 separation = surface_view - receiver_view;
            if (dot(separation, separation) <= self_radius_m * self_radius_m
                    && abs(dot(separation, receiver_normal_view)) <= plane_epsilon_m) {
                continue;
            }
        }
        result.blocking_confidence = span_confidence
            * smoothstep(0.0, 4.0, PlantBorderPixels(sample_uv))
            * (1.0 - smoothstep(0.5 * slab_m, slab_m, gap_m))
            * (1.0 - smoothstep(0.0625, 0.25, quantum_m));
        break;
    }
    return result;
}

#endif

#endif // LIB_SHADOW_PLANT_DISTANT_SHADOW_GLSL
