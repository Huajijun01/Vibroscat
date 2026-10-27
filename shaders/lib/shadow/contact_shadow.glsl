#ifndef LIB_SHADOW_CONTACT_SHADOW_GLSL
#define LIB_SHADOW_CONTACT_SHADOW_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/render_scale.glsl"

// ============================================================================
// Screen-space short-range contact shadows.
// ============================================================================
//
// Evaluated inline in deferred4 (opaque lighting) on the receiver: a short
// depth-buffer march toward the active directional light (sun or moon, world
// space), re-projected to the depth buffer per sample. Occluders are
// surfaces that sit in front of the ray point within a thickness slab; the
// first hit removes opaque direct light. Plant receivers retain partial
// visibility instead, using only the receiver material (no per-hit material
// fetch). Their partial visibility constrains transmission at every distance.
// Opaque visibility bounds map visibility; plant visibility multiplies it.
//
// False-shadow guards:
//   - opaque rays start offset along the receiver normal by a pixel-scaled,
//     1/NdotL-weighted bias, so the receiver's own surface plane cannot
//     self-occlude at grazing light angles; plants instead skip a light stride;
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
// A wider plant footprint spreads partial occupancy across blade clusters.
// Use the full depth budget: sparse, heavily weighted hits make bands on grass.
const float CONTACT_SHADOW_PLANT_REACH_FRACTION = 0.12;
const float CONTACT_SHADOW_PLANT_REACH_MIN_METERS = 0.2;
// Receiver normal offset: pixel world size times this scale, divided by the
// light-facing cosine, keeps the start off the surface plane (grazing light
// needs the largest push-out).
const float CONTACT_SHADOW_NORMAL_BIAS_SCALE = 0.75;
// Thickness growth per meter of view distance (m/m): depth precision
// coarsens with distance, so the slab widens accordingly.
const float CONTACT_SHADOW_THICKNESS_GROWTH_PER_METER = 0.0125;
// Optical path represented by one fully occupied march. Depth increases the
// footprint/subpixel foliage density, so distant hits absorb more. The budget
// is divided by the step count once, preserving the effect across quality tiers.
const float CONTACT_SHADOW_PLANT_PATH_BASE = 2.0;
const float CONTACT_SHADOW_PLANT_PATH_DEPTH_SCALE = 0.5;

