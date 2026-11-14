#ifndef LIB_LIGHTING_GI_DENOISE_GLSL
#define LIB_LIGHTING_GI_DENOISE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/color/spaces.glsl"
#include "/lib/lighting/gi_history.glsl"

// RGB16F attachment writes truncate and would bias the history accumulator
// downward; round to adjacent exact half values with unbiased probability.
vec3 QuantizeGIHistory(vec3 irradiance, ivec2 gi_texel, int frame) {
    irradiance = clamp(irradiance, vec3(0.0), vec3(65504.0));
    uint packed_rg = packHalf2x16(irradiance.rg);
    uint packed_b = packHalf2x16(vec2(irradiance.b, 0.0));
    uvec3 codes = uvec3(packed_rg & 65535u, packed_rg >> 16, packed_b & 65535u);
    vec3 nearest = vec3(unpackHalf2x16(packed_rg), unpackHalf2x16(packed_b).x);
    uvec3 lower_codes = codes - uvec3(greaterThan(nearest, irradiance));
    vec3 lower = vec3(unpackHalf2x16(lower_codes.r).x,
        unpackHalf2x16(lower_codes.g).x, unpackHalf2x16(lower_codes.b).x);
    uvec3 upper_codes = min(lower_codes + 1u, uvec3(31743u));
    vec3 upper = vec3(unpackHalf2x16(upper_codes.r).x,
        unpackHalf2x16(upper_codes.g).x, unpackHalf2x16(upper_codes.b).x);
    vec3 probability = (irradiance - lower) / max(upper - lower, vec3(5.960464477539063e-8));
    uint random_bits = LowBias32Hash(uint(gi_texel.x) ^ (uint(gi_texel.y) * 0x9e3779b9u)
        ^ (uint(frame) * 0x85ebca6bu));
    vec3 thresholds = vec3(random_bits & 1023u, (random_bits >> 10) & 1023u, random_bits >> 20)
        * vec3(1.0 / 1024.0, 1.0 / 1024.0, 1.0 / 4096.0);
    return mix(lower, upper, lessThan(thresholds, probability));
}

// Same RGBA16F conversion bias as irradiance; the offset hash decorrelates
// color and variance rounding.
float QuantizeGISecondMoment(float second_moment, ivec2 gi_texel, int frame) {
    return QuantizeGIHistory(vec3(second_moment), gi_texel + ivec2(13, 29), frame).r;
}

// Irradiance filters before albedo demodulation, per Schied et al., SVGF (2017).
vec3 AccumulateGI(vec3 current_irradiance, float sample_sigma,
        inout GIReprojectedHistory reprojected, out float history_status) {
    history_status = 1.0;
    float current_luminance = Luminance(current_irradiance);
    if (reprojected.weight < 0.05) {
        reprojected.change_count = 0.0;
        reprojected.second_moment = current_luminance * current_luminance;
        return current_irradiance;
    }
    float history_luminance = Luminance(reprojected.irradiance);
    float temporal_sigma = sqrt(max(reprojected.second_moment - history_luminance * history_luminance, 0.0));
    // noise_extent is angular/lighting contrast, not estimator noise: it must
    // not veto a changed light on an unchanged plane. Variance covers rare hits.
    float noise_extent = 1.25 * temporal_sigma + 0.015
        + 0.05 * max(current_luminance, history_luminance);
    float change = abs(current_luminance - history_luminance) / max(noise_extent, 0.015);
    float age = min(floor(reprojected.age) + 1.0, GI_HISTORY_LIMIT);
    float previous_change_count = reprojected.change_count;
    reprojected.change_count = 0.0;
    history_status = age;
    if (reprojected.age >= 16.0 && change > 1.0) {
        float direction = sign(current_luminance - history_luminance);
        float count = sign(previous_change_count) == direction
            ? floor(abs(previous_change_count)) + 1.0 : 1.0;
        if (count >= GI_RESPONSE_FRAMES) {
            age = 2.0;
            history_status = age;
        } else {
            reprojected.change_count = direction * count;
        }
    }
    // The cap bounds both the real age and the EMA window 1/age drives.
    reprojected.second_moment = mix(reprojected.second_moment,
        current_luminance * current_luminance, 1.0 / age);
    return mix(reprojected.irradiance, current_irradiance, 1.0 / age);
}

