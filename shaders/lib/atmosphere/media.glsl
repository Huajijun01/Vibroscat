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

// Aerosol absorption (km^-1 per g/m3), folded from OPAC species data. Same
// fold as ATM_SM_A/ATM_SM_B above: base density plus the smoothstep-weighted
// background step.
const float ATM_WASO_ABS_0 = 87.64557617;
const float ATM_WASO_ABS_1 = 74.40373230;
const float ATM_WASO_ABS_2 = 71.74945068;
const float ATM_WASO_ABS_3 = 67.95589447;
const float ATM_INSO_ABS_0 = 70.23886871;
const float ATM_INSO_ABS_1 = 67.22508240;
const float ATM_INSO_ABS_2 = 63.19934082;
const float ATM_INSO_ABS_3 = 59.32960892;
const float ATM_SOOT_ABS_0 = 10068.87792969;
const float ATM_SOOT_ABS_1 = 8693.68359375;
const float ATM_SOOT_ABS_2 = 7045.56591797;
const float ATM_SOOT_ABS_3 = 5828.49169922;
const vec4 ATM_AA_A = vec4(
    ATM_WASO_BASE * ATM_WASO_ABS_0 + ATM_INSO_BASE * ATM_INSO_ABS_0 + ATM_SOOT_BASE * ATM_SOOT_ABS_0,
    ATM_WASO_BASE * ATM_WASO_ABS_1 + ATM_INSO_BASE * ATM_INSO_ABS_1 + ATM_SOOT_BASE * ATM_SOOT_ABS_1,
    ATM_WASO_BASE * ATM_WASO_ABS_2 + ATM_INSO_BASE * ATM_INSO_ABS_2 + ATM_SOOT_BASE * ATM_SOOT_ABS_2,
    ATM_WASO_BASE * ATM_WASO_ABS_3 + ATM_INSO_BASE * ATM_INSO_ABS_3 + ATM_SOOT_BASE * ATM_SOOT_ABS_3);
const vec4 ATM_AA_B = vec4(
    (ATM_WASO_BG - ATM_WASO_BASE) * ATM_WASO_ABS_0 + (ATM_INSO_BG - ATM_INSO_BASE) * ATM_INSO_ABS_0 + (ATM_SOOT_BG - ATM_SOOT_BASE) * ATM_SOOT_ABS_0,
    (ATM_WASO_BG - ATM_WASO_BASE) * ATM_WASO_ABS_1 + (ATM_INSO_BG - ATM_INSO_BASE) * ATM_INSO_ABS_1 + (ATM_SOOT_BG - ATM_SOOT_BASE) * ATM_SOOT_ABS_1,
    (ATM_WASO_BG - ATM_WASO_BASE) * ATM_WASO_ABS_2 + (ATM_INSO_BG - ATM_INSO_BASE) * ATM_INSO_ABS_2 + (ATM_SOOT_BG - ATM_SOOT_BASE) * ATM_SOOT_ABS_2,
    (ATM_WASO_BG - ATM_WASO_BASE) * ATM_WASO_ABS_3 + (ATM_INSO_BG - ATM_INSO_BASE) * ATM_INSO_ABS_3 + (ATM_SOOT_BG - ATM_SOOT_BASE) * ATM_SOOT_ABS_3);

// -- Mie extinction (compile-time fold of the scattering and absorption
//    pairs above): scattering and absorption ride the same vertical profile,
//    so summing the coefficients lets the aerosol extinction term cost one
//    exp, one smoothstep, and one FMA chain per evaluation. --
const vec4 ATM_EM_A = ATM_SM_A + ATM_AA_A;
const vec4 ATM_EM_B = ATM_SM_B + ATM_AA_B;

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

// Aerosol vertical profile shared by the Mie folds: an exponential falloff
// (8 km scale height) whose sea-level base blends into the background term
// across the low-atmosphere window. base/background pair with the ATM_*_A /
// ATM_*_B constants above; the scattering and extinction folds differ only
// in the coefficient pair they run through this one profile.
vec4 AeroSigma(float h, vec4 base, vec4 background) {
    float t = smoothstep(ATM_AERO_SMOOTH_LO, ATM_AERO_SMOOTH_HI, h);
    return exp(-h / ATM_AERO_SCALE) * (base + t * background);
}

vec4 GetSigmaSMie(float h) {
    return AeroSigma(h, ATM_SM_A, ATM_SM_B);
}

// Total aerosol extinction (scattering + absorption) over the folded
// ATM_EM_A/B constants.
vec4 GetSigmaEMie(float h) {
    return AeroSigma(h, ATM_EM_A, ATM_EM_B);
}

vec4 GetSigmaAOzone(float h) {
    float d = DensityOzone(ATM_PLANET_R + h);
    return d * ATM_OZONE_SIGMA;
}

// Total extinction: Rayleigh + aerosol (scattering and absorption in one
// folded evaluation) + ozone absorption. GetScattering below is the
// scattering-only subset (Rayleigh + Mie) that the sky radiance integration
// uses.
vec4 GetExtinction(float h) {
    return GetSigmaSRay(h) + GetSigmaEMie(h) + GetSigmaAOzone(h);
}

vec4 GetScattering(float h) {
    return GetSigmaSRay(h) + GetSigmaSMie(h);
}

#endif // LIB_ATMOSPHERE_MEDIA_GLSL
