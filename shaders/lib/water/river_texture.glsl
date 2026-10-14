#ifndef LIB_WATER_RIVER_TEXTURE_GLSL
#define LIB_WATER_RIVER_TEXTURE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Three affine frames reuse ONE periodic 128x128 R8 Phillips height basis.
// POM uses layers 0 and 1; all three normal layers reuse ONE 128x128 RG8
// slope basis. The continuous trochoidal inverse map sharpens crests without
// folds. Compact bands with independent phases fit the height, slope power
// and crest/body statistics of a dense Phillips short-wave reference.
// The main and middle layers carry body detail; the finest fills their band.
// UV/s advection fits deep-water dispersion offline, weighted by slope power.
// Fixed texture translations approximate free-wave phases within each packet;
// bound crest harmonics travel with their parent wave.
const float RIVER_TEX_FREQ[3] = float[](0.062500000, 0.120122105, 0.226634028);
const vec2 RIVER_TEX_VEL[3] = vec2[](vec2(0.100904140, 0.033737910),
    vec2(0.139887994, 0.046772398),
    vec2(0.192146082, 0.064245206));
// per-layer sampling-frame rotation (cos, sin) of the world XZ vector
const vec2 RIVER_TEX_ROT[3] = vec2[](vec2(1.000000000, 0.000000000),
    vec2(0.999989316, 0.004622615),
    vec2(0.998649850, -0.051946867));
// Full-range height swing in metres. Subtract the baked mean instead of
// assuming that the asymmetric crest/trough range is centered at 0.5.
const float RIVER_TEX_AMP[3] = float[](0.131795961, 0.058332975, 0.022463026);
const float RIVER_TEX_CENTER = 0.440103036;

// POM chases these two layers (the largest-energy pair)
const int RIVER_TEX_POM_LAYERS[2] = int[](0, 1);

// Continuous Fourier derivatives transformed by the inverse crest Jacobian,
// then projected onto the hardware bilinear basis before RG8 quantization.
// Each channel independently remaps its full fitted slope range to [0, 1].
const vec2 RIVER_SLOPE_MIN_UV = vec2(-22.964086615, -14.789986130);
const vec2 RIVER_SLOPE_RANGE_UV = vec2(52.728907765, 29.079023962);

// One static, low-frequency cloud-map fetch offsets all wave layers together.
// Cache the result before POM so its whole search and the final normal share
// the same offset. The R8 map supplies one scalar along a fixed direction;
// the maximum displacement is 3 m over a 2048 m repeating noise domain.
vec2 RiverTextureWarpPosition(vec2 xz) {
    float noise = textureLod(utex_cloud_distribution_tex, xz * (1.0 / 2048.0), 0.0).r;
    return xz + (noise - 0.5) * vec2(0.6, 0.8) * 10.0;
}

// Height of layer j at world XZ: one bilinear fetch, hardware wrap.
float RiverTextureLayerHeight(vec2 xz, float time, int j) {
    vec2 uv = vec2(dot(RIVER_TEX_ROT[j], xz), -RIVER_TEX_ROT[j].y * xz.x
                   + RIVER_TEX_ROT[j].x * xz.y);
    uv = uv * RIVER_TEX_FREQ[j] - RIVER_TEX_VEL[j] * time;
    return RIVER_TEX_AMP[j] * WATER_RIVER_GAIN
         * (texture(utex_mother_river, uv).r - RIVER_TEX_CENTER);
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
