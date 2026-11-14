#ifndef LIB_CORE_NOISE_GLSL
#define LIB_CORE_NOISE_GLSL

// STBN volume, baked offline with a void-and-cluster generator.

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Decorrelation slice offsets into the STBN volume; together they form the
// pack-wide stream registry: within one pass, every STBN consumer must use a
// distinct stream. Pair consumers add a spatial shift to decorrelate their scalars.
const int STBN_STREAM_0 = 0;
const int STBN_STREAM_1 = 16;
const int STBN_STREAM_2 = 23;
const int STBN_STREAM_3 = 32;

const ivec3 STBN_SCALAR_SIZE = ivec3(128, 128, 64);

// Point sampling preserves the spatial and temporal blue-noise distribution.
float SampleSTBN(ivec2 pixel, int frame) {
    return texelFetch(utex_stbn_scalar, ivec3(pixel & (STBN_SCALAR_SIZE.xy - ivec2(1)),
        frame & (STBN_SCALAR_SIZE.z - 1)), 0).r;
}

// .x is the unshifted stream, .y the one advanced by slice_offset and spatial_shift;
// callers pass registered registry offsets. Bit-mask wrap: GLSL % is undefined for negatives.
vec2 SampleSTBNPair(ivec2 texel, int frame, int slice_offset, ivec2 spatial_shift) {
    ivec2 p0 = texel & (STBN_SCALAR_SIZE.xy - ivec2(1));
    int z = frame & (STBN_SCALAR_SIZE.z - 1);
    ivec2 p1 = (p0 + spatial_shift) & (STBN_SCALAR_SIZE.xy - ivec2(1));
    return vec2(
        texelFetch(utex_stbn_scalar, ivec3(p0, z), 0).r,
        texelFetch(utex_stbn_scalar, ivec3(p1, (z + slice_offset) & (STBN_SCALAR_SIZE.z - 1)), 0).r);
}

// Exists only with TAA; effects without temporal accumulation pass slice 0
// instead, since an advancing slice would shimmer without accumulation.
// Effects with a dedicated accumulator (AO, GI) keep advancing with frameCounter and must not use this.
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

// Wellons' lowbias32 avalanche hash; IGN is a dither pattern, not a hash, and
// correlates across draws that need per-cell randoms.
uint LowBias32Hash(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

// Continuous R2 offset for sub-resolution grids: starts at the cell center, then
// covers it without a finite phase table.
vec2 R2Offset() {
    // Frame-uniform: shaders.properties derives it from frameCounter.
    return u_r2_offset;
}

#endif // LIB_CORE_NOISE_GLSL
