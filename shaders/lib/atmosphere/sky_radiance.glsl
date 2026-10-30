#ifndef LIB_ATMOSPHERE_SKY_RADIANCE_GLSL
#define LIB_ATMOSPHERE_SKY_RADIANCE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/illumination.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/transmittance.glsl"
#include "/lib/scattering/phase.glsl"

// ===============================================================
// Sky Integration  (midpoint + analytic, vec4 spectral)
// ===============================================================

const float ATM_NUM_STEPS = 32.0;

// Uses this frame's pinned atmosphere camera and LUT-aligned sun direction.
vec4 ComputeSkyRadiance(vec3 view_dir) {
    vec3 camera_pos = AtmosphereCameraPosition();
    vec3 sun_dir = u_sky_lut_sun_dir;
    // -- sphere intersection --
    float t0, t1;
    if (!RayIntersectSphere(camera_pos, view_dir, ATM_ATMO_R, t0, t1)) return vec4(0.0);

    // Horizon below-dip: a below-horizon ray terminates on a sphere placed
    // ATM_HORIZON_DIP_SCALE km beneath the planet surface instead of on the
    // surface itself, so it integrates a little of the exponentially denser
    // low-altitude Mie/aerosol air and the horizon reads thicker/hazier.
    // The terminator serves only as a march bound: the ground's own reflected
    // radiance is not evaluated, because the below-surface dip puts that
    // shell out of sight.
    float max_dist = t1;
    {
        float ground_radius = ATM_PLANET_R;
#ifdef ATM_HORIZON_DIP
        ground_radius = max(ATM_PLANET_R - ATM_HORIZON_DIP_SCALE, 1.0);
#endif
        float t_entry;
        float t_discard;  // far root: unread, only the near one bounds the march
        if (RayIntersectSphere(camera_pos, view_dir, ground_radius, t_entry, t_discard) && t_entry > 0.0) {
            max_dist = t_entry;
        }
    }
    if (max_dist <= 0.0) return vec4(0.0);

    // -- phase (loop-invariant) --
    float cos_vs = dot(view_dir, sun_dir);
    // Precondition: the only caller passes AtmosphereCameraPosition() and the
    // LUT sun direction, so this dot is r * sun.y on the CPU.
    float phase_rayleigh   = PhaseRayleigh(cos_vs);
    float phase_mie   = PhaseHenyeyGreensteinTripleLobe(cos_vs, ATM_MIE_PHASE);
    float phase_mie_moon = PhaseHenyeyGreensteinTripleLobe(-cos_vs, ATM_MIE_PHASE);  // moon=-sun, Rayleigh is even

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

        // Density radius: the media functions take the real signed radius and
        // fold altitude into their fma constants, so the march never forms
        // h = r - R. The below-surface dip still thickens the horizon. Only the
        // transmittance LUT is parameterized on r >= planet radius
        // (sqrt(r^2 - R^2) is undefined below the surface); the multiscatter
        // LUT spans the baked signed range and is sampled at the real radius.
        float r_lut   = max(r_mid, ATM_PLANET_R);
        float r2_lut  = r_lut * r_lut;

        // Midpoint sigmas are 4-wave spectra (450/510/580/650 nm): sr/sm are
        // the Rayleigh/Mie scattering terms, sigma_t the total extinction, ss
        // the scattering sum; rs/ms_raw fold in the transmittance,
        // ms is the multi-scatter LUT sample, xs their product.
        AtmosphereMedia media = AtmosphereMediaAt(r_mid);

        // dot(camera_pos + view_dir*t, sun) splits into two loop-invariant
        // dots plus one scalar FMA; the real-number value is identical.
        float mu_mid = (u_cam_sun_dot + t_mid * cos_vs) / r_mid;
        // Both horizon UVs share one rho/discriminant sqrt; the two tslut
        // fetches stay separated by the mslut fetch on purpose (see the
        // mirrored-mu driver merge note in cirrus.glsl).
        vec2 tslut_uv;
        vec2 tslut_uv_moon;
        GetTransmittanceLUTUVPair(r_lut, r2_lut, mu_mid, tslut_uv, tslut_uv_moon);
        vec4 trans_mid = textureLod(utex_tslut, tslut_uv, 0.0);
        vec4 ms_mid = SampleMultiScatter(utex_mslut, r_mid, mu_mid);
        // moonlight: opposite direction, shared extinction
        vec4 ts_moon_mid = textureLod(utex_tslut, tslut_uv_moon, 0.0);

        vec4 rs_mid      = trans_mid * media.sigma_s_ray;
        vec4 ms_raw_mid  = trans_mid * media.sigma_s_mie;
        vec4 xs_mid      = media.sigma_s * ms_mid;

        vec4 rs_moon_mid = ts_moon_mid * media.sigma_s_ray;
        vec4 ms_moon_mid = ts_moon_mid * media.sigma_s_mie;

        // -- analytic integral with midpoint extinction --
        vec4 optical_depth_mid = media.sigma_t * dt_seg;
        vec4 step_trans = exp(-optical_depth_mid);
        vec4 integral  = (vec4(1.0) - step_trans) * (dt_seg / optical_depth_mid);

        vec4 w = trans * integral;
        acc_ray += w * rs_mid;
        acc_mie += w * ms_raw_mid;
        acc_x += w * xs_mid;
        acc_ray_moon += w * rs_moon_mid;
        acc_mie_moon += w * ms_moon_mid;

        trans  *= step_trans;
        t_prev  = t_cur;
    }

    return ATM_SOLAR   * (phase_rayleigh * acc_ray + phase_mie * acc_mie + acc_x)
         + ATM_MOON_IRR * (phase_rayleigh * acc_ray_moon + phase_mie_moon * acc_mie_moon);
}

#endif // LIB_ATMOSPHERE_SKY_RADIANCE_GLSL
