#ifndef LIB_CLOUD_CHECKERBOARD_GLSL
#define LIB_CLOUD_CHECKERBOARD_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

#if CLOUD_RECONSTRUCTION_MODE == 1 && CLOUD_TEMPORAL_UPSCALING > 1

const int CLOUD_CHECKERBOARD_AREA = CLOUD_TEMPORAL_UPSCALING * CLOUD_TEMPORAL_UPSCALING;

// N + 1 is coprime to N squared, so the permutation visits every offset once.
ivec2 CloudCheckerboardOffset() {
    int phase = frameCounter % CLOUD_CHECKERBOARD_AREA;
    int index = (phase * (CLOUD_TEMPORAL_UPSCALING + 1)) % CLOUD_CHECKERBOARD_AREA;
    int y = index / CLOUD_TEMPORAL_UPSCALING;
    return ivec2(index - y * CLOUD_TEMPORAL_UPSCALING, y);
}

ivec2 CloudCheckerboardSize() {
    return (ivec2(u_render_res) + ivec2(CLOUD_TEMPORAL_UPSCALING - 1)) / CLOUD_TEMPORAL_UPSCALING;
}

#endif

#endif // LIB_CLOUD_CHECKERBOARD_GLSL
