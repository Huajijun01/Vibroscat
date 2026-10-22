#ifndef LIB_RAYTRACE_OPAQUE_REFLECTION_HISTORY_GLSL
#define LIB_RAYTRACE_OPAQUE_REFLECTION_HISTORY_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/color/spaces.glsl"

// RGB is the unblurred mean of Z = (Li * sampled throughput) / material factor.
// RGBA16UI: depth half | rough8/selector8 | RGB remainder8/age5/state3 | log2(1+v_Z) half.
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

// Add three red/green and two blue mantissa bits inside the existing metadata.
// Every consumer must reconstruct these before accumulating/filtering Z.
vec3 OpaqueHistoryMean(ivec2 texel, uvec4 data) {
    vec3 coarse = texelFetch(colortex3, texel, 0).rgb;
    uvec3 exponent = (floatBitsToUint(coarse) >> 23) & uvec3(255u);
    // The spacing is a normal, exact power of two, including the coarse
    // format's subnormal range (biased exponent floor 127 - 14 = 113).
    vec3 spacing = uintBitsToFloat((max(exponent, uvec3(113u)) - uvec3(9u, 9u, 7u)) << 23);
    uvec3 remainder = uvec3(data.b & 7u, (data.b >> 3) & 7u, (data.b >> 6) & 3u);
    return coarse + vec3(remainder) * spacing;
}

uvec4 PackOpaqueHistory(float depth_view, vec2 material, uint remainder,
        float age, int change_state, float variance) {
    uint depth_bits = packHalf2x16(vec2(depth_view, 0.0)) & 65535u;
    // Reject unrepresentable depths, including half overflow and underflow.
    if (depth_bits == 0u || depth_bits >= 0x7c00u) return uvec4(0u);
    uint roughness = uint(round(clamp(material.x, 0.0, 1.0) * 255.0));
    uint selector = uint(round(clamp(material.y, 0.0, 1.0) * 255.0));
    uint state = change_state < 0 ? uint(3 - change_state) : uint(change_state);
    return uvec4(depth_bits, roughness | (selector << 8),
        remainder | (uint(round(clamp(age, 1.0, OPAQUE_HISTORY_MAX))) << 8) | (state << 13),
        packHalf2x16(vec2(log2(1.0 + max(variance, 0.0)), 0.0)) & 65535u);
}

// Stochastic rounding at the combined 9/9/7-bit mantissa precision, then
// split into an exactly representable R11/G11/B10 coarse value and low bits.
// This stream is independent of STBN and of the optional display dither.
vec3 QuantizeOpaqueHistory(vec3 value, ivec2 texel, out uint remainder, out vec3 reconstructed) {
    uvec3 bits = floatBitsToUint(value);
    uvec3 exponent = (bits >> 23) & uvec3(255u);
    vec3 spacing = uintBitsToFloat((max(exponent, uvec3(113u)) - uvec3(9u, 9u, 7u)) << 23);
    vec3 units = value / spacing;
    // Avalanche before splitting independent RGB bit fields. A linear seed
    // followed by xorshift leaves strong spatial periods in this low-bit RGB.
    uint seed = LowBias32Hash(uint(texel.x) ^ (uint(texel.y) * 0x9e3779b9u)
        ^ (uint(frameCounter) * 0x85ebca6bu) ^ 0x68bc21ebu);
    vec3 random_value = (vec3(seed & 1023u, (seed >> 10) & 1023u, seed >> 20) + 0.5)
        * vec3(1.0 / 1024.0, 1.0 / 1024.0, 1.0 / 4096.0);
    uvec3 codes = uvec3(floor(units) + step(random_value, fract(units)));
    uvec3 low_bits = codes & uvec3(7u, 7u, 3u);
    remainder = low_bits.r | (low_bits.g << 3) | (low_bits.b << 6);
    reconstructed = vec3(codes) * spacing;
    return vec3(codes - low_bits) * spacing;
}

#if defined(OPAQUE_SSR) && OPAQUE_SSR_FILTER > 0

struct OpaqueHistoryGather {
    vec3 sum_z;
    float sum_second;
    float sum_age;
    float sum_weight;
    float dominant_weight;
    uint dominant_data;
};

