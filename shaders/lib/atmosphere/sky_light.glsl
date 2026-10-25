#ifndef LIB_ATMOSPHERE_SKY_LIGHT_GLSL
#define LIB_ATMOSPHERE_SKY_LIGHT_GLSL

// Sky SH irradiance - full-sphere diffuse L=0,1,2: radiance coeffs (SSBO,
// from sky_spherical_harmonics.compute / prepare2, cloud skybox) x
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

// Evaluate the projected sky radiance with a roughness-aware low-order
// specular convolution. L=0..2 SH cannot reproduce a GGX lobe exactly, so use
// a normalized Phong-equivalent zonal kernel to attenuate the higher bands
// while preserving the L0 energy. The exponent mapping follows the usual
// perceptual-roughness-to-Phong approximation and keeps the result stable for
// the rough surfaces that use the SH fallback.
vec3 EvalSkyRadiance(vec3 direction, float perceptual_roughness) {
    if (dot(direction, direction) < 1e-8) return vec3(0.0);
    vec3 unit_direction = normalize(direction);
    float roughness_squared = max(perceptual_roughness * perceptual_roughness, 1e-3);
    float phong_exponent = max(2.0 / roughness_squared - 2.0, 0.0);
    float sh_l1_weight = (phong_exponent + 1.0) / (phong_exponent + 2.0);
    // 0.5*(p+1)*(3/(p+3) - 1/(p+1)) collapses algebraically to p/(p+3).
    float sh_l2_weight = phong_exponent / (phong_exponent + 3.0);
    float basis_y1 = SH_Y1 * unit_direction.y * sh_l1_weight;
    float basis_y2 = SH_Y1 * unit_direction.z * sh_l1_weight;
    float basis_y3 = SH_Y1 * unit_direction.x * sh_l1_weight;
    // Second-band terms; each y2* name spells its monomial (y2yz = Y21*y*z,
    // y2x2z2 = Y22*(x*x - z*z)).
    float basis_y20 = SH_Y20 * (3.0 * unit_direction.y * unit_direction.y - 1.0) * sh_l2_weight;
    float y2yz = SH_Y21 * unit_direction.y * unit_direction.z * sh_l2_weight;
    float y2xz = SH_Y21 * unit_direction.x * unit_direction.z * sh_l2_weight;
    float y2xy = SH_Y21 * unit_direction.x * unit_direction.y * sh_l2_weight;
    float y2x2z2 = SH_Y22 * (unit_direction.x * unit_direction.x - unit_direction.z * unit_direction.z) * sh_l2_weight;

    vec3 radiance = vec3(
        dot(sky_sh_r0, vec4(SH_Y0, basis_y1, basis_y2, basis_y3))
      + dot(sky_sh_r1, vec4(basis_y20, y2yz, y2xz, y2xy))
      + sky_sh_r2.x * y2x2z2,
        dot(sky_sh_g0, vec4(SH_Y0, basis_y1, basis_y2, basis_y3))
      + dot(sky_sh_g1, vec4(basis_y20, y2yz, y2xz, y2xy))
      + sky_sh_g2.x * y2x2z2,
        dot(sky_sh_b0, vec4(SH_Y0, basis_y1, basis_y2, basis_y3))
      + dot(sky_sh_b1, vec4(basis_y20, y2yz, y2xz, y2xy))
      + sky_sh_b2.x * y2x2z2);
    // Low-order SH truncation can produce negative lobes. Keep each channel
    // above its spherical-average baseline so those lobes do not create dark
    // or color-shifted reflection artifacts.
    vec3 sh_average = max(
        vec3(sky_sh_r0.x, sky_sh_g0.x, sky_sh_b0.x) * SH_Y0,
        vec3(0.0));
    return max(radiance, sh_average);
}

// Preserve the unparameterized call for host/debug code that wants the sharp
// projected field. Deferred specular shading should pass material roughness.
vec3 EvalSkyRadiance(vec3 direction) {
    return EvalSkyRadiance(direction, 0.0);
}

