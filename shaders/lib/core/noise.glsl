#ifndef LIB_CORE_NOISE_GLSL
#define LIB_CORE_NOISE_GLSL

// STBN volume: independently generated (void-and-cluster) from
// Wolfe, Morrical, Akenine-Möller, Ramamoorthi, "Scalar Spatiotemporal Blue
// Noise Masks", 2022; lineage Heitz et al., "Spatiotemporal Blue Noise
// Masks", ACM TOG 2019. See licenses/THIRD_PARTY_NOTICES.md section 8.

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Decorrelation slice offsets into the 64-slice STBN volume: a consumer that
// needs an independent stream on the same spatial seed advances the time
// slice by one of these. The values form the pack-wide stream registry;
// within one pass, every STBN consumer must use a distinct stream. A pair
// consumer additionally passes a spatial shift so its two scalars decorrelate.
const int STBN_STREAM_0 = 0;
const int STBN_STREAM_1 = 16;
const int STBN_STREAM_2 = 23;
const int STBN_STREAM_3 = 32;

// Spatiotemporal blue-noise scalar from the shared 128x128x64 STBN volume.
// Point sampling preserves the spatial and temporal blue-noise distribution.
float SampleSTBN(ivec2 pixel, int frame) {
    return texelFetch(utex_stbn_scalar, ivec3(pixel & ivec2(127, 127), frame & 63), 0).r;
}

// Two decorrelated STBN scalars from one texel: the second stream advances
// the time slice by slice_offset and the spatial texel by spatial_shift.
// Callers pass their registered registry offsets. Value order is stable:
// .x is the unshifted stream, .y the shifted one.
vec2 SampleSTBNPair(ivec2 texel, int frame, int slice_offset, ivec2 spatial_shift) {
    ivec3 size = textureSize(utex_stbn_scalar, 0);
    ivec2 p0 = ivec2(
        (texel.x % size.x + size.x) % size.x,
        (texel.y % size.y + size.y) % size.y);
    int z = (frame % size.z + size.z) % size.z;
    ivec2 p1 = (p0 + spatial_shift) % size.xy;
    return vec2(
        texelFetch(utex_stbn_scalar, ivec3(p0, z), 0).r,
        texelFetch(utex_stbn_scalar, ivec3(p1, (z + slice_offset) % size.z), 0).r);
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

// 32-bit avalanche hash (Wellons' lowbias32 constants). Interleaved gradient
// noise is a dither pattern, not a hash: over cell indices its values are far
// from uniform and correlate across draws that need per-cell randoms.
uint LowBias32Hash(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

// Continuous R2 offset for sub-resolution grids. The first frame starts at
// the cell center; subsequent frames cover the cell without a finite phase
// table.
vec2 R2Offset(int frame) {
    return fract(vec2(0.5) + float(frame) * vec2(
        1.0 / 1.3247179572,
        1.0 / 1.7548776662
    ));
}

#endif // LIB_CORE_NOISE_GLSL
