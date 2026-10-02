#ifndef LIB_RAYTRACE_SSR_GLSL
#define LIB_RAYTRACE_SSR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/raytrace/ssr_depth.glsl"

// Shared screen-space reflection marcher. Both water and opaque reflection
// use the same depth-crossing rule; only their step
// budget, distance limit, and treatment of a far-plane miss differ.
#define SSR_REFINE_STEPS 6
#define SSR_TOL_SLOPE 0.1
#define SSR_TOL_BIAS 0.5

// Keep one statically bounded loop while allowing the water and opaque passes
// to select different runtime budgets. OPAQUE_SSR_STEPS is absent at quality
// 0, so the water budget remains the bound in that configuration.
#if defined(OPAQUE_SSR_STEPS) && OPAQUE_SSR_STEPS > WATER_SSR_STEPS
#define SSR_TRACE_MAX_STEPS OPAQUE_SSR_STEPS
#else
#define SSR_TRACE_MAX_STEPS WATER_SSR_STEPS
#endif

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
        vec3 view_direction, float jitter, float max_distance,
        int step_budget, bool allow_sky) {
    SSRHit miss = SSRMiss();
    if (!IsFinite(view_origin) || !IsFinite(view_direction)) return miss;

    float direction_length = length(view_direction);
    if (direction_length < 0.999) return miss;
    view_direction /= direction_length;

    // Project the ray through a second point in front of the origin. This is
    // the alpha v0.1.0 water path: one straight direction in screen UV/NDC-z
    // space, then an endpoint at the first screen edge or depth-plane exit.
    vec3 start_pos = ViewToNDC(view_origin) * 0.5 + 0.5;
    // Keep the projected reference point in front of the origin along the
    // actual ray. View space faces negative Z, so a ray toward the camera
    // needs a nearer (less negative) target instead of the usual far target.
    float target_view_z = view_direction.z < 0.0
        ? -(max(1.0, -view_origin.z) + 1.0)
        : min(-1.0e-3, view_origin.z + 1.0);
    float projection_t = abs(view_direction.z) > 1e-6
        ? clamp((target_view_z - view_origin.z) / view_direction.z,
            -1.0e6, 1.0e6)
        : 2.0;
    vec3 projected_pos = ViewToNDC(
        view_origin + view_direction * projection_t) * 0.5 + 0.5;
    vec3 projected_direction = projected_pos - start_pos;
    if (!IsFinite(start_pos) || !IsFinite(projected_pos)
            || !IsFinite(projected_direction)
            || !SSRScreenInside(start_pos.xy)) {
        return miss;
    }
    float projected_length = length(projected_direction);
    if (projected_length < 1e-6) return miss;
    vec3 dir = projected_direction / projected_length;

    // Screen-edge extent in UV-parametrization units. The clip-form mapping
    // (uv * 2 - 1, w = 1; dir_uv * 2, w = 0) leaves t unchanged, and the
    // shared solver reduces to the same per-axis (edge - origin) / direction
    // minimum for an in-rect origin.
    float s_end = ClipRayScreenExitT(
        vec4(start_pos.xy * 2.0 - 1.0, 0.0, 1.0),
        vec4(dir.xy * 2.0, 0.0, 0.0),
        1.0e20);
    if (dir.z > 0.0) {
        s_end = min(s_end, (1.0 - start_pos.z) / dir.z);
    }
    if (max_distance > 0.0) {
        vec3 max_pos = ViewToNDC(
            view_origin + view_direction * max_distance) * 0.5 + 0.5;
        if (IsFinite(max_pos)) {
            float max_s = dot(max_pos - start_pos, dir);
            if (max_s > 0.0) s_end = min(s_end, max_s);
        }
    }
    if (!(s_end > 0.0) || !IsFinite(vec3(s_end))) return miss;

    int budget = clamp(step_budget, 2, SSR_TRACE_MAX_STEPS);
    float step_length = 1.0 / float(max(budget - 1, 1));
    float sample_t = step_length
        * (0.5 + 0.5 * clamp(jitter, 0.0, 1.0));
    float ray_start_depth = -view_origin.z;
    float previous_t = 0.0;
    vec3 previous_pos = start_pos;

    for (int i = 0; i < SSR_TRACE_MAX_STEPS; ++i) {
        if (i >= budget) break;
        float t = min(sample_t, 1.0);
        vec3 ray_pos = start_pos + dir * (t * s_end);
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
                vec3 mid_pos = start_pos + dir * (mid_t * s_end);
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
            float hit_surface_depth = ReadSSRDepthSample(hit_pos.xy);
#ifndef SSR_QUARTER_DEPTH_ACTIVE
            hit_surface_depth = LinearDepthFromScreenDepth(hit_surface_depth);
#endif
            float hit_ray_depth = LinearDepthFromScreenDepth(
                clamp(hit_pos.z, 0.0, 1.0));
            float travelled = max(hit_ray_depth - ray_start_depth, 0.0);
            // Metre-domain tolerance, calibrated for a refined hit that sits
            // at the crossing itself; sub-step convergence is assumed.
            if (abs(hit_ray_depth - hit_surface_depth)
                    <= SSR_TOL_SLOPE * travelled + SSR_TOL_BIAS) {
                SSRHit hit;
                hit.screen = hit_pos;
                hit.valid = true;
                hit.sky = false;
                return hit;
            }
#else
            // Without bisection, interpolate the crossing inside the step:
            // convert both straddling samples to linear view depth and take
            // the fraction where the ray meets the surface. One extra depth
            // fetch replaces the six bisection fetches, and the estimate
            // tracks the crossing itself instead of the jittered sample
            // grid, so hit positions stay temporally stable. A raw crossing
            // can sit a full march step past the surface, which is metres
            // in linear view depth, so the refined hit's metre tolerance
            // cannot grade this estimate.
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
            SSRHit hit;
            hit.screen = mix(previous_pos, ray_pos, hit_frac);
            hit.valid = true;
            hit.sky = false;
            return hit;
#endif
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
