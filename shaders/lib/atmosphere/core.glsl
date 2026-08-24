// ═══════════════════════════════════════════════════════════════
// Atmosphere Sky — 4-Wave Spectral (GLSL 430 desktop)
// Optimal wavelengths: 410, 480, 560, 630 nm
// Density/phase model: Hillaire-style (licenses/THIRD_PARTY_NOTICES.md section 7),
// offline 4-wave spectral fit (HSPEAtmosCreator tool).
// Provenance: licenses/THIRD_PARTY_NOTICES.md section 15.
// ═══════════════════════════════════════════════════════════════

// ── Custom Texture bindings (registered in shaders.properties) ──
#ifndef LIB_ATMOSPHERE_CORE_GLSL
#define LIB_ATMOSPHERE_CORE_GLSL


#define TRANSMITTANCE_LUT utex_tslut
#define MULTISCATTER_LUT utex_mslut

#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"

// MS LUT: raw 4-wave radiance in RGBA16F (32x32), no per-channel
// normalization — sampled values are absolute spectral radiance.

#include "/lib/atmosphere/atmosphere_geometry.glsl"

// ═══════════════════════════════════════════════════════════════
// Baked Constants
// ═══════════════════════════════════════════════════════════════

// ── Geometry ──
const float ATM_H = sqrt(ATM_ATMO_R2 - ATM_PLANET_R2);
const float ATM_ATMO_MINUS_P = ATM_ATMO_R - ATM_PLANET_R;
const float ATM_RCP_ATMO_MINUS_P = 1.0 / ATM_ATMO_MINUS_P;

// ── Rayleigh density: exp(-A * h^B) ──
const float ATM_RAY_EXP_A = 0.07771971;
const float ATM_RAY_EXP_B = 1.16364243;

// ── Rayleigh scattering base (km⁻¹ at sea level, per wavelength) ──
const vec4 ATM_SIGMA_S_RAY = vec4(0.0478, 0.02545, 0.01374, 0.008576);

// ── Ozone: lognormal centred at ~25.1 km ──
const float ATM_OZONE_CENTER_LOG = 3.22261;
const float ATM_OZONE_INV_VAR = 5.55555555;
const float ATM_OZONE_DENS_SCALE = 3.78547397e+20;

// ── Ozone cross-section * Dobson  (pre-merged) ──
const vec4 ATM_OZONE_SIGMA = 381.0 * vec4(2.91000003e-27, 7.11000026e-26, 3.88000004e-25, 3.43e-25);

// ── Aerosol ──
const float ATM_AERO_SCALE = 8.0;
const float ATM_AERO_SMOOTH_LO = 1.0;
const float ATM_AERO_SMOOTH_HI = 2.0;

// ── Aerosol base density (g/m³ at sea level, Rural) ──
const float ATM_WASO_BASE = 1.48999998e-05;
const float ATM_WASO_BG   = 4.57099986e-07;
const float ATM_INSO_BASE = 1.00999996e-05;
const float ATM_INSO_BG   = 2.2910001e-06;
const float ATM_SOOT_BASE = 5.31000012e-07;
const float ATM_SOOT_BG   = 1.36200002e-08;

// ── Aerosol sigma_sca per species (km⁻¹ per g/m³) ──
const float ATM_WASO_SCA_0 = 4612.52978516;
const float ATM_WASO_SCA_1 = 3786.26000977;
const float ATM_WASO_SCA_2 = 3034.39990234;
const float ATM_WASO_SCA_3 = 2533.01000977;
const float ATM_INSO_SCA_0 = 160.83000183;
const float ATM_INSO_SCA_1 = 167.19000244;
const float ATM_INSO_SCA_2 = 173.88000488;
const float ATM_INSO_SCA_3 = 179.25999451;
const float ATM_SOOT_SCA_0 = 3680.42993164;
const float ATM_SOOT_SCA_1 = 2652.76000977;
const float ATM_SOOT_SCA_2 = 1860.20996094;
const float ATM_SOOT_SCA_3 = 1397.32995605;

