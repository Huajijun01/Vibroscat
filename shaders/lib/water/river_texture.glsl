#ifndef LIB_WATER_RIVER_TEXTURE_GLSL
#define LIB_WATER_RIVER_TEXTURE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// River water height field from ONE periodic R8 height texture
// (utex_mother_river, 128x128, 32 m period, 4-16 m Phillips anchor band
// baked offline -- research/PhillipsOceanBasis).  Four fetches sample the
// SAME texels in four rotated/scaled frames:
//   layer 0  anchor band  4-16 m, drifts at 1 m/s along 20 deg
//   layer 1  detail band  1-4 m,   1 m/s along 65 deg
//   layer 2  detail band 0.25-1 m, 1 m/s along -25 deg
//   layer 3  the anchor band's 60 deg crossing copy (same freq/speed as
//            layer 0, half its amplitude): gives the large swell a
//            crossing motion; the former finest layer (0.06-0.25 m,
//            ~9 mm swing) was dropped as invisible.
// Layer amplitudes follow the baked spectrum exactly; WATER_RIVER_GAIN
// scales them all.
//
// POM chases the two largest-energy layers (0, 3): 2 fetches per height
// sample instead of 4; the shading normal uses all four layers.

const float RIVER_TEX_SPEED = 1.0;   // m/s, shared by every layer

// freq_j = R^j / 32 m (layer 3 reuses the anchor freq); world velocity =
// SPEED along the layer direction, pre-folded with freq and rotation into
// tile-space advection constants.
const float RIVER_TEX_FREQ[4] = float[](0.03125, 0.125, 0.5, 0.03125);
const vec2 RIVER_TEX_VEL[4] = vec2[](vec2(0.029365, 0.010688),
                                     vec2(0.117461, 0.042753),
                                     vec2(0.171010, 0.469846),
                                     vec2(0.029365, 0.010688));
// per-layer sampling-frame rotation (cos, sin) of the world XZ vector
const vec2 RIVER_TEX_ROT[4] = vec2[](vec2(1.0, 0.0),
                                     vec2(0.70710678, 0.70710678),
                                     vec2(0.70710678, -0.70710678),
                                     vec2(0.5, 0.8660254));
// full-range height swing (m): amp_j * WATER_RIVER_GAIN * (r - 0.5),
// r = texture R in [0, 1].  Spectrum-exact falloff for the detail ladder.
const float RIVER_TEX_AMP[4] = float[](0.58502, 0.14598, 0.03229, 0.43876);

// POM chases these two layers (the largest-energy pair: anchor + crossing)
const int RIVER_TEX_POM_LAYERS[2] = int[](0, 3);

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
        h += RiverTextureLayerHeight(xz, time, RIVER_TEX_POM_LAYERS[j]);
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
