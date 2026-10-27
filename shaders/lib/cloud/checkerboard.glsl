#ifndef LIB_CLOUD_CHECKERBOARD_GLSL
#define LIB_CLOUD_CHECKERBOARD_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

#if CLOUD_RECONSTRUCTION_MODE == 1 && CLOUD_TEMPORAL_UPSCALING > 1

const int CLOUD_CHECKERBOARD_AREA = CLOUD_TEMPORAL_UPSCALING * CLOUD_TEMPORAL_UPSCALING;

// N + 1 is coprime to N squared, so this diagonal-first permutation visits
// every offset once. No lookup table or temporal noise stream is required.
ivec2 CloudCheckerboardOffset() {
    int phase = frameCounter % CLOUD_CHECKERBOARD_AREA;
    int index = (phase * (CLOUD_TEMPORAL_UPSCALING + 1)) % CLOUD_CHECKERBOARD_AREA;
    // One division: index % N is exactly index - (index / N) * N.
    int y = index / CLOUD_TEMPORAL_UPSCALING;
    return ivec2(index - y * CLOUD_TEMPORAL_UPSCALING, y);
}

// Ceil division retains partial edge blocks. Out-of-scene phase positions
// write an invalid current sample; valid pixels still refresh once per cycle.
ivec2 CloudCheckerboardSize() {
    return (ivec2(u_render_res) + ivec2(CLOUD_TEMPORAL_UPSCALING - 1)) / CLOUD_TEMPORAL_UPSCALING;
}

#endif

#endif // LIB_CLOUD_CHECKERBOARD_GLSL
