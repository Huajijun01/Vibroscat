#ifndef LIB_ATMOSPHERE_SKYBOX_UV_GLSL
#define LIB_ATMOSPHERE_SKYBOX_UV_GLSL
#include "/lib/core/math_scalar.glsl"

// World-aligned equal-area cloud skybox: u = azimuth, v = sin(elevation),
// so every texel covers a constant solid angle (4*pi/N^2) and the SH pass
// needs no per-pixel Jacobian.
#define SKY_RADIANCE_LUT_SIZE 256

// Row-center v of LUT row i: 2*((i + 0.5)/N) - 1, the exact expression both
// the bake and the SH pass sample at (constexpr in C++). Consumers that need
// the row index of a v value invert this locally; the paired shift by one half
// row only cancels exactly when it is written this way, so do not respell it.
#define SKY_RADIANCE_LUT_ROW_CENTER(i) (2.0 * ((float(i) + 0.5) / float(SKY_RADIANCE_LUT_SIZE)) - 1.0)

// Inverse of the bake mapping: world direction -> equal-area skybox UV.
// +X at u = 0.5, zenith at v = 1, v = (sin(elevation) + 1) / 2.
vec2 SkyRadianceUV(vec3 dir) {
    // fract() folds the +pi/-pi seam onto u = 0; the bake's rightmost column
    // already transitions toward column 0, so CLAMP sampling is seamless.
    float u = fract(atan(dir.z, dir.x) * INV_TWO_PI + 0.5);
    float v = dir.y * 0.5 + 0.5;
    return vec2(u, v);
}

#endif // LIB_ATMOSPHERE_SKYBOX_UV_GLSL
