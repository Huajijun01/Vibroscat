#ifndef LIB_POST_BLOOM_GLSL
#define LIB_POST_BLOOM_GLSL

// ════════════════════════════════════════════════════════════════════════════
// Bloom mip-map tile layout — 7 mip levels packed into a single atlas texture
// ════════════════════════════════════════════════════════════════════════════
//
// Mip layout (each level is half the resolution of the previous):
//   mip1: top-left quarter                  (full/2  x full/2)
//   mip2: top-right quarter                 (full/4  x full/4)
//   mip3: bottom-left quarter               (full/8  x full/8)
//   mip4: bottom-left, right of mip3        (full/16 x full/16)
//   mip5: bottom-left, right of mip4        (full/32 x full/32)
//   mip6: bottom-left, right of mip5        (full/64 x full/64)
//   mip7: bottom-left, right of mip6        (full/128 x full/128)
//
// Origin returns the top-left texel of each mip level in atlas coordinates.

ivec2 GetBloomMipOrigin(ivec2 full_size, int mip) {
    switch (mip) {
        case 1: return ivec2(0);
        case 2: return ivec2(full_size.x / 2, 0);
        case 3: return ivec2(0, full_size.y / 2);
        case 4: return ivec2(full_size.x / 8, full_size.y / 2);
        case 5: return ivec2(full_size.x / 8 + full_size.x / 16, full_size.y / 2);
        case 6: return ivec2(full_size.x / 8 + full_size.x / 16 + full_size.x / 32, full_size.y / 2);
        case 7: return ivec2(full_size.x / 8 + full_size.x / 16 + full_size.x / 32 + full_size.x / 64, full_size.y / 2);
    }
    return ivec2(0);
}

ivec2 GetBloomMipSize(ivec2 full_size, int mip) {
    return full_size >> mip;
}

#endif // POST_BLOOM_GLSL
