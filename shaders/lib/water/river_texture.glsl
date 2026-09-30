#ifndef LIB_WATER_RIVER_TEXTURE_GLSL
#define LIB_WATER_RIVER_TEXTURE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// River water height field from ONE periodic R8 height texture
// (utex_mother_river, 128x128, 32 m period, 4-16 m Phillips anchor band
// baked offline -- research/PhillipsOceanBasis).  Four layers sample the
// SAME texels at frequency steps x4 in four rotated frames.
//
// Motion model: every layer translates at RIVER_TEX_SPEED (1 m/s) along its
// own direction, so the surface drifts like a river while the crossing
// directions keep the interference alive.  Layer amplitudes follow the
// baked spectrum exactly (no reshaping); WATER_RIVER_GAIN scales them.
//
// POM chases only the two largest-energy layers (0, 1): 2 fetches per
// height sample instead of 4; the shading normal uses all four layers.

const float RIVER_TEX_SPEED = 1.0;   // m/s, shared by every layer

// freq_j = R^j / 32 m; world velocity = SPEED along dir_j, pre-folded with
// freq and the layer rotation into tile-space advection constants.
const float RIVER_TEX_FREQ[4] = float[](0.03125, 0.125, 0.5, 2.0);
const vec2 RIVER_TEX_VEL[4] = vec2[](vec2(0.029365, 0.010688),
                                     vec2(0.117461, 0.042753),
                                     vec2(0.171010, 0.469846),
                                     vec2(1.879382, 0.684040));
// per-layer sampling-frame rotation (cos, sin) of the world XZ vector
const vec2 RIVER_TEX_ROT[4] = vec2[](vec2(1.0, 0.0),
                                     vec2(0.70710678, 0.70710678),
                                     vec2(0.70710678, -0.70710678),
                                     vec2(0.0, 1.0));
// full-range height swing (m): amp_j * WATER_RIVER_GAIN * (r - 0.5),
// r = texture R in [0, 1].  Spectrum-exact falloff (no reshaping).
const float RIVER_TEX_AMP[4] = float[](0.51026, 0.20714, 0.07451, 0.00912);

// central-difference step (m), same value as the fitted value-noise ocean
const float RIVER_TEX_DIFF_EPS = 0.1;

// Height of layer j at world XZ: one bilinear fetch, hardware wrap.
float RiverTextureLayerHeight(vec2 xz, float time, int j) {
    vec2 uv = vec2(dot(RIVER_TEX_ROT[j], xz), -RIVER_TEX_ROT[j].y * xz.x
                   + RIVER_TEX_ROT[j].x * xz.y);
    uv = uv * RIVER_TEX_FREQ[j] - RIVER_TEX_VEL[j] * time;
    return RIVER_TEX_AMP[j] * WATER_RIVER_GAIN
         * (texture(utex_mother_river, uv).r - 0.5);
}

// Full water height: all four layers.
float RiverTextureHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int j = 0; j < 4; ++j) {
        h += RiverTextureLayerHeight(xz, time, j);
    }
    return h;
}

// POM height: the two largest-energy layers only (2 fetches per sample).
float RiverTexturePOMHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int j = 0; j < 2; ++j) {
        h += RiverTextureLayerHeight(xz, time, j);
    }
    return h;
}

// World-space normal (y up) from a central-difference gradient of the full
// field (same step and convention as the fitted value-noise ocean).
void RiverTextureNormal(vec2 xz, float time, out vec3 normal) {
    float eps = RIVER_TEX_DIFF_EPS;
    float hx = RiverTextureHeight(xz + vec2(eps, 0.0), time)
             - RiverTextureHeight(xz - vec2(eps, 0.0), time);
    float hz = RiverTextureHeight(xz + vec2(0.0, eps), time)
             - RiverTextureHeight(xz - vec2(0.0, eps), time);
    vec2 grad = vec2(hx, hz) / (2.0 * eps);
    normal = normalize(vec3(-grad.x, 1.0, -grad.y));
}

#endif // LIB_WATER_RIVER_TEXTURE_GLSL
