#ifndef LIB_ATMOSPHERE_MEDIA_GLSL
#define LIB_ATMOSPHERE_MEDIA_GLSL

#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/scattering/phase.glsl"

// ===============================================================
// Atmosphere Sky - 4-Wave Spectral (GLSL 430 desktop)
// Wavelengths: 450 / 510 / 580 / 650 nm (sky-tracer realtime bands)
// Medium: the sky-tracer OPAC/libRadtran tables (inso/waso/soot/suso,
// US-standard air, ozone), evaluated as piecewise-linear profiles that
// match the offline iterative-MS pack LUT bake exactly. vec4 channels
// map to ascending wavelength order.
// Provenance: licenses/THIRD_PARTY_NOTICES.md section 14.
// ===============================================================

// ===============================================================
// Baked Constants
// ===============================================================

// -- Solar irradiance (W/m2/nm at TOA; bands.csv width / 10 nm) --
const vec4 ATM_SOLAR = vec4(2.01085377, 1.92558253, 1.85678685, 1.56775546);

// -- Moonlight irradiance (W/m2/nm), refitted for the new bands to keep
//    the previous Rec.2020 moon tint (~0.88, 0.95, 1.18) and the moon/sun
//    luminance ratio of the 410-630 nm constants --
const vec4 ATM_MOON_IRR = vec4(0.079351753, 0.0547947548, 0.0660177767, 0.0125392675);

// -- Rayleigh scattering: sigma = air_cm3 * ATM_RAY_COEF (km^-1) --
const vec4 ATM_RAY_COEF = vec4(1.29428139e-21, 7.8450922e-22, 4.68993434e-22, 2.97320817e-22);

// -- Ozone absorption: sigma = ozone_cm3 * ATM_O3_COEF (km^-1) --
const vec4 ATM_O3_COEF = vec4(1.71000004e-17, 1.57999994e-16, 4.55e-16, 2.42000013e-16);

// -- Aerosol mass extinction (km^-1 per g/m3) per species --
const vec4 ATM_INSO_SCA = vec4(164.565384, 169.777802, 175.440735, 180.778854);
const vec4 ATM_INSO_ABS = vec4(68.6669235, 65.8117371, 62.783947, 60.0372276);
const vec4 ATM_WASO_SCA = vec4(4107.271, 3479.43579, 2884.22949, 2399.55371);
const vec4 ATM_WASO_ABS = vec4(80.2539062, 71.6364517, 70.2021713, 70.4473343);
const vec4 ATM_SOOT_SCA = vec4(3032.16089, 2313.80054, 1712.43762, 1287.43335);
const vec4 ATM_SOOT_ABS = vec4(9308.44629, 8087.02734, 6899.54736, 6040.99561);
const vec4 ATM_SUSO_SCA = vec4(4002.83301, 3708.14746, 3374.3313, 3054.79688);
const vec4 ATM_SUSO_ABS = vec4(0.000100455356, 9.81555859e-05, 0.000304512127, 0.000523557945);

// -- Aerosol below-surface growth scale (horizon dip region) --
const float ATM_AERO_SCALE = 8.0;

const float ATM_AIR_H[50] = float[](0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 27.5, 30.0, 32.5, 35.0, 37.5, 40.0, 42.5, 45.0, 47.5, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 100.0, 105.0, 110.0, 115.0, 120.0);
const float ATM_AIR_V[50] = float[](2.54581802e+19, 2.31093595e+19, 2.09233105e+19, 1.89010491e+19, 1.70326699e+19, 1.53100595e+19, 1.372429e+19, 1.22684497e+19, 1.09317899e+19, 9.71184107e+18, 8.59545689e+18, 7.5836522e+18, 6.48417411e+18, 5.54162876e+18, 4.73612105e+18, 4.04759505e+18, 3.45934011e+18, 2.957987e+18, 2.52849411e+18, 2.16150297e+18, 1.84799001e+18, 1.57406401e+18, 1.34089497e+18, 1.14349202e+18, 9.75787226e+17, 8.33128273e+17, 5.63587292e+17, 3.82769891e+17, 2.60501895e+17, 1.75973108e+17, 1.20239302e+17, 8.30444726e+16, 5.79881488e+16, 4.08748902e+16, 2.91749805e+16, 2.13460497e+16, 1.180302e+16, 6.42183188e+15, 3.38394702e+15, 1.72166999e+15, 8.34113922e+14, 3.82932204e+14, 1.71007294e+14, 7.13050638e+13, 2.92175993e+13, 1.18796698e+13, 5.02978419e+12, 2.14268799e+12, 9.68132788e+11, 5.11026004e+11);

