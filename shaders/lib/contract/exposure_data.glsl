#ifndef LIB_CONTRACT_EXPOSURE_DATA_GLSL
#define LIB_CONTRACT_EXPOSURE_DATA_GLSL

// Binding 0: 264-byte std430 payload in a 268-byte host allocation.
layout(std430, binding = 0) buffer ExposureData {
    float smooth_lum;
    float exposure;
    float partial_sums[64];
};

#endif
