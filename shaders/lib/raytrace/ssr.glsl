#ifndef LIB_RAYTRACE_SSR_GLSL
#define LIB_RAYTRACE_SSR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/raytrace/ssr_depth.glsl"

// SSR_OPAQUE_TRACE enables near-plane exits and toward-eye crossings.
#define SSR_REFINE_STEPS 6
#define SSR_TOL_SLOPE 0.1
#define SSR_TOL_BIAS 0.5

struct SSRHit {
    vec3 screen;
    bool valid;
    bool sky;
};

SSRHit SSRMiss() {
    SSRHit hit;
    hit.screen = vec3(0.0);
    hit.valid = false;
    hit.sky = false;
    return hit;
}

bool SSRScreenInside(vec2 uv) {
    // The [0,1] comparisons already reject NaN (unordered) and +-Inf for
    // every input, so an explicit IsFinite sweep is redundant.
    return all(greaterThanEqual(uv, vec2(0.0)))
        && all(lessThanEqual(uv, vec2(1.0)));
}

SSRHit TraceScreenSpaceReflection(vec3 view_origin,
        vec3 view_direction, float jitter, int step_budget, bool allow_sky) {
    SSRHit miss = SSRMiss();
    // Project the origin and the ray direction through clip space once.
    // Moving a view-space distance t along the unit ray adds
    // PROJ.xyz * t to the clip position and -t * dir.z to the clip w, so
    // the projected ray is rational in t and every screen-space crossing
    // solves in closed form (reference stepper structure: one origin, one
    // direction, one exit, one span).
    vec4 origin_clip = gbufferProjection * vec4(view_origin, 1.0);
    // Same value chain as ViewToNDC(origin) * 0.5 + 0.5 (identical operation
    // order), derived from the clip position the ray stepper already needs.
    vec3 start_pos = origin_clip.xyz / -view_origin.z * 0.5 + 0.5;
    vec4 direction_clip = gbufferProjection * vec4(view_direction, 0.0);

    // Screen-edge extent: the smallest forward clip parameter reaching any
    // NDC edge; crossings at or behind the origin fall back to a
    // beyond-far sentinel so the minimum stays forward-facing.
    vec2 edge_near_t = ClipRayScreenCoordT(origin_clip, direction_clip,
        1.0, far + 32.0);
    vec2 edge_far_t = ClipRayScreenCoordT(origin_clip, direction_clip,
        -1.0, far + 32.0);
    float trace_length = min(min(edge_near_t.x, edge_near_t.y),
        min(edge_far_t.x, edge_far_t.y));

#ifdef SSR_OPAQUE_TRACE
    bool toward_eye = view_direction.z > 0.0;
#else
    const bool toward_eye = false;
#endif
    // Choose the forward NDC depth boundary; the far exit is behind toward-eye rays.
    float depth_plane = toward_eye ? -1.0 : 1.0;
    float depth_plane_t = (depth_plane * origin_clip.w - origin_clip.z)
        / (direction_clip.z - depth_plane * direction_clip.w);
    trace_length = min(trace_length, depth_plane_t);
    // March span: one straight (uv, NDC z) chord from the origin to the
    // projected exit point.
    vec4 exit_clip = origin_clip + direction_clip * trace_length;
    vec3 span = exit_clip.xyz / exit_clip.w * 0.5 + 0.5 - start_pos;

    vec3 march_step = span / float(step_budget - 1);
    vec3 sample_pos = start_pos + march_step * jitter;
    float ray_start_depth = -view_origin.z;
    vec3 previous_pos = start_pos;
    float previous_ray_depth = SSRRayDepthFromScreen(start_pos.z);
    float surface_sample = 0.0;
    float ray_depth = previous_ray_depth;
    bool hit_found = false;

    for (int i = 0; i < step_budget; ++i) {
        if (!SSRScreenInside(sample_pos.xy)) break;

        surface_sample = ReadSSRDepthSample(sample_pos.xy);
        ray_depth = SSRRayDepthFromScreen(sample_pos.z);
        // Toward-eye crossings require the previous point behind this surface.
        bool behind_surface = SSRDepthSampleBeforeRay(surface_sample, ray_depth);
        bool depth_crossing = toward_eye
            ? !behind_surface && SSRDepthSampleBeforeRay(surface_sample, previous_ray_depth)
            : behind_surface;
        if (depth_crossing) {
            float surface_view_depth = surface_sample;
#ifndef SSR_QUARTER_DEPTH_ACTIVE
            surface_view_depth = LinearDepthFromScreenDepth(surface_view_depth);
#endif
            // Accept segment/thickness overlap before spending work on refinement.
            float segment_start_depth = LinearDepthFromScreenDepth(
                clamp(previous_pos.z, 0.0, 1.0));
            float segment_end_depth = LinearDepthFromScreenDepth(
                clamp(sample_pos.z, 0.0, 1.0));
            float hit_ray_depth = clamp(surface_view_depth,
                min(segment_start_depth, segment_end_depth),
                max(segment_start_depth, segment_end_depth));
            float travelled = max(hit_ray_depth - ray_start_depth, 0.0);
            if (abs(hit_ray_depth - surface_view_depth)
                    <= SSR_TOL_SLOPE * travelled + SSR_TOL_BIAS) {
                hit_found = true;
                break;
            }
        }

        previous_pos = sample_pos;
        previous_ray_depth = ray_depth;
        sample_pos += march_step;
    }
    // The clipped chord reaches the far plane at the end of the march budget.
    // Classify its last sampled depth once; known sky needs no refinement.
    if (SSRDepthSampleIsSky(surface_sample)) {
        vec3 sky_pos = hit_found ? sample_pos : previous_pos;
        if (!allow_sky || sky_pos.z < 1.0) return miss;
        SSRHit sky_hit;
        sky_hit.screen = vec3(sky_pos.xy, 1.0);
        sky_hit.valid = true;
        sky_hit.sky = true;
        return sky_hit;
    }
    if (!hit_found) return miss;

#ifdef SSR_BISECTION_REFINE
    // Refine the accepted bracket once, including the jittered first step.
    vec3 hit_pos = 0.5 * (previous_pos + sample_pos);
    vec3 refine_step = (sample_pos - previous_pos) * (0.25 - 0.5 * float(toward_eye));
    for (int j = 0; j < SSR_REFINE_STEPS; ++j) {
        float mid_surface = ReadSSRDepthSample(hit_pos.xy);
        float mid_ray_depth = SSRRayDepthFromScreen(hit_pos.z);
#ifdef SSR_QUARTER_DEPTH_ACTIVE
        float depth_delta = mid_ray_depth * mid_surface - 1.0;
#else
        float depth_delta = mid_surface - mid_ray_depth;
#endif
        float refine_sign = sign(depth_delta);
        hit_pos += refine_sign * refine_step;
        refine_step *= 0.5;
    }
#else
    // Interpolate in the affine ray-depth domain, then correct for the
    // candidate's local surface depth without clamping the jittered endpoint.
    float ray_depth_span = ray_depth - previous_ray_depth;
    float span_sign = sign(ray_depth_span);
    float inverse_span = span_sign / max(abs(ray_depth_span), 1e-20);
    // A zero span keeps the midpoint; nonzero spans retain their sign.
#ifdef SSR_QUARTER_DEPTH_ACTIVE
    float surface_depth = 1.0 / surface_sample;
#else
    float surface_depth = surface_sample;
#endif
    float hit_frac = clamp((surface_depth - previous_ray_depth) * inverse_span, 0.0, 1.0);
    vec3 hit_pos = mix(previous_pos, sample_pos, hit_frac);
    float candidate_surface_depth = ReadSSRDepthSample(hit_pos.xy);
#ifdef SSR_QUARTER_DEPTH_ACTIVE
    candidate_surface_depth = 1.0 / candidate_surface_depth;
#endif
    hit_frac = clamp((candidate_surface_depth - previous_ray_depth) * inverse_span, 0.0, 1.0);
    hit_pos = mix(previous_pos, sample_pos, hit_frac);
#endif
    bool hit_sky = SSRDepthSampleIsSky(ReadSSRDepthSample(hit_pos.xy));
    if (hit_sky && (!allow_sky || hit_pos.z < 1.0)) return miss;
    SSRHit hit;
    hit.screen = vec3(hit_pos.xy, hit_sky ? 1.0 : hit_pos.z);
    hit.valid = true;
    hit.sky = hit_sky;
    return hit;
}

#endif // LIB_RAYTRACE_SSR_GLSL
