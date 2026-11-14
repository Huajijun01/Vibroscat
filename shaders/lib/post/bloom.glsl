#ifndef LIB_POST_BLOOM_GLSL
#define LIB_POST_BLOOM_GLSL

ivec2 GetBloomMipSize(ivec2 full_size, int mip) {
    return (full_size + (1 << mip) - 1) >> mip;
}

ivec2 GetBloomMipOrigin(ivec2 full_size, int mip) {
    ivec2 half_size = GetBloomMipSize(full_size, 1);
    switch (mip) {
        case 1: return ivec2(0);
        case 2: return ivec2(half_size.x, 0);
        case 3: return ivec2(0, half_size.y);
        case 4: return ivec2(GetBloomMipSize(full_size, 3).x, half_size.y);
        case 5: return ivec2(GetBloomMipSize(full_size, 3).x + GetBloomMipSize(full_size, 4).x, half_size.y);
        case 6: return ivec2(GetBloomMipSize(full_size, 3).x + GetBloomMipSize(full_size, 4).x
                          + GetBloomMipSize(full_size, 5).x, half_size.y);
        case 7: return ivec2(GetBloomMipSize(full_size, 3).x + GetBloomMipSize(full_size, 4).x
                          + GetBloomMipSize(full_size, 5).x + GetBloomMipSize(full_size, 6).x, half_size.y);
    }
    return ivec2(0);
}

vec3 SampleBloomTent(sampler2D source, ivec2 src_origin, ivec2 src_size, ivec2 dst_coord, vec2 pixel_size) {
    vec2 src_min = vec2(src_origin) + 0.5;
    vec2 src_max = vec2(src_origin + src_size) - 0.5;
    vec2 center = vec2(src_origin + (dst_coord >> 1)) + 0.5;
    vec2 direction = mix(vec2(-1.0), vec2(1.0), notEqual(dst_coord & 1, ivec2(0)));
    // Radius-1 tent taps [5,10,1]/16 pair to [15,1]/16; the weights are the axis products.
    vec2 dominant_texel = center + direction * (1.0 / 3.0);
    vec2 weak_texel = center - direction;
    vec2 p00 = clamp(dominant_texel, src_min, src_max) * pixel_size;
    vec2 p10 = clamp(vec2(weak_texel.x, dominant_texel.y), src_min, src_max) * pixel_size;
    vec2 p01 = clamp(vec2(dominant_texel.x, weak_texel.y), src_min, src_max) * pixel_size;
    vec2 p11 = clamp(weak_texel, src_min, src_max) * pixel_size;
    return textureLod(source, p00, 0.0).rgb * (225.0 / 256.0)
         + (textureLod(source, p10, 0.0).rgb + textureLod(source, p01, 0.0).rgb) * (15.0 / 256.0)
         + textureLod(source, p11, 0.0).rgb * (1.0 / 256.0);
}

#endif // LIB_POST_BLOOM_GLSL