// World-space reconstruction: coefficients baked in the cloud-skybox axes
// (+X azimuth 0, +Y up, +Z +90deg), so a world normal maps directly (no
// sun-azimuth rotation); all 9 terms kept (clouds break the sun-azimuth
// mirror symmetry).
vec3 EvalSkyLight(vec3 normal_world) {
    // L=0,1 basis
    float basis_y1 = SH_Y1 * normal_world.y;
    float basis_y2 = SH_Y1 * normal_world.z;
    float basis_y3 = SH_Y1 * normal_world.x;

    // L=2 basis (5 terms)
    float basis_y20 = SH_Y20 * (3.0 * normal_world.y * normal_world.y - 1.0);
    float y2yz = SH_Y21 * normal_world.y * normal_world.z;
    float y2xz = SH_Y21 * normal_world.x * normal_world.z;
    float y2xy = SH_Y21 * normal_world.x * normal_world.y;
    float y2x2z2 = SH_Y22 * (normal_world.x * normal_world.x - normal_world.z * normal_world.z);

    // Full-sphere irradiance (radiance coeffs x A_l convolution)
    vec3 irradiance = vec3(dot(sky_sh_r0, vec4(SH_Y0 * SH_A0, basis_y1 * SH_A1, basis_y2 * SH_A1, basis_y3 * SH_A1))
      + dot(sky_sh_r1, vec4(basis_y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + sky_sh_r2.x * y2x2z2 * SH_A2,
        dot(sky_sh_g0, vec4(SH_Y0 * SH_A0, basis_y1 * SH_A1, basis_y2 * SH_A1, basis_y3 * SH_A1))
      + dot(sky_sh_g1, vec4(basis_y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + sky_sh_g2.x * y2x2z2 * SH_A2,
        dot(sky_sh_b0, vec4(SH_Y0 * SH_A0, basis_y1 * SH_A1, basis_y2 * SH_A1, basis_y3 * SH_A1))
      + dot(sky_sh_b1, vec4(basis_y20 * SH_A2, y2yz * SH_A2, y2xz * SH_A2, y2xy * SH_A2)) + sky_sh_b2.x * y2x2z2 * SH_A2);

    return max(irradiance, 0.0);
}

// L=2 band alone of the sky irradiance. The directional sky visibility
// integrates the L0/L1 field over its blocked arcs exactly and estimates the
// blocked L2 share as this band scaled by the cosine-weighted blocked
// fraction, so the per-slice arc polynomial stays at three RGB terms. No
// clamp here: a negative lobe legitimately reduces the correction, and the
// receiver clamps the composed result once.
vec3 EvalSkyLightL2(vec3 normal_world) {
    float basis_y20 = SH_Y20 * (3.0 * normal_world.y * normal_world.y - 1.0);
    float y2yz = SH_Y21 * normal_world.y * normal_world.z;
    float y2xz = SH_Y21 * normal_world.x * normal_world.z;
    float y2xy = SH_Y21 * normal_world.x * normal_world.y;
    float y2x2z2 = SH_Y22 * (normal_world.x * normal_world.x - normal_world.z * normal_world.z);
    return SH_A2 * vec3(
        dot(sky_sh_r1, vec4(basis_y20, y2yz, y2xz, y2xy)) + sky_sh_r2.x * y2x2z2,
        dot(sky_sh_g1, vec4(basis_y20, y2yz, y2xz, y2xy)) + sky_sh_g2.x * y2x2z2,
        dot(sky_sh_b1, vec4(basis_y20, y2yz, y2xz, y2xy)) + sky_sh_b2.x * y2x2z2);
}

// Isotropic component of the SH sky irradiance (L0 only). Used for
// multiple-scattered air/water fog, where the scattered light is treated as
// direction-independent instead of using the view-direction irradiance.
vec3 EvalSkyLightAverage() {
    return max(vec3(sky_sh_r0.x, sky_sh_g0.x, sky_sh_b0.x) * (SH_Y0 * SH_A0), vec3(0.0));
}

#endif // LIB_ATMOSPHERE_SKY_LIGHT_GLSL
