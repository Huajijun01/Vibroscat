#ifndef LIB_WATER_RIVER_TEXTURE_GLSL
#define LIB_WATER_RIVER_TEXTURE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// River water height field from ONE periodic R8 height texture
// (utex_mother_river, 128x128, 32 m period). The texels are an offline
// Phillips-spectrum basis bake (research/PhillipsOceanBasis): four layers
// sample the SAME texels at frequency steps x4, each with its own rotation
// and deep-water advection velocity (world frame, precomputed into the
// constants). Layer amplitudes use a flattened falloff (exponent 0.5) and a
// river gain so the crossing trains stay visible; the 0-1 texture channel is
// remapped to +/- half its metre range per layer.
// POM chases only the two largest-energy layers (0, 1): 2 fetches per height
// sample instead of 4; the shading normal still uses all four layers.

// freq_j = R^j / 32 m; velocities already include freq and the layer
// advection model (river): world velocity = flow (0.5 m/s @ 20 deg)
// + RIVER_TEX_DISPERSION_BLEND * phase speed along each layer's own
// direction. Full deep-water dispersion at 4-16 m wavelengths would
// force 2.5-5 m/s translation; the blend trades that for the slow
// river look (set 1.0 to restore strict dispersion).
#define RIVER_TEX_DISPERSION_BLEND 0.25
const float RIVER_TEX_FREQ[4] = float[](0.03125, 0.125, 0.5, 2.0);
const vec2 RIVER_TEX_FLOW = vec2(0.46985, 0.17101);  // river current (m/s)
const vec2 RIVER_TEX_VEL[4] = vec2[](vec2(0.040598, 0.014776),
                                     vec2(0.108621, -0.007496),
                                     vec2(0.209021, 0.264199),
                                     vec2(0.548753, -0.864448));
// per-layer sampling-frame rotation (cos, sin) of the world XZ vector
const vec2 RIVER_TEX_ROT[4] = vec2[](vec2(1.0, 0.0),
                                     vec2(0.70710678, 0.70710678),
                                     vec2(0.70710678, -0.70710678),
                                     vec2(0.0, 1.0));
// full-range height swing (m) at gain 1.0 (master-band-matched):
// amp_j * WATER_RIVER_GAIN * (r - 0.5), r = texture R in [0, 1]
const float RIVER_TEX_AMP[4] = float[](0.51026, 0.31351, 0.17070, 0.03161);

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
