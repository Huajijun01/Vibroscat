#ifndef LIB_SHADOW_CONTACT_SHADOW_GLSL
#define LIB_SHADOW_CONTACT_SHADOW_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"

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
// False-shadow guards:
//   - the ray starts offset along the receiver normal by a pixel-scaled,
//     1/NdotL-weighted bias, so the receiver's own surface plane cannot
//     self-occlude at grazing light angles;
//   - the thickness slab grows with view distance to track depth precision
//     while staying tight near the receiver;
//   - each sample is projected exactly (perspective divide per step) instead
//     of interpolating screen depth along the ray.
// Edge softness comes from the per-step STBN dither converged by the pack's
// TAA. With TAA disabled the dither stays fixed so the shadow is static.

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
//   stbn_dither   - STBN dither sampled by the pass main (STBNFrame():
//                   static without TAA)
// Returns 0.0 when an occluder sits inside the thickness slab, else 1.0.
float ContactShadowOcclusion(vec3 receiver_view, vec3 normal_view, float ndotl,
    float stbn_dither) {
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

    float step_count = float(CONTACT_SHADOW_STEPS);

    // Step pattern: linear strides that grow by 0.3 per
    // step, each sample dithered inside its stride. The first sample starts
    // one full stride out, so the receiver's own surface neighborhood is
    // skipped entirely instead of being probed by dense near-field samples.
    float stride = 1.0;
    float travelled = 0.0;
    float total_travel = step_count + 0.15 * step_count * (step_count - 1.0);

    for (int i = 0; i < CONTACT_SHADOW_STEPS; ++i) {
        float sample_t = travelled + stbn_dither * stride;
        vec3 sample_view = ray_origin + light_view * (march_distance * sample_t / total_travel);
        travelled += stride;
        stride += 0.3;
        if (sample_view.z > -0.05) {
            break;  // crossed the camera near plane
        }
        // Exact perspective projection per sample (no screen-depth lerp).
        // Only the XY clip rows are read, so the projection reduces to two
        // row dot products instead of a full mat4*vec4.
        vec4 sample_view4 = vec4(sample_view, 1.0);
        vec2 clip_xy = vec2(
            dot(vec4(gbufferProjection[0][0], gbufferProjection[1][0],
                     gbufferProjection[2][0], gbufferProjection[3][0]), sample_view4),
            dot(vec4(gbufferProjection[0][1], gbufferProjection[1][1],
                     gbufferProjection[2][1], gbufferProjection[3][1]), sample_view4));
        vec2 sample_uv = clip_xy / -sample_view.z * 0.5 + 0.5;
        if (any(lessThan(sample_uv, vec2(0.0)))
                || any(greaterThan(sample_uv, vec2(1.0)))) {
            break;  // left the screen
        }
        float sample_z = texture(depthtex1, sample_uv).r;
        // Occluder distance in view-space meters via the sparse inverse
        // projection (the same |view z| metric NDCToView reconstructs, and
        // the SSR helpers' canonical linearization). Sky falls out on its
        // own: the far-plane distance makes the gap negative.
        float sample_linear = LinearDepthFromScreenDepth(sample_z);
        float gap = -sample_view.z - sample_linear;
        // Strict inequalities: with both bounds at zero the window is empty.
        // The closed form would admit gap == 0.0, which still occurs when a
        // sample lands bit-exactly on a surface depth.
        if (gap > CONTACT_SHADOW_GAP_MIN_METERS && gap < thickness) {
            // First occluder inside the slab: remove the direct light.
            return 0.0;
        }
    }
    return 1.0;
}

#endif // LIB_SHADOW_CONTACT_SHADOW_GLSL