// ── Mie combined (compile-time folded from per-species data) ──
// GetSigmaSMie(h) = exp(-h/AERO_SCALE) * (SM_A + smoothstep(lo,hi,h) * SM_B)
const vec4 ATM_SM_A = vec4(
    ATM_WASO_BASE * ATM_WASO_SCA_0 + ATM_INSO_BASE * ATM_INSO_SCA_0 + ATM_SOOT_BASE * ATM_SOOT_SCA_0,
    ATM_WASO_BASE * ATM_WASO_SCA_1 + ATM_INSO_BASE * ATM_INSO_SCA_1 + ATM_SOOT_BASE * ATM_SOOT_SCA_1,
    ATM_WASO_BASE * ATM_WASO_SCA_2 + ATM_INSO_BASE * ATM_INSO_SCA_2 + ATM_SOOT_BASE * ATM_SOOT_SCA_2,
    ATM_WASO_BASE * ATM_WASO_SCA_3 + ATM_INSO_BASE * ATM_INSO_SCA_3 + ATM_SOOT_BASE * ATM_SOOT_SCA_3);
const vec4 ATM_SM_B = vec4(
    (ATM_WASO_BG - ATM_WASO_BASE) * ATM_WASO_SCA_0 + (ATM_INSO_BG - ATM_INSO_BASE) * ATM_INSO_SCA_0 + (ATM_SOOT_BG - ATM_SOOT_BASE) * ATM_SOOT_SCA_0,
    (ATM_WASO_BG - ATM_WASO_BASE) * ATM_WASO_SCA_1 + (ATM_INSO_BG - ATM_INSO_BASE) * ATM_INSO_SCA_1 + (ATM_SOOT_BG - ATM_SOOT_BASE) * ATM_SOOT_SCA_1,
    (ATM_WASO_BG - ATM_WASO_BASE) * ATM_WASO_SCA_2 + (ATM_INSO_BG - ATM_INSO_BASE) * ATM_INSO_SCA_2 + (ATM_SOOT_BG - ATM_SOOT_BASE) * ATM_SOOT_SCA_2,
    (ATM_WASO_BG - ATM_WASO_BASE) * ATM_WASO_SCA_3 + (ATM_INSO_BG - ATM_INSO_BASE) * ATM_INSO_SCA_3 + (ATM_SOOT_BG - ATM_SOOT_BASE) * ATM_SOOT_SCA_3
);

// ── Solar irradiance (W/m²/nm at TOA) ──
const vec4 ATM_SOLAR = vec4(1.74769998, 2.05660009, 1.85350001, 1.65419996);

// ── Phase ──
const float ATM_G = 0.7;
const float ATM_G2 = ATM_G * ATM_G;
const float ATM_MIE_K1 = ATM_G2 + 1.0;
const float ATM_MIE_K2 = -2.0 * ATM_G;
const float ATM_PHASE_RAY_SCALE = 0.0596831;
const float ATM_PHASE_MIE_K = 0.0244485;

// ── Display ──
const float ATM_EXPOSURE = 0.05;  // from the 4-wave offline fit

// ── Integration ──
const float ATM_NUM_STEPS = 128.0;
const vec4 ATM_EPS = vec4(1.0e-5);

// ── Ground albedo (Lambertian) ──
const float ATM_GROUND_ALBEDO_BAKE = 0.25;  // used when baking LUTs
const float ATM_GROUND_ALBEDO      = 0.01;  // runtime, tweak independently

// ── Moonlight irradiance (W/m²/nm) ──
// Re-tinted through the 4-wave CMF matrix: Rec.2020 reads ≈ (0.88, 0.95, 1.18)
// vs neutral — cooler moonlight.
const vec4 ATM_MOON_IRR = vec4(0.1522710, 0.2695135, 0.1635034, 0.1553021) * 0.6;

// ═══════════════════════════════════════════════════════════════
// Density functions  (Hillaire / the pack's 4-wave spectral fit model)
// ═══════════════════════════════════════════════════════════════

float DensityRay(float r) {
    float h = max(r - ATM_PLANET_R, 0.0);
    return exp(-ATM_RAY_EXP_A * pow(h, ATM_RAY_EXP_B));
}

float DensityOzone(float r) {
    float h = max(r - ATM_PLANET_R, 1.0e-5);
    float t = log(h) - ATM_OZONE_CENTER_LOG;
    return ATM_OZONE_DENS_SCALE * (1.0 / h) * exp(-t * t * ATM_OZONE_INV_VAR);
}

// ═══════════════════════════════════════════════════════════════
// Scattering & extinction per wavelength  (vec4 = [410,480,560,630])
// ═══════════════════════════════════════════════════════════════

