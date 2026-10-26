#ifndef LIB_LIGHTING_GI_HISTORY_GLSL
#define LIB_LIGHTING_GI_HISTORY_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"

const float GI_HISTORY_LIMIT = GI_MODE == 2 ? 128.0 : 64.0;
const float GI_RESPONSE_FRAMES = 8.0;
const float GI_NORMAL_DOT_FLOOR = 0.95;

// Both history attachments have half-display allocations. TAAU crops their
// lower-left active rectangle; projection UVs still span the complete view.
ivec2 GIHistorySize() {
    return max(ivec2(floor(u_render_res * 0.5)), ivec2(1));
}

// Two endpoint samples per axis also cover odd-size blocks (occasionally
// three pixels wide). The two-bit selector records the exact receiver ray.
vec2 RepresentativePixel(ivec2 gi_texel, int offset_code, vec2 block_scale) {
    vec2 selector = vec2(offset_code & 1, (offset_code >> 1) & 1);
    return floor((vec2(gi_texel) + selector) * block_scale) - selector + 0.5;
}

vec2 RepresentativePixelUV(ivec2 gi_texel, int offset_code) {
    return RepresentativePixel(gi_texel, offset_code, u_render_res / vec2(GIHistorySize())) / u_render_res;
}

// Oct6 geometry and fifteen signed change states fit in the 61440 normal,
// finite half bit patterns. Keep age independent: a noisy estimate must not
// round age down or repeatedly stall convergence at a sixteen-frame boundary.
float PackGIHistoryNormal(vec3 normal_world, float change_count) {
    uvec2 oct = uvec2(round(saturate(EncodeOctahedralNormal(normal_world)) * 63.0));
    uint count = uint(clamp(round(abs(change_count)), 0.0, GI_RESPONSE_FRAMES - 1.0));
    uint state = count + (change_count < 0.0 ? 7u : 0u);
    uint payload = oct.x + (oct.y << 6) + (state << 12);
    uint code = payload < 30720u ? payload + 0x0400u : payload - 30720u + 0x8400u;
    return unpackHalf2x16(code).x;
}

uint GIHistoryPayload(vec4 metadata) {
    uint code = packHalf2x16(vec2(metadata.r, 0.0)) & 65535u;
    return (code & 0x8000u) == 0u ? code - 0x0400u : code - 0x8400u + 30720u;
}

vec3 GIHistoryNormal(vec4 metadata) {
    uint payload = GIHistoryPayload(metadata);
    return DecodeOctahedralNormal(vec2(payload & 63u, (payload >> 6) & 63u) * (1.0 / 63.0));
}

// RGBA16F: packed oct6 normal/change count, temporal second moment, view depth,
// and exact real age[0:7]/representative[8:9]/source[10]. Age zero is invalid.
vec4 EncodeGIHistory(vec3 normal_world, float depth_view, float age, int offset_code,
        float second_moment, float change_count) {
    int code = int(clamp(age, 1.0, GI_HISTORY_LIMIT))
        + 256 * offset_code + 1024 * int(GI_MODE == 2);
    return vec4(PackGIHistoryNormal(normal_world, change_count), clamp(second_moment, 0.0, 65504.0),
        min(depth_view, 65000.0), float(code));
}

float GIHistoryAge(vec4 metadata) {
    if (any(isnan(metadata)) || any(isinf(metadata)) || metadata.b <= 0.0) return 0.0;
    int code = int(round(metadata.a));
    if ((code >> 10) != int(GI_MODE == 2)) return 0.0;
    float age = float(code & 255);
    return age <= GI_HISTORY_LIMIT ? age : 0.0;
}

float GIHistoryChange(vec4 metadata) {
    uint state = GIHistoryPayload(metadata) >> 12;
    return state <= 7u ? float(state) : -float(state - 7u);
}

int GIHistoryOffset(vec4 metadata) {
    return (int(round(metadata.a)) >> 8) & 3;
}

vec3 ReceiverViewFromUV(vec2 sample_uv, float depth_view, bool previous) {
    vec2 ndc_xy = sample_uv * 2.0 - 1.0;
#ifdef TAA
    ndc_xy -= previous ? u_taa_offset_previous : u_taa_offset;
#endif
    mat4 projection = previous ? gbufferPreviousProjection : gbufferProjection;
    vec2 ray_xy = (ndc_xy + projection[2].xy) / vec2(projection[0].x, projection[1].y);
    return vec3(ray_xy, -1.0) * depth_view;
}

