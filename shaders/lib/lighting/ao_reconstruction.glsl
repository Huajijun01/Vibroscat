#ifndef LIB_LIGHTING_AO_RECONSTRUCTION_GLSL
#define LIB_LIGHTING_AO_RECONSTRUCTION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/packing.glsl"

// Temporal sampling covers all four full-res pixels in each 2x2 block.
// Without AO history, keep a fixed lattice instead of introducing flicker.
ivec2 AOGridOffset() {
#if defined(AO_TEMPORAL_ENABLED)
    return ivec2(frameCounter & 1, (frameCounter >> 1) & 1);
#else
    return ivec2(0);
#endif
}

// Joint bilateral reconstruction on the generator's actual pixel lattice:
// half texel h represents full texel 2*h + AOGridOffset().
// Guide normals share the RGBA8 AO workspace; depth stays in depthtex2.
// Reject other planes/faces before interpolation, including sky samples.
vec2 ReconstructAO(ivec2 texel, float scene_depth, vec2 normal_oct) {
    ivec2 half_size = max((ivec2(u_render_res) + 1) / 2, ivec2(1));
    ivec2 grid_offset = AOGridOffset();
    ivec2 full_max = ivec2(u_render_res) - 1;
    ivec2 base_texel = clamp(ivec2(floor(vec2(texel - grid_offset) * 0.5)), ivec2(0), half_size - 1);
    ivec2 lower_pixel = min(base_texel * 2 + grid_offset, full_max);
    ivec2 upper_pixel = min(min(base_texel + 1, half_size - 1) * 2 + grid_offset, full_max);
    // The final interval is one pixel wide at an odd-sized scene boundary.
    vec2 fraction = clamp(vec2(texel - lower_pixel) / vec2(max(upper_pixel - lower_pixel, 1)), 0.0, 1.0);
    vec3 normal_world = DecodeOctahedralNormal(normal_oct);
    vec2 receiver_ndc = (vec2(texel) + 0.5) * u_render_pixel_size * 2.0 - 1.0;
#ifdef TAA
    receiver_ndc -= u_taa_offset;
#endif
    vec3 receiver_view = NDCToViewSparse(receiver_ndc, scene_depth * 2.0 - 1.0);
    vec3 normal_view = mat3(gbufferModelView) * normal_world;
    // Project the receiver plane once. Comparing the cross-multiplied plane
    // equation avoids reconstructing/dividing a view position for each tap.
    vec2 plane_xy = normal_view.xy
        * vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y);
    vec2 ray_bias = vec2(-1.0);
#ifdef TAA
    ray_bias -= u_taa_offset;
#endif
    vec3 projected_plane = vec3(plane_xy * (2.0 * u_render_pixel_size),
        dot(plane_xy, ray_bias) + normal_view.z * gbufferProjectionInverse[3].z);
    float receiver_plane = dot(receiver_view, normal_view);
    // One centimeter near the camera, plus depth-relative tolerance for
    // quantized geometric normals and distant depth precision.
    float plane_tolerance_m = 0.01 + abs(receiver_view.z) * 0.001;
    vec2 ao_sum = vec2(0.0);
    float weight_sum = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            vec2 weights = mix(vec2(1.0) - fraction, fraction, bvec2(x != 0, y != 0));
            float weight = weights.x * weights.y;
            if (weight <= 0.0) continue;
            ivec2 sample_texel = min(base_texel + ivec2(x, y), half_size - 1);
            ivec2 sample_pixel = min(sample_texel * 2 + grid_offset, full_max);
            float sample_depth = texelFetch(depthtex2, sample_pixel, 0).r;
            if (sample_depth >= 1.0) continue;
            vec4 sample_data = texelFetch(colortex2, sample_texel, 0);
            // Coplanar block faces have identical stored normals. Avoid a
            // second normalization when their exact UNORM8 codes agree.
            if (any(notEqual(sample_data.gb, normal_oct))) {
                vec3 sample_normal = DecodeOctahedralNormal(sample_data.gb);
                if (dot(normal_world, sample_normal) < 0.85) continue;
            }
            float sample_ndc_depth = sample_depth * 2.0 - 1.0;
            float inverse_depth = gbufferProjectionInverse[2].w * sample_ndc_depth
                + gbufferProjectionInverse[3].w;
            float plane_error = dot(vec3(vec2(sample_pixel) + 0.5, 1.0), projected_plane)
                + normal_view.z * gbufferProjectionInverse[2].z * sample_ndc_depth
                - receiver_plane * inverse_depth;
            if (abs(plane_error) > plane_tolerance_m * abs(inverse_depth)) continue;
            ao_sum += sample_data.ra * vec2(1.0, 255.0) * weight;
            weight_sum += weight;
        }
    }
    // A surface missing from the half-res lattice must not inherit another
    // surface's shadow. Age zero asks the caller to reuse validated history;
    // the rotating lattice supplies a fresh estimate within four frames.
    return weight_sum > 1.0e-5 ? ao_sum / weight_sum : vec2(1.0, 0.0);
}

#endif // LIB_LIGHTING_AO_RECONSTRUCTION_GLSL