vec4 GetSigmaSRay(float h) {
    float d = DensityRay(ATM_PLANET_R + h);
    return d * ATM_SIGMA_S_RAY;
}

vec4 GetSigmaSMie(float h) {
    float t = smoothstep(ATM_AERO_SMOOTH_LO, ATM_AERO_SMOOTH_HI, h);
    return exp(-h / ATM_AERO_SCALE) * (ATM_SM_A + t * ATM_SM_B);
}

vec4 GetSigmaAOzone(float h) {
    float d = DensityOzone(ATM_PLANET_R + h);
    return d * ATM_OZONE_SIGMA;
}

vec4 GetExtinction(float h) {
    return GetSigmaSRay(h) + GetSigmaSMie(h) + GetSigmaAOzone(h);
}

vec4 GetScattering(float h) {
    return GetSigmaSRay(h) + GetSigmaSMie(h);
}

// ═══════════════════════════════════════════════════════════════
// Geometry
// ═══════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════
// LUT UV mapping
// ═══════════════════════════════════════════════════════════════

vec2 GetTransmittanceLUTUV(float r, float r2, float mu) {
    float rho = sqrt(r2 - ATM_PLANET_R2);
    float disc = r2 * (mu * mu - 1.0) + ATM_ATMO_R2;
    float d = max(0.0, (-r * mu + sqrt(max(disc, 0.0))));
    float d_min = ATM_ATMO_R - r;
    float d_max = rho + ATM_H;
    float x_mu = (d - d_min) / max(d_max - d_min, 1.0e-5);
    float x_r  = rho / max(ATM_H, 1.0e-5);
    x_mu = x_mu * x_mu;  // square remap → more resolution near horizon
    return vec2(x_mu, x_r);
}

vec2 GetMultiScatterLUTUV(float r, float mu) {
    return vec2(mu * 0.5 + 0.5, (r - ATM_PLANET_R) * ATM_RCP_ATMO_MINUS_P);
}

// ═══════════════════════════════════════════════════════════════
// LUT Sampling
// ═══════════════════════════════════════════════════════════════

vec4 SampleTransmittance(sampler2D lut_tex, float r, float r2, float mu) {
    vec2 uv = GetTransmittanceLUTUV(r, r2, mu);
    return textureLod(lut_tex, uv, 0.0);
}

vec4 SampleMultiScatter(sampler2D lut_tex, float r, float mu) {
    return textureLod(lut_tex, GetMultiScatterLUTUV(r, mu), 0.0);
}

// ═══════════════════════════════════════════════════════════════
// Phase functions  (Cornette-Shanks for Mie, matched to the pack's 4-wave spectral fit)
// ═══════════════════════════════════════════════════════════════

float PhaseRayleigh(float cos_theta) {
    return (cos_theta * cos_theta + 1.0) * ATM_PHASE_RAY_SCALE;
}

float PhaseMieHG(float cos_theta, float eccentricity) {
    float eccentricity2 = eccentricity * eccentricity;
    float denominator = max(1.0 + eccentricity2 - 2.0 * eccentricity * cos_theta, 1.0e-4);
    return (1.0 / (4.0 * PI)) * (1.0 - eccentricity2) / (denominator * sqrt(denominator));
}

// Cornette-Shanks phase (normalized single-lobe; g=0 reduces to Rayleigh).
// Used by the water fog: positive g biases scattering toward the forward
// (sun) direction.
float PhaseCornetteShanks(float cos_theta, float eccentricity) {
    float p = 1.0 + eccentricity * eccentricity - 2.0 * eccentricity * cos_theta;
    return (3.0 / (8.0 * PI)) * ((1.0 - eccentricity * eccentricity) * (1.0 + cos_theta * cos_theta)) / ((2.0 + eccentricity * eccentricity) * p * sqrt(p));
}

// ═══════════════════════════════════════════════════════════════
// Spectral → linear sRGB  (4×3 manually expanded, FMA-friendly)
// ═══════════════════════════════════════════════════════════════

vec3 SpectralToLinearSRGB(vec4 L) {
    return vec3(dot(L, vec4(6.321843624, -26.517091751, 30.142539978, 118.707962036)),
        dot(L, vec4(-5.534153461, 17.321765900, 98.470054626, -8.898775101)),
        dot(L, vec4(39.173206329, 71.765632629, -12.650737762, -1.295249343)));
}

