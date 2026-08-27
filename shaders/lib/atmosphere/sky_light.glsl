#ifndef LIB_ATMOSPHERE_SKY_LIGHT_GLSL
#define LIB_ATMOSPHERE_SKY_LIGHT_GLSL

// Sky SH irradiance — full-sphere diffuse L=0,1,2: radiance coeffs (SSBO,
// from sky_spherical_harmonics.compute / prepare2, cloud skybox) ×
// Ramamoorthi A_l.

#include "/lib/contract/sky_light_data.glsl"

// L=0,1,2 constants
const float SH_Y0  = 0.282095;
const float SH_Y1  = 0.488603;
const float SH_Y20 = 0.315392;
const float SH_Y21 = 1.092548;
const float SH_Y22 = 0.546274;

// Irradiance convolution A_l (Ramamoorthi 2001, orthonormal SH)
const float SH_A0 = 3.141593;
const float SH_A1 = 2.094395;
const float SH_A2 = 0.785398;

// Evaluate the projected sky radiance itself. Unlike EvalSkyLight, this
// leaves the SH coefficients unconvolved so specular environment lookups do
// not receive a diffuse irradiance integral.
vec3 EvalSkyRadiance(vec3 direction) {
    if (dot(direction, direction) < 1e-8) return vec3(0.0);
    vec3 unit_direction = normalize(direction);
    float x = unit_direction.x;
    float y = unit_direction.y;
    float z = unit_direction.z;

    float Y0 = SH_Y0;
    float Y1 = SH_Y1 * y;
    float Y2 = SH_Y1 * z;
    float Y3 = SH_Y1 * x;
    float Y20 = SH_Y20 * (3.0 * y * y - 1.0);
    float y2yz = SH_Y21 * y * z;
    float y2xz = SH_Y21 * x * z;
    float y2xy = SH_Y21 * x * y;
    float y2x2z2 = SH_Y22 * (x * x - z * z);

    vec3 radiance = vec3(
        dot(skySH_R0, vec4(Y0, Y1, Y2, Y3))
      + dot(skySH_R1, vec4(Y20, y2yz, y2xz, y2xy))
      + skySH_R2.x * y2x2z2,
        dot(skySH_G0, vec4(Y0, Y1, Y2, Y3))
      + dot(skySH_G1, vec4(Y20, y2yz, y2xz, y2xy))
      + skySH_G2.x * y2x2z2,
        dot(skySH_B0, vec4(Y0, Y1, Y2, Y3))
      + dot(skySH_B1, vec4(Y20, y2yz, y2xz, y2xy))
      + skySH_B2.x * y2x2z2);
    return max(radiance, 0.0);
}

// World-space reconstruction: coefficients baked in the cloud-skybox axes
// (+X azimuth 0, +Y up, +Z +90°), so a world normal maps directly (no
// sun-azimuth rotation); all 9 terms kept (clouds break the sun-azimuth
// mirror symmetry).
vec3 EvalSkyLight(vec3 normal) {
    float x = normal.x;
    float y = normal.y;
    float z = normal.z;

    // L=0,1 basis
    float Y0 = SH_Y0;
    float Y1 = SH_Y1 * y;
    float Y2 = SH_Y1 * z;
    float Y3 = SH_Y1 * x;

    // L=2 basis (5 terms)
    float Y20 = SH_Y20 * (3.0 * y * y - 1.0);
    float y2yz = SH_Y21 * y * z;
    float y2xz = SH_Y21 * x * z;
    float y2xy = SH_Y21 * x * y;
    float y2x2z2 = SH_Y22 * (x * x - z * z);

    // Full-sphere irradiance (radiance coeffs x A_l convolution)
    vec3 irradiance = vec3(dot(skySH_R0, vec4(Y0 * SH_A0, Y1 * SH_A1, Y2 * SH_A1, Y3 * SH_A1))
      + dot(skySH_R1, vec4(Y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + skySH_R2.x * y2x2z2 * SH_A2,
        dot(skySH_G0, vec4(Y0 * SH_A0, Y1 * SH_A1, Y2 * SH_A1, Y3 * SH_A1))
      + dot(skySH_G1, vec4(Y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + skySH_G2.x * y2x2z2 * SH_A2,
        dot(skySH_B0, vec4(Y0 * SH_A0, Y1 * SH_A1, Y2 * SH_A1, Y3 * SH_A1))
      + dot(skySH_B1, vec4(Y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + skySH_B2.x * y2x2z2 * SH_A2);

    return max(irradiance, 0.0);
}

// Isotropic component of the SH sky irradiance (L0 only). Used for
// multiple-scattered air/water fog, where the scattered light is treated as
// direction-independent instead of using the view-direction irradiance.
vec3 EvalSkyLightAverage() {
    return max(vec3(skySH_R0.x, skySH_G0.x, skySH_B0.x) * (SH_Y0 * SH_A0), vec3(0.0));
}

#endif
