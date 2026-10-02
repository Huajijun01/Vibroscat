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

    float step_length = 1.0 / float(step_budget - 1);
    float sample_t = step_length * (jitter);
    float ray_start_depth = -view_origin.z;
    float previous_t = 0.0;
    vec3 previous_pos = start_pos;

    for (int i = 0; i < step_budget; ++i) {
        float t = sample_t;
        vec3 ray_pos = start_pos + span * sample_t;
        if (!SSRScreenInside(ray_pos.xy)) break;

        float surface_sample = ReadSSRDepthSample(ray_pos.xy);
        float ray_depth = SSRRayDepthFromScreen(ray_pos.z);
        if (SSRDepthSampleBeforeRay(surface_sample, ray_depth)) {
#ifdef SSR_BISECTION_REFINE
            // Bisection locates the first depth crossing; this trace
            // performs no thickness or normal rejection.
            float lo = previous_t;
            float hi = t;
            vec3 lo_pos = previous_pos;
            vec3 hi_pos = ray_pos;
            for (int j = 0; j < SSR_REFINE_STEPS; ++j) {
                float mid_t = 0.5 * (lo + hi);
                vec3 mid_pos = start_pos + span * mid_t;
                float mid_surface = ReadSSRDepthSample(mid_pos.xy);
                float mid_ray_depth = SSRRayDepthFromScreen(mid_pos.z);
                if (SSRDepthSampleBeforeRay(mid_surface, mid_ray_depth)) {
                    hi = mid_t;
                    hi_pos = mid_pos;
                } else {
                    lo = mid_t;
                    lo_pos = mid_pos;
                }
            }

            vec3 hit_pos = 0.5 * (lo_pos + hi_pos);
#else
            // Without bisection, interpolate the crossing inside the step:
            // convert both straddling samples to linear view depth and take
            // the fraction where the ray meets the surface. One extra depth
            // fetch replaces the six bisection fetches, and the estimate
            // tracks the crossing itself instead of the jittered sample
            // grid, so hit positions stay temporally stable.
            float surface_lo_depth = ReadSSRDepthSample(previous_pos.xy);
#ifndef SSR_QUARTER_DEPTH_ACTIVE
            surface_lo_depth = LinearDepthFromScreenDepth(surface_lo_depth);
#endif
            float surface_hi_depth = surface_sample;
#ifndef SSR_QUARTER_DEPTH_ACTIVE
            surface_hi_depth = LinearDepthFromScreenDepth(surface_hi_depth);
#endif
            float pen_lo = LinearDepthFromScreenDepth(
                clamp(previous_pos.z, 0.0, 1.0)) - surface_lo_depth;
            float pen_hi = LinearDepthFromScreenDepth(
                clamp(ray_pos.z, 0.0, 1.0)) - surface_hi_depth;
            float pen_span = pen_hi - pen_lo;
            float hit_frac = pen_span > 1.0e-6
                ? clamp(-pen_lo / pen_span, 0.0, 1.0)
                : 0.5;
            vec3 hit_pos = mix(previous_pos, ray_pos, hit_frac);
#endif
            // Depth slop at the hit. Both hit estimators place the hit where
            // the ray meets the surface it crossed, so a large residual here
            // means the step slid across a silhouette: the crossing fired
            // against geometry much nearer than the surface the ray was
            // tracking, and accepting it would let foreground objects
            // occlude reflections they never intersect. Reject and keep
            // marching, exactly as the refined path does.
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

        if (ray_pos.z >= 1.0) {
            if (allow_sky && SSRDepthSampleIsSky(surface_sample)) {
                SSRHit sky_hit;
                sky_hit.screen = ray_pos;
                sky_hit.valid = true;
                sky_hit.sky = true;
                return sky_hit;
            }
            break;
        }

        previous_t = t;
        previous_pos = ray_pos;
        sample_t += step_length;
    }
    return miss;
}

#endif // LIB_RAYTRACE_SSR_GLSL
