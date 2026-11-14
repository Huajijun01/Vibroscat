#ifndef LIB_ATMOSPHERE_SKYBOX_UV_GLSL
#define LIB_ATMOSPHERE_SKYBOX_UV_GLSL
#include "/lib/core/math_scalar.glsl"

// Equal-area cloud skybox: u = azimuth, v = sin(elevation) (constant solid angle per texel).
#define SKY_RADIANCE_LUT_SIZE 256

// Row-center v shared by the bake and the SH pass; the half-row shift cancels exactly only as
// written here, so do not respell it.
#define SKY_RADIANCE_LUT_ROW_CENTER(i) (2.0 * ((float(i) + 0.5) / float(SKY_RADIANCE_LUT_SIZE)) - 1.0)

// Inverse of the bake mapping: +X at u = 0.5, zenith at v = 1.
vec2 SkyRadianceUV(vec3 dir) {
    // fract() folds the seam onto u = 0; with CLAMP sampling the wrap is seamless.
    float u = fract(atan(dir.z, dir.x) * INV_TWO_PI + 0.5);
    float v = dir.y * 0.5 + 0.5;
    return vec2(u, v);
}

#endif // LIB_ATMOSPHERE_SKYBOX_UV_GLSL
