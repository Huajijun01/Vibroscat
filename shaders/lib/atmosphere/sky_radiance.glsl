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
    // The terminator serves only as a march bound: with the dip on, the
    // below-surface shell is out of sight and the ground's own reflected
    // radiance is not evaluated. Without the dip the terminator is the
    // surface itself, and the ray ends on Lambertian ground whose reflected
    // radiance the tail of this function adds.
    float max_dist = t1;
    bool ground_hit = false;
    {
        float ground_radius = ATM_PLANET_R;
#ifdef ATM_HORIZON_DIP
        ground_radius = max(ATM_PLANET_R - ATM_HORIZON_DIP_SCALE, 1.0);
#endif
        float t_entry;
        float t_discard;  // far root: unread, only the near one bounds the march
        if (RayIntersectSphere(camera_pos, view_dir, ground_radius, t_entry, t_discard) && t_entry > 0.0) {
            max_dist = t_entry;
            ground_hit = true;
        }
    }
    if (max_dist <= 0.0) return vec4(0.0);

    // -- phase (loop-invariant) --
    float cos_vs = dot(view_dir, sun_dir);
    // Precondition: the only caller passes AtmosphereCameraPosition() and the
    // LUT sun direction, so this dot is r * sun.y on the CPU.
    float phase_rayleigh   = PhaseRayleigh(cos_vs);
    float phase_mie   = AtmMiePhase(cos_vs);
    float phase_mie_moon = AtmMiePhase(-cos_vs);  // moon=-sun, Rayleigh is even

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
        // Out-of-range u means the light direction is occluded by the planet
        // from this point: the LUT only stores chords that clear the horizon.
        // A raw clamp-to-edge fetch would read the mu = -1 corner cell and
        // light below-horizon air at night, so apply the same contract as
        // SampleTransmittance().
        vec4 trans_mid = tslut_uv.x <= 1.0 ? textureLod(utex_tslut, tslut_uv, 0.0) : vec4(0.0);
        vec4 ms_mid = SampleMultiScatter(utex_mslut, r_mid, mu_mid);
        // moonlight: opposite direction, shared extinction
        vec4 ts_moon_mid = tslut_uv_moon.x <= 1.0 ? textureLod(utex_tslut, tslut_uv_moon, 0.0) : vec4(0.0);

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

    // -- Lambert ground reflection (no-dip only) --
    // Without the dip the terminator is the surface itself, so a ray that
    // ended there adds the ground's reflected radiance through the
    // accumulated camera-to-ground transmittance. This reproduces the bake's
    // ground feedback - direct sun on a horizontal surface plus the ambient
    // field, times albedo / PI - with the MS LUT's isotropic ambient standing
    // in for the bake's cosine-weighted directional field (its radiance times
    // PI is the ambient irradiance). The moon contributes direct light only:
    // the bake carries no moon field, matching the moon-free multiscatter of
    // this march.
    vec4 radiance = ATM_SOLAR   * (phase_rayleigh * acc_ray + phase_mie * acc_mie + acc_x)
         + ATM_MOON_IRR * (phase_rayleigh * acc_ray_moon + phase_mie_moon * acc_mie_moon);
#ifndef ATM_HORIZON_DIP
    if (ground_hit) {
        // Same sun-cosine form as the march's mu_mid, evaluated at the end
        // of the ray on the surface sphere.
        float ground_mu = (u_cam_sun_dot + max_dist * cos_vs) / ATM_PLANET_R;
        vec4 sun_trans = SampleTransmittance(utex_tslut, ATM_PLANET_R, ATM_PLANET_R2, ground_mu);
        vec4 ground_irradiance = ATM_SOLAR * sun_trans * max(ground_mu, 0.0);
        vec4 ambient_radiance = ATM_SOLAR * SampleMultiScatter(utex_mslut, ATM_PLANET_R, ground_mu);
        vec4 moon_trans = SampleTransmittance(utex_tslut, ATM_PLANET_R, ATM_PLANET_R2, -ground_mu);
        ground_irradiance += ATM_MOON_IRR * moon_trans * max(-ground_mu, 0.0);
        radiance += trans * ((ATM_GROUND_ALBEDO / PI) * ground_irradiance + ATM_GROUND_ALBEDO * ambient_radiance);
    }
#endif
    return radiance;
}

#endif // LIB_ATMOSPHERE_SKY_RADIANCE_GLSL