// Rejects on current-frame representative geometry, never on history.
bool SampleGITap(ivec2 sample_texel, ivec2 gi_size, vec2 block_scale,
        vec2 receiver_pixel, vec4 receiver_plane, float inverse_tolerance,
        vec3 normal_world, uint normal_code, float spatial_falloff,
        out vec3 irradiance, out float age, out float weight) {
    bool result = false;
    irradiance = vec3(0.0);
    age = 0.0;
    weight = 0.0;
    if (!(any(lessThan(sample_texel, ivec2(0))) || any(greaterThanEqual(sample_texel, gi_size)))) {
        vec4 metadata = texelFetch(colortex10, sample_texel, 0);
        irradiance = texelFetch(colortex9, sample_texel, 0).rgb;
        // deferred4 guarantees a valid age code here; validation belongs to
        // previous-frame readers.
        age = float(int(metadata.a) & 255);
        if (!(age < 1.0)) {
            // Matching code skips the dot test: oct8 vs oct6 center dot >= 0.9977.
            uint payload = GIHistoryPayload(metadata);
            float normal_dot = 1.0;
            if ((payload & 4095u) != normal_code) {
                vec3 sample_normal = DecodeOctahedralNormal(
                    vec2(payload & 63u, (payload >> 6) & 63u) * (1.0 / 63.0));
                normal_dot = dot(normal_world, sample_normal);
            }
            if (!(normal_dot < GI_NORMAL_DOT_FLOOR)) {
                vec2 sample_pixel = RepresentativePixel(sample_texel, GIHistoryOffset(metadata), block_scale);
                // receiver_plane is the per-pixel form built in ReconstructGI;
                // evaluating at the sample pixel times metadata.b gives n . v.
                float plane_distance = abs(dot(vec3(sample_pixel, 1.0), receiver_plane.xyz)
                    * metadata.b - receiver_plane.w) * inverse_tolerance;
                if (!(plane_distance >= 1.0)) {
                    if (!(any(isnan(irradiance)) || any(isinf(irradiance)))) {
                        vec2 spatial_delta = (sample_pixel - receiver_pixel) / block_scale;
                        float plane_weight = 1.0 - plane_distance;
                        // Young estimates keep their real confidence so converged
                        // geometry-matched neighbors dominate.
                        float confidence = saturate(age / 64.0);
                        confidence *= confidence;
                        weight = exp2(-spatial_falloff * dot(spatial_delta, spatial_delta))
                            * plane_weight * plane_weight * confidence;
                        result = true;
                    }
                }
            }
        }
    }
    return result;
}

bool ReconstructGI(ivec2 scene_texel, vec3 receiver_view, vec3 normal_world, out vec3 reconstructed) {
    // Symmetric filtering also smooths mature sampling error; output stays
    // outside the history so real light is not diffused back in.
    ivec2 gi_size = GIHistorySize();
    vec2 block_scale = u_render_res / vec2(gi_size);
    vec2 receiver_pixel = vec2(scene_texel) + 0.5;
    vec2 filter_position = receiver_pixel / block_scale - 0.5;
    ivec2 base_texel = ivec2(floor(filter_position));
    vec3 normal_view = normalize(mat3(gbufferModelView) * normal_world);
    vec2 plane_xy = normal_view.xy / vec2(gbufferProjection[0].x, gbufferProjection[1].y);
    vec2 ray_bias = gbufferProjection[2].xy - 1.0;
#ifdef TAA
    ray_bias -= u_taa_offset;
#endif
    vec4 receiver_plane = vec4(plane_xy * (2.0 / u_render_res),
        dot(plane_xy, ray_bias) - normal_view.z, dot(receiver_view, normal_view));
    float inverse_tolerance = 1.0 / (0.015 + abs(receiver_view.z) * 0.0015);
    uvec2 normal_oct = uvec2(round(saturate(EncodeOctahedralNormal(normal_world)) * 63.0));
    uint normal_code = normal_oct.x + (normal_oct.y << 6);
    vec3 irradiance_sum = vec3(0.0);
    float weight_sum = 0.0;
    float maximum_age = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            vec3 irradiance;
            float age;
            float weight;
            if (!SampleGITap(base_texel + ivec2(x, y), gi_size, block_scale,
                    receiver_pixel, receiver_plane, inverse_tolerance,
                    normal_world, normal_code, 0.25, irradiance, age, weight)) continue;
            irradiance_sum += irradiance * weight;
            weight_sum += weight;
            maximum_age = max(maximum_age, age);
        }
    }
    if (maximum_age > 0.0) {
        for (int i = 0; i < 8; ++i) {
            ivec2 offset;
            if (i < 4) offset = ivec2(i < 2 ? -1 : 2, i & 1);
            else offset = ivec2(i & 1, i < 6 ? -1 : 2);
            vec3 irradiance;
            float age;
            float weight;
            if (!SampleGITap(base_texel + offset, gi_size, block_scale,
                    receiver_pixel, receiver_plane, inverse_tolerance,
                    normal_world, normal_code, 0.25, irradiance, age, weight)) continue;
            irradiance_sum += irradiance * weight;
            weight_sum += weight;
        }
        // Bounded extended support for young disocclusion footprints; ages come
        // from real history only.
        float support_strength = saturate(1.0 - maximum_age / 32.0);
        support_strength *= support_strength;
        for (int i = 0; i < 16 && maximum_age < 8.0; ++i) {
            int radius = i < 8 ? 4 : 8;
            int direction = i & 7;
            ivec2 offset = direction < 4 ? ivec2(direction < 2 ? -radius : 1 + radius, direction & 1)
                : ivec2(direction & 1, direction < 6 ? -radius : 1 + radius);
            vec3 irradiance;
            float age;
            float weight;
            if (!SampleGITap(base_texel + offset, gi_size, block_scale,
                    receiver_pixel, receiver_plane, inverse_tolerance,
                    normal_world, normal_code, 0.04, irradiance, age, weight) || age < 16.0) continue;
            weight *= support_strength;
            irradiance_sum += irradiance * weight;
            weight_sum += weight;
        }
    }
    // A half-res representative can miss a thin receiver; zero beats borrowed
    // neighbor irradiance.
    reconstructed = weight_sum > 1.0e-5 ? irradiance_sum / weight_sum : vec3(0.0);
    return weight_sum > 1.0e-5;
}

#endif // LIB_LIGHTING_GI_DENOISE_GLSL
