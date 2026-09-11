#ifndef LIB_CORE_NOISE_GLSL
#define LIB_CORE_NOISE_GLSL

// STBN volume: independently generated (void-and-cluster) from
// Wolfe, Morrical, Akenine-Möller, Ramamoorthi, "Scalar Spatiotemporal Blue
// Noise Masks", 2022; lineage Heitz et al., "Spatiotemporal Blue Noise
// Masks", ACM TOG 2019. See licenses/THIRD_PARTY_NOTICES.md section 9.

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Decorrelation slice offsets into the 64-slice STBN volume: a consumer that
// needs an independent stream on the same spatial seed advances the time
// slice by one of these. The values form the pack-wide stream registry;
// within one pass, every STBN consumer must use a distinct stream.
// (OpaqueSSRRandom2 additionally shifts the spatial texel; see there.)
const int STBN_STREAM_0 = 0;
const int STBN_STREAM_1 = 16;
const int STBN_STREAM_2 = 23;
const int STBN_STREAM_3 = 32;

// Spatiotemporal blue-noise scalar from the shared 128x128x64 STBN volume.
// Point sampling preserves the spatial and temporal blue-noise distribution.
float SampleSTBN(ivec2 pixel, int frame) {
    return texelFetch(utex_stbn_scalar, ivec3(pixel & ivec2(127, 127), frame & 63), 0).r;
}

// Shared STBN time slice for effects without their own temporal accumulation:
// with TAA off the slice pins to 0 so the dither stays static instead of
// shimmering. Effects with a dedicated accumulator (AO, GI) keep advancing
// with frameCounter and must not use this.
int STBNFrame() {
#ifdef TAA
    return frameCounter;
#else
    return 0;
#endif
}

float InterleavedGradientNoise(vec2 pixel) {
    return fract(52.9829189
        * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// Continuous R2 offset for sub-resolution grids. The first frame starts at
// the cell center; subsequent frames cover the cell without a finite phase
// table.
vec2 CloudR2Offset(int frame) {
    return fract(vec2(0.5) + float(frame) * vec2(
        1.0 / 1.3247179572,
        1.0 / 1.7548776662
    ));
}

#endif
