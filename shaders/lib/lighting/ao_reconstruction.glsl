#ifndef LIB_LIGHTING_AO_RECONSTRUCTION_GLSL
#define LIB_LIGHTING_AO_RECONSTRUCTION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"

// Four-tap bilateral upsample of the half-res workspace: half texel h maps to
// full texel 2*h; guide normals share the AO workspace, depth is depthtex2.
vec2 ReconstructAO(ivec2 texel, float scene_depth, vec2 normal_oct) {
    ivec2 half_size = ivec2(u_ao_half_res);
    ivec2 full_max = ivec2(u_render_res) - 1;
    ivec2 base_texel = min(texel / 2, half_size - 1);
    ivec2 lower_pixel = min(base_texel * 2, full_max);
    ivec2 upper_pixel = min(min(base_texel + 1, half_size - 1) * 2, full_max);
    // Odd sizes: the +1 tap lands past the half-res lattice but inside full res.
    vec2 fraction = saturate(vec2(texel - lower_pixel) / vec2(max(upper_pixel - lower_pixel, 1)));
    float fetched_depth[4];
    vec4 fetched_data[4];
    for (int i = 0; i < 4; ++i) {
        ivec2 sample_texel = min(base_texel + ivec2(i & 1, i >> 1), half_size - 1);
        ivec2 sample_pixel = min(sample_texel * 2, full_max);
        fetched_depth[i] = texelFetch(depthtex2, sample_pixel, 0).r;
        fetched_data[i] = texelFetch(colortex2, sample_texel, 0);
    }
    vec3 normal_world = DecodeOctahedralNormal(normal_oct);
    vec3 normal_view = mat3(gbufferModelView) * normal_world;
    float receiver_depth_m = LinearDepthFromScreenDepth(scene_depth);
    vec2 plane_xy = normal_view.xy * vec2(
        gbufferProjectionInverse[0][0], gbufferProjectionInverse[1][1]);
    vec2 receiver_ndc = (vec2(texel) + 0.5) * u_render_pixel_size * 2.0 - 1.0;
#ifdef TAA
    receiver_ndc -= u_taa_offset;
#endif
    float receiver_ray_plane = dot(plane_xy, receiver_ndc) - normal_view.z;
    vec2 plane_pixel_step = plane_xy * (2.0 * u_render_pixel_size);
    // Compare displacement off the receiver ray plane: grazing neighbors share
    // the surface but differ in view depth.
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
            ivec2 sample_pixel = min((base_texel + ivec2(x, y)) * 2, full_max);
            float plane_distance = abs((sample_depth_m - receiver_depth_m) * receiver_ray_plane
                + sample_depth_m * dot(plane_pixel_step, vec2(sample_pixel - texel)));
            float depth_weight = saturate(1.0 - plane_distance * inv_depth_window);
            vec3 sample_normal = DecodeOctahedralNormal(sample_data.gb);
            float normal_weight = saturate((dot(normal_world, sample_normal) - 0.85) * (1.0 / 0.15));
            weight *= depth_weight * normal_weight * float(sample_depth < 1.0);
            ao_sum += sample_data.ra * vec2(1.0, 255.0) * weight;
            weight_sum += weight;
        }
    }
    // No support: resolve to open AO instead of a full-res history lookup.
    return weight_sum > 1.0e-5 ? ao_sum / weight_sum : vec2(1.0, 0.0);
}

#endif // LIB_LIGHTING_AO_RECONSTRUCTION_GLSL