const float ATM_OZONE_H[50] = float[](0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 27.5, 30.0, 32.5, 35.0, 37.5, 40.0, 42.5, 45.0, 47.5, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 100.0, 105.0, 110.0, 115.0, 120.0);
const float ATM_OZONE_V[50] = float[](6.77768004e+11, 6.77940232e+11, 6.77827903e+11, 6.27433669e+11, 5.77144816e+11, 5.77257603e+11, 5.64577632e+11, 6.15105167e+11, 6.5268043e+11, 8.91037876e+11, 1.12944297e+12, 1.63087594e+12, 2.00834495e+12, 2.13299207e+12, 2.38371707e+12, 2.63452492e+12, 3.01228596e+12, 3.51351996e+12, 4.01510996e+12, 4.39088998e+12, 4.7685708e+12, 4.76909981e+12, 4.89427409e+12, 4.76819174e+12, 4.51826523e+12, 4.26687699e+12, 3.27289196e+12, 2.5097989e+12, 1.86094505e+12, 1.38009602e+12, 9.65640126e+11, 6.06629986e+11, 3.59785988e+11, 2.14725001e+11, 1.19720002e+11, 6.62160015e+10, 2.12580004e+10, 7.06859981e+09, 2.37020006e+09, 516900000.0, 208675008.0, 114960000.0, 85550000.0, 49952000.0, 20468000.0, 4756001.0, 1006600.0, 107200.0, 4844.0, 255.699997);

const float ATM_MASS_INSO_H[14] = float[](0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 35.0);
const float ATM_MASS_INSO_V[14] = float[](1.00899997e-05, 8.90699994e-06, 2.2910001e-06, 2.021e-06, 1.78400001e-06, 1.57399995e-06, 1.38899998e-06, 1.22599999e-06, 1.08200004e-06, 9.54899974e-07, 8.4269999e-07, 7.43600026e-07, 0.0, 0.0);

const float ATM_MASS_WASO_H[14] = float[](0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 35.0);
const float ATM_MASS_WASO_V[14] = float[](1.48700001e-05, 1.31300003e-05, 4.57099986e-07, 4.03400009e-07, 3.55999987e-07, 3.14200008e-07, 2.77200002e-07, 2.44700004e-07, 2.15900002e-07, 1.90500003e-07, 1.68200003e-07, 1.48400005e-07, 0.0, 0.0);

const float ATM_MASS_SOOT_H[14] = float[](0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 35.0);
const float ATM_MASS_SOOT_V[14] = float[](5.31199987e-07, 4.6880001e-07, 1.36200002e-08, 1.20200001e-08, 1.06e-08, 9.35799971e-09, 8.25899971e-09, 7.28799998e-09, 6.43199982e-09, 5.67600011e-09, 5.00899988e-09, 4.41999992e-09, 0.0, 0.0);

const float ATM_MASS_SUSO_H[14] = float[](0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 35.0);
const float ATM_MASS_SUSO_V[14] = float[](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 6.83999986e-08, 0.0);

// -- Phase --
// Triple-lobe Mie blend, same structure as the tuned cirrus phase
// (shaders/lib/cloud/cirrus.glsl): a narrow high-g forward peak keeps the
// silver lining, a broad low-g forward lobe adds smooth haze, and a
// backward lobe (effective eccentricity -0.3) brightens the anti-solar sky.
// Weights sum to 1, so the blend stays a normalized phase. Formulas live in
// /lib/scattering/phase.glsl. The multi-scatter bake resolves the per-species
// tabulated Mie phases instead; this blend stays the runtime's direct
// single-scattering tuning.
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

