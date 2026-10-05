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
// Folded scene-boundary conversions
// ===============================================================

// The 4x3 CMF rows, the Rec.2020 -> sRGB rows, the illuminant and the scene
// exposure collapse into three constant dot-product rows per illuminant.
// Reassociated from exposure * (Rec2020 -> sRGB) * Rec2020 rows for the
// 450/510/580/650 nm quadrature; the chain was validated against the
// previous 410/480/560/630 constants (research/sky-tracer/scripts/
// pack_glsl_constants.py).
vec3 SpectralRadianceToSRGB(vec4 x) {
    return vec3(dot(x, vec4(0.020110596, -0.143679932, 0.245733663, 0.139913872)),
        dot(x, vec4(-0.0412693955, 0.167519823, 0.0970612317, -0.0133161424)),
        dot(x, vec4(0.22385776, 0.0236539561, -0.00706659723, -0.00149277458)));
}

vec3 SpectralSolarToSRGB(vec4 x) {
    return vec3(dot(x, vec4(0.808789372, -5.53335094, 9.12550068, 4.38701487)),
        dot(x, vec4(-1.65973449, 6.45146465, 3.60444045, -0.417529106)),
        dot(x, vec4(9.00290489, 0.910952926, -0.262423307, -0.0468061119)));
}

vec3 SpectralMoonIrradianceToSRGB(vec4 x) {
    return vec3(dot(x, vec4(0.0319162197, -0.157458127, 0.324455798, 0.0350883938)),
        dot(x, vec4(-0.0654959828, 0.183584154, 0.128155336, -0.00333949784)),
        dot(x, vec4(0.355270118, 0.0259222556, -0.00933042075, -0.0003743665)));
}

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
    float ground_radius = ATM_PLANET_R;
    {
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
    float cam_dot_sun = dot(camera_pos, sun_dir);
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
        // with the LUTs: sr/sm/so are the scattering components, se the Mie
        // extinction (scattering + absorption), sigma_t the total, ss the
        // scattering sum; rs/ms_raw fold in the transmittance,
        // ms is the multi-scatter LUT sample, xs their product.
        vec4 sr_mid = GetSigmaSRay(h_mid);
        vec4 sm_mid = GetSigmaSMie(h_mid);
        vec4 se_mid = GetSigmaEMie(h_mid);
        vec4 so_mid = GetSigmaAOzone(h_mid);
        vec4 sigma_t_mid = sr_mid + se_mid + so_mid;
        vec4 ss_mid = sr_mid + sm_mid;

        // dot(camera_pos + view_dir*t, sun) splits into two loop-invariant
        // dots plus one scalar FMA; the real-number value is identical.
        float mu_mid = (cam_dot_sun + t_mid * cos_vs) / r_mid;
        // Both horizon UVs share one rho/discriminant sqrt; the two tslut
        // fetches stay separated by the mslut fetch on purpose (see the
        // mirrored-mu driver merge note in cirrus.glsl).
        vec2 tslut_uv;
        vec2 tslut_uv_moon;
        GetTransmittanceLUTUVPair(r_lut, r2_lut, mu_mid, tslut_uv, tslut_uv_moon);
        vec4 trans_mid = textureLod(utex_tslut, tslut_uv, 0.0);
        vec4 ms_mid = SampleMultiScatter(utex_mslut, r_lut, mu_mid);
        // moonlight: opposite direction, shared extinction
        vec4 ts_moon_mid = textureLod(utex_tslut, tslut_uv_moon, 0.0);

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
        // ground_pos lies on the ground_radius sphere from the dip block.
        float mu_sun_g = dot(ground_pos, sun_dir) / ground_radius;

        // sunlight -> ground; the paired UV helper shares the rho and
        // discriminant sqrt between the sun and the mirrored moon direction
        // (each output bit-identical to GetTransmittanceLUTUV).
        vec2 uv_sun_g;
        vec2 uv_moon_g;
        GetTransmittanceLUTUVPair(r_g, r2_g, mu_sun_g, uv_sun_g, uv_moon_g);
        vec4 trans_sun_g = textureLod(utex_tslut, uv_sun_g, 0.0);
        vec4 ms_g = SampleMultiScatter(utex_mslut, r_g, mu_sun_g);
        ground_sun_radiance = (trans_sun_g * Saturate(mu_sun_g) * (1.0 / PI) + ms_g) * ATM_GROUND_ALBEDO * trans;

        // moonlight -> ground (no multiscat)
        vec4 trans_moon_g = textureLod(utex_tslut, uv_moon_g, 0.0);
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

vec3 GetAmbientColorAt(float r, float mu) {
    vec4 ss = GetScattering(r - ATM_PLANET_R);
    vec4 ms = SampleMultiScatter(utex_mslut, r, mu);
    return SpectralSolarToSRGB(ss * ms);
}

vec3 GetAmbientColor(vec3 camera_pos, vec3 sun_dir) {
    float r = length(camera_pos);
    float mu = dot(camera_pos, sun_dir) / r;
    return GetAmbientColorAt(r, mu);
}


#endif // LIB_ATMOSPHERE_SKY_RADIANCE_GLSL
