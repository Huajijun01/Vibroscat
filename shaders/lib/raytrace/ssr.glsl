#ifndef LIB_RAYTRACE_SSR_GLSL
#define LIB_RAYTRACE_SSR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/raytrace/ssr_depth.glsl"

// Shared screen-space reflection marcher. Both water and opaque reflection
// use the same depth-crossing rule; only their step budget and treatment
// of a far-plane miss differ.
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
    vec3 start_pos = ViewToNDC(view_origin) * 0.5 + 0.5;
    vec4 origin_clip = gbufferProjection * vec4(view_origin, 1.0);
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

    // Far-plane exit: the clip parameter where the projected NDC z
    // reaches 1.
    float far_plane_t = (origin_clip.w - origin_clip.z)
        / (direction_clip.z - direction_clip.w);
    trace_length = min(trace_length, far_plane_t);
    // March span: one straight (uv, NDC z) chord from the origin to the
    // projected exit point.
    vec4 exit_clip = origin_clip + direction_clip * trace_length;
    vec3 span = exit_clip.xyz / exit_clip.w * 0.5 + 0.5 - start_pos;

    vec3 march_step = span / float(step_budget - 1);
    vec3 sample_pos = start_pos + march_step * jitter;
    float ray_start_depth = -view_origin.z;
    vec3 previous_pos = start_pos;

    for (int i = 0; i < step_budget; ++i) {
        if (!SSRScreenInside(sample_pos.xy)) break;

        float surface_sample = ReadSSRDepthSample(sample_pos.xy);
        float ray_depth = SSRRayDepthFromScreen(sample_pos.z);
        if (SSRDepthSampleBeforeRay(surface_sample, ray_depth)) {
#ifdef SSR_BISECTION_REFINE
            // Bisection locates the first depth crossing; this trace
            // performs no thickness or normal rejection. The bracket is
            // carried as sample points; each midpoint is their average.
            vec3 lo_pos = previous_pos;
            vec3 hi_pos = sample_pos;
            for (int j = 0; j < SSR_REFINE_STEPS; ++j) {
                vec3 mid_pos = 0.5 * (lo_pos + hi_pos);
                float mid_surface = ReadSSRDepthSample(mid_pos.xy);
                float mid_ray_depth = SSRRayDepthFromScreen(mid_pos.z);
                if (SSRDepthSampleBeforeRay(mid_surface, mid_ray_depth)) {
                    hi_pos = mid_pos;
                } else {
                    lo_pos = mid_pos;
                }
            }

            vec3 hit_pos = 0.5 * (lo_pos + hi_pos);
#else
            // Intersect in the affine ray-depth domain, without clamping the
            // jittered endpoint. Reuse the old previous-point fetch at the
            // candidate instead, correcting for the local surface depth.
            float ray_lo_depth = SSRRayDepthFromScreen(previous_pos.z);
            float ray_depth_span = ray_depth - ray_lo_depth;
            float inverse_span = ray_depth_span != 0.0 ? 1.0 / ray_depth_span : 0.0;
#ifdef SSR_QUARTER_DEPTH_ACTIVE
            float surface_depth = 1.0 / surface_sample;
#else
            float surface_depth = surface_sample;
#endif
            float hit_frac = ray_depth_span != 0.0
                ? clamp((surface_depth - ray_lo_depth) * inverse_span, 0.0, 1.0)
                : 0.5;
            vec3 hit_pos = mix(previous_pos, sample_pos, hit_frac);
            float candidate_surface_depth = ReadSSRDepthSample(hit_pos.xy);
#ifdef SSR_QUARTER_DEPTH_ACTIVE
            candidate_surface_depth = 1.0 / candidate_surface_depth;
#endif
            hit_frac = ray_depth_span != 0.0
                ? clamp((candidate_surface_depth - ray_lo_depth) * inverse_span, 0.0, 1.0)
                : 0.5;
            hit_pos = mix(previous_pos, sample_pos, hit_frac);
#endif
            float hit_surface_depth = ReadSSRDepthSample(hit_pos.xy);
#ifndef SSR_QUARTER_DEPTH_ACTIVE
            hit_surface_depth = LinearDepthFromScreenDepth(hit_surface_depth);
#endif
            float hit_ray_depth = LinearDepthFromScreenDepth(
                clamp(hit_pos.z, 0.0, 1.0));
            float travelled = max(hit_ray_depth - ray_start_depth, 0.0);
            if (abs(hit_ray_depth - hit_surface_depth)
                    <= SSR_TOL_SLOPE * travelled + SSR_TOL_BIAS) {
                SSRHit hit;
                hit.screen = hit_pos;
                hit.valid = true;
                hit.sky = false;
                return hit;
            }
        }

        if (sample_pos.z >= 1.0) {
            if (allow_sky && SSRDepthSampleIsSky(surface_sample)) {
                SSRHit sky_hit;
                sky_hit.screen = sample_pos;
                sky_hit.valid = true;
                sky_hit.sky = true;
                return sky_hit;
            }
            break;
        }

        previous_pos = sample_pos;
        sample_pos += march_step;
    }
    return miss;
}

#endif // LIB_RAYTRACE_SSR_GLSL