// A previous tap is reconstructed at its OWN texel center and stored depth.
vec3 OpaquePreviousPosition(ivec2 texel, float depth_view) {
    vec2 uv = (vec2(texel) + 0.5) * u_render_pixel_size;
#ifdef TAA
    uv -= u_taa_offset_previous * 0.5;
#endif
    vec2 ray = (uv * 2.0 - 1.0 + gbufferPreviousProjection[2].xy)
        / vec2(gbufferPreviousProjection[0][0], gbufferPreviousProjection[1][1]);
    return vec3(ray, -1.0) * depth_view;
}

// Visibility and normal proxy at a historical tap's CURRENT projected location.
float OpaqueHistoryTapWeight(ivec2 receiver_texel, ivec2 history_texel, uvec4 data,
        vec3 previous_receiver_view, vec3 receiver_view, vec3 geo_normal_world,
        vec3 normal_world, vec2 material) {
    float depth_view = OpaqueHistoryDepth(data);
    if (OpaqueHistoryAge(data) < 1.0 || !(depth_view > 0.0) || isinf(depth_view)) return 0.0;
    if (abs(OpaqueHistoryRoughness(data) - material.x) > 0.025) return 0.0;
    if (abs(float(data.g >> 8) / 255.0 - material.y) > 1.5 / 255.0) return 0.0;
    vec3 old_view = OpaquePreviousPosition(history_texel, depth_view);
    vec3 delta_world = transpose(mat3(gbufferPreviousModelView)) * (old_view - previous_receiver_view);
    float depth_error = 0.0006 * depth_view;
    float plane_tolerance = 0.015 + depth_error;
    float plane_error = abs(dot(delta_world, geo_normal_world));
    if (plane_error > plane_tolerance * 2.0) return 0.0;
    vec3 predicted_view = receiver_view + mat3(gbufferModelView) * delta_world;
    if (predicted_view.z >= -1e-4 || !IsFinite(predicted_view)) return 0.0;
    vec2 current_uv = ViewToNDC(predicted_view).xy * 0.5 + 0.5;
#ifdef TAA
    current_uv += u_taa_offset * 0.5;
#endif
    if (any(lessThan(current_uv, vec2(0.0))) || any(greaterThanEqual(current_uv, vec2(1.0)))) return 0.0;
    ivec2 current_texel = ivec2(current_uv * u_render_res);
    float plane_weight = 1.0 - smoothstep(plane_tolerance, plane_tolerance * 2.0, plane_error);
    // The caller already decoded this texel's visible depth, material and
    // normal. The same proxy needs no additional GBuffer reads or transforms.
    if (all(equal(current_texel, receiver_texel))) return plane_weight;
    float current_depth = texelFetch(depthtex0, current_texel, 0).r;
    if (current_depth >= 1.0) return 0.0;
    // Hand/view-model positions have no static world correspondence.
    int material_id = int(texelFetch(colortex1, current_texel, 0).a * 255.0 + 0.5);
    if (material_id == 64) return 0.0;
    vec2 current_material = texelFetch(colortex2, current_texel, 0).rg;
    if (abs(current_material.x - material.x) > 0.025
            || abs(current_material.y - material.y) > 1.5 / 255.0) return 0.0;
    vec2 center_uv = (vec2(current_texel) + 0.5) * u_render_pixel_size;
#ifdef TAA
    center_uv -= u_taa_offset * 0.5;
#endif
    vec3 visible_view = NDCToView(vec3(center_uv * 2.0 - 1.0, current_depth * 2.0 - 1.0));
    vec3 geo_view = mat3(gbufferModelView) * geo_normal_world;
    // Ray/plane intersection accounts for the legitimate tangential offset
    // between a continuous projection and the current nearest texel center.
    float ray_plane = dot(geo_view, visible_view);
    if (abs(ray_plane) < 1e-6) return 0.0;
    vec3 plane_view = visible_view * (dot(geo_view, predicted_view) / ray_plane);
    float footprint = -predicted_view.z * 2.0 * u_render_pixel_size.y
        / abs(gbufferProjection[1][1]);
    if (abs(visible_view.z - plane_view.z) > 0.02 + depth_error + footprint * 0.5) return 0.0;
    if (abs(dot(visible_view - predicted_view, geo_view)) > plane_tolerance * 2.0) return 0.0;
    vec3 proxy_normal = DecodeOctahedralNormal(texelFetch(colortex12, current_texel, 0).rg);
    float normal_floor = mix(0.999, 0.92, material.x * material.x);
    return plane_weight * smoothstep(normal_floor, 1.0, dot(proxy_normal, normal_world));
}

