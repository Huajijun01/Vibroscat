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
    float path_length;
    bool valid;
    bool sky;
};

SSRHit SSRMiss() {
    SSRHit hit;
    hit.screen = vec3(0.0);
    hit.surface_depth = 1.0;
    hit.path_length = 0.0;
    hit.valid = false;
    hit.sky = false;
    return hit;
}

bool SSRFinite(vec3 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

SSRHit TraceScreenSpaceReflection(vec3 view_origin,
        vec3 view_direction, float jitter, float max_distance,
        int step_budget, bool allow_sky) {
    SSRHit miss = SSRMiss();
    if (!SSRFinite(view_origin) || !SSRFinite(view_direction)) return miss;

    float direction_length = length(view_direction);
    if (direction_length < 0.999) return miss;
    view_direction /= direction_length;

    // A zero distance means the water path may continue to the far plane.
    // Opaque reflections pass their finite distance budget here.
    float ray_length = max_distance > 0.0 ? max_distance : far;
    if (view_direction.z > 1e-6) {
        ray_length = min(ray_length,
            (-near * 1.01 - view_origin.z) / view_direction.z);
    } else if (view_direction.z < -1e-6) {
        ray_length = min(ray_length,
            (-far * 0.999 - view_origin.z) / view_direction.z);
    }
    if (ray_length <= 0.05) return miss;

    vec3 view_end = view_origin + view_direction * ray_length;
    vec3 start_pos = ViewToNDC(view_origin) * 0.5 + 0.5;
    vec3 end_pos = ViewToNDC(view_end) * 0.5 + 0.5;
    if (!SSRFinite(start_pos) || !SSRFinite(end_pos)
            || any(lessThan(start_pos.xy, vec2(0.0)))
            || any(greaterThan(start_pos.xy, vec2(1.0)))) {
        return miss;
    }

    // Clip the projected line to the visible rectangle and both depth planes.
    // This preserves full-path coverage without accepting samples outside the
    // depth texture.
    vec3 projected_delta = end_pos - start_pos;
    float end_fraction = 1.0;
    if (projected_delta.x > 0.0) {
        end_fraction = min(end_fraction,
            (1.0 - start_pos.x) / projected_delta.x);
    } else if (projected_delta.x < 0.0) {
        end_fraction = min(end_fraction,
            (0.0 - start_pos.x) / projected_delta.x);
    }
    if (projected_delta.y > 0.0) {
        end_fraction = min(end_fraction,
            (1.0 - start_pos.y) / projected_delta.y);
    } else if (projected_delta.y < 0.0) {
        end_fraction = min(end_fraction,
            (0.0 - start_pos.y) / projected_delta.y);
    }
    if (projected_delta.z > 0.0) {
        end_fraction = min(end_fraction,
            (1.0 - start_pos.z) / projected_delta.z);
    } else if (projected_delta.z < 0.0) {
        end_fraction = min(end_fraction,
            (0.0 - start_pos.z) / projected_delta.z);
    }
    end_fraction = clamp(end_fraction, 0.0, 1.0);
    vec3 end_screen = mix(start_pos, end_pos, end_fraction);
    projected_delta = end_screen - start_pos;
    float projected_length = max(abs(projected_delta.x),
        abs(projected_delta.y));
    float quarter_pixel = 0.25 * max(u_view_pixel_size.x,
        u_view_pixel_size.y);
    if (projected_length < quarter_pixel) return miss;

    int budget = clamp(step_budget, 2, SSR_TRACE_MAX_STEPS);
    float step_length = 1.0 / float(max(budget - 1, 1));
    float sample_t = step_length
        * (0.5 + 0.5 * clamp(jitter, 0.0, 1.0));
    float ray_start_depth = LinearDepthFromScreenDepth(start_pos.z);
    float previous_t = 0.0;
    vec3 previous_pos = start_pos;
    SSRHit sky_candidate = SSRMiss();
    bool last_sample_sky = false;

    for (int i = 0; i < SSR_TRACE_MAX_STEPS; ++i) {
        if (i >= budget) break;
        float t = min(sample_t, 1.0);
        vec3 ray_pos = start_pos + projected_delta * t;
        if (any(lessThan(ray_pos.xy, vec2(0.0)))
                || any(greaterThan(ray_pos.xy, vec2(1.0)))) break;

        float surface_depth = textureLod(depthtex1, ray_pos.xy, 0.0).x;
        last_sample_sky = allow_sky && surface_depth >= 1.0;
        if (last_sample_sky) {
            // Open sky at an intermediate pixel does not prove that the rest
            // of the projected ray cannot intersect geometry.
            SSRHit sky_hit;
            sky_hit.screen = ray_pos;
            sky_hit.surface_depth = 1.0;
            sky_hit.path_length = length(
                NDCToView(ray_pos * 2.0 - 1.0) - view_origin);
            sky_hit.valid = sky_hit.path_length > 0.05;
            sky_hit.sky = sky_hit.valid;
            sky_candidate = sky_hit;
        } else {
            sky_candidate = miss;
        }

        if (ray_pos.z >= 1.0) {
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
                vec3 mid_pos = mix(start_pos, end_screen, mid_t);
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
                hit.path_length = length(
                    NDCToView(hit_pos * 2.0 - 1.0) - view_origin);
                hit.valid = true;
                hit.sky = false;
                return hit;
            }
        }

        previous_t = t;
        previous_pos = ray_pos;
        sample_t += step_length;
    }
    if (last_sample_sky) return sky_candidate;
    return miss;
}

#endif
