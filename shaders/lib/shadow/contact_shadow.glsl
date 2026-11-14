#ifndef LIB_SHADOW_CONTACT_SHADOW_GLSL
#define LIB_SHADOW_CONTACT_SHADOW_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/render_scale.glsl"

// Ordinary opaque contact shadows; plant visibility uses its own estimator in
// plant_distant_shadow.glsl.
const float CONTACT_SHADOW_REACH_FRACTION = 0.07;
const float CONTACT_SHADOW_REACH_MIN_METERS = 0.12;
// Receiver normal offset: pixel world size * scale / light-facing cosine;
// grazing light needs the largest push-out.
const float CONTACT_SHADOW_NORMAL_BIAS_SCALE = 0.75;
// m/m slab growth: depth precision coarsens with distance.
const float CONTACT_SHADOW_THICKNESS_GROWTH_PER_METER = 0.0125;
float ContactShadowOcclusion(vec3 receiver_view, vec3 normal_view, float ndotl,
    float stbn_dither) {
    float receiver_distance = -receiver_view.z;

    float pixel_world_size = receiver_distance / u_pixel_world_scale;
    vec3 ray_origin = receiver_view + normal_view
        * (CONTACT_SHADOW_NORMAL_BIAS_SCALE * pixel_world_size / max(ndotl, 0.1));
    float minimum_gap = CONTACT_SHADOW_GAP_MIN_METERS;

    float thickness = CONTACT_SHADOW_THICKNESS
        + CONTACT_SHADOW_THICKNESS_GROWTH_PER_METER * receiver_distance;

    float march_distance = min(CONTACT_SHADOW_MAX_DISTANCE,
        max(CONTACT_SHADOW_REACH_MIN_METERS,
            CONTACT_SHADOW_REACH_FRACTION * receiver_distance));

    float step_count = float(CONTACT_SHADOW_STEPS);

    float stride = 1.0;
    float travelled = 0.0;
    float total_travel = travelled + step_count + 0.15 * step_count * (step_count - 1.0);
    float step_scale = march_distance / total_travel;
    float visibility = 1.0;

    // Projection is linear before the perspective divide: hoist the origin and
    // stride projections, then reconstruct clip XY per sample with one divide.
    vec4 clip_row_x = vec4(gbufferProjection[0][0], gbufferProjection[1][0],
        gbufferProjection[2][0], gbufferProjection[3][0]);
    vec4 clip_row_y = vec4(gbufferProjection[0][1], gbufferProjection[1][1],
        gbufferProjection[2][1], gbufferProjection[3][1]);
    vec3 ray_step = u_view_light_dir * step_scale;
    vec2 clip_origin = vec2(dot(clip_row_x, vec4(ray_origin, 1.0)),
        dot(clip_row_y, vec4(ray_origin, 1.0)));
    vec2 clip_step = vec2(dot(clip_row_x, vec4(ray_step, 0.0)),
        dot(clip_row_y, vec4(ray_step, 0.0)));
    // Batched for independent depth reads; stride updates stay ordered to
    // preserve sample positions.
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
            / max(ray_depth, vec4(0.05)) * 0.5 + 0.5;
        vec4 sample_v = (clip_origin.y + clip_step.y * sample_t)
            / max(ray_depth, vec4(0.05)) * 0.5 + 0.5;
        vec4 edge_distance = min(min(sample_u, 1.0 - sample_u),
            min(sample_v, 1.0 - sample_v));
        bvec4 valid = bvec4(
            i + 0 < CONTACT_SHADOW_STEPS && ray_depth.x >= 0.05 && edge_distance.x >= 0.0,
            i + 1 < CONTACT_SHADOW_STEPS && ray_depth.y >= 0.05 && edge_distance.y >= 0.0,
            i + 2 < CONTACT_SHADOW_STEPS && ray_depth.z >= 0.05 && edge_distance.z >= 0.0,
            i + 3 < CONTACT_SHADOW_STEPS && ray_depth.w >= 0.05 && edge_distance.w >= 0.0
        );
        valid.y = valid.x && valid.y;
        valid.z = valid.y && valid.z;
        valid.w = valid.z && valid.w;
        if (!valid.x) break;
        // deferred1 precedes translucency: depthtex0 == depthtex1 for opaque/hand
        // depth here, so reuse depthtex0 instead of a second depth texture.
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
        // The slab comparison is precision-sensitive; do not reassociate.
        vec4 sample_linear = 1.0 / ((sample_z * 2.0 - 1.0) * gbufferProjectionInverse[2][3]
            + gbufferProjectionInverse[3][3]);
        vec4 gap = ray_depth - sample_linear;
        bvec4 hit = bvec4(
            valid.x && gap.x > minimum_gap && gap.x < thickness,
            valid.y && gap.y > minimum_gap && gap.y < thickness,
            valid.z && gap.z > minimum_gap && gap.z < thickness,
            valid.w && gap.w > minimum_gap && gap.w < thickness
        );
        visibility *= (1.0 - float(hit.x)) * (1.0 - float(hit.y))
            * (1.0 - float(hit.z)) * (1.0 - float(hit.w));
        if (visibility < 0.015 || !valid.w) break;
    }
    return visibility;
}

#endif // LIB_SHADOW_CONTACT_SHADOW_GLSL
