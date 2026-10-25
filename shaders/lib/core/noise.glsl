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

// Baked volume is 128x128x64 (customTexture.utex_stbn_scalar).
const ivec3 STBN_SCALAR_SIZE = ivec3(128, 128, 64);

// Spatiotemporal blue-noise scalar from the shared 128x128x64 STBN volume.
// Point sampling preserves the spatial and temporal blue-noise distribution.
float SampleSTBN(ivec2 pixel, int frame) {
    return texelFetch(utex_stbn_scalar, ivec3(pixel & (STBN_SCALAR_SIZE.xy - ivec2(1)),
        frame & (STBN_SCALAR_SIZE.z - 1)), 0).r;
}

// Two decorrelated STBN scalars from one texel: the second stream advances
// the time slice by slice_offset and the spatial texel by spatial_shift.
// Callers pass their registered registry offsets. Value order is stable:
// .x is the unshifted stream, .y the shifted one.
// Wrapping uses bit masks like SampleSTBN: the volume sizes are powers of
// two, and x & (size - 1) equals the floor modulo for every int32 input,
// including negatives (the plain % form is undefined for negative operands
// in GLSL and would emit out-of-range texel coordinates).
vec2 SampleSTBNPair(ivec2 texel, int frame, int slice_offset, ivec2 spatial_shift) {
    ivec2 p0 = texel & (STBN_SCALAR_SIZE.xy - ivec2(1));
    int z = frame & (STBN_SCALAR_SIZE.z - 1);
    ivec2 p1 = (p0 + spatial_shift) & (STBN_SCALAR_SIZE.xy - ivec2(1));
    return vec2(
        texelFetch(utex_stbn_scalar, ivec3(p0, z), 0).r,
        texelFetch(utex_stbn_scalar, ivec3(p1, (z + slice_offset) & (STBN_SCALAR_SIZE.z - 1)), 0).r);
}

// Shared STBN time slice for effects without their own temporal accumulation.
// Exists only with TAA: without temporal accumulation an advancing slice would
// shimmer, so consumers pass 0 and keep a static spatial pattern. Effects with
// a dedicated accumulator (AO, GI) keep advancing with frameCounter and must
// not use this.
#ifdef TAA
int STBNFrame() {
    return frameCounter;
}
#endif

// Interleaved gradient noise (Jimenez et al. 2016).
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
vec2 R2Offset() {
    // Frame-uniform: shaders.properties derives it from frameCounter.
    return u_r2_offset;
}

#endif // LIB_CORE_NOISE_GLSL
