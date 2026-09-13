#ifndef LIB_WATER_VALUE_NOISE_GLSL
#define LIB_WATER_VALUE_NOISE_GLSL

#include "/lib/contract/uniforms.glsl"

// Single-texture value-noise ocean (offline-fitted).
// 7 layers from the 64x64 R8 utex_noise2d_tex (hardware bilinear, repeat);
// per-band layer selection solved against the analytic Phillips band
// features (n=8, low-frequency allocation 3,2,1,1,1). The finest fitted band
// (lambda 0.131 m, amplitude 0.0057) was dropped: the OCEAN_WAVE_DIFF_EPS central
// difference has its first zero at 2*eps = 0.2 m, so that band held 0.4% of
// the normal's slope variance while costing 4 of its 32 fetches.
// Statically optimized: freq pre-multiplied into uv, fitted gain into
// amplitude. Normals from a central-difference gradient.

struct OceanWave {
    vec4 uv;         // precombined 2x2 uv transform (layer angle + wind
                     // frame cross-wind stretch), row-major, pre-scaled
                     // by freq = 2*pi/lambda
    float amplitude; // fitted height amplitude (m), pre-scaled by gain
    float omega;     // deep-water dispersion: pixel advection speed
};

const int OCEAN_WAVE_LAYERS = 7; // full wave table size
const OceanWave OCEAN_WAVES[OCEAN_WAVE_LAYERS] = OceanWave[](
    OceanWave(vec4(0.48383789, 0.06497906, 0.12574129, 0.11980542), 0.419068, 2.23419),
    OceanWave(vec4(0.38679537, 0.23157128, 0.00831051, 0.21160617), -0.424931, 2.14238),
    OceanWave(vec4(0.62624209, 0.24421508, 0.09593550, 0.26013725), -0.301118, 2.61903),
    OceanWave(vec4(0.60644167, 0.20562579, 0.10357081, 0.24136490), -0.315376, 2.55639),
    OceanWave(vec4(1.98834646, 2.86292616, -1.32892738, 1.76140873), -0.039151, 5.93238),
    OceanWave(vec4(1.02173311, 1.11223367, -0.62825168, 0.89748953), -0.123701, 3.89348),
    OceanWave(vec4(3.64585845, -1.68458698, 1.34745029, 0.11760039), 0.044025, 6.41017));

// Offline normalization gain (fitted std -> target wave table std) and the
// central-difference step, matched to the offline 384-grid (32 m) gradient.
const float OCEAN_WAVE_DIFF_EPS = 0.1; // central-difference step (m)

// Single hardware bilinear fetch with smoothstep-equivalent weights (uv
// pre-distorted: w = f2(3 - 2f)).
float OceanWaveNoise(vec2 pos) {
    vec2 f = fract(pos);
    vec2 p = floor(pos) + f * f * (3.0 - 2.0 * f);
    return texture(utex_noise2d_tex, (p + 0.5) / 64.0).r;
}

// Cheap bilinear fetch for the POM field only (saves ~8 ALU/sample; the
// final normal still uses the smoothstep sample).
float OceanWaveNoiseFast(vec2 pos) {
    return texture(utex_noise2d_tex, (pos + 0.5) / 64.0).r;
}

// Height of a single layer at world XZ.
float OceanLayerHeight(vec2 xz, float time, OceanWave w) {
    // uv already includes freq: r = (uv * freq) . xz, then advect at omega
    vec2 r = vec2(dot(w.uv.xy, xz), dot(w.uv.zw, xz));
    r.x += w.omega * time;
    return w.amplitude * (OceanWaveNoise(r) - 0.5);
}

float OceanValueNoiseHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int i = 0; i < OCEAN_WAVE_LAYERS; ++i) {
        h += OceanLayerHeight(xz, time, OCEAN_WAVES[i]);
    }
    return h;
}

// World-space normal (y up) from a central-difference gradient (central
// sample omitted when only the normal is needed).
void OceanValueNoiseNormal(vec2 xz, float time, out vec3 normal) {
    float eps = OCEAN_WAVE_DIFF_EPS;
    float hx = OceanValueNoiseHeight(xz + vec2(eps, 0.0), time) - OceanValueNoiseHeight(xz - vec2(eps, 0.0), time);
    float hz = OceanValueNoiseHeight(xz + vec2(0.0, eps), time) - OceanValueNoiseHeight(xz - vec2(0.0, eps), time);
    vec2 grad = vec2(hx, hz) / (2.0 * eps);
    normal = normalize(vec3(-grad.x, 1.0, -grad.y));
}

#endif // LIB_WATER_VALUE_NOISE_GLSL