void GatherOpaqueHistoryTap(ivec2 receiver_texel, ivec2 tap, float weight,
        vec3 previous_view, vec3 receiver_view, vec3 geo_normal_world,
        vec3 normal_world, vec2 material, inout OpaqueHistoryGather gather) {
    if (any(lessThan(tap, ivec2(0))) || any(greaterThanEqual(tap, ivec2(u_render_res)))) return;
    if (weight < 1e-5) return;
    uvec4 data = texelFetch(colortex6, tap, 0);
    weight *= OpaqueHistoryTapWeight(receiver_texel, tap, data, previous_view, receiver_view,
        geo_normal_world, normal_world, material);
    if (weight <= 0.0) return;
    vec3 history_z = OpaqueHistoryMean(tap, data);
    float history_variance = OpaqueHistoryVariance(data);
    if (!IsFinite(history_z) || isnan(history_variance) || isinf(history_variance)) return;
    float y = Luminance(history_z);
    gather.sum_z += weight * history_z;
    gather.sum_second += weight * (history_variance + y * y);
    gather.sum_age += weight * OpaqueHistoryAge(data);
    gather.sum_weight += weight;
    if (weight > gather.dominant_weight) {
        gather.dominant_weight = weight;
        gather.dominant_data = data.b;
    }
}