struct GIReprojectedHistory {
    vec3 irradiance;
    float age;
    float weight;
    float change_count;
    float second_moment;
};

// Barycentric coordinates at the origin. Affine interpolation has zero
// spatial first moment, so repeated reprojection cannot advect a light ramp.
vec3 GIHistoryTriangleWeights(vec2 a, vec2 b, vec2 c) {
    vec2 ab = b - a;
    vec2 ac = c - a;
    float area = ab.x * ac.y - ab.y * ac.x;
    if (abs(area) < 1.0e-5) return vec3(-1.0);
    return vec3(b.x * c.y - b.y * c.x, c.x * a.y - c.y * a.x,
        a.x * b.y - a.y * b.x) / area;
}

// Neighboring rays on a grazing plane can meet meters apart. Reject the
// depth error from that ray's intersection with the receiver plane, rather
// than the legitimate displacement along the plane. Cross multiplication
// avoids a divide near the horizon; opposite-side intersections stay invalid.
bool GIHistoryMatchesPlane(vec3 sample_view, vec3 receiver_view, vec3 normal_view,
        float plane_tolerance_m, float depth_tolerance_m) {
    float receiver_plane = dot(receiver_view, normal_view);
    float sample_plane = dot(sample_view, normal_view);
    float plane_error_m = dot(sample_view - receiver_view, normal_view);
    return receiver_plane * sample_plane > 0.0
        && abs(plane_error_m) <= plane_tolerance_m
        && dot(sample_view, sample_view) * plane_error_m * plane_error_m
            <= depth_tolerance_m * depth_tolerance_m * sample_plane * sample_plane;
}

// Disocclusion has no receiver history. Use only nearby, converged samples
// of the same plane as a bounded prior, worth at most 16 temporal samples.
// Its confidence is deliberately lower than the donor's true history age.
GIReprojectedHistory BootstrapGIHistory(vec2 previous_uv, vec3 previous_view,
        vec3 normal_previous_view, vec3 normal_world) {
    GIReprojectedHistory result;
    result.irradiance = vec3(0.0);
    result.age = 0.0;
    result.weight = 0.0;
    result.change_count = 0.0;
    result.second_moment = 0.0;
    ivec2 history_size = GIHistorySize();
    ivec2 base_texel = ivec2(floor(previous_uv * vec2(history_size) - 0.5));
    float plane_tolerance_m = 0.015 + abs(previous_view.z) * 0.0015;
    float footprint_m = abs(previous_view.z) * 6.0 / u_pixel_world_scale_prev;
    float support_radius_m = saturate(0.10 + 4.0 * footprint_m);
    float weight_sum = 0.0;
    for (int i = 0; i < 24; ++i) {
        int radius = i < 8 ? 2 : (i < 16 ? 4 : 8);
        int direction = i & 7;
        ivec2 offset = direction < 4 ? ivec2(direction < 2 ? -radius : 1 + radius, direction & 1)
            : ivec2(direction & 1, direction < 6 ? -radius : 1 + radius);
        ivec2 sample_texel = base_texel + offset;
        if (any(lessThan(sample_texel, ivec2(0))) || any(greaterThanEqual(sample_texel, history_size))) continue;
        vec4 metadata = texelFetch(colortex10, sample_texel, 0);
        float age = GIHistoryAge(metadata);
        if (age < 32.0 || dot(normal_world, GIHistoryNormal(metadata)) < GI_NORMAL_DOT_FLOOR) continue;
        vec2 sample_uv = RepresentativePixelUV(sample_texel, GIHistoryOffset(metadata));
        vec3 sample_view = ReceiverViewFromUV(sample_uv, metadata.b, true);
        vec3 delta_view = sample_view - previous_view;
        float plane_distance = abs(dot(delta_view, normal_previous_view)) / plane_tolerance_m;
        if (!GIHistoryMatchesPlane(sample_view, previous_view, normal_previous_view,
                plane_tolerance_m, support_radius_m)
                || dot(delta_view, delta_view) > support_radius_m * support_radius_m) continue;
        vec3 irradiance = texelFetch(colortex9, sample_texel, 0).rgb;
        if (any(isnan(irradiance)) || any(isinf(irradiance))) continue;
        vec2 pixel_delta = (sample_uv - previous_uv) * u_render_res * 0.5;
        float confidence = saturate(age / 64.0);
        float weight = exp2(-0.04 * dot(pixel_delta, pixel_delta))
            * (1.0 - plane_distance) * (1.0 - plane_distance) * confidence * confidence;
        result.irradiance += irradiance * weight;
        result.second_moment += metadata.g * weight;
        weight_sum += weight;
    }
    if (weight_sum <= 1.0e-5) return result;
    result.irradiance /= weight_sum;
    result.second_moment /= weight_sum;
    result.age = 16.0;
    result.weight = 1.0;
    return result;
}

