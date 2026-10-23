#ifndef LIB_RAYTRACE_SSR_GLSL
#define LIB_RAYTRACE_SSR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/raytrace/ssr_depth.glsl"

// Accepted-crossing thickness: a hit is valid when the surface sits within
// SSR_TOL_SLOPE * travelled + SSR_TOL_BIAS view-depth units of the ray depth.
#define SSR_TOL_SLOPE 0.1
#define SSR_TOL_BIAS 0.5

struct SSRHit {
    vec3 screen;
    bool valid;
    bool sky;
};

// Projected march chord: one straight (uv, NDC z) span from the origin to
// the projected exit point.
struct SSRChord {
    vec3 start_pos;
    vec3 span;
    // True when the clipped exit is the far-plane crossing rather than a
    // screen-edge exit; only rays that do not travel toward the eye can
    // reach it. Decided from the extent winner because the solved exit
    // z/w straddles the plane within rounding.
    bool exit_on_far_plane;
};

// The march bracket: the two samples straddling the first accepted crossing,
// with the ray depth and surface sample from the crossing end.
struct SSRBracket {
    vec3 previous_pos;
    vec3 sample_pos;
    float previous_ray_depth;
    float previous_surface_sample;
    float ray_depth;
    float surface_sample;
    bool hit_found;
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

// Project the origin and the ray direction through clip space once. Moving a
// view-space distance t along the unit ray adds PROJ.xyz * t to the clip
// position and -t * dir.z to the clip w, so the projected ray is rational in
// t and every screen-space crossing solves in closed form (reference stepper
// structure: one origin, one direction, one exit, one span). Toward-eye rays
// leave through the near plane, all others through the far plane; the
// screen-edge extent is the smallest forward clip parameter reaching any NDC
// edge, with crossings at or behind the origin falling back to a beyond-far
// sentinel so the minimum stays forward-facing.
SSRChord ComputeSSRChord(vec3 view_origin, vec3 view_direction, bool toward_eye) {
    vec4 origin_clip = gbufferProjection * vec4(view_origin, 1.0);
    // Same value chain as ViewToNDC(origin) * 0.5 + 0.5 (identical operation
    // order), derived from the clip position the ray stepper already needs.
    SSRChord chord;
    chord.start_pos = origin_clip.xyz / -view_origin.z * 0.5 + 0.5;
    vec4 direction_clip = gbufferProjection * vec4(view_direction, 0.0);

    // Iris 'far' is the render distance, not the clipping plane, which is
    // roughly far * 4.0 (ShaderDoc, uniform far). The no-crossing fallback
    // must exceed the oblique distance to the true far plane, or chords stop
    // short of it and their sky end never classifies.
    float clip_far_distance = u_clip_far_distance;
    vec2 edge_near_t = ClipRayScreenCoordT(origin_clip, direction_clip,
        1.0, clip_far_distance * 4.0);
    vec2 edge_far_t = ClipRayScreenCoordT(origin_clip, direction_clip,
        -1.0, clip_far_distance * 4.0);
    float trace_length = min(min(edge_near_t.x, edge_near_t.y),
        min(edge_far_t.x, edge_far_t.y));
    // Choose the forward NDC depth boundary; the far exit is behind
    // toward-eye rays.
    float depth_plane = toward_eye ? -1.0 : 1.0;
    float depth_plane_t = (depth_plane * origin_clip.w - origin_clip.z)
        / (direction_clip.z - depth_plane * direction_clip.w);
    trace_length = min(trace_length, depth_plane_t);

    vec4 exit_clip = origin_clip + direction_clip * trace_length;
    chord.span = exit_clip.xyz / exit_clip.w * 0.5 + 0.5 - chord.start_pos;
    chord.exit_on_far_plane = !toward_eye && trace_length == depth_plane_t;
    return chord;
}

// Opaque rays need a front-to-behind bracket relative to the sampled surface,
// independently of their view-space z direction. Initial occlusion is skipped
// until the ray becomes visible, preventing an origin self-hit. Translucent
// rays retain their segment/thickness test and away-from-eye policy.
SSRBracket MarchSSRChord(vec3 view_origin, SSRChord chord, float jitter,
        int step_budget, bool opaque_trace) {
    SSRBracket bracket;
    vec3 march_step = chord.span / float(step_budget - 1);
    vec3 sample_pos = chord.start_pos + march_step * jitter;
    float ray_start_depth = -view_origin.z;
    bracket.previous_pos = chord.start_pos;
    bracket.previous_ray_depth = SSRRayDepthFromScreen(chord.start_pos.z);
    bracket.previous_surface_sample = opaque_trace
        ? ReadSSRDepthSample(chord.start_pos.xy) : 0.0;
    bool previous_behind = opaque_trace && SSRDepthSampleBeforeRay(
        bracket.previous_surface_sample, bracket.previous_ray_depth);
    bracket.surface_sample = 0.0;
    bracket.ray_depth = bracket.previous_ray_depth;
    bracket.hit_found = false;

    for (int i = 0; i < step_budget; ++i) {
        if (!SSRScreenInside(sample_pos.xy)) break;

        bracket.surface_sample = ReadSSRDepthSample(sample_pos.xy);
        bracket.ray_depth = SSRRayDepthFromScreen(sample_pos.z);
        bool behind_surface = SSRDepthSampleBeforeRay(bracket.surface_sample,
            bracket.ray_depth);
        bool depth_crossing = opaque_trace
            ? behind_surface && !previous_behind
            : behind_surface;
        if (depth_crossing) {
            // A coarse endpoint may sit far behind a sloping surface even
            // when the bracket contains an exact hit. Validate opaque
            // thickness at the refined intersection instead.
            if (opaque_trace) {
                bracket.hit_found = true;
                break;
            }
            float surface_view_depth = bracket.surface_sample;
#if !defined(SSR_QUARTER_DEPTH_ACTIVE)
            surface_view_depth = LinearDepthFromScreenDepth(surface_view_depth);
#endif
            // Accept segment/thickness overlap before spending work on
            // refinement.
            float segment_start_depth = LinearDepthFromScreenDepth(
                clamp(bracket.previous_pos.z, 0.0, 1.0));
            float segment_end_depth = LinearDepthFromScreenDepth(
                clamp(sample_pos.z, 0.0, 1.0));
            float hit_ray_depth = clamp(surface_view_depth,
                min(segment_start_depth, segment_end_depth),
                max(segment_start_depth, segment_end_depth));
            float travelled = max(hit_ray_depth - ray_start_depth, 0.0);
            if (abs(hit_ray_depth - surface_view_depth)
                    <= SSR_TOL_SLOPE * travelled + SSR_TOL_BIAS) {
                bracket.hit_found = true;
                break;
            }
        }

        bracket.previous_pos = sample_pos;
        bracket.previous_ray_depth = bracket.ray_depth;
        bracket.previous_surface_sample = bracket.surface_sample;
        previous_behind = behind_surface;
        sample_pos += march_step;
    }
    bracket.sample_pos = sample_pos;
    return bracket;
}

// Positive behind the surface in both depth encodings. Reciprocal view depth
// and raw screen depth are affine along the projected ray and a planar face,
// allowing a secant inside the narrowed bracket without projecting onto the
// depth of an unrelated UV (which fails on slopes and constant-depth rays).
float SSRDepthResidual(float surface_sample, float ray_depth) {
#if defined(SSR_QUARTER_DEPTH_ACTIVE)
    return 1.0 / surface_sample - ray_depth;
#else
    return ray_depth - surface_sample;
#endif
}

SSRHit RefineOpaqueSSR(SSRBracket bracket, float ray_start_depth) {
    vec3 front_pos = bracket.previous_pos;
    vec3 behind_pos = bracket.sample_pos;
    float front_delta = SSRDepthResidual(bracket.previous_surface_sample,
        bracket.previous_ray_depth);
    float behind_delta = SSRDepthResidual(bracket.surface_sample,
        bracket.ray_depth);
#ifdef SSR_INTERPOLATION
    for (int j = 0; j < OPAQUE_SSR_BISECT_STEPS; ++j) {
        vec3 mid_pos = 0.5 * (front_pos + behind_pos);
        float mid_delta = SSRDepthResidual(ReadSSRDepthSample(mid_pos.xy),
            SSRRayDepthFromScreen(mid_pos.z));
        if (mid_delta > 0.0) {
            behind_pos = mid_pos;
            behind_delta = mid_delta;
        } else {
            front_pos = mid_pos;
            front_delta = mid_delta;
        }
    }
    float hit_fraction = clamp(-front_delta
        / max(behind_delta - front_delta, 1e-20), 0.0, 1.0);
    vec3 hit_pos = mix(front_pos, behind_pos, hit_fraction);
#else
    vec3 hit_pos = behind_pos;
#endif
    float hit_surface = ReadSSRDepthSample(hit_pos.xy);
    bool hit_sky = SSRDepthSampleIsSky(hit_surface);
    if (hit_sky && hit_pos.z < 1.0) return SSRMiss();
    float surface_view_depth = hit_surface;
#if !defined(SSR_QUARTER_DEPTH_ACTIVE)
    surface_view_depth = LinearDepthFromScreenDepth(hit_surface);
#endif
    float hit_view_depth = LinearDepthFromScreenDepth(clamp(hit_pos.z, 0.0, 1.0));
    float travelled = abs(hit_view_depth - ray_start_depth);
    if (abs(hit_view_depth - surface_view_depth)
            > SSR_TOL_SLOPE * travelled + SSR_TOL_BIAS) return SSRMiss();

    SSRHit hit;
    hit.screen = vec3(hit_pos.xy, hit_sky ? 1.0 : hit_pos.z);
    hit.valid = true;
    hit.sky = hit_sky;
    return hit;
}

// Refine the accepted crossing: unconditional bisection localizes the depth
// flip inside the march bracket — planar faces and silhouette steps alike —
// then one chord-domain correction reads the surface at the bisected
// position and projects the hit onto it, which restores the interpolation's
// exact landing on planar surfaces without clamping the jittered endpoint.
vec3 RefineSSRBisection(vec3 previous_pos, vec3 sample_pos,
        float previous_ray_depth, float ray_depth, bool toward_eye,
        int refine_steps) {
    vec3 hit_pos = 0.5 * (previous_pos + sample_pos);
    // The initial step sign encodes the ray-depth direction, which reverses
    // for toward-eye rays.
    vec3 refine_step = (sample_pos - previous_pos)
        * (0.25 - 0.5 * float(toward_eye));
    for (int j = 0; j < refine_steps; ++j) {
        float mid_surface = ReadSSRDepthSample(hit_pos.xy);
        float mid_ray_depth = SSRRayDepthFromScreen(hit_pos.z);
#if defined(SSR_QUARTER_DEPTH_ACTIVE)
        float depth_delta = mid_ray_depth * mid_surface - 1.0;
#else
        float depth_delta = mid_surface - mid_ray_depth;
#endif
        hit_pos += sign(depth_delta) * refine_step;
        refine_step *= 0.5;
    }
    float ray_depth_span = ray_depth - previous_ray_depth;
    float inverse_span = sign(ray_depth_span)
        / max(abs(ray_depth_span), 1e-20);
    // A zero span collapses hit_frac to the bracket's front sample; nonzero spans retain their sign.
    float hit_surface = ReadSSRDepthSample(hit_pos.xy);
#if defined(SSR_QUARTER_DEPTH_ACTIVE)
    float hit_frac = clamp((1.0 / hit_surface - previous_ray_depth)
        * inverse_span, 0.0, 1.0);
#else
    float hit_frac = clamp((hit_surface - previous_ray_depth)
        * inverse_span, 0.0, 1.0);
#endif
    return mix(previous_pos, sample_pos, hit_frac);
}

// Known sky at the march end: reported at the chord's projected far-plane
// exit rather than the jittered march endpoint, so the reflected sky sample
// does not inherit the trace dither. The caller owns the far-plane decision.
SSRHit SSRSkyEndpointHit(vec2 exit_uv) {
    SSRHit hit;
    hit.screen = vec3(exit_uv, 1.0);
    hit.valid = true;
    hit.sky = true;
    return hit;
}

// Assemble the refined hit: a crossing that lands on sky keeps the far-plane
// endpoint and reports sky so consumers can suppress their glint term there.
SSRHit SSRClassifyScreenHit(vec3 screen_pos) {
    bool hit_sky = SSRDepthSampleIsSky(ReadSSRDepthSample(screen_pos.xy));
    if (hit_sky && screen_pos.z < 1.0) return SSRMiss();
    SSRHit hit;
    hit.screen = vec3(screen_pos.xy, hit_sky ? 1.0 : screen_pos.z);
    hit.valid = true;
    hit.sky = hit_sky;
    return hit;
}

// Opaque SSR (deferred2): reflected rays may point back toward the eye, so
// the chord can leave through the near plane. Surface crossings use their
// actual depth bracket. The march budget is owned by OPAQUE_SSR_STEPS; the shared
// SSR_INTERPOLATION toggle owns first-crossing refinement.
SSRHit TraceOpaqueSSR(vec3 view_origin, vec3 view_direction, float jitter) {
    bool toward_eye = view_direction.z > 0.0;
    SSRChord chord = ComputeSSRChord(view_origin, view_direction, toward_eye);
    SSRBracket bracket = MarchSSRChord(view_origin, chord, jitter,
        OPAQUE_SSR_STEPS, true);
    // The ray end is the chord's clipped exit unless a geometry crossing was
    // accepted; a sky surface_sample at the final step is the ray passing the
    // far plane, not geometry. The exit pixel owns the sky decision (the last
    // march sample rides the trace jitter); edge exits are misses.
    if (!bracket.hit_found || SSRDepthSampleIsSky(bracket.surface_sample)) {
        if (chord.exit_on_far_plane) {
            vec2 exit_uv = chord.start_pos.xy + chord.span.xy;
            if (SSRDepthSampleIsSky(ReadSSRDepthSample(exit_uv))) {
                return SSRSkyEndpointHit(exit_uv);
            }
        }
        if (!bracket.hit_found) return SSRMiss();
    }

    return RefineOpaqueSSR(bracket, -view_origin.z);
}

// Translucent SSR (water and glass gbuffers): reflections always travel away
// from the eye, so the chord exits through the far plane and only surfaces in
// front of the ray point count as crossings. The march budget is owned by
// WATER_SSR_STEPS; the shared SSR_INTERPOLATION toggle owns first-crossing
// refinement.
SSRHit TraceTranslucentSSR(vec3 view_origin, vec3 view_direction, float jitter) {
    SSRChord chord = ComputeSSRChord(view_origin, view_direction, false);
    SSRBracket bracket = MarchSSRChord(view_origin, chord, jitter,
        WATER_SSR_STEPS, false);
    // The ray end is the chord's clipped exit unless a geometry crossing was
    // accepted; a sky surface_sample at the final step is the ray passing the
    // far plane, not geometry. The exit pixel owns the sky decision (the last
    // march sample rides the trace jitter); edge exits are misses.
    if (!bracket.hit_found || SSRDepthSampleIsSky(bracket.surface_sample)) {
        if (chord.exit_on_far_plane) {
            vec2 exit_uv = chord.start_pos.xy + chord.span.xy;
            if (SSRDepthSampleIsSky(ReadSSRDepthSample(exit_uv))) {
                return SSRSkyEndpointHit(exit_uv);
            }
        }
        if (!bracket.hit_found) return SSRMiss();
    }

#ifdef SSR_INTERPOLATION
    vec3 hit_pos = RefineSSRBisection(bracket.previous_pos,
        bracket.sample_pos, bracket.previous_ray_depth, bracket.ray_depth,
        false, WATER_SSR_BISECT_STEPS);
#else
    // Raw trace: report the accepted march sample without refinement.
    vec3 hit_pos = bracket.sample_pos;
#endif
    return SSRClassifyScreenHit(hit_pos);
}

#endif // LIB_RAYTRACE_SSR_GLSL