// ═══════════════════════════════════════════════════════════════
// Spectral → linear Rec.2020  (4×3, solar-white-balanced to D65)
//
// Linear Rec.2020 working space (smaller CMF negative weights); columns
// pre-multiplied by a Bradford solar-white→D65 adaptation. Convert back
// with Rec2020ToSRGB() at the scene boundary.
// ═══════════════════════════════════════════════════════════════

vec3 SpectralToLinearRec2020(vec4 L) {
    return vec3(dot(L, vec4(3.845798926, -7.86893214, 48.567284779, 70.210607852)),
        dot(L, vec4(-4.264385887, 15.066919918, 93.470569559, -0.049300629)),
        dot(L, vec4(35.719363513, 67.276565483, -2.226660272, 0.023773354)));
}

vec3 Rec2020ToSRGB(vec3 rgb) {
    // GLSL mat3 is column-major: pass columns of the row-major matrix.
    return mat3(1.660226750, -0.124553300, -0.018155170,
                -0.587547610, 1.132926080, -0.100603050,
                -0.072838260, -0.008349570, 1.118998170) * rgb;
}

// Spectral transmittance → linear sRGB, normalized so T = 1 maps to white
// under the incident light spectrum; pass equal-energy for unknown light.
vec3 TransmittanceToLinearSRGB(vec4 t, vec4 light) {
    vec4 safe_light = max(light, vec4(1.0e-4));
    vec3 white = SpectralToLinearSRGB(safe_light);
    return clamp(SpectralToLinearSRGB(clamp(t, vec4(0.0), vec4(1.0)) * safe_light)
        / max(white, vec3(1.0e-4)), vec3(0.0), vec3(1.0));
}

// Rec.2020 variant; convert back with Rec2020ToSRGB at the scene boundary.
vec3 TransmittanceToLinearRec2020(vec4 t, vec4 light) {
    vec4 safe_light = max(light, vec4(1.0e-4));
    vec3 white = SpectralToLinearRec2020(safe_light);
    return clamp(SpectralToLinearRec2020(clamp(t, vec4(0.0), vec4(1.0)) * safe_light)
        / max(white, vec3(1.0e-4)), vec3(0.0), vec3(1.0));
}

// ═══════════════════════════════════════════════════════════════
// Sky Integration  (midpoint + analytic, vec4 spectral)
// ═══════════════════════════════════════════════════════════════