// Validate each actual previous geometry tap before reading its irradiance.
// Camera-only reprojection cannot track arbitrary moving objects.
GIReprojectedHistory ReprojectGIHistory(vec3 receiver_world, vec3 normal_world) {
    GIReprojectedHistory result;
    result.irradiance = vec3(0.0);
    result.age = 0.0;
    result.weight = 0.0;
    result.change_count = 0.0;
    result.second_moment = 0.0;
    if (frameCounter < 2 || dot(u_camera_delta, u_camera_delta) > 64.0) return result;
    // Sprint/flight FOV changes do not invalidate world-space history. Use
    // the actual previous projection and validate each previous surface;
    // rejecting a projection-scale change would reset the whole screen.
    vec3 previous_view = (gbufferPreviousModelView * vec4(receiver_world + u_camera_delta, 1.0)).xyz;
    vec4 previous_clip = gbufferPreviousProjection * vec4(previous_view, 1.0);
    if (previous_clip.w <= 0.0) return result;
    vec2 previous_uv = previous_clip.xy / previous_clip.w * 0.5 + 0.5;
#ifdef TAA
    previous_uv += u_taa_offset_previous * 0.5;
#endif
    vec2 support_margin = 18.0 / u_render_res;
    if (any(lessThan(previous_uv, -support_margin))
            || any(greaterThanEqual(previous_uv, vec2(1.0) + support_margin))) return result;

    ivec2 history_size = GIHistorySize();
    // Rounded block endpoints can lie before the normalized block boundary
    // at odd resolutions. The half-pixel correction keeps that endpoint in
    // the search fan, including motion smaller than the rounding discrepancy.
    vec2 block_scale = u_render_res / vec2(history_size);
    ivec2 owner_texel = clamp(ivec2(ceil((previous_uv * u_render_res + 0.5) / block_scale)) - 1,
        ivec2(0), history_size - 1);
    vec4 owner_metadata = texelFetch(colortex10, owner_texel, 0);
    vec2 owner_delta = RepresentativePixelUV(owner_texel, GIHistoryOffset(owner_metadata)) - previous_uv;
    ivec2 primary_corner = ivec2(greaterThan(owner_delta, vec2(0.0)));
    // RGBA8 octahedral storage cannot represent 0.5 exactly. Restore block
    // axes within its quantization cell before predicting plane depth: the
    // tiny decoded tilt otherwise becomes a large error at grazing angles.
    vec3 axis_normal = vec3(greaterThan(abs(normal_world), vec3(0.99998))) * sign(normal_world);
    vec3 plane_normal_world = dot(axis_normal, axis_normal) > 0.5 ? axis_normal : normal_world;
    vec3 normal_previous_view = normalize(mat3(gbufferPreviousModelView) * plane_normal_world);
    float plane_tolerance_m = 0.015 + abs(previous_view.z) * 0.0015;
    float footprint_m = abs(previous_view.z) * 6.0 / u_pixel_world_scale_prev;
    float reject_radius_m = 0.05 + footprint_m;
    // A stationary receiver needs no quad search or interpolation. This also
    // covers the two block endpoints when their normalized boundary is exact.
    if (dot(owner_delta * u_render_res, owner_delta * u_render_res) < 1.0e-6) {
        float age = GIHistoryAge(owner_metadata);
        vec3 sample_view = ReceiverViewFromUV(previous_uv, owner_metadata.b, true);
        if (age >= 1.0 && dot(normal_world, GIHistoryNormal(owner_metadata)) >= GI_NORMAL_DOT_FLOOR
                && GIHistoryMatchesPlane(sample_view, previous_view, normal_previous_view,
                    plane_tolerance_m, reject_radius_m)) {
            vec3 irradiance = texelFetch(colortex9, owner_texel, 0).rgb;
            if (!any(isnan(irradiance)) && !any(isinf(irradiance))) {
                result.irradiance = irradiance;
                result.age = age;
                result.weight = 1.0;
                result.change_count = GIHistoryChange(owner_metadata);
                result.second_moment = owner_metadata.g;
                return result;
            }
        }
    }
    float weight_sum = 0.0;
    // Representatives lie at block endpoints, not grid centers. First use
    // the quad toward the target from its owning representative. Only mixed
    // endpoint selections can require another adjacent quad (four at most).
    for (int candidate = 0; candidate < 4; ++candidate) {
        ivec2 corner = primary_corner ^ ivec2(candidate & 1, candidate >> 1);
        ivec2 base_texel = owner_texel - corner;
        if (any(lessThan(base_texel, ivec2(0)))
                || any(greaterThanEqual(base_texel + 1, history_size))) continue;
        vec4 samples[4];
        vec2 deltas[4];
        for (int i = 0; i < 4; ++i) {
            ivec2 sample_texel = base_texel + ivec2(i & 1, i >> 1);
            samples[i] = texelFetch(colortex10, sample_texel, 0);
            deltas[i] = (RepresentativePixelUV(sample_texel, GIHistoryOffset(samples[i])) - previous_uv) * u_render_res;
        }
        vec3 triangle = GIHistoryTriangleWeights(deltas[0], deltas[1], deltas[2]);
        vec4 weights = vec4(triangle, 0.0);
        if (any(lessThan(triangle, vec3(-1.0e-5)))) {
            triangle = GIHistoryTriangleWeights(deltas[3], deltas[2], deltas[1]);
            weights = vec4(0.0, triangle.z, triangle.y, triangle.x);
        }
        if (any(lessThan(triangle, vec3(-1.0e-5)))) continue;
        weights = max(weights, vec4(0.0));
        for (int i = 0; i < 4; ++i) {
            float weight = weights[i];
            if (weight <= 0.0) continue;
            ivec2 sample_texel = base_texel + ivec2(i & 1, i >> 1);
            vec4 metadata = samples[i];
            float age = GIHistoryAge(metadata);
            if (age < 1.0 || dot(normal_world, GIHistoryNormal(metadata)) < GI_NORMAL_DOT_FLOOR) continue;
            vec2 sample_uv = RepresentativePixelUV(sample_texel, GIHistoryOffset(metadata));
            vec3 sample_view = ReceiverViewFromUV(sample_uv, metadata.b, true);
            if (!GIHistoryMatchesPlane(sample_view, previous_view, normal_previous_view,
                    plane_tolerance_m, reject_radius_m)) continue;
            vec3 irradiance = texelFetch(colortex9, sample_texel, 0).rgb;
            if (any(isnan(irradiance)) || any(isinf(irradiance))) continue;
            float pixel_distance2 = dot(deltas[i], deltas[i]);
            if (pixel_distance2 < 1.0e-6) {
                result.irradiance = irradiance;
                result.age = age;
                result.weight = 1.0;
                result.change_count = GIHistoryChange(metadata);
                result.second_moment = metadata.g;
                return result;
            }
            result.irradiance += irradiance * weight;
            result.age += age * weight;
            result.change_count += GIHistoryChange(metadata) * weight;
            result.second_moment += metadata.g * weight;
            weight_sum += weight;
        }
        break;
    }
    if (weight_sum < 0.05) {
        return BootstrapGIHistory(previous_uv, previous_view, normal_previous_view, normal_world);
    }
    result.irradiance /= weight_sum;
    result.age /= weight_sum;
    result.change_count /= weight_sum;
    result.second_moment /= weight_sum;
    result.weight = saturate(weight_sum);
    return result;
}

#endif // LIB_LIGHTING_GI_HISTORY_GLSL
