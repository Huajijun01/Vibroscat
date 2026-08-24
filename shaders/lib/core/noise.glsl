#ifndef LIB_CORE_NOISE_GLSL
#define LIB_CORE_NOISE_GLSL

// STBN volume: independently generated (void-and-cluster) from
// Wolfe, Morrical, Akenine-Möller, Ramamoorthi, "Scalar Spatiotemporal Blue
// Noise Masks", 2022; lineage Heitz et al., "Spatiotemporal Blue Noise
// Masks", ACM TOG 2019. See licenses/THIRD_PARTY_NOTICES.md section 9.

#include "/lib/contract/uniforms.glsl"

// Spatiotemporal blue-noise scalar from the shared 128x128x64 STBN volume.
// Point sampling preserves the spatial and temporal blue-noise distribution.
float SampleSTBN(ivec2 pixel, int frame) {
    return texelFetch(utex_stbn_scalar, ivec3(pixel & ivec2(127, 127), frame & 63), 0).r;
}

float InterleavedGradientNoise(vec2 pixel) {
    return fract(52.9829189
        * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

#endif
