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
};

// The march bracket: the two samples straddling the first accepted crossing,
// with the ray depth and surface sample from the crossing end.
struct SSRBracket {
    vec3 previous_pos;
    vec3 sample_pos;
    float previous_ray_depth;
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

    vec2 edge_near_t = ClipRayScreenCoordT(origin_clip, direction_clip,
        1.0, far + 32.0);
    vec2 edge_far_t = ClipRayScreenCoordT(origin_clip, direction_clip,
        -1.0, far + 32.0);
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
    return chord;
}

// March the chord with fixed steps until the first depth crossing. Each path
// passes its own crossing rule through toward_eye: opaque reflections may
// point back toward the eye and cross surfaces in either direction, while
// translucent reflections always travel away from the eye and only accept a
// surface sitting in front of the ray point.
SSRBracket MarchSSRChord(vec3 view_origin, SSRChord chord, float jitter,
        int step_budget, bool toward_eye) {
    SSRBracket bracket;
    vec3 march_step = chord.span / float(step_budget - 1);
    vec3 sample_pos = chord.start_pos + march_step * jitter;
    float ray_start_depth = -view_origin.z;
    bracket.previous_pos = chord.start_pos;
    bracket.previous_ray_depth = SSRRayDepthFromScreen(chord.start_pos.z);
    bracket.surface_sample = 0.0;
    bracket.ray_depth = bracket.previous_ray_depth;
    bracket.hit_found = false;

    for (int i = 0; i < step_budget; ++i) {
        if (!SSRScreenInside(sample_pos.xy)) break;

        bracket.surface_sample = ReadSSRDepthSample(sample_pos.xy);
        bracket.ray_depth = SSRRayDepthFromScreen(sample_pos.z);
        // Toward-eye crossings require the previous point behind this surface.
        bool behind_surface = SSRDepthSampleBeforeRay(bracket.surface_sample,
            bracket.ray_depth);
        bool depth_crossing = toward_eye
            ? !behind_surface
                && SSRDepthSampleBeforeRay(bracket.surface_sample,
                    bracket.previous_ray_depth)
            : behind_surface;
        if (depth_crossing) {
            float surface_view_depth = bracket.surface_sample;
#ifndef SSR_QUARTER_DEPTH_ACTIVE
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
        sample_pos += march_step;
    }
    bracket.sample_pos = sample_pos;
    return bracket;
}

// Bisection refinement of the accepted bracket, including the jittered first
// step: each iteration samples the current position and halves the step after
// moving toward the crossing. The initial step sign encodes the ray-depth
// direction, which reverses for toward-eye rays.
vec3 RefineSSRBisection(vec3 previous_pos, vec3 sample_pos, bool toward_eye,
        int refine_steps) {
    vec3 hit_pos = 0.5 * (previous_pos + sample_pos);
    vec3 refine_step = (sample_pos - previous_pos) * (0.25 - 0.5 * float(toward_eye));
    for (int j = 0; j < refine_steps; ++j) {
        float mid_surface = ReadSSRDepthSample(hit_pos.xy);
        float mid_ray_depth = SSRRayDepthFromScreen(hit_pos.z);
#ifdef SSR_QUARTER_DEPTH_ACTIVE
        float depth_delta = mid_ray_depth * mid_surface - 1.0;
#else
        float depth_delta = mid_surface - mid_ray_depth;
#endif
        hit_pos += sign(depth_delta) * refine_step;
        refine_step *= 0.5;
    }
    return hit_pos;
}

// Interpolate the crossing inside the march step in the affine ray-depth
// domain, then correct once for the candidate's local surface depth without
// clamping the jittered endpoint.
vec3 RefineSSRInterpolation(vec3 previous_pos, vec3 sample_pos,
        float previous_ray_depth, float ray_depth, float surface_sample) {
    float ray_depth_span = ray_depth - previous_ray_depth;
    float span_sign = sign(ray_depth_span);
    float inverse_span = span_sign / max(abs(ray_depth_span), 1e-20);
    // A zero span keeps the midpoint; nonzero spans retain their sign.
#ifdef SSR_QUARTER_DEPTH_ACTIVE
    float surface_depth = 1.0 / surface_sample;
#else
    float surface_depth = surface_sample;
#endif
    float hit_frac = clamp((surface_depth - previous_ray_depth) * inverse_span,
        0.0, 1.0);
    vec3 hit_pos = mix(previous_pos, sample_pos, hit_frac);
    float candidate_surface_depth = ReadSSRDepthSample(hit_pos.xy);
#ifdef SSR_QUARTER_DEPTH_ACTIVE
    candidate_surface_depth = 1.0 / candidate_surface_depth;
#endif
    hit_frac = clamp((candidate_surface_depth - previous_ray_depth) * inverse_span,
        0.0, 1.0);
    return mix(previous_pos, sample_pos, hit_frac);
}

// Known sky at the march endpoint: accepted only when the chord actually
// reached the far plane, reported with the clipped endpoint position.
SSRHit SSRSkyEndpointHit(vec3 endpoint_pos) {
    if (endpoint_pos.z < 1.0) return SSRMiss();
    SSRHit hit;
    hit.screen = vec3(endpoint_pos.xy, 1.0);
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
// the chord can leave through the near plane and both crossing directions
// are accepted. The march budget and the first-crossing refinement are owned
// by the OPAQUE_SSR_* settings.
SSRHit TraceOpaqueSSR(vec3 view_origin, vec3 view_direction, float jitter) {
    bool toward_eye = view_direction.z > 0.0;
    SSRChord chord = ComputeSSRChord(view_origin, view_direction, toward_eye);
    SSRBracket bracket = MarchSSRChord(view_origin, chord, jitter,
        OPAQUE_SSR_STEPS, toward_eye);
    // The clipped chord reaches the far plane at the end of the march budget.
    // Classify its last sampled depth once; known sky needs no refinement.
    if (SSRDepthSampleIsSky(bracket.surface_sample)) {
        return SSRSkyEndpointHit(bracket.hit_found ? bracket.sample_pos
            : bracket.previous_pos);
    }
    if (!bracket.hit_found) return SSRMiss();

#ifdef OPAQUE_SSR_BISECTION
    vec3 hit_pos = RefineSSRBisection(bracket.previous_pos, bracket.sample_pos,
        toward_eye, OPAQUE_SSR_BISECT_STEPS);
#else
    vec3 hit_pos = RefineSSRInterpolation(bracket.previous_pos,
        bracket.sample_pos, bracket.previous_ray_depth, bracket.ray_depth,
        bracket.surface_sample);
#endif
    return SSRClassifyScreenHit(hit_pos);
}

// Translucent SSR (water and glass gbuffers): reflections always travel away
// from the eye, so the chord exits through the far plane and only surfaces in
// front of the ray point count as crossings. The march budget and the
// first-crossing refinement are owned by the WATER_SSR_* settings.
SSRHit TraceTranslucentSSR(vec3 view_origin, vec3 view_direction, float jitter) {
    SSRChord chord = ComputeSSRChord(view_origin, view_direction, false);
    SSRBracket bracket = MarchSSRChord(view_origin, chord, jitter,
        WATER_SSR_STEPS, false);
    if (SSRDepthSampleIsSky(bracket.surface_sample)) {
        return SSRSkyEndpointHit(bracket.hit_found ? bracket.sample_pos
            : bracket.previous_pos);
    }
    if (!bracket.hit_found) return SSRMiss();

#ifdef WATER_SSR_BISECTION
    vec3 hit_pos = RefineSSRBisection(bracket.previous_pos, bracket.sample_pos,
        false, WATER_SSR_BISECT_STEPS);
#else
    vec3 hit_pos = RefineSSRInterpolation(bracket.previous_pos,
        bracket.sample_pos, bracket.previous_ray_depth, bracket.ray_depth,
        bracket.surface_sample);
#endif
    return SSRClassifyScreenHit(hit_pos);
}

#endif // LIB_RAYTRACE_SSR_GLSL
