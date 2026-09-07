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
// space), re-projected to the depth buffer per sample. Occluders are
// surfaces that sit in front of the ray point within a thickness slab; the
// first hit removes the direct light outright, so a contact hit fills a
// shadow-map seam to full black. The result is an
// upper bound (min) on the shadow-map result, so it only darkens what the
// map left lit.
//
// False-shadow guards, studied from iterationT 3.2.0
// shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl (ScreenSpaceShadow) under
// the project's pack-study rules; that snapshot has no pack-level license,
// so only the concepts were taken:
//   - the ray starts offset along the receiver normal by a pixel-scaled,
//     1/NdotL-weighted bias, so the receiver's own surface plane cannot
//     self-occlude at grazing light angles;
//   - the thickness slab grows with view distance to track depth precision
//     while staying tight near the receiver;
//   - each sample is projected exactly (perspective divide per step) instead
//     of interpolating screen depth along the ray.
// Edge softness comes from the per-step STBN dither converged by the pack's
// TAA. With TAA disabled the dither stays fixed so the shadow is static.
//
// The technique was also compared against Photon v1.3b
// shaders/include/lighting/shadows/ssrt.glsl and Revelation-dev
// shaders/lib/lighting/shadow/Render.glsl; this file is an independent
// re-expression around Vibroscat coordinate helpers and settings.

// The march reach scales with view distance (a fixed angular footprint
// matches the screen-space resolvability), bounded by the near floor and
// the CONTACT_SHADOW_MAX_DISTANCE cap. A fixed world reach would sweep a
// long grazing path near the camera and manufacture false hits.
const float CONTACT_SHADOW_REACH_FRACTION = 0.07;
const float CONTACT_SHADOW_REACH_MIN_METERS = 0.12;
// Receiver normal offset: pixel world size times this scale, divided by the
// light-facing cosine, keeps the start off the surface plane (grazing light
// needs the largest push-out).
const float CONTACT_SHADOW_NORMAL_BIAS_SCALE = 0.75;
// Thickness growth per meter of view distance (m/m): depth precision
// coarsens with distance, so the slab widens accordingly.
const float CONTACT_SHADOW_THICKNESS_GROWTH_PER_METER = 0.0125;

// March from a view-space receiver along the world light direction.
//   receiver_view - camera-relative view-space receiver position
//   normal_view   - view-space geometric normal
//   ndotl         - geometric normal dot light direction
//   stbn_texel    - fragment texel used as the STBN spatial seed
//   frame         - STBN time slice (frameCounter with TAA, 0 without)
// Returns 0.0 when an occluder sits inside the thickness slab, else 1.0.
float ContactShadowOcclusion(vec3 receiver_view, vec3 normal_view, float ndotl,
    ivec2 stbn_texel, int frame) {
    vec3 light_view = normalize(mat3(gbufferModelView) * u_world_light_dir);
    float receiver_distance = -receiver_view.z;

    // Push the ray start off the receiver's surface plane. The offset is one
    // screen pixel of world size at this depth, amplified for grazing light.
    float pixel_world_size = receiver_distance
        / max(gbufferProjection[1][1] * viewHeight, 1.0);
    vec3 ray_origin = receiver_view + normal_view
        * (CONTACT_SHADOW_NORMAL_BIAS_SCALE * pixel_world_size / max(ndotl, 0.1));

    // Thickness widens with distance, tracking depth quantization.
    float thickness = CONTACT_SHADOW_THICKNESS
        + CONTACT_SHADOW_THICKNESS_GROWTH_PER_METER * receiver_distance;

    // Distance-scaled reach: short near the camera, growing toward the
    // shadow-map boundary, capped by the user option.
    float march_distance = min(CONTACT_SHADOW_MAX_DISTANCE,
        max(CONTACT_SHADOW_REACH_MIN_METERS,
            CONTACT_SHADOW_REACH_FRACTION * receiver_distance));

    float dither = SampleSTBN(stbn_texel, frame);
    float step_count = float(CONTACT_SHADOW_STEPS);
    vec2 full_resolution = vec2(viewWidth, viewHeight);

    // iterationT-style step pattern: linear strides that grow by 0.3 per
    // step, each sample dithered inside its stride. The first sample starts
    // one full stride out, so the receiver's own surface neighborhood is
    // skipped entirely instead of being probed by dense near-field samples.
    float stride = 1.0;
    float travelled = 0.0;
    float total_travel = step_count + 0.15 * step_count * (step_count - 1.0);

    for (int i = 0; i < CONTACT_SHADOW_STEPS; ++i) {
        float sample_t = travelled + dither * stride;
        vec3 sample_view = ray_origin + light_view * (march_distance * sample_t / total_travel);
        travelled += stride;
        stride += 0.3;
        if (sample_view.z > -0.05) {
            break;  // crossed the camera near plane
        }
        // Exact perspective projection per sample (no screen-depth lerp).
        vec4 clip_h = gbufferProjection * vec4(sample_view, 1.0);
        vec2 sample_uv = clip_h.xy / -sample_view.z * 0.5 + 0.5;
        if (any(lessThan(sample_uv, vec2(0.0)))
                || any(greaterThan(sample_uv, vec2(1.0)))) {
            break;  // left the screen
        }
        float sample_z = texelFetch(depthtex1, ivec2(sample_uv * full_resolution), 0).r;
        if (sample_z >= 1.0) {
            continue;  // sky: no occluder
        }
        // Gap in view-space meters via the canonical reconstruction (the
        // same space as GTAO_RADIUS). The SSR depth helper is only a
        // monotonic metric with its own tolerance units.
        vec2 sample_ndc_xy = sample_uv * 2.0 - 1.0;
        float sample_linear = -NDCToView(vec3(sample_ndc_xy, sample_z * 2.0 - 1.0)).z;
        float gap = -sample_view.z - sample_linear;
        if (gap < CONTACT_SHADOW_GAP_MIN_METERS || gap > thickness) {
            continue;
        }
        // Binary response: the first occluder inside the thickness slab
        // removes the direct light outright.
        return 0.0;
    }
    return 1.0;
}

#endif // LIB_SHADOW_CONTACT_SHADOW_GLSL
