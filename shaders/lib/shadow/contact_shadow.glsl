#ifndef LIB_SHADOW_CONTACT_SHADOW_GLSL
#define LIB_SHADOW_CONTACT_SHADOW_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"

// ============================================================================
// Screen-space short-range contact shadows.
// ============================================================================
//
// Evaluated inline in deferred4 (opaque lighting) on the receiver: a short
// depth-buffer march toward the active directional light (sun or moon, world
// space). The ray is projected to screen space, so its reach is limited to
// occluders visible on screen, which is exactly the domain where the shadow
// map loses detail:
//   - near the receiver, PCF seams and bias leaks appear along contact lines;
//   - beyond the shadow-map boundary the map is absent and the march provides
//     the only directional occlusion.
//
// Occlusion model. Each step samples depthtex1 (all opaque geometry plus
// entities, the same layer the SSR trace uses). A sample occludes when the
// surface sits in front of the ray point within a world-space thickness slab
// (CONTACT_SHADOW_THICKNESS); the strongest proximity over the march becomes
// the shadow. The result is a visibility factor in
// [1 - CONTACT_SHADOW_DARKNESS, 1], applied in deferred4 as an upper bound
// (min) on the shadow-map result, so it only darkens what the map left lit.
//
// Softness comes from the per-step STBN dither (spatiotemporal blue noise)
// converged by the pack's TAA; the proximity exponent CONTACT_SHADOW_SOFTNESS
// shapes the edge. With TAA disabled the dither stays fixed to frame 0 so the
// shadow is static instead of shimmering.
//
// Provenance. The technique was studied from two reference packs under the
// project's pack-study rules (see docs/shader-architecture.md):
//   - Photon v1.3b, shaders/include/lighting/shadows/ssrt.glsl (custom study
//     license): screen-projected light ray marched against the depth buffer
//     with geometric steps, dither and a thickness tolerance;
//   - Revelation-dev, shaders/lib/lighting/shadow/Render.glsl (Apache-2.0):
//     fixed-step screen-space march with per-step transmittance absorption.
// This file is an independent re-expression around Vibroscat coordinate
// helpers, depth conversions and settings; no code or constants were taken.

// March from a view-space receiver along the world light direction.
//   receiver_view - camera-relative view-space receiver position
//   stbn_texel    - half-res texel used as the STBN spatial seed
//   frame         - STBN time slice (frameCounter with TAA, 0 without)
// Returns a visibility factor in [1 - CONTACT_SHADOW_DARKNESS, 1].
float ContactShadowOcclusion(vec3 receiver_view, ivec2 stbn_texel, int frame) {
    vec3 light_view = normalize(mat3(gbufferModelView) * u_world_light_dir);

    // When the light points toward the camera the projected endpoint would
    // cross the camera plane, where ViewToNDC divides by -z. Cap the march
    // distance so the endpoint stays strictly in front of the camera.
    float max_distance = CONTACT_SHADOW_MAX_DISTANCE;
    if (light_view.z > 1.0e-4) {
        max_distance = min(max_distance, -0.5 * receiver_view.z / light_view.z);
    }

    vec3 start_screen = ViewToNDC(receiver_view) * 0.5 + 0.5;
    vec3 end_screen = ViewToNDC(receiver_view + light_view * max_distance) * 0.5 + 0.5;
    vec3 screen_dir = end_screen - start_screen;

    // Box clamp: the largest t that keeps the ray inside the screen.
    vec2 bound = mix(vec2(0.0), vec2(1.0), step(0.0, screen_dir.xy));
    vec2 t_axis = (bound - start_screen.xy) / screen_dir.xy;
    t_axis = mix(t_axis, vec2(1.0), lessThan(abs(screen_dir.xy), vec2(1.0e-8)));
    float t_max = min(min(t_axis.x, t_axis.y), 1.0);
    if (t_max <= 0.0) {
        return 1.0;
    }

    float dither = SampleSTBN(stbn_texel, frame);
    float step_count = float(CONTACT_SHADOW_STEPS);
    float strongest_proximity = 0.0;
    vec2 full_resolution = vec2(viewWidth, viewHeight);

    for (int i = 0; i < CONTACT_SHADOW_STEPS; ++i) {
        // Quadratic spacing keeps the samples dense next to the receiver,
        // where contact occlusion lives; the shared dither jitters every
        // step so the silhouette converges under TAA.
        float u = (float(i) + 0.5 + 0.5 * dither) / step_count;
        float t = t_max * u * u;
        vec3 ray_screen = start_screen + screen_dir * t;
        if (any(lessThan(ray_screen.xy, vec2(0.0)))
                || any(greaterThan(ray_screen.xy, vec2(1.0)))
                || ray_screen.z >= 1.0 || ray_screen.z < 0.0) {
            break;
        }
        float sample_z = texelFetch(depthtex1, ivec2(ray_screen.xy * full_resolution), 0).r;
        if (sample_z >= 1.0) {
            continue;  // sky: no occluder
        }
        float gap = LinearDepthFromScreenDepth(ray_screen.z)
            - LinearDepthFromScreenDepth(sample_z);
        // Below the minimum gap the sample is the receiver's own surface
        // (self-shadow acne); beyond the thickness slab the surface sits too
        // far behind the ray point to cast a contact shadow.
        if (gap < CONTACT_SHADOW_GAP_MIN_METERS || gap > CONTACT_SHADOW_THICKNESS) {
            continue;
        }
        float proximity = 1.0 - gap / CONTACT_SHADOW_THICKNESS;
        // Contact shaping: the contribution fades linearly with the distance
        // along the ray, so nearby occluders darken strongly while grazing
        // hits far from the receiver barely register. This keeps the march a
        // short-range contact term instead of blanket directional occlusion.
        strongest_proximity = max(strongest_proximity, proximity * (1.0 - u));
    }

    float occlusion = pow(strongest_proximity, CONTACT_SHADOW_SOFTNESS);
    return mix(1.0, CONTACT_SHADOW_DARKNESS, occlusion);
}

#endif // LIB_SHADOW_CONTACT_SHADOW_GLSL
