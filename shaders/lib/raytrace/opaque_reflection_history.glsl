#ifndef LIB_RAYTRACE_OPAQUE_REFLECTION_HISTORY_GLSL
#define LIB_RAYTRACE_OPAQUE_REFLECTION_HISTORY_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/color/spaces.glsl"
#include "/lib/material/opaque_surface.glsl"

// RGB is the unblurred mean of Z = (Li * sampled throughput) / material factor.
// RGB is stored directly in colortex3; metadata carries no color bits.
// RGBA16UI: depth half | rough8/selector8 | unused8/age5/state3 | log2(1+v_Z) half.
// No historical normal: each previous tap is projected into the current GBuffer.
const float OPAQUE_HISTORY_MAX = 31.0;
const vec3 OPAQUE_HISTORY_RGB_MAX = vec3(65024.0, 65024.0, 64512.0);

float OpaqueHistoryDepth(uvec4 data) {
    return unpackHalf2x16(data.r).x;
}

float OpaqueHistoryAge(uvec4 data) {
    return float((data.b >> 8) & 31u);
}

float OpaqueHistoryVariance(uvec4 data) {
    return exp2(unpackHalf2x16(data.a).x) - 1.0;
}

float OpaqueHistoryRoughness(uvec4 data) {
    return float(data.g & 255u) / 255.0;
}

uvec4 PackOpaqueHistory(float depth_view, vec2 material,
        float age, int change_state, float variance) {
    uint depth_bits = packHalf2x16(vec2(depth_view, 0.0)) & 65535u;
    // Reject unrepresentable depths, including half overflow and underflow.
    if (depth_bits == 0u || depth_bits >= 0x7c00u) return uvec4(0u);
    uint roughness = uint(round(saturate(material.x) * 255.0));
    uint selector = uint(round(saturate(material.y) * 255.0));
    uint state = change_state < 0 ? uint(3 - change_state) : uint(change_state);
    uint variance_bits = packHalf2x16(vec2(log2(1.0 + max(variance, 0.0)), 0.0)) & 65535u;
    // A nonzero age certifies finite RGB and a finite decoded variance.
    // Half log values >= 128 would overflow exp2 on the next frame.
    if (variance_bits >= 0x5800u) return uvec4(0u);
    return uvec4(depth_bits, roughness | (selector << 8),
        (uint(round(clamp(age, 1.0, OPAQUE_HISTORY_MAX))) << 8) | (state << 13),
        variance_bits);
}

#if defined(OPAQUE_SSR) && OPAQUE_SSR_FILTER > 0

struct OpaqueHistoryGather {
    vec3 sum_z;
    float sum_second;
    float sum_age;
    float weight_sum;
    float dominant_weight;
    uint dominant_data;
};

struct OpaqueHistoryGuide {
    vec3 receiver_view;
    vec3 previous_receiver_view;
    vec3 geo_previous_view;
    vec3 geo_view;
    vec3 normal_world;
    vec2 material;
    float normal_floor;
};

// A previous tap is reconstructed at its OWN texel center and stored depth.
// History addressing follows camera motion only, independently of TAA jitter.
vec3 OpaquePreviousPosition(ivec2 texel, float depth_view) {
    vec2 uv = (vec2(texel) + 0.5) * u_render_pixel_size;
    vec2 ray = (uv * 2.0 - 1.0 + gbufferPreviousProjection[2].xy)
        / vec2(gbufferPreviousProjection[0][0], gbufferPreviousProjection[1][1]);
    return vec3(ray, -1.0) * depth_view;
}

