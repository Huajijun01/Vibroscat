#ifndef LIB_ATMOSPHERE_MEDIA_GLSL
#define LIB_ATMOSPHERE_MEDIA_GLSL

#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/scattering/phase.glsl"

// ===============================================================
// Atmosphere Sky - 4-Wave Spectral (GLSL 430 desktop)
// Optimal wavelengths: 410, 480, 560, 630 nm
// Density/phase model: Hillaire-style (licenses/THIRD_PARTY_NOTICES.md section 7),
// offline 4-wave spectral fit (HSPEAtmosCreator tool).
// Provenance: licenses/THIRD_PARTY_NOTICES.md section 15.
// ===============================================================

// ===============================================================
// Baked Constants
// ===============================================================


// -- Rayleigh density: exp(-A * h^B) --
const float ATM_RAY_EXP_A = 0.07771971;
const float ATM_RAY_EXP_B = 1.16364243;

// -- Rayleigh scattering base (km-^1 at sea level, per wavelength) --
const vec4 ATM_SIGMA_S_RAY = vec4(0.0478, 0.02545, 0.01374, 0.008576);

// -- Ozone: lognormal centred at ~25.1 km --
const float ATM_OZONE_CENTER_LOG = 3.22261;
const float ATM_OZONE_INV_VAR = 5.55555555;
const float ATM_OZONE_DENS_SCALE = 3.78547397e+20;

// -- Ozone cross-section * Dobson  (pre-merged) --
const vec4 ATM_OZONE_SIGMA = 381.0 * vec4(2.91000003e-27, 7.11000026e-26, 3.88000004e-25, 3.43e-25);

// -- Aerosol --
const float ATM_AERO_SCALE = 8.0;
const float ATM_AERO_SMOOTH_LO = 1.0;
const float ATM_AERO_SMOOTH_HI = 2.0;

// -- Aerosol base density (g/m3 at sea level, Rural) --
const float ATM_WASO_BASE = 1.48999998e-05;
const float ATM_WASO_BG   = 4.57099986e-07;
const float ATM_INSO_BASE = 1.00999996e-05;
const float ATM_INSO_BG   = 2.2910001e-06;
const float ATM_SOOT_BASE = 5.31000012e-07;
const float ATM_SOOT_BG   = 1.36200002e-08;

// -- Aerosol sigma_sca per species (km-^1 per g/m3) --
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

// -- Mie combined (compile-time folded from per-species data) --
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

// -- Solar irradiance (W/m2/nm at TOA) --
const vec4 ATM_SOLAR = vec4(1.74769998, 2.05660009, 1.85350001, 1.65419996);

// -- Phase --
// Triple-lobe Mie blend, same structure as the tuned cirrus phase
// (shaders/lib/cloud/cirrus.glsl): a narrow high-g forward peak keeps the
// silver lining, a broad low-g forward lobe adds smooth haze, and a
// backward lobe (effective eccentricity -0.3) brightens the anti-solar sky.
// Weights sum to 1, so the blend stays a normalized phase. Formulas live in
// /lib/scattering/phase.glsl.
const HenyeyGreensteinTripleLobe ATM_MIE_PHASE = HenyeyGreensteinTripleLobe(
    0.8, 0.1,  // forward peak
    0.5, 0.7,  // forward mid
    0.3, 0.2); // backward

// -- Display --
const float ATM_EXPOSURE = 0.05;  // from the 4-wave offline fit

// -- Integration --
const float ATM_NUM_STEPS = 128.0;
const vec4 ATM_EPS = vec4(1.0e-5);

// -- Ground albedo (Lambertian) --
const float ATM_GROUND_ALBEDO_BAKE = 0.25;  // used when baking LUTs
const float ATM_GROUND_ALBEDO      = 0.05;  // runtime, tweak independently

// -- Moonlight irradiance (W/m2/nm) --
// Re-tinted through the 4-wave CMF matrix: Rec.2020 reads ~= (0.88, 0.95, 1.18)
// vs neutral - cooler moonlight.
const vec4 ATM_MOON_IRR = vec4(0.1522710, 0.2695135, 0.1635034, 0.1553021) * 0.6;

// ===============================================================
// Density functions  (Hillaire / the pack's 4-wave spectral fit model)
// ===============================================================

float DensityRay(float r) {
    float h = max(r - ATM_PLANET_R, 0.0);
    return exp(-ATM_RAY_EXP_A * pow(h, ATM_RAY_EXP_B));
}

float DensityOzone(float r) {
    float h = max(r - ATM_PLANET_R, 1.0e-5);
    float t = log(h) - ATM_OZONE_CENTER_LOG;
    return ATM_OZONE_DENS_SCALE * (1.0 / h) * exp(-t * t * ATM_OZONE_INV_VAR);
}

// ===============================================================
// Scattering & extinction per wavelength  (vec4 = [410,480,560,630])
// ===============================================================

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

vec4 GetScattering(float h) {
    return GetSigmaSRay(h) + GetSigmaSMie(h);
}

#endif // LIB_ATMOSPHERE_MEDIA_GLSL
