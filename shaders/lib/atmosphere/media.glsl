#ifndef LIB_ATMOSPHERE_MEDIA_GLSL
#define LIB_ATMOSPHERE_MEDIA_GLSL

#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/scattering/phase.glsl"

// ===============================================================
// Atmosphere Sky - 4-Wave Spectral (GLSL 430 desktop)
// Wavelengths: 450, 510, 580, 650 nm (sky-tracer realtime bands)
// Density/phase model: Hillaire-style (licenses/THIRD_PARTY_NOTICES.md section 6),
// fitted closed-form profiles kept from the 410-630 nm constants; only the
// per-band coefficients follow sky-tracer's OPAC/libRadtran tables. The
// offline iterative-MS LUT bake (sky-baker pack) evaluates these same forms.
// Provenance: licenses/THIRD_PARTY_NOTICES.md section 14.
// ===============================================================

// ===============================================================
// Baked Constants
// ===============================================================


// -- Rayleigh density: exp(-A * h^B) --
const float ATM_RAY_EXP_A = 0.07771971;
const float ATM_RAY_EXP_B = 1.16364243;

// -- Rayleigh scattering base (km-^1 at sea level, per wavelength) --
const vec4 ATM_SIGMA_S_RAY = vec4(0.03295005, 0.01997218, 0.01193972, 0.00756925);

// -- Ozone: lognormal centred at ~25.1 km --
const float ATM_OZONE_CENTER_LOG = 3.22261;
const float ATM_OZONE_INV_VAR = 5.55555555;
const float ATM_OZONE_DENS_SCALE = 3.78547397e+20;

// -- Ozone cross-section * Dobson  (pre-merged) --
const vec4 ATM_OZONE_SIGMA = 381.0 * vec4(1.70999998e-26, 1.57999997e-25, 4.55000008e-25, 2.41999995e-25);

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
const float ATM_WASO_SCA_0 = 4107.27099609;
const float ATM_WASO_SCA_1 = 3479.43579102;
const float ATM_WASO_SCA_2 = 2884.22949219;
const float ATM_WASO_SCA_3 = 2399.55371094;
const float ATM_INSO_SCA_0 = 164.56538391;
const float ATM_INSO_SCA_1 = 169.77780151;
const float ATM_INSO_SCA_2 = 175.44073486;
const float ATM_INSO_SCA_3 = 180.77885437;
const float ATM_SOOT_SCA_0 = 3032.16088867;
const float ATM_SOOT_SCA_1 = 2313.80053711;
const float ATM_SOOT_SCA_2 = 1712.43762207;
const float ATM_SOOT_SCA_3 = 1287.43334961;

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
const float ATM_WASO_ABS_0 = 80.25390625;
const float ATM_WASO_ABS_1 = 71.63645172;
const float ATM_WASO_ABS_2 = 70.20217133;
const float ATM_WASO_ABS_3 = 70.44733429;
const float ATM_INSO_ABS_0 = 68.66692352;
const float ATM_INSO_ABS_1 = 65.81173706;
const float ATM_INSO_ABS_2 = 62.78394699;
const float ATM_INSO_ABS_3 = 60.03722763;
const float ATM_SOOT_ABS_0 = 9308.44628906;
const float ATM_SOOT_ABS_1 = 8087.02734375;
const float ATM_SOOT_ABS_2 = 6899.54736328;
const float ATM_SOOT_ABS_3 = 6040.99560547;

// -- suso (stratospheric sulfate): the species the 410-630 nm set lacked,
//    a thin near-pure-scattering layer peaking at 12 km that the shared
//    tropospheric fold above cannot express --
const float ATM_SUSO_SCA_0 = 4002.83300781;
const float ATM_SUSO_SCA_1 = 3708.14746094;
const float ATM_SUSO_SCA_2 = 3374.33129883;
const float ATM_SUSO_SCA_3 = 3054.79687500;
const float ATM_SUSO_ABS_0 = 0.00010045536;
const float ATM_SUSO_ABS_1 = 0.00009815559;
const float ATM_SUSO_ABS_2 = 0.00030451213;
const float ATM_SUSO_ABS_3 = 0.00052355795;
const vec4 ATM_SUSO_SCA_V = vec4(ATM_SUSO_SCA_0, ATM_SUSO_SCA_1, ATM_SUSO_SCA_2, ATM_SUSO_SCA_3);
const vec4 ATM_SUSO_ABS_V = vec4(ATM_SUSO_ABS_0, ATM_SUSO_ABS_1, ATM_SUSO_ABS_2, ATM_SUSO_ABS_3);
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
const vec4 ATM_SOLAR = vec4(2.01085377, 1.92558253, 1.85678685, 1.56775546);

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
const vec4 ATM_MOON_IRR = vec4(3.0, 2.0, 1.0, 1.0) * 0.002;

// ===============================================================
// Density functions  (Hillaire / the pack's 4-wave spectral fit model)
// ===============================================================

// Density profiles in altitude above the planet surface. Callers hold the
// altitude directly (the sky march carries h_mid), so the folds clamp h
// instead of paying an (R+h)-R float round trip per sample; the below-surface
// clamps keep the radius-domain semantics.
float DensityRayH(float h) {
    return exp(-ATM_RAY_EXP_A * pow(max(h, 0.0), ATM_RAY_EXP_B));
}

float DensityOzoneH(float h) {
    float h_clamped = max(h, 1.0e-5);
    float t = log(h_clamped) - ATM_OZONE_CENTER_LOG;
    return ATM_OZONE_DENS_SCALE * (1.0 / h_clamped) * exp(-t * t * ATM_OZONE_INV_VAR);
}

// suso mass: linear-like rise into the 12 km peak (smoothstep), exponential
// tail over the 12-35 km limb, zero below 11 km like the source table.
float DensitySusoH(float h) {
    return 6.83999986e-08 * smoothstep(11.0, 12.0, h) * exp(-max(h - 12.0, 0.0) / 3.0);
}

// ===============================================================
// Scattering & extinction per wavelength  (vec4 = [450,510,580,650])
// ===============================================================

vec4 GetSigmaSRay(float h) {
    return DensityRayH(h) * ATM_SIGMA_S_RAY;
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
    return AeroSigma(h, ATM_SM_A, ATM_SM_B) + DensitySusoH(h) * ATM_SUSO_SCA_V;
}

// Total aerosol extinction (scattering + absorption) over the folded
// ATM_EM_A/B constants.
vec4 GetSigmaEMie(float h) {
    return AeroSigma(h, ATM_EM_A, ATM_EM_B) + DensitySusoH(h) * (ATM_SUSO_SCA_V + ATM_SUSO_ABS_V);
}

vec4 GetSigmaAOzone(float h) {
    return DensityOzoneH(h) * ATM_OZONE_SIGMA;
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