// ===============================================================
// Density functions (piecewise-linear sky-tracer tables)
// ===============================================================

// Ascending-key table lookup: returns (lo, hi, t) with lo/hi row indices.
// GLSL requires sized array parameters, so each table width gets an entry
// point; the search itself is a short binary scan inside the per-sample sky
// march.
vec3 TableBracket(const float keys[50], int n, float h) {
    int lo = 0;
    int hi = n - 1;
    while (hi - lo > 1) {
        int mid = (lo + hi) >> 1;
        if (keys[mid] <= h) lo = mid; else hi = mid;
    }
    float t = clamp((h - keys[lo]) / max(keys[hi] - keys[lo], 1.0e-20), 0.0, 1.0);
    return vec3(float(lo), float(hi), t);
}

vec3 TableBracket14(const float keys[14], int n, float h) {
    int lo = 0;
    int hi = n - 1;
    while (hi - lo > 1) {
        int mid = (lo + hi) >> 1;
        if (keys[mid] <= h) lo = mid; else hi = mid;
    }
    float t = clamp((h - keys[lo]) / max(keys[hi] - keys[lo], 1.0e-20), 0.0, 1.0);
    return vec3(float(lo), float(hi), t);
}

// Aerosol mass per species (g/m3). Below the surface the masses keep
// growing with the 8 km scale height so the horizon dip region feeds the
// same exponentially denser air the runtime sky march integrates; suso is
// zero at the surface, so its clamp contributes nothing.
vec4 AerosolMasses(float h) {
    if (h < 0.0) {
        float g = exp(-h / ATM_AERO_SCALE);
        return vec4(ATM_MASS_INSO_V[0], ATM_MASS_WASO_V[0], ATM_MASS_SOOT_V[0], ATM_MASS_SUSO_V[0]) * g;
    }
    vec3 b = TableBracket14(ATM_MASS_INSO_H, 14, h);
    int lo = int(b.x);
    int hi = int(b.y);
    float t = b.z;
    return vec4(
        mix(ATM_MASS_INSO_V[lo], ATM_MASS_INSO_V[hi], t),
        mix(ATM_MASS_WASO_V[lo], ATM_MASS_WASO_V[hi], t),
        mix(ATM_MASS_SOOT_V[lo], ATM_MASS_SOOT_V[hi], t),
        mix(ATM_MASS_SUSO_V[lo], ATM_MASS_SUSO_V[hi], t));
}

// ===============================================================
// Scattering & extinction per wavelength  (vec4 = [450,510,580,650])
// ===============================================================

vec4 GetSigmaSRay(float h) {
    vec3 b = TableBracket(ATM_AIR_H, 50, max(h, 0.0));
    float air = mix(ATM_AIR_V[int(b.x)], ATM_AIR_V[int(b.y)], b.z);
    return air * ATM_RAY_COEF;
}

vec4 GetSigmaSMie(float h) {
    vec4 m = AerosolMasses(h);
    return m.x * ATM_INSO_SCA + m.y * ATM_WASO_SCA
         + m.z * ATM_SOOT_SCA + m.w * ATM_SUSO_SCA;
}

// Total aerosol extinction (scattering + absorption).
vec4 GetSigmaEMie(float h) {
    vec4 m = AerosolMasses(h);
    return m.x * (ATM_INSO_SCA + ATM_INSO_ABS) + m.y * (ATM_WASO_SCA + ATM_WASO_ABS)
         + m.z * (ATM_SOOT_SCA + ATM_SOOT_ABS) + m.w * (ATM_SUSO_SCA + ATM_SUSO_ABS);
}

vec4 GetSigmaAOzone(float h) {
    vec3 b = TableBracket(ATM_OZONE_H, 50, max(h, 0.0));
    float o3 = mix(ATM_OZONE_V[int(b.x)], ATM_OZONE_V[int(b.y)], b.z);
    return o3 * ATM_O3_COEF;
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
