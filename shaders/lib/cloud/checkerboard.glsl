#include "/lib/contract/settings.glsl"
#ifndef LIB_CLOUD_CHECKERBOARD_GLSL
#define LIB_CLOUD_CHECKERBOARD_GLSL


// n×n checkerboard phase for the low-res cloud grid: every sub-pixel
// sampled once per n² frames (each full-res pixel accumulates its own raw
// samples). 3x3/4x4 orderings coarse-to-fine (corners → center → edges:
// early frames stay spatially spread).
const ivec2[1] CloudCheckerboardOffsets1x1 = ivec2[1](ivec2(0, 0));

const ivec2[4] CloudCheckerboardOffsets2x2 = ivec2[4](ivec2(0, 0), ivec2(1, 1), ivec2(1, 0), ivec2(0, 1));

const ivec2[9] CloudCheckerboardOffsets3x3 = ivec2[9](ivec2(0, 0), ivec2(2, 0), ivec2(0, 2), ivec2(2, 2), ivec2(1, 1),
                                                      ivec2(1, 0), ivec2(1, 2), ivec2(0, 1), ivec2(2, 1));

const ivec2[16] CloudCheckerboardOffsets4x4 = ivec2[16](ivec2(0, 0), ivec2(2, 0), ivec2(0, 2), ivec2(2, 2), ivec2(1, 1),
    ivec2(3, 1), ivec2(1, 3), ivec2(3, 3), ivec2(1, 0), ivec2(3, 0), ivec2(1, 2), ivec2(3, 2), ivec2(0, 1), ivec2(2, 1),
    ivec2(0, 3), ivec2(2, 3));

#if CLOUD_TEMPORAL_UPSCALING == 1
#define CLOUD_CHECKERBOARD_OFFSETS CloudCheckerboardOffsets1x1
#elif CLOUD_TEMPORAL_UPSCALING == 2
#define CLOUD_CHECKERBOARD_OFFSETS CloudCheckerboardOffsets2x2
#elif CLOUD_TEMPORAL_UPSCALING == 3
#define CLOUD_CHECKERBOARD_OFFSETS CloudCheckerboardOffsets3x3
#elif CLOUD_TEMPORAL_UPSCALING == 4
#define CLOUD_CHECKERBOARD_OFFSETS CloudCheckerboardOffsets4x4
#endif

ivec2 CloudCheckerboardOffset(uint phase) {
    return CLOUD_CHECKERBOARD_OFFSETS[phase % uint(CLOUD_CHECKERBOARD_AREA)];
}

#endif
