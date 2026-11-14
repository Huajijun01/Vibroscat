#ifndef LIB_CONTRACT_SKY_LIGHT_DATA_GLSL
#define LIB_CONTRACT_SKY_LIGHT_DATA_GLSL

// Binding 1: ten vec4 values = 160 bytes in std430 layout. Per channel, 9
// orthonormal SH coefficients packed into 3 vec4:
//   sky_sh_*0 = (L0, L1y, L1z, L1x)
//   sky_sh_*1 = (L20, L2yz, L2xz, L2xy)
//   sky_sh_*2 = (L2(x^2-z^2), unused, unused, unused)
// Upper-sky radiance plus a uniform Lambertian ground; raw coefficients, each
// consumer applies its own kernel. Clouds break the sun-azimuth symmetry, so
// L1x and the xz/xy terms stay nonzero. ground_light is direct sun/moon light
// at the camera altitude, not the closure already in the SH coefficients.
layout(std430, binding = 1) buffer SkyLightData {
    vec4 sky_sh_r0;
    vec4 sky_sh_r1;
    vec4 sky_sh_r2;
    vec4 sky_sh_g0;
    vec4 sky_sh_g1;
    vec4 sky_sh_g2;
    vec4 sky_sh_b0;
    vec4 sky_sh_b1;
    vec4 sky_sh_b2;
    vec4 ground_light;
};

#endif // LIB_CONTRACT_SKY_LIGHT_DATA_GLSL
