#ifndef LIB_CONTRACT_EXPOSURE_DATA_GLSL
#define LIB_CONTRACT_EXPOSURE_DATA_GLSL

// Binding 0: persistent adapted exposure plus per-workgroup statistics.
layout(std430, binding = 0) buffer ExposureData {
    // Log2 exposure multiplier, initialized by exposure_final on pack reload.
    float adapted_exposure_ev;
    float exposure;
    float log_lum_sums[64];
    float weight_sums[64];
    uint luminance_histogram[4096];
};

#endif
