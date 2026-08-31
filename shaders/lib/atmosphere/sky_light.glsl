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

    float basis_y0 = SH_Y0;
    float basis_y1 = SH_Y1 * y;
    float basis_y2 = SH_Y1 * z;
    float basis_y3 = SH_Y1 * x;
    float basis_y20 = SH_Y20 * (3.0 * y * y - 1.0);
    float y2yz = SH_Y21 * y * z;
    float y2xz = SH_Y21 * x * z;
    float y2xy = SH_Y21 * x * y;
    float y2x2z2 = SH_Y22 * (x * x - z * z);

    vec3 radiance = vec3(
        dot(sky_sh_r0, vec4(basis_y0, basis_y1, basis_y2, basis_y3))
      + dot(sky_sh_r1, vec4(basis_y20, y2yz, y2xz, y2xy))
      + sky_sh_r2.x * y2x2z2,
        dot(sky_sh_g0, vec4(basis_y0, basis_y1, basis_y2, basis_y3))
      + dot(sky_sh_g1, vec4(basis_y20, y2yz, y2xz, y2xy))
      + sky_sh_g2.x * y2x2z2,
        dot(sky_sh_b0, vec4(basis_y0, basis_y1, basis_y2, basis_y3))
      + dot(sky_sh_b1, vec4(basis_y20, y2yz, y2xz, y2xy))
      + sky_sh_b2.x * y2x2z2);
    // The spherical average of an un-convolved SH field is its L0 term
    // multiplied by Y0. Keep every RGB channel at least at that baseline so
    // negative higher-order lobes cannot turn reflection energy too dark.
    vec3 sh_average = max(vec3(sky_sh_r0.x, sky_sh_g0.x, sky_sh_b0.x) * SH_Y0, vec3(0.0));
    return max(radiance, sh_average);
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
    float basis_y0 = SH_Y0;
    float basis_y1 = SH_Y1 * y;
    float basis_y2 = SH_Y1 * z;
    float basis_y3 = SH_Y1 * x;

    // L=2 basis (5 terms)
    float basis_y20 = SH_Y20 * (3.0 * y * y - 1.0);
    float y2yz = SH_Y21 * y * z;
    float y2xz = SH_Y21 * x * z;
    float y2xy = SH_Y21 * x * y;
    float y2x2z2 = SH_Y22 * (x * x - z * z);

    // Full-sphere irradiance (radiance coeffs x A_l convolution)
    vec3 irradiance = vec3(dot(sky_sh_r0, vec4(basis_y0 * SH_A0, basis_y1 * SH_A1, basis_y2 * SH_A1, basis_y3 * SH_A1))
      + dot(sky_sh_r1, vec4(basis_y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + sky_sh_r2.x * y2x2z2 * SH_A2,
        dot(sky_sh_g0, vec4(basis_y0 * SH_A0, basis_y1 * SH_A1, basis_y2 * SH_A1, basis_y3 * SH_A1))
      + dot(sky_sh_g1, vec4(basis_y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + sky_sh_g2.x * y2x2z2 * SH_A2,
        dot(sky_sh_b0, vec4(basis_y0 * SH_A0, basis_y1 * SH_A1, basis_y2 * SH_A1, basis_y3 * SH_A1))
      + dot(sky_sh_b1, vec4(basis_y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + sky_sh_b2.x * y2x2z2 * SH_A2);

    return max(irradiance, 0.0);
}

// Isotropic component of the SH sky irradiance (L0 only). Used for
// multiple-scattered air/water fog, where the scattered light is treated as
// direction-independent instead of using the view-direction irradiance.
vec3 EvalSkyLightAverage() {
    return max(vec3(sky_sh_r0.x, sky_sh_g0.x, sky_sh_b0.x) * (SH_Y0 * SH_A0), vec3(0.0));
}

#endif
