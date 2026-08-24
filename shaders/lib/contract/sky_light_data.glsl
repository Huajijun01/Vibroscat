#ifndef LIB_CONTRACT_SKY_LIGHT_DATA_GLSL
#define LIB_CONTRACT_SKY_LIGHT_DATA_GLSL

// Binding 1: ten vec4 values = 160 bytes in std430 layout.
// Per channel, 9 orthonormal SH coefficients packed into 3 vec4:
//   skySH_*0 = (L0, L1y, L1z, L1x)
//   skySH_*1 = (L20, L2yz, L2xz, L2xy)
//   skySH_*2 = (L2(x^2-z^2), unused, unused, unused)
// The full-sphere cloud skybox breaks sun-azimuth mirror symmetry, so the
// L1x and xz/xy L2 terms stay nonzero.
layout(std430, binding = 1) buffer SkyLightData {
    vec4 skySH_R0;
    vec4 skySH_R1;
    vec4 skySH_R2;
    vec4 skySH_G0;
    vec4 skySH_G1;
    vec4 skySH_G2;
    vec4 skySH_B0;
    vec4 skySH_B1;
    vec4 skySH_B2;
    vec4 ground_light;
};

#endif