vec4 ComputeSkyRadiance(vec3 camera_pos, vec3 view_dir, vec3 sun_dir
) {
    // ── sphere intersection ──
    float t0, t1;
    if (!RayIntersectSphere(camera_pos, view_dir, ATM_ATMO_R, t0, t1)) return vec4(0.0);

    float max_dist = t1;
    float t_ground = -1.0;  // negative = no ground hit
    {  float te0, te1;
        if (RayIntersectSphere(camera_pos, view_dir, ATM_PLANET_R, te0, te1) && te0 > 0.0) {
            max_dist = te0;
            t_ground = te0;
        }
    }
    if (max_dist <= 0.0) return vec4(0.0);

    // ── phase (loop-invariant) ──
    float cos_vs = dot(view_dir, sun_dir);
    float pr   = PhaseRayleigh(cos_vs);
    float pm   = PhaseMieHG(cos_vs, 0.76);
    float pm_moon = PhaseMieHG(-cos_vs, 0.76);  // moon=-sun, Rayleigh is even

    float dt      = max_dist / ATM_NUM_STEPS;
    vec4  trans   = vec4(1.0);

    // accumulators: sun
    vec4 acc_ray = vec4(0.0);
    vec4 acc_mie = vec4(0.0);
    vec4 acc_x = vec4(0.0); // multiscat (sun only)
    // accumulators: moon (no multiscat)
    vec4 acc_ray_moon = vec4(0.0);
    vec4 acc_mie_moon = vec4(0.0);

    // ── midpoint stepping: sample at segment centre, analytic extinction ──
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

        vec4 sr_mid = GetSigmaSRay(h_mid);
        vec4 sm_mid = GetSigmaSMie(h_mid);
        vec4 so_mid = GetSigmaAOzone(h_mid);
        vec4 sigma_t_mid = sr_mid + sm_mid + so_mid;
        vec4 ss_mid = sr_mid + sm_mid;

        float mu_mid = dot(p_mid, sun_dir) / r_mid;
        vec4 trans_mid = SampleTransmittance(TRANSMITTANCE_LUT, r_mid, r2_mid, mu_mid);
        vec4 ms_mid = SampleMultiScatter(MULTISCATTER_LUT, r_mid, mu_mid);
        // moonlight: opposite direction, shared extinction
        vec4 ts_moon_mid = SampleTransmittance(TRANSMITTANCE_LUT, r_mid, r2_mid, -mu_mid);

        vec4 rs_mid      = trans_mid * sr_mid;
        vec4 ms_raw_mid  = trans_mid * sm_mid;
        vec4 xs_mid      = ss_mid * ms_mid;

        vec4 rs_moon_mid = ts_moon_mid * sr_mid;
        vec4 ms_moon_mid = ts_moon_mid * sm_mid;

        // ── analytic integral with midpoint extinction ──
        vec4 od        = sigma_t_mid * dt_seg;
        vec4 step_trans = exp(-od);
        vec4 integral  = (vec4(1.0) - step_trans) * (dt_seg / max(od, ATM_EPS));

        vec4 w = trans * integral;
        acc_ray += w * rs_mid;
        acc_mie += w * ms_raw_mid;
        acc_x += w * xs_mid;
        acc_ray_moon += w * rs_moon_mid;
        acc_mie_moon += w * ms_moon_mid;

        trans  *= step_trans;
        t_prev  = t_cur;
    }

    // ── ground albedo (sun + moon) ──
    vec4 L_ground_sun = vec4(0.0);
    vec4 L_ground_moon = vec4(0.0);
    if (t_ground > 0.0) {
        vec3 ground_pos = camera_pos + view_dir * t_ground;
        float r_g  = ATM_PLANET_R + 0.01;
        float r2_g = r_g * r_g;
        float mu_sun_g = dot(ground_pos, sun_dir) / ATM_PLANET_R;

        // sunlight → ground
        vec4 trans_sun_g = SampleTransmittance(TRANSMITTANCE_LUT, r_g, r2_g, mu_sun_g);
        vec4 ms_g = SampleMultiScatter(MULTISCATTER_LUT, r_g, mu_sun_g);
        L_ground_sun = (trans_sun_g + ms_g) * ATM_GROUND_ALBEDO * (1.0 / PI) * trans;

        // moonlight → ground (no multiscat)
        vec4 trans_moon_g = SampleTransmittance(TRANSMITTANCE_LUT, r_g, r2_g, -mu_sun_g);
        L_ground_moon = trans_moon_g * ATM_GROUND_ALBEDO * (1.0 / PI) * trans;
    }

    return ATM_SOLAR   * (pr * acc_ray + pm * acc_mie + acc_x + L_ground_sun)
         + ATM_MOON_IRR * (pr * acc_ray_moon + pm_moon * acc_mie_moon + L_ground_moon);
}

// ═══════════════════════════════════════════════════════════════
// SkyViewLookup — 4-wave spectral → ACES tonemapped sRGB
// ═══════════════════════════════════════════════════════════════

vec3 SkyViewLookup(vec3 camera_pos, vec3 view_dir, vec3 sun_dir) {
    vec4 L_spec = ComputeSkyRadiance(camera_pos, view_dir, sun_dir);
    vec3 L = max(Rec2020ToSRGB(SpectralToLinearRec2020(L_spec)), vec3(0.0));
    L *= ATM_EXPOSURE;
    L = (L * (2.51 * L + 0.03)) / (L * (2.43 * L + 0.59) + 0.14);
    return pow(clamp(L, 0.0, 1.0), vec3(0.45454545));
}

// ═══════════════════════════════════════════════════════════════
// GetAmbientColor — sky ambient light (linear HDR, no tonemap)
// ═══════════════════════════════════════════════════════════════

vec3 GetAmbientColor(vec3 camera_pos, vec3 sun_dir) {
    float r = length(camera_pos);
    float mu = dot(camera_pos, sun_dir) / r;
    float h = r - ATM_PLANET_R;
    vec4 ss = GetScattering(h);
    vec4 ms = SampleMultiScatter(MULTISCATTER_LUT, r, mu);
    return SpectralToLinearSRGB(ss * ms * ATM_SOLAR) * ATM_EXPOSURE;
}

#endif
