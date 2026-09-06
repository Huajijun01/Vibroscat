#ifndef LIB_CONTRACT_EXPOSURE_DATA_GLSL
#define LIB_CONTRACT_EXPOSURE_DATA_GLSL

// Binding 0: persistent exposure state plus per-workgroup statistics.
layout(std430, binding = 0) buffer ExposureData {
    float smooth_lum;
    float exposure;
    float log_lum_sums[64];
    float weight_sums[64];
    uint luminance_histogram[4096];
};

#endif