// March from a view-space receiver along the world light direction.
//   receiver_view - camera-relative view-space receiver position
//   normal_view   - view-space geometric normal
//   ndotl         - geometric normal dot light direction
//   stbn_dither   - STBN dither sampled by the pass main (STBNFrame():
//                   static without TAA)
// sss_amount is the receiver's translucency; zero keeps first-hit opaque shadows.
// Returns visibility in [0,1]. Receiver attenuation cannot identify solid
// blockers: the map and skylight retain large-scale sheltering for plants.
float ContactShadowOcclusion(vec3 receiver_view, vec3 normal_view, float ndotl,
    float stbn_dither, float sss_amount) {
    float receiver_distance = -receiver_view.z;

    // Opaque normal bias uses one pixel of world size at this depth,
    // amplified for grazing light. Plants use their initial light stride.
    float pixel_world_size = receiver_distance / u_pixel_world_scale;
    bool plant_receiver = sss_amount > 0.01;
    // Crossed blades have no unique solid surface normal. Their initial light
    // stride below guards self-hits without a lateral normal-dependent offset.
    vec3 ray_origin = receiver_view;
    if (!plant_receiver) {
        ray_origin += normal_view
            * (CONTACT_SHADOW_NORMAL_BIAS_SCALE * pixel_world_size / max(ndotl, 0.1));
    }
    float minimum_gap = plant_receiver ? 0.001 : CONTACT_SHADOW_GAP_MIN_METERS;

    // Thickness widens with distance, tracking depth quantization.
    float thickness = CONTACT_SHADOW_THICKNESS
        + CONTACT_SHADOW_THICKNESS_GROWTH_PER_METER * receiver_distance;

    // Distance-scaled reach: short near the camera, growing toward the
    // shadow-map boundary, capped by the user option.
    float march_distance = min(CONTACT_SHADOW_MAX_DISTANCE,
        max(plant_receiver ? CONTACT_SHADOW_PLANT_REACH_MIN_METERS : CONTACT_SHADOW_REACH_MIN_METERS,
            (plant_receiver ? CONTACT_SHADOW_PLANT_REACH_FRACTION : CONTACT_SHADOW_REACH_FRACTION)
                * receiver_distance));

    float step_count = float(CONTACT_SHADOW_STEPS);

    // Step pattern: linear strides that grow by 0.3 per step, each sample
    // dithered inside its stride. The normal bias and minimum gap guard the
    // receiver's surface. Thin plants skip one base stride toward the light
    // so the first sample does not repeatedly probe their own crossed quads.
    float stride = 1.0;
    float travelled = plant_receiver ? 1.0 : 0.0;
    float total_travel = travelled + step_count + 0.15 * step_count * (step_count - 1.0);
    // Loop-invariant sample scaling: the per-step distance is linear in the
    // travelled parameter, so fold march_distance/total_travel once.
    float step_scale = march_distance / total_travel;
    // Compute extinction once for this receiver. Every accepted depth hit
    // multiplies this factor; no sampled-pixel classification or per-hit exp.
    float step_visibility = 0.0;
    if (plant_receiver) {
        float plant_path = (CONTACT_SHADOW_PLANT_PATH_BASE
            + CONTACT_SHADOW_PLANT_PATH_DEPTH_SCALE * sqrt(receiver_distance))
            * (SHADOW_SSS_DENSITY / 3.0) / max(sss_amount, 0.35);
        step_visibility = exp(-plant_path / step_count);
    }
    // Opaque hits have full confidence and zero retention. Each batch keeps
    // the same first-hit result without a receiver/material branch per hit.
    float edge_confidence_floor = plant_receiver ? 0.0 : 1.0;
    float visibility = 1.0;

    // Projection is linear before the perspective divide. Project the origin
    // and world-space stride once, then reconstruct exact clip XY per sample.
    // The per-sample divide still preserves perspective depth and ray shape.
    vec4 clip_row_x = vec4(gbufferProjection[0][0], gbufferProjection[1][0],
        gbufferProjection[2][0], gbufferProjection[3][0]);
    vec4 clip_row_y = vec4(gbufferProjection[0][1], gbufferProjection[1][1],
        gbufferProjection[2][1], gbufferProjection[3][1]);
    vec3 ray_step = u_view_light_dir * step_scale;
    vec2 clip_origin = vec2(dot(clip_row_x, vec4(ray_origin, 1.0)),
        dot(clip_row_y, vec4(ray_origin, 1.0)));
    vec2 clip_step = vec2(dot(clip_row_x, vec4(ray_step, 0.0)),
        dot(clip_row_y, vec4(ray_step, 0.0)));
    vec2 depth_jitter = vec2(0.0);
#ifdef TAA
    // The receiver was reconstructed without jitter; sample the jittered
    // depth lattice again for plants. Decide once, outside the sample loop.
    if (plant_receiver) depth_jitter = u_taa_offset * 0.5;
#endif

    // Batch four consecutive steps to expose the four depth reads as
    // independent work before any hit consumes them. Stride updates and hit
    // products stay scalar and ordered to preserve sample positions and
    // plant accumulation.
    for (int i = 0; i < CONTACT_SHADOW_STEPS; i += 4) {
        vec4 sample_t;
        sample_t.x = travelled + stbn_dither * stride;
        travelled += stride;
        stride += 0.3;
        sample_t.y = travelled + stbn_dither * stride;
        travelled += stride;
        stride += 0.3;
        sample_t.z = travelled + stbn_dither * stride;
        travelled += stride;
        stride += 0.3;
        sample_t.w = travelled + stbn_dither * stride;
        travelled += stride;
        stride += 0.3;
        vec4 ray_depth = -(ray_origin.z + ray_step.z * sample_t);
        vec4 sample_u = (clip_origin.x + clip_step.x * sample_t)
            / max(ray_depth, vec4(0.05)) * 0.5 + 0.5 + depth_jitter.x;
        vec4 sample_v = (clip_origin.y + clip_step.y * sample_t)
            / max(ray_depth, vec4(0.05)) * 0.5 + 0.5 + depth_jitter.y;
        // One signed border distance serves both bounds rejection and plant
        // edge fading; four independent UV comparisons duplicate this work.
        vec4 edge_distance = min(min(sample_u, 1.0 - sample_u),
            min(sample_v, 1.0 - sample_v));
        bvec4 valid = bvec4(
            i + 0 < CONTACT_SHADOW_STEPS && ray_depth.x >= 0.05 && edge_distance.x >= 0.0,
            i + 1 < CONTACT_SHADOW_STEPS && ray_depth.y >= 0.05 && edge_distance.y >= 0.0,
            i + 2 < CONTACT_SHADOW_STEPS && ray_depth.z >= 0.05 && edge_distance.z >= 0.0,
            i + 3 < CONTACT_SHADOW_STEPS && ray_depth.w >= 0.05 && edge_distance.w >= 0.0
        );
        // for (int j = 0; j < 4; ++j) {
        //     valid[j] = i + j < CONTACT_SHADOW_STEPS && ray_depth[j] >= 0.05 && edge_distance[j] >= 0.0;
        // }
        // Stop at the first invalid sample, including a partial final batch.
        valid.y = valid.x && valid.y;
        valid.z = valid.y && valid.z;
        valid.w = valid.z && valid.w;
        if (!valid.x) break;
        // deferred4 precedes translucent geometry: depthtex0 and depthtex1
        // contain the same opaque/hand depth here. Reuse the receiver's
        // depthtex0 resource instead of sampling a second depth texture.
        vec2 sample_uv_0 = vec2(sample_u.x, sample_v.x);
        vec2 sample_uv_1 = vec2(sample_u.y, sample_v.y);
        vec2 sample_uv_2 = vec2(sample_u.z, sample_v.z);
        vec2 sample_uv_3 = vec2(sample_u.w, sample_v.w);
#if defined(TAAU_ACTIVE)
        sample_uv_0 = SceneTextureUV(sample_uv_0);
        sample_uv_1 = SceneTextureUV(sample_uv_1);
        sample_uv_2 = SceneTextureUV(sample_uv_2);
        sample_uv_3 = SceneTextureUV(sample_uv_3);
#endif
#if CONTACT_SHADOW_STEPS % 4 == 0
        vec4 sample_z = vec4(
            textureLod(depthtex0, sample_uv_0, 0.0).r,
            textureLod(depthtex0, sample_uv_1, 0.0).r,
            textureLod(depthtex0, sample_uv_2, 0.0).r,
            textureLod(depthtex0, sample_uv_3, 0.0).r);
#else
        // The six-step option has only two samples in its final batch.
        vec4 sample_z = vec4(
            textureLod(depthtex0, sample_uv_0, 0.0).r,
            textureLod(depthtex0, sample_uv_1, 0.0).r,
            1.0, 1.0);
        if (i + 2 < CONTACT_SHADOW_STEPS) {
            sample_z.z = textureLod(depthtex0, sample_uv_2, 0.0).r;
            sample_z.w = textureLod(depthtex0, sample_uv_3, 0.0).r;
        }
#endif
        // Keep the original view-depth subtraction and strict slab bounds.
        // Reconstruct the independent depths without reassociating the
        // precision-sensitive comparison against the thickness slab.
        vec4 sample_linear = 1.0 / ((sample_z * 2.0 - 1.0) * gbufferProjectionInverse[2][3]
            + gbufferProjectionInverse[3][3]);
        vec4 gap = ray_depth - sample_linear;
        vec4 confidence = max(vec4(edge_confidence_floor),
            saturate(edge_distance * 16.0));
        bvec4 hit = bvec4(
            valid.x && gap.x > minimum_gap && gap.x < thickness,
            valid.y && gap.y > minimum_gap && gap.y < thickness,
            valid.z && gap.z > minimum_gap && gap.z < thickness,
            valid.w && gap.w > minimum_gap && gap.w < thickness
        );
        vec4 retention = mix(vec4(1.0), vec4(step_visibility), confidence * vec4(hit));
        // for (int j = 0; j < 4; ++j) {
        //     bool hit = valid[j] && gap[j] > minimum_gap && gap[j] < thickness;
        //     visibility *= hit ? retention[j] : 1.0;
        // }
        visibility *= retention.x * retention.y * retention.z * retention.w;
        if (visibility < 0.015 || !valid.w) break;
    }
    return visibility;
}

#endif // LIB_SHADOW_CONTACT_SHADOW_GLSL