vec3 AccumulateOpaqueHistory(ivec2 texel, vec3 sample_z, vec3 world_pos,
        vec3 receiver_view, vec3 normal_world, vec3 geo_normal_world,
        vec2 material, int material_id, out uvec4 metadata) {
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
    if (frameCounter > 1 && material_id != 64 && camera_valid) {
        vec3 previous_view = (gbufferPreviousModelView * vec4(world_pos + u_camera_delta, 1.0)).xyz;
        vec4 clip = gbufferPreviousProjection * vec4(previous_view, 1.0);
        vec2 previous_uv = clip.xy / clip.w * 0.5 + 0.5;
#ifdef TAA
        previous_uv += u_taa_offset_previous * 0.5;
#endif
        if (clip.w > 0.0 && all(greaterThanEqual(previous_uv, vec2(0.0)))
                && all(lessThan(previous_uv, vec2(1.0)))) {
            vec2 history_pixel = previous_uv * u_render_res - 0.5;
            ivec2 base = ivec2(floor(history_pixel));
            vec2 fraction = fract(history_pixel);
            OpaqueHistoryGather gather;
            gather.sum_z = vec3(0.0);
            gather.sum_second = 0.0;
            gather.sum_age = 0.0;
            gather.sum_weight = 0.0;
            gather.dominant_weight = 0.0;
            gather.dominant_data = 0u;
            vec2 inverse_fraction = vec2(1.0) - fraction;
            // Four fixed bilinear taps in the original order. Explicit calls
            // specialize offsets without changing visibility or response.
            GatherOpaqueHistoryTap(texel, base, inverse_fraction.x * inverse_fraction.y,
                previous_view, receiver_view, geo_normal_world, normal_world, material, gather);
            GatherOpaqueHistoryTap(texel, base + ivec2(1, 0), fraction.x * inverse_fraction.y,
                previous_view, receiver_view, geo_normal_world, normal_world, material, gather);
            GatherOpaqueHistoryTap(texel, base + ivec2(0, 1), inverse_fraction.x * fraction.y,
                previous_view, receiver_view, geo_normal_world, normal_world, material, gather);
            GatherOpaqueHistoryTap(texel, base + ivec2(1, 1), fraction.x * fraction.y,
                previous_view, receiver_view, geo_normal_world, normal_world, material, gather);
            if (gather.sum_weight > 0.2) {
                vec3 old_z = gather.sum_z / gather.sum_weight;
                float old_y = Luminance(old_z);
                float old_variance = max(gather.sum_second / gather.sum_weight - old_y * old_y, 0.0);
                float old_age = gather.sum_age / gather.sum_weight * min(gather.sum_weight, 1.0);
                vec3 old_eye_world = transpose(mat3(gbufferPreviousModelView)) * normalize(-previous_view);
                vec3 eye_world = normalize(EyePositionSceneSpace() - world_pos);
                float angle_motion = length(eye_world - old_eye_world);
                float history_limit = OPAQUE_HISTORY_MAX;
                float motion_risk = angle_motion / max(material.x * material.x, 0.002);
                history_limit = mix(history_limit, 2.0, smoothstep(0.1, 1.0, motion_risk));
                // A fixed world receiver can keep the same eye direction
                // during camera rotation while its reflection moves on screen.
                // Account for that resampling/visibility change independently
                // of angular parallax. Remove projection jitter from velocity.
                vec2 screen_velocity = previous_uv - (vec2(texel) + 0.5) * u_render_pixel_size;
#ifdef TAA
                screen_velocity -= (u_taa_offset_previous - u_taa_offset) * 0.5;
#endif
                float screen_speed = length(screen_velocity * u_render_res);
                float motion_response = smoothstep(0.25, 2.0, screen_speed);
                float moving_frames = mix(3.0, 6.0, smoothstep(0.08, 0.3, material.x));
                // Interpolate update rates, so even slow movement shortens
                // the trail instead of retaining almost the full 31 frames.
                float screen_limit = 1.0 / mix(1.0 / OPAQUE_HISTORY_MAX,
                    1.0 / moving_frames, motion_response);
                history_limit = min(history_limit, screen_limit);
                // Random VNDF hit/miss changes at reflection silhouettes are
                // estimator noise. Geometry, camera motion and sustained
                // radiance changes govern validity and temporal response.
                // Generic entities share class zero with unclassified terrain.
                // Keep that class conservative; no exact entity motion is available.
                if (material_id == 0) history_limit = min(history_limit, 16.0);
                if ((material_id >= 128 && material_id <= 134)
                        || (wetness > 0.01 && geo_normal_world.y > 0.9)) {
                    history_limit = min(history_limit, 4.0);
                }
                uint state = gather.dominant_data >> 13;
                int old_change = state <= 3u ? int(state) : state <= 6u ? 3 - int(state) : 0;
                float residual = sample_y - old_y;
                float threshold = max(mix(2.5, 1.25, motion_response) * sqrt(old_variance),
                    0.12 * max(old_y, 0.05));
                if (abs(residual) > threshold) {
                    int direction = residual > 0.0 ? 1 : -1;
                    change_state = old_change * direction > 0 ? old_change + direction : direction;
                    change_state = clamp(change_state, -3, 3);
                    int change_frames = motion_response > 0.5 ? 2 : 3;
                    if (abs(change_state) >= change_frames) history_limit = min(history_limit, 2.0);
                }
                old_age = min(old_age, history_limit - 1.0);
                float beta = 1.0 / (old_age + 1.0);
                mean_z = mix(old_z, sample_z, beta);
                variance = (1.0 - beta) * (old_variance + beta * residual * residual);
                age = min(old_age + 1.0, OPAQUE_HISTORY_MAX);
            }
        }
    }
    // Out-of-range input is exposed by debug 14, never silently clamped to black.
    // Reset confidence; finite RGB export still exposes an overflow as Inf.
    if (!IsFinite(mean_z) || any(greaterThan(mean_z, OPAQUE_HISTORY_RGB_MAX))) {
        metadata = uvec4(0u);
        return mean_z;
    }
    uint remainder;
    vec3 reconstructed;
    vec3 stored_z = QuantizeOpaqueHistory(mean_z, texel, remainder, reconstructed);
    float rounding_error = Luminance(reconstructed - mean_z);
    variance += rounding_error * rounding_error;
    metadata = PackOpaqueHistory(-receiver_view.z, material, remainder, age, change_state, variance);
    return stored_z;
}

#endif
#endif // LIB_RAYTRACE_OPAQUE_REFLECTION_HISTORY_GLSL
