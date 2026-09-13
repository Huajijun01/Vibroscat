#ifndef LIB_ATMOSPHERE_SKY_LUT_GLSL
#define LIB_ATMOSPHERE_SKY_LUT_GLSL

#include "/lib/core/math_scalar.glsl"

#define SKY_LUT_W  128
#define SKY_LUT_H  128
#define SKY_LUT_SKY 96
#define SKY_LUT_GND 32
#define SKY_LUT_N  16384
#define SKY_LUT_RCP_W (1.0 / float(SKY_LUT_W))
#define SKY_LUT_RCP_H (1.0 / float(SKY_LUT_H))

// -- Sampling: view_dir + sun_dir -> LUT UV --
vec2 SkyLUTUV(vec3 view_dir, vec3 sun_dir, float planet_r, float altitude) {
    float theta_h = asin(planet_r / (planet_r + altitude)) - PI * 0.5;
    float theta = asin(view_dir.y);
    float v = 0.0;
    if (theta >= theta_h) {
        float t = (theta - theta_h) / (PI * 0.5 - theta_h);
        v = sqrt(t) * float(SKY_LUT_SKY - 1) + float(SKY_LUT_GND) + 0.5;
    } else {
        float t = (theta_h - theta) / (PI * 0.5 + theta_h);
        v = float(SKY_LUT_GND) - 0.5 - sqrt(sqrt(t)) * float(SKY_LUT_GND - 1);
    }
    vec2 view_xz = view_dir.xz;
    vec2 sun_xz = sun_dir.xz;
    float cos_phi = clamp(dot(view_xz, sun_xz) * inversesqrt(max(dot(view_xz, view_xz) * dot(sun_xz, sun_xz), 1e-5)), -0.99999, 0.99999);
    float u = (asin(cos_phi) / PI + 0.5) * float(SKY_LUT_W - 1) + 0.5;
    return vec2(u * SKY_LUT_RCP_W, v * SKY_LUT_RCP_H);
}

#endif // LIB_ATMOSPHERE_SKY_LUT_GLSL
