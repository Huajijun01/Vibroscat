#ifndef LIB_ATMOSPHERE_SKY_RADIANCE_GLSL
#define LIB_ATMOSPHERE_SKY_RADIANCE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/atmosphere/transmittance.glsl"
#include "/lib/scattering/phase.glsl"

// ===============================================================
// Sky Integration  (midpoint + analytic, vec4 spectral)
// ===============================================================

vec4 ComputeSkyRadiance(vec3 camera_pos, vec3 view_dir, vec3 sun_dir
) {
    // -- sphere intersection --
    float t0, t1;
    if (!RayIntersectSphere(camera_pos, view_dir, ATM_ATMO_R, t0, t1)) return vec4(0.0);

    // Horizon below-dip: a below-horizon ray terminates on a sphere placed
    // ATM_HORIZON_DIP_SCALE km beneath the planet surface instead of on the
    // surface itself, so it integrates a little of the exponentially denser
    // low-altitude Mie/aerosol air and the horizon reads thicker/hazier.
    float max_dist = t1;
    float t_ground = -1.0;  // negative = no ground hit
    {
        float ground_radius = ATM_PLANET_R;
#if ATM_HORIZON_DIP
        ground_radius = max(ATM_PLANET_R - ATM_HORIZON_DIP_SCALE, 1.0);
#endif
        float t_entry, t_exit;
        if (RayIntersectSphere(camera_pos, view_dir, ground_radius, t_entry, t_exit) && t_entry > 0.0) {
            max_dist = t_entry;
            t_ground = t_entry;
        }
    }
    if (max_dist <= 0.0) return vec4(0.0);

    // -- phase (loop-invariant) --
    float cos_vs = dot(view_dir, sun_dir);
    float phase_rayleigh   = PhaseRayleigh(cos_vs);
    float phase_mie   = PhaseHenyeyGreensteinTripleLobe(cos_vs, ATM_MIE_PHASE);
    float phase_mie_moon = PhaseHenyeyGreensteinTripleLobe(-cos_vs, ATM_MIE_PHASE);  // moon=-sun, Rayleigh is even

    float dt      = max_dist / ATM_NUM_STEPS;
    vec4  trans   = vec4(1.0);

    // accumulators: sun
    vec4 acc_ray = vec4(0.0);
    vec4 acc_mie = vec4(0.0);
    vec4 acc_x = vec4(0.0); // multiscat (sun only)
    // accumulators: moon (no multiscat)
    vec4 acc_ray_moon = vec4(0.0);
    vec4 acc_mie_moon = vec4(0.0);

    // -- midpoint stepping: sample at segment center, analytic extinction --
    float t_prev = 0.0;

    for (float i = 1.0; i <= ATM_NUM_STEPS; i += 1.0) {
        float u = i / ATM_NUM_STEPS;
        float t_cur  = u * u * max_dist;
        float dt_seg = t_cur - t_prev;
        float t_mid  = (t_prev + t_cur) * 0.5;

        vec3 p_mid    = camera_pos + view_dir * t_mid;
        float r2_mid  = dot(p_mid, p_mid);
        float r_mid   = sqrt(r2_mid);
        float h_mid   = r_mid - ATM_PLANET_R;

        // Density altitude: DensityRay / DensityOzone clamp below the surface
        // and GetSigmaSMie (a plain exp) grows there, so the below-surface Mie
        // term thickens the horizon without NaN. The transmittance and
        // multiscatter LUTs are parameterised on r >= planet radius
        // (sqrt(r^2 - R^2) is undefined below the surface), so clamp the radius
        // used for the LUT lookups.
        float r_lut   = max(r_mid, ATM_PLANET_R);
        float r2_lut  = r_lut * r_lut;

        // Midpoint sigmas, vec4 = (Rayleigh, Mie, Ozone) RGB packing shared
        // with the LUTs: sr/sm/so are the scattering components, sigma_t the
        // total, ss the scattering sum; rs/ms_raw fold in the transmittance,
        // ms is the multi-scatter LUT sample, xs their product.
        vec4 sr_mid = GetSigmaSRay(h_mid);
        vec4 sm_mid = GetSigmaSMie(h_mid);
        vec4 so_mid = GetSigmaAOzone(h_mid);
        vec4 sigma_t_mid = sr_mid + sm_mid + so_mid;
        vec4 ss_mid = sr_mid + sm_mid;

        float mu_mid = dot(p_mid, sun_dir) / r_mid;
        vec4 trans_mid = SampleTransmittance(utex_tslut, r_lut, r2_lut, mu_mid);
        vec4 ms_mid = SampleMultiScatter(utex_mslut, r_lut, mu_mid);
        // moonlight: opposite direction, shared extinction
        vec4 ts_moon_mid = SampleTransmittance(utex_tslut, r_lut, r2_lut, -mu_mid);

        vec4 rs_mid      = trans_mid * sr_mid;
        vec4 ms_raw_mid  = trans_mid * sm_mid;
        vec4 xs_mid      = ss_mid * ms_mid;

        vec4 rs_moon_mid = ts_moon_mid * sr_mid;
        vec4 ms_moon_mid = ts_moon_mid * sm_mid;

        // -- analytic integral with midpoint extinction --
        vec4 optical_depth_mid = sigma_t_mid * dt_seg;
        vec4 step_trans = exp(-optical_depth_mid);
        vec4 integral  = (vec4(1.0) - step_trans) * (dt_seg / max(optical_depth_mid, ATM_EPS));

        vec4 w = trans * integral;
        acc_ray += w * rs_mid;
        acc_mie += w * ms_raw_mid;
        acc_x += w * xs_mid;
        acc_ray_moon += w * rs_moon_mid;
        acc_mie_moon += w * ms_moon_mid;

        trans  *= step_trans;
        t_prev  = t_cur;
    }

    // -- ground albedo (sun + moon) --
    vec4 ground_sun_radiance = vec4(0.0);
    vec4 ground_moon_radiance = vec4(0.0);
    if (t_ground > 0.0) {
        vec3 ground_pos = camera_pos + view_dir * t_ground;
        float r_g  = ATM_PLANET_R + 0.01;
        float r2_g = r_g * r_g;
        float mu_sun_g = dot(ground_pos, sun_dir) / max(length(ground_pos), 1.0e-4);

        // sunlight -> ground
        vec4 trans_sun_g = SampleTransmittance(utex_tslut, r_g, r2_g, mu_sun_g);
        vec4 ms_g = SampleMultiScatter(utex_mslut, r_g, mu_sun_g);
        ground_sun_radiance = (trans_sun_g * Saturate(mu_sun_g) * (1.0 / PI) + ms_g) * ATM_GROUND_ALBEDO * trans;

        // moonlight -> ground (no multiscat)
        vec4 trans_moon_g = SampleTransmittance(utex_tslut, r_g, r2_g, -mu_sun_g);
        ground_moon_radiance = trans_moon_g * ATM_GROUND_ALBEDO * (1.0 / PI) * trans * Saturate(-mu_sun_g);
    }

    return ATM_SOLAR   * (phase_rayleigh * acc_ray + phase_mie * acc_mie + acc_x + ground_sun_radiance)
         + ATM_MOON_IRR * (phase_rayleigh * acc_ray_moon + phase_mie_moon * acc_mie_moon + ground_moon_radiance);
}

// ===============================================================
// GetAmbientColor - sky ambient light (linear HDR, no tonemap), converted
// with the sky's solar->D65 white-balanced pair so ambient stays consistent
// with the sky LUT it is derived from.
// ===============================================================

vec3 GetAmbientColor(vec3 camera_pos, vec3 sun_dir) {
    float r = length(camera_pos);
    float mu = dot(camera_pos, sun_dir) / r;
    float h = r - ATM_PLANET_R;
    vec4 ss = GetScattering(h);
    vec4 ms = SampleMultiScatter(utex_mslut, r, mu);
    return Rec2020ToSRGB(SpectralToLinearRec2020(ss * ms * ATM_SOLAR)) * ATM_EXPOSURE;
}


#endif // LIB_ATMOSPHERE_SKY_RADIANCE_GLSL