// Visibility and normal proxy at a historical tap's CURRENT projected location.
float OpaqueHistoryTapWeight(ivec2 receiver_texel, ivec2 history_texel, uvec4 data,
        OpaqueHistoryGuide guide) {
    // Nonzero age certifies a positive finite depth from PackOpaqueHistory.
    if (OpaqueHistoryAge(data) < 1.0) return 0.0;
    float depth_view = OpaqueHistoryDepth(data);
    if (abs(OpaqueHistoryRoughness(data) - guide.material.x) > 0.025) return 0.0;
    if (abs(float(data.g >> 8) / 255.0 - guide.material.y) > 1.5 / 255.0) return 0.0;
    if (u_ssr_history_static) {
        // Identical camera frames have one tap at this receiver. Its
        // stored depth scales the same view ray, so the plane residual is
        // a scalar depth difference; no projection or normal proxy is needed.
        float plane_tolerance = 0.015 + 0.0006 * depth_view;
        float plane_error = abs((depth_view + guide.receiver_view.z)
            * (dot(guide.geo_view, guide.receiver_view) / guide.receiver_view.z));
        return 1.0 - smoothstep(plane_tolerance, plane_tolerance * 2.0, plane_error);
    }
    vec3 old_view = OpaquePreviousPosition(history_texel, depth_view);
    vec3 delta_previous = old_view - guide.previous_receiver_view;
    float depth_error = 0.0006 * depth_view;
    float plane_tolerance = 0.015 + depth_error;
    float plane_error = abs(dot(delta_previous, guide.geo_previous_view));
    if (plane_error > plane_tolerance * 2.0) return 0.0;
    vec3 predicted_view = guide.receiver_view + vec3(
        dot(u_ssr_previous_to_view_x, delta_previous),
        dot(u_ssr_previous_to_view_y, delta_previous),
        dot(u_ssr_previous_to_view_z, delta_previous));
    if (predicted_view.z >= -1e-4 || !IsFinite(predicted_view)) return 0.0;
    vec2 current_uv = ViewToNDC(predicted_view).xy * 0.5 + 0.5;
    if (any(lessThan(current_uv, vec2(0.0))) || any(greaterThanEqual(current_uv, vec2(1.0)))) return 0.0;
    ivec2 current_texel = ivec2(current_uv * u_render_res);
    float plane_weight = 1.0 - smoothstep(plane_tolerance, plane_tolerance * 2.0, plane_error);
    // The caller already decoded this texel's visible depth, material and
    // normal. The same proxy needs no additional GBuffer reads or transforms.
    if (all(equal(current_texel, receiver_texel))) return plane_weight;
    float current_depth = texelFetch(depthtex0, current_texel, 0).r;
    if (current_depth >= 1.0) return 0.0;
    // Depth first: sky does not write the opaque surface packet.
    vec4 proxy = texelFetch(colortex11, current_texel, 0);
    vec2 current_material = UnpackOpaqueReflectance(proxy);
    if (abs(current_material.x - guide.material.x) > 0.025
            || abs(current_material.y - guide.material.y) > 1.5 / 255.0) return 0.0;
    if (int(texelFetch(colortex1, current_texel, 0).a * 255.0 + 0.5) == 64) return 0.0;
    vec2 center_uv = (vec2(current_texel) + 0.5) * u_render_pixel_size;
    float visible_z = -LinearDepthFromScreenDepth(current_depth);
    vec2 ray_xy = (center_uv * 2.0 - 1.0)
        * vec2(gbufferProjectionInverse[0][0], gbufferProjectionInverse[1][1]);
    float ray_plane_rate = dot(guide.geo_view.xy, ray_xy) - guide.geo_view.z;
    float ray_plane = -visible_z * ray_plane_rate;
    if (abs(ray_plane) < 1e-6) return 0.0;
    // Both original 3D tests share the same plane residual. The ray/plane
    // depth error is residual / ray_plane_rate; compare after multiplying
    // the tolerance so neither an intersection vector nor a division is needed.
    float plane_residual = abs(ray_plane - dot(guide.geo_view, predicted_view));
    float footprint = -predicted_view.z * 2.0 * u_render_pixel_size.y
        / abs(gbufferProjection[1][1]);
    if (plane_residual > min((0.02 + depth_error + footprint * 0.5) * abs(ray_plane_rate),
            plane_tolerance * 2.0)) return 0.0;
    vec3 proxy_normal = DecodeOctahedralNormal(proxy.rg);
    return plane_weight * smoothstep(guide.normal_floor, 1.0, dot(proxy_normal, guide.normal_world));
}

void GatherOpaqueHistoryTap(ivec2 receiver_texel, ivec2 tap, float weight,
        OpaqueHistoryGuide guide, inout OpaqueHistoryGather gather) {
    if (any(lessThan(tap, ivec2(0))) || any(greaterThanEqual(tap, ivec2(u_render_res)))) return;
    if (weight < 1e-5) return;
    uvec4 data = texelFetch(colortex6, tap, 0);
    weight *= OpaqueHistoryTapWeight(receiver_texel, tap, data, guide);
    if (weight <= 0.0) return;
    vec3 history_z = texelFetch(colortex3, tap, 0).rgb;
    float history_variance = OpaqueHistoryVariance(data);
    // Both MRT outputs are written and flipped together. PackOpaqueHistory
    // and the export check validate them once, rather than at every read.
    float y = Luminance(history_z);
    gather.sum_z += weight * history_z;
    gather.sum_second += weight * (history_variance + y * y);
    gather.sum_age += weight * OpaqueHistoryAge(data);
    gather.weight_sum += weight;
    if (weight > gather.dominant_weight) {
        gather.dominant_weight = weight;
        gather.dominant_data = data.b;
    }
}

