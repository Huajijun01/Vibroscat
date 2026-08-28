#ifndef LIB_RAYTRACE_SSR_GLSL
#define LIB_RAYTRACE_SSR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"

// Shared screen-space reflection marcher. Both water and opaque reflection
// use the same deliberately permissive depth-crossing rule; only their step
// budget, distance limit, and treatment of a far-plane miss differ.
#define SSR_REFINE_STEPS 6
#define SSR_TOL_SLOPE 0.1
#define SSR_TOL_BIAS 0.5

// Keep one statically bounded loop while allowing the water and opaque passes
// to select different runtime budgets. OPAQUE_SSR_STEPS is absent at quality
// 0, so the water budget remains the bound in that configuration.
#if defined(OPAQUE_SSR_STEPS) && OPAQUE_SSR_STEPS > SSR_STEPS
#define SSR_TRACE_MAX_STEPS OPAQUE_SSR_STEPS
#else
#define SSR_TRACE_MAX_STEPS SSR_STEPS
#endif

struct SSRHit {
    vec3 screen;
    float surface_depth;
    bool valid;
    bool sky;
};

SSRHit SSRMiss() {
    SSRHit hit;
    hit.screen = vec3(0.0);
    hit.surface_depth = 1.0;
    hit.valid = false;
    hit.sky = false;
    return hit;
}

bool SSRFinite(vec3 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

bool SSRScreenInside(vec2 uv) {
    return SSRFinite(vec3(uv, 0.0))
        && all(greaterThanEqual(uv, vec2(0.0)))
        && all(lessThanEqual(uv, vec2(1.0)));
}

SSRHit TraceScreenSpaceReflection(vec3 view_origin,
        vec3 view_direction, float jitter, float max_distance,
        int step_budget, bool allow_sky) {
    SSRHit miss = SSRMiss();
    if (!SSRFinite(view_origin) || !SSRFinite(view_direction)) return miss;

    float direction_length = length(view_direction);
    if (direction_length < 0.999) return miss;
    view_direction /= direction_length;

    // Project the ray through a second point in front of the origin. This is
    // the alpha v0.1.0 water path: one straight direction in screen UV/NDC-z
    // space, then an endpoint at the first screen edge or far plane.
    vec3 start_pos = ViewToNDC(view_origin) * 0.5 + 0.5;
    float sample_z = max(1.0, -view_origin.z) + 1.0;
    float projection_t = abs(view_direction.z) > 1e-6
        ? clamp((-sample_z - view_origin.z) / view_direction.z,
            -1.0e6, 1.0e6)
        : 2.0;
    vec3 projected_pos = ViewToNDC(
        view_origin + view_direction * projection_t) * 0.5 + 0.5;
    vec3 projected_direction = projected_pos - start_pos;
    if (!SSRFinite(start_pos) || !SSRFinite(projected_pos)
            || !SSRFinite(projected_direction)
            || !SSRScreenInside(start_pos.xy)) {
        return miss;
    }
    float projected_length = length(projected_direction);
    if (projected_length < 1e-6) return miss;
    vec3 dir = projected_direction / projected_length;

    float s_end = 1e20;
    if (dir.x > 0.0) {
        s_end = min(s_end, (1.0 - start_pos.x) / dir.x);
    } else if (dir.x < 0.0) {
        s_end = min(s_end, (0.0 - start_pos.x) / dir.x);
    }
    if (dir.y > 0.0) {
        s_end = min(s_end, (1.0 - start_pos.y) / dir.y);
    } else if (dir.y < 0.0) {
        s_end = min(s_end, (0.0 - start_pos.y) / dir.y);
    }
    if (dir.z > 0.0) {
        s_end = min(s_end, (1.0 - start_pos.z) / dir.z);
    }
    if (max_distance > 0.0) {
        vec3 max_pos = ViewToNDC(
            view_origin + view_direction * max_distance) * 0.5 + 0.5;
        if (SSRFinite(max_pos)) {
            float max_s = dot(max_pos - start_pos, dir);
            if (max_s > 0.0) s_end = min(s_end, max_s);
        }
    }
    if (!(s_end > 0.0) || !SSRFinite(vec3(s_end))) return miss;

    int budget = clamp(step_budget, 2, SSR_TRACE_MAX_STEPS);
    float step_length = 1.0 / float(max(budget - 1, 1));
    float sample_t = step_length
        * (0.5 + 0.5 * clamp(jitter, 0.0, 1.0));
    float ray_start_depth = LinearDepthFromScreenDepth(start_pos.z);
    float previous_t = 0.0;
    vec3 previous_pos = start_pos;

    for (int i = 0; i < SSR_TRACE_MAX_STEPS; ++i) {
        if (i >= budget) break;
        float t = min(sample_t, 1.0);
        vec3 ray_pos = start_pos + dir * (t * s_end);
        if (!SSRScreenInside(ray_pos.xy)) break;

        float surface_depth = textureLod(depthtex1, ray_pos.xy, 0.0).x;
        if (ray_pos.z >= 1.0) {
            if (allow_sky && surface_depth >= 1.0) {
                SSRHit sky_hit;
                sky_hit.screen = ray_pos;
                sky_hit.surface_depth = 1.0;
                sky_hit.valid = true;
                sky_hit.sky = true;
                return sky_hit;
            }
            break;
        }

        float ray_depth = LinearDepthFromScreenDepth(ray_pos.z);
        float surface_linear = LinearDepthFromScreenDepth(surface_depth);
        if (surface_depth < 1.0 && surface_linear < ray_depth) {
            // The first permissive crossing is enough. Bisection only locates
            // it; there is intentionally no thickness or normal rejection.
            float lo = previous_t;
            float hi = t;
            vec3 lo_pos = previous_pos;
            vec3 hi_pos = ray_pos;
            for (int j = 0; j < SSR_REFINE_STEPS; ++j) {
                float mid_t = 0.5 * (lo + hi);
                vec3 mid_pos = start_pos + dir * (mid_t * s_end);
                float mid_surface = LinearDepthFromScreenDepth(
                    textureLod(depthtex1, mid_pos.xy, 0.0).x);
                float mid_ray = LinearDepthFromScreenDepth(mid_pos.z);
                if (mid_surface < mid_ray) {
                    hi = mid_t;
                    hi_pos = mid_pos;
                } else {
                    lo = mid_t;
                    lo_pos = mid_pos;
                }
            }

            vec3 hit_pos = 0.5 * (lo_pos + hi_pos);
            float hit_depth = textureLod(depthtex1, hit_pos.xy, 0.0).x;
            float hit_ray_depth = LinearDepthFromScreenDepth(hit_pos.z);
            float hit_surface_depth = LinearDepthFromScreenDepth(hit_depth);
            float travelled = max(hit_ray_depth - ray_start_depth, 0.0);
            if (abs(hit_ray_depth - hit_surface_depth)
                    <= SSR_TOL_SLOPE * travelled + SSR_TOL_BIAS) {
                SSRHit hit;
                hit.screen = hit_pos;
                hit.surface_depth = hit_depth;
                hit.valid = true;
                hit.sky = false;
                return hit;
            }
        }

        previous_t = t;
        previous_pos = ray_pos;
        sample_t += step_length;
    }
    return miss;
}

#endif
