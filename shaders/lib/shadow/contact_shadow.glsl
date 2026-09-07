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
// space), re-projected to the depth buffer per sample. A surface occludes
// when it sits in front of the ray point within a thickness slab; the first
// hit removes the direct light outright, so a contact hit fills a shadow-map
// seam to full black. The result is an upper bound (min) on the shadow-map
// result, so it only darkens what the map left lit.
//
// The march is a parameter-faithful adaptation of iterationT 3.2.0
// shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl (ScreenSpaceShadow) under
// the project's pack-study rules; that snapshot has no pack-level license,
// so only the concepts and parameters were taken:
//   - the ray scale is stride_budget * per_meter_scale * vertical_fov, with
//     a near floor tied to the shadow texel world size, so the reach grows
//     with view distance and stays short near the camera;
//   - the start is pushed off the receiver twice: along the ray by a
//     pixel-scaled amount that grows when the surface faces away from the
//     camera, and along the normal by a pixel-scaled amount that grows at
//     grazing light;
//   - linear strides that grow by 0.3 per step, each sample dithered inside
//     its stride, the first sample one full stride out;
//   - the thickness slab is 0.025 m near and widens with view distance to
//     track depth precision;
//   - each sample is projected exactly (perspective divide per step).
// Edge softness comes from the per-step STBN dither converged by the pack's
// TAA. With TAA disabled the dither stays fixed so the shadow is static.
//
// The technique was also compared against Photon v1.3b
// shaders/include/lighting/shadows/ssrt.glsl and Revelation-dev
// shaders/lib/lighting/shadow/Render.glsl; this file is an independent
// re-expression around Vibroscat coordinate helpers and settings.

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

    float dither = SampleSTBN(stbn_texel, frame);
    float step_count = float(CONTACT_SHADOW_STEPS);

    // Ray scale: the stride budget (1 + 1.3 + 1.6 + ...) times a per-meter
    // scale tied to the vertical field of view, floored by the shadow texel
    // world size so close receivers still get a minimum march. The reach in
    // meters is the scale times the budget, capped by the user option.
    float total_travel = step_count + 0.15 * step_count * (step_count - 1.0);
    float fov_degrees = atan(1.0 / max(gbufferProjection[1][1], 1.0e-4)) * 360.0 / PI;
    float ray_scale = max(receiver_distance * 3.0e-5 * fov_degrees,
        0.06 * shadowDistance / float(shadowMapResolution));
    float march_distance = min(CONTACT_SHADOW_MAX_DISTANCE, ray_scale * total_travel);

    // Start bias: off the receiver's own surface plane along the ray (grows
    // when the surface faces away from the camera), then along the normal
    // (grows at grazing light).
    float pixel_scale = 1.0 / max(min(viewWidth, viewHeight), 1.0);
    float nov = Max0(dot(normal_view, -normalize(receiver_view)));
    vec3 ray_origin = receiver_view
        + light_view * (ray_scale * pixel_scale * max(0.04 / max(nov, 0.1), 1.0e3))
        + normal_view * (8.0e-3 * fov_degrees * receiver_distance * pixel_scale
            / max(ndotl, 0.01));

    float thickness = CONTACT_SHADOW_THICKNESS
        + CONTACT_SHADOW_THICKNESS_GROWTH_PER_METER * receiver_distance;
    vec2 full_resolution = vec2(viewWidth, viewHeight);

    float stride = 1.0;
    float travelled = 0.0;
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
        if (gap > 0.0 && gap < thickness) {
            // First occluder inside the slab: remove the direct light.
            return 0.0;
        }
    }
    return 1.0;
}

#endif // LIB_SHADOW_CONTACT_SHADOW_GLSL
