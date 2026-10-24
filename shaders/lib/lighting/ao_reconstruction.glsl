#ifndef LIB_LIGHTING_AO_RECONSTRUCTION_GLSL
#define LIB_LIGHTING_AO_RECONSTRUCTION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/packing.glsl"

// Four-tap bilateral upsampling on the generator's fixed pixel lattice:
// half texel h represents full texel 2*h, refreshed every frame.
// Guide normals share the RGBA8 AO workspace; depth stays in depthtex2.
// Spatial, linear-depth and normal weights suppress foreign surfaces and sky.
vec2 ReconstructAO(ivec2 texel, float scene_depth, vec2 normal_oct) {
    ivec2 half_size = ivec2(u_ao_half_res);
    ivec2 full_max = ivec2(u_render_res) - 1;
    ivec2 base_texel = min(texel / 2, half_size - 1);
    ivec2 lower_pixel = min(base_texel * 2, full_max);
    ivec2 upper_pixel = min(min(base_texel + 1, half_size - 1) * 2, full_max);
    // Clamp the final footprint to the actual scene, including odd sizes.
    vec2 fraction = clamp(vec2(texel - lower_pixel) / vec2(max(upper_pixel - lower_pixel, 1)), 0.0, 1.0);
    // These depth/workspace reads are independent of the rejection weights:
    // all four taps are fetched unconditionally (the UNORM8 workspace holds
    // only finite values) and every address stays bounded, zero-weight taps
    // included.
    float fetched_depth[4];
    vec4 fetched_data[4];
    for (int i = 0; i < 4; ++i) {
        ivec2 sample_texel = min(base_texel + ivec2(i & 1, i >> 1), half_size - 1);
        ivec2 sample_pixel = min(sample_texel * 2, full_max);
        fetched_depth[i] = texelFetch(depthtex2, sample_pixel, 0).r;
        fetched_data[i] = texelFetch(colortex2, sample_texel, 0);
    }
    vec3 normal_world = DecodeOctahedralNormal(normal_oct);
    float receiver_depth_m = LinearDepthFromScreenDepth(scene_depth);
    // Two centimeters near the camera, then a relative depth window. This
    // deliberately replaces strict plane rejection; close parallel surfaces
    // inside this window can share support.
    float inv_depth_window = 1.0 / (0.02 + receiver_depth_m * 0.01);
    vec2 ao_sum = vec2(0.0);
    float weight_sum = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            vec2 weights = mix(vec2(1.0) - fraction, fraction, bvec2(x != 0, y != 0));
            float weight = weights.x * weights.y;
            float sample_depth = fetched_depth[y * 2 + x];
            vec4 sample_data = fetched_data[y * 2 + x];
            float sample_depth_m = LinearDepthFromScreenDepth(sample_depth);
            float depth_weight = clamp(1.0 - abs(sample_depth_m - receiver_depth_m) * inv_depth_window,
                0.0, 1.0);
            vec3 sample_normal = DecodeOctahedralNormal(sample_data.gb);
            float normal_weight = clamp((dot(normal_world, sample_normal) - 0.85) * (1.0 / 0.15), 0.0, 1.0);
            weight *= depth_weight * normal_weight * float(sample_depth < 1.0);
            ao_sum += sample_data.ra * vec2(1.0, 255.0) * weight;
            weight_sum += weight;
        }
    }
    // Missing support resolves to open AO without a full-res history lookup.
    return weight_sum > 1.0e-5 ? ao_sum / weight_sum : vec2(1.0, 0.0);
}

#endif // LIB_LIGHTING_AO_RECONSTRUCTION_GLSL
