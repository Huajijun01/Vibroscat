#ifndef LIB_RAYTRACE_SSR_GLSL
#define LIB_RAYTRACE_SSR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"

// Screen-space reflections for the water forward pass (translucent gbuffer).
//
// March design (McGuire & Mara, "Efficient GPU Screen-Space Ray Tracing",
// JCGT 3(4), 2014): the ray's projection is a straight segment in (screen UV,
// NDC z) space ending where the ray first leaves the screen or reaches the
// far plane. The segment is covered by SSR_STEPS samples at constant pitch
// (1/(SSR_STEPS-1) of the path), the first sample jittered within one pitch,
// so the march is guaranteed to reach its endpoint for every jitter phase.
// Depth crossings are detected in linearized view distance (coordinates.glsl
// LinearDepthFromScreenDepth), refined by interval bisection, accepted by a
// distance-scaled tolerance. depthtex1 is always sampled.
// SSR_STEPS (march samples) is a user option declared in
// contract/settings.glsl.
#define SSR_REFINE_STEPS 6           // bisection iterations per depth crossing
#define SSR_TOL_SLOPE 0.1           // k: tolerance grows k * travelled (metres)
#define SSR_TOL_BIAS 0.5             // eps: fixed tolerance (metres)

bool RayTraceHIT(vec3 view_ray_ori, vec3 view_screen_step_dir, float ndot_v, float noise, bool is_hand, inout vec3 screen_pos, out bool hit_sky){
    // Projection of the ray is a straight line in (screen UV, NDC z) space.
    // A second point on the ray line, at least ~2 m in front of the origin,
    // fixes its screen-space direction.
    float sample_z = max(1.0, -view_ray_ori.z) + 1.0;
    float t = clamp((-sample_z - view_ray_ori.z) / view_screen_step_dir.z, -1.0e6, 1.0e6);
    vec3 dir = normalize(ViewToNDC(view_ray_ori + view_screen_step_dir * t) * 0.5 + 0.5 - screen_pos);

    // Endpoint: first intersection of the projected line with a screen edge
    // (UV = 0/1) or with the far plane (NDC z = 1), whichever comes first.
    float s_end = 1e20;
    if (dir.x > 0.0) s_end = min(s_end, (1.0 - screen_pos.x) / dir.x);
    else if (dir.x < 0.0) s_end = min(s_end, (0.0 - screen_pos.x) / dir.x);
    if (dir.y > 0.0) s_end = min(s_end, (1.0 - screen_pos.y) / dir.y);
    else if (dir.y < 0.0) s_end = min(s_end, (0.0 - screen_pos.y) / dir.y);
    if (dir.z > 0.0) s_end = min(s_end, (1.0 - screen_pos.z) / dir.z);

    // Constant pitch over the full path; the jittered first sample still
    // leaves (SSR_STEPS - 1) pitches, so the last sample sits at or beyond
    // the endpoint for every noise phase: a miss always means the whole path
    // was covered, never a truncated budget.
    float step_len = 1.0 / float(SSR_STEPS - 1);
    float s = step_len * (0.5 + 0.5 * noise);

    hit_sky = false;

    vec3 start_pos = screen_pos;
    float ray_start_lin = LinearDepthFromScreenDepth(start_pos.z);

    for (int i = 0; i < SSR_STEPS; i++) {
        vec3 prev_pos = screen_pos;
        screen_pos = start_pos + dir * (s * s_end);

        if (Saturate(screen_pos.xy) != screen_pos.xy) break;  // left the screen

        // Sample once per step; the far-plane test below reuses this sample
        // (no extra depth fetch).
        float surf_depth = textureLod(depthtex1, screen_pos.xy, 0.0).x;

        if (screen_pos.z >= 1.0) {
            // Past the far plane: a sky pixel here (depth 1.0 = no geometry)
            // is a sky hit — the consumer reuses the in-screen sky color from
            // last frame instead of the sky-LUT fallback. A geometry pixel
            // means the ray exited beyond it without a crossing: no hit.
            if (surf_depth >= 1.0) {
                hit_sky = true;
                return true;
            }
            break;
        }

        float surf_lin = LinearDepthFromScreenDepth(surf_depth);
        float ray_lin = LinearDepthFromScreenDepth(screen_pos.z);

        if (surf_lin < ray_lin) {
            // Depth crossing inside [prev_pos, screen_pos]: bisect the
            // interval branch-free — step() selects the half that still
            // contains the crossing, mix() applies the selection.
            vec3 lo = prev_pos;
            vec3 hi = screen_pos;
            for (int j = 0; j < SSR_REFINE_STEPS; j++) {
                vec3 mid = (lo + hi) * 0.5;
                float mid_surf = LinearDepthFromScreenDepth(
                    textureLod(depthtex1, mid.xy, 0.0).x);
                // sel = 1 when the surface is nearer than the ray at mid,
                // i.e. the crossing lies in [lo, mid]: hi <- mid; else lo <- mid.
                float sel = step(mid_surf, LinearDepthFromScreenDepth(mid.z));
                lo = mix(mid, lo, sel);
                hi = mix(hi, mid, sel);
            }

            vec3 hit_pos = (lo + hi) * 0.5;
            float hit_depth = textureLod(depthtex1, hit_pos.xy, 0.0).x;

            float hit_ray = LinearDepthFromScreenDepth(hit_pos.z);
            float hit_surf = LinearDepthFromScreenDepth(hit_depth);
            float travelled = hit_ray - ray_start_lin;

            if (abs(hit_ray - hit_surf) < SSR_TOL_SLOPE * travelled + SSR_TOL_BIAS) {
                screen_pos = hit_pos;
                return true;
            }
        }

        s += step_len;
    }

    return false;
}

#endif
