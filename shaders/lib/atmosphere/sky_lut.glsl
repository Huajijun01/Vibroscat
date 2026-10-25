#ifndef LIB_ATMOSPHERE_SKY_LUT_GLSL
#define LIB_ATMOSPHERE_SKY_LUT_GLSL

#include "/lib/contract/uniforms.glsl"
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
    // Precondition: every caller passes ATM_PLANET_R and the camera altitude,
    // so the CPU derives this horizon angle once per frame.
    float theta = asin(view_dir.y);
    float v = 0.0;
    if (theta >= u_sky_lut_horizon_theta) {
        float t = (theta - u_sky_lut_horizon_theta) / (PI * 0.5 - u_sky_lut_horizon_theta);
        v = sqrt(t) * float(SKY_LUT_SKY - 1) + float(SKY_LUT_GND) + 0.5;
    } else {
        float t = (u_sky_lut_horizon_theta - theta) / (PI * 0.5 + u_sky_lut_horizon_theta);
        v = float(SKY_LUT_GND) - 0.5 - sqrt(sqrt(t)) * float(SKY_LUT_GND - 1);
    }
    float cos_phi = clamp(dot(view_dir.xz, sun_dir.xz)
        * inversesqrt(max(dot(view_dir.xz, view_dir.xz) * dot(sun_dir.xz, sun_dir.xz), 1e-5)), -0.99999, 0.99999);
    float u = (asin(cos_phi) / PI + 0.5) * float(SKY_LUT_W - 1) + 0.5;
    return vec2(u * SKY_LUT_RCP_W, v * SKY_LUT_RCP_H);
}

#endif // LIB_ATMOSPHERE_SKY_LUT_GLSL