vec3 AccumulateOpaqueHistory(ivec2 texel, vec3 sample_z, vec3 world_pos,
        vec3 receiver_view, vec3 view_to_eye, vec3 normal_world, vec3 geo_normal_world, vec3 geo_view,
        vec2 material, int material_id, out uvec4 metadata) {
    vec3 result;
    // View-model samples cannot become history for newly uncovered world surfaces.
    if (material_id == 64) {
        metadata = uvec4(0u);
        result = sample_z;
    } else {
        float age = 1.0;
        float variance = 0.0;
        int change_state = 0;
        vec3 mean_z = sample_z;
        float sample_y = Luminance(sample_z);
        // Resizing/reloading recreates and clears both sides. Abrupt translation,
        // view rotation, or projection discontinuities must not reuse old samples.
        vec3 current_forward = gbufferModelViewInverse[2].xyz;
        vec3 previous_forward = transpose(mat3(gbufferPreviousModelView)) * vec3(0.0, 0.0, 1.0);
        bool camera_valid = u_camera_delta_sq < 16.0 && dot(current_forward, previous_forward) > 0.85
            && abs(gbufferPreviousProjection[1][1] / gbufferProjection[1][1] - 1.0) < 0.15;
        if (frameCounter > 1 && camera_valid) {
            // Reproject a displacement, not a view -> world -> view round trip.
            // This preserves exact zero pixel motion for identical camera frames;
            // round-off must not activate three almost-zero bilinear taps.
            vec3 previous_view = receiver_view;
            vec2 ndc_delta = vec2(0.0);
            if (!u_ssr_history_static) {
                vec4 receiver_world = vec4(world_pos, 1.0);
                vec3 delta_view = vec3(dot(u_ssr_previous_delta_x, receiver_world),
                    dot(u_ssr_previous_delta_y, receiver_world), dot(u_ssr_previous_delta_z, receiver_world));
                previous_view += delta_view;
                vec2 current_ndc = (vec2(texel) + 0.5) * u_render_pixel_size * 2.0 - 1.0;
                ndc_delta = (vec2(gbufferPreviousProjection[0][0], gbufferPreviousProjection[1][1])
                    * delta_view.xy + u_ssr_projection_delta * receiver_view.xy + current_ndc * delta_view.z
                    + gbufferPreviousProjection[2].xy * previous_view.z) / -previous_view.z;
            }
            vec2 pixel_motion = ndc_delta * (0.5 * u_render_res);
            vec2 history_pixel = vec2(texel) + pixel_motion;
            vec2 previous_uv = (history_pixel + 0.5) * u_render_pixel_size;
            if (previous_view.z < 0.0 && all(greaterThanEqual(previous_uv, vec2(0.0)))
                    && all(lessThan(previous_uv, vec2(1.0)))) {
                ivec2 base = ivec2(floor(history_pixel));
                vec2 fraction = fract(history_pixel);
                OpaqueHistoryGather gather;
                gather.sum_z = vec3(0.0);
                gather.sum_second = 0.0;
                gather.sum_age = 0.0;
                gather.weight_sum = 0.0;
                gather.dominant_weight = 0.0;
                gather.dominant_data = 0u;
                vec2 inverse_fraction = vec2(1.0) - fraction;
                OpaqueHistoryGuide guide;
                guide.receiver_view = receiver_view;
                guide.previous_receiver_view = previous_view;
                guide.geo_previous_view = u_ssr_history_static
                    ? geo_view : mat3(gbufferPreviousModelView) * geo_normal_world;
                guide.geo_view = geo_view;
                guide.normal_world = normal_world;
                guide.material = material;
                guide.normal_floor = mix(0.999, 0.92, material.x * material.x);
                // Four fixed bilinear taps in the original order. Explicit calls
                // specialize offsets without changing visibility or response.
                GatherOpaqueHistoryTap(texel, base, inverse_fraction.x * inverse_fraction.y,
                    guide, gather);
                GatherOpaqueHistoryTap(texel, base + ivec2(1, 0), fraction.x * inverse_fraction.y,
                    guide, gather);
                GatherOpaqueHistoryTap(texel, base + ivec2(0, 1), inverse_fraction.x * fraction.y,
                    guide, gather);
                GatherOpaqueHistoryTap(texel, base + ivec2(1, 1), fraction.x * fraction.y,
                    guide, gather);
                if (gather.weight_sum > 0.2) {
                    vec3 old_z = gather.sum_z / gather.weight_sum;
                    float old_y = Luminance(old_z);
                    float old_variance = max(gather.sum_second / gather.weight_sum - old_y * old_y, 0.0);
                    float old_age = gather.sum_age / gather.weight_sum * saturate(gather.weight_sum);
                    float angle_motion = 0.0;
                    if (!u_ssr_history_static) {
                        vec3 old_eye_world = transpose(mat3(gbufferPreviousModelView)) * normalize(-previous_view);
                        angle_motion = length(view_to_eye - old_eye_world);
                    }
                    // Valid reprojection still carries useful samples in motion.
                    // Reserve fast replacement for sustained radiance changes;
                    // a receiver moving on screen does not invalidate its history.
                    float rough_history = smoothstep(0.08, 0.4, material.x);
                    float responsive_frames = mix(2.0, 8.0, rough_history);
                    float motion_risk = angle_motion / max(material.x * material.x, 0.002);
                    float angular_response = smoothstep(0.1, 1.0, motion_risk);
                    // A fixed world receiver can keep the same eye direction
                    // during camera rotation while its reflection moves on screen.
                    // Account for that resampling/visibility change independently
                    // of angular parallax. Only camera motion enters this velocity.
                    float screen_speed = length(ndc_delta * (0.5 * u_render_res));
                    float motion_response = max(angular_response, smoothstep(0.25, 2.0, screen_speed));
                    float moving_frames = mix(8.0, 20.0, rough_history);
                    // Even full motion response retains 7/8 of valid smooth
                    // history at convergence, instead of injecting 50% new noise.
                    float history_limit = 1.0 / mix(1.0 / OPAQUE_HISTORY_MAX,
                        1.0 / moving_frames, motion_response);
                    // Random VNDF hit/miss changes at reflection silhouettes are
                    // estimator noise. Geometry, camera motion and sustained
                    // radiance changes govern validity and temporal response.
                    // Generic entities share class zero with unclassified terrain.
                    // Keep that class conservative; no exact entity motion is available.
                    if (material_id == 0) {
                        history_limit = min(history_limit, 16.0);
                    }
                    if ((material_id >= 128 && material_id <= 137)
                            || (wetness > 0.01 && geo_normal_world.y > 0.9)) {
                        history_limit = min(history_limit, 4.0);
                    }
                    uint state = gather.dominant_data >> 13;
                    int old_change = state <= 3u ? int(state) : state <= 6u ? 3 - int(state) : 0;
                    float residual = sample_y - old_y;
                    // A wider noise threshold keeps motion from turning ordinary
                    // stochastic variation into a sustained radiance-change event.
                    float change_response = motion_response * (1.0 - rough_history);
                    float threshold = max(mix(2.5, 2.0, change_response) * sqrt(old_variance),
                        0.12 * max(old_y, 0.05));
                    if (abs(residual) > threshold) {
                        int direction = residual > 0.0 ? 1 : -1;
                        change_state = old_change * direction > 0 ? old_change + direction : direction;
                        change_state = clamp(change_state, -3, 3);
                        int change_frames = change_response > 0.5 ? 2 : 3;
                        if (abs(change_state) >= change_frames) {
                            history_limit = min(history_limit, responsive_frames);
                        }
                    }
                    old_age = min(old_age, history_limit - 1.0);
                    float beta = 1.0 / (old_age + 1.0);
                    mean_z = mix(old_z, sample_z, beta);
                    variance = (1.0 - beta) * (old_variance + beta * residual * residual);
                    age = min(old_age + 1.0, OPAQUE_HISTORY_MAX);
                }
            }
        }
        // Reset confidence; finite RGB export still exposes an overflow as Inf.
        if (!IsFinite(mean_z) || any(greaterThan(mean_z, OPAQUE_HISTORY_RGB_MAX))) {
            metadata = uvec4(0u);
            result = mean_z;
        } else {
            metadata = PackOpaqueHistory(-receiver_view.z, material, age, change_state, variance);
            result = mean_z;
        }
    }
    return result;
}

#endif
#endif // LIB_RAYTRACE_OPAQUE_REFLECTION_HISTORY_GLSL
