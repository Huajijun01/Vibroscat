#ifndef LIB_WATER_RIVER_TEXTURE_GLSL
#define LIB_WATER_RIVER_TEXTURE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Three affine sampling frames share a periodic 128x128 R8 mother height
// (32 m anchor period, Phillips spectrum baked in research/PhillipsOceanBasis).
// POM uses layers 0 and 1; normals use a separate RG8 mother-slope texture.
// Frequencies are incommensurate to avoid a stationary crest-intersection grid.
// Advection velocities below are in normalized UV per second.
const float RIVER_TEX_FREQ[3] = float[](0.03125, 0.12875, 0.5224);
const vec2 RIVER_TEX_VEL[3] = vec2[](vec2(0.117463, 0.042755),
                                     vec2(0.234900, 0.085433),
                                     vec2(0.170991, 0.470297));
// per-layer sampling-frame rotation (cos, sin) of the world XZ vector
const vec2 RIVER_TEX_ROT[3] = vec2[](vec2(1.0, 0.0),
                                     vec2(0.70710678, 0.70710678),
                                     vec2(0.70710678, -0.70710678));
// full-range height swing (m): amp_j * WATER_RIVER_GAIN * (r - 0.5),
// r = texture R in [0, 1].  Spectrum-exact falloff for the detail ladder.
const float RIVER_TEX_AMP[3] = float[](0.58502, 0.14598, 0.03229 * 0.68);

// POM chases these two layers (the largest-energy pair)
const int RIVER_TEX_POM_LAYERS[2] = int[](0, 1);

// Periodic one-texel central differences in normalized UV units. Each RG8
// channel independently remaps its full baked slope range to [0, 1].
const vec2 RIVER_SLOPE_MIN_UV = vec2(-7.780392157, -8.282352941);
const vec2 RIVER_SLOPE_RANGE_UV = vec2(14.556862745, 17.066666667);

// Height of layer j at world XZ: one bilinear fetch, hardware wrap.
float RiverTextureLayerHeight(vec2 xz, float time, int j) {
    vec2 uv = vec2(dot(RIVER_TEX_ROT[j], xz), -RIVER_TEX_ROT[j].y * xz.x
                   + RIVER_TEX_ROT[j].x * xz.y);
    uv = uv * RIVER_TEX_FREQ[j] - RIVER_TEX_VEL[j] * time;
    return RIVER_TEX_AMP[j] * WATER_RIVER_GAIN
         * (texture(utex_mother_river, uv).r - 0.5);
}

// Full water height: all three layers.
float RiverTextureHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int j = 0; j < 3; ++j) {
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

// The chain rule transforms each mother slope by amplitude * frequency * R^T.
// Sum slopes before normalization, preserving the shared POM-adjusted position.
void RiverTextureNormal(vec2 xz, float time, out vec3 normal) {
    vec2 grad = vec2(0.0);
    for (int j = 0; j < 3; ++j) {
        vec2 rot = RIVER_TEX_ROT[j];
        vec2 uv = vec2(dot(rot, xz), -rot.y * xz.x + rot.x * xz.y);
        uv = uv * RIVER_TEX_FREQ[j] - RIVER_TEX_VEL[j] * time;
        vec2 slope = texture(utex_mother_river_slope, uv).rg
                   * RIVER_SLOPE_RANGE_UV + RIVER_SLOPE_MIN_UV;
        slope = vec2(rot.x * slope.x - rot.y * slope.y,
                     rot.y * slope.x + rot.x * slope.y);
        grad += slope * (RIVER_TEX_AMP[j] * WATER_RIVER_GAIN * RIVER_TEX_FREQ[j]);
    }
    normal = normalize(vec3(-grad.x, 1.0, -grad.y));
}

#endif // LIB_WATER_RIVER_TEXTURE_GLSL
