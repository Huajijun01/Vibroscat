#ifndef LIB_WATER_RIVER_TEXTURE_GLSL
#define LIB_WATER_RIVER_TEXTURE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

#if WATER_SURFACE_QUALITY == 1
// Medium-large sea state: the same R8 height and RG8 continuous-slope
// mother basis is reused by 5 normal layers and the 3 POM body layers.
// Offline Phillips fit, height sigma ~0.18 m at gain 1. Fixed per-layer
// phases decorrelate the sampling frames; bound crest harmonics advect
// with their parent waves. Texture translations approximate dispersion.
const int RIVER_TEX_LAYER_COUNT = 5;
const int RIVER_TEX_POM_LAYER_COUNT = 3;
const float RIVER_TEX_FREQ[5] = float[](0.013255621305, 0.029946960090, 0.066835916798, 0.128822849201, 0.234602063648);
const vec2 RIVER_TEX_VEL[5] = vec2[](vec2(0.052675630718, 0.014954379110),
    vec2(0.079174635396, 0.022477329601),
    vec2(0.118280909432, 0.033579428229),
    vec2(0.164212476339, 0.046619197384),
    vec2(0.221602989153, 0.062912110715));
const vec2 RIVER_TEX_ROT[5] = vec2[](vec2(1.000000000000, 0.000000000000),
    vec2(0.999825697382, 0.018670159444),
    vec2(0.998252386321, 0.059094612321),
    vec2(0.998313359606, 0.058055456519),
    vec2(0.998816676703, 0.048633798335));
const vec2 RIVER_TEX_PHASE[5] = vec2[](vec2(0.869876998442, 0.133983279604),
    vec2(0.215115153409, 0.025895432751),
    vec2(0.142706711576, 0.002183496120),
    vec2(0.315397575392, 0.596563910699),
    vec2(0.758387072897, 0.491125316131));
const float RIVER_TEX_AMP[5] = float[](1.175320385206, 0.494370417196, 0.209815698999, 0.091604803343, 0.041068472115);
const float RIVER_TEX_CENTER = 0.445920458027;
const int RIVER_TEX_POM_LAYERS[3] = int[](0, 1, 2);
const float RIVER_TEX_POM_AMPLITUDE = RIVER_TEX_AMP[0] + RIVER_TEX_AMP[1] + RIVER_TEX_AMP[2];
const float RIVER_TEX_POM_GAIN = WATER_LARGE_POM_HEIGHT;
const vec2 RIVER_SLOPE_MIN_UV = vec2(-22.704304827758, -13.275997465604);
const vec2 RIVER_SLOPE_RANGE_UV = vec2(44.459864590068, 24.353513033894);
#else
const int RIVER_TEX_LAYER_COUNT = 3;
const int RIVER_TEX_POM_LAYER_COUNT = 2;
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
// Full-range height swing in meters. Subtract the baked mean instead of
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
const float RIVER_TEX_POM_AMPLITUDE = RIVER_TEX_AMP[0] + RIVER_TEX_AMP[1];
const float RIVER_TEX_POM_GAIN = WATER_RIVER_GAIN;
#endif

// Small waves only: one cloud-map fetch offsets all wave layers together.
// Cache the result before POM so its whole search and the final normal share
// the same offset. The R8 map supplies one scalar along a fixed direction;
// the maximum displacement is 4 m over a 1024 m repeating noise domain.
vec2 RiverTextureWarpPosition(vec2 xz) {
#if WATER_SURFACE_QUALITY == 1
    return xz;
#else
    float noise = textureLod(utex_cloud_distribution_tex, xz * (1.0 / 1024.0), 0.0).r;
    return xz + (noise - 0.5) * vec2(0.6, 0.8) * 8.0;
#endif
}

float RiverTextureLayerHeight(vec2 xz, float time, int j, float gain) {
    vec2 uv = vec2(dot(RIVER_TEX_ROT[j], xz), -RIVER_TEX_ROT[j].y * xz.x
                   + RIVER_TEX_ROT[j].x * xz.y);
    uv = uv * RIVER_TEX_FREQ[j] - RIVER_TEX_VEL[j] * time;
#if WATER_SURFACE_QUALITY == 1
    uv += RIVER_TEX_PHASE[j];
#endif
    return RIVER_TEX_AMP[j] * gain
         * (texture(utex_mother_river, uv).r - RIVER_TEX_CENTER);
}


// POM height: the selected mode's 2 or 3 largest-energy layers.
float RiverTexturePOMHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int j = 0; j < RIVER_TEX_POM_LAYER_COUNT; ++j) {
        h += RiverTextureLayerHeight(xz, time, RIVER_TEX_POM_LAYERS[j], RIVER_TEX_POM_GAIN);
    }
    return h;
}

// The chain rule transforms each mother slope by amplitude * frequency * R^T.
// Sum slopes before normalization, preserving the shared POM-adjusted position.
void RiverTextureNormal(vec2 xz, float time, out vec3 normal) {
    vec2 grad = vec2(0.0);
    for (int j = 0; j < RIVER_TEX_LAYER_COUNT; ++j) {
        vec2 rot = RIVER_TEX_ROT[j];
        vec2 uv = vec2(dot(rot, xz), -rot.y * xz.x + rot.x * xz.y);
        uv = uv * RIVER_TEX_FREQ[j] - RIVER_TEX_VEL[j] * time;
#if WATER_SURFACE_QUALITY == 1
        uv += RIVER_TEX_PHASE[j];
#endif
        vec2 slope = texture(utex_mother_river_slope, uv).rg
                   * RIVER_SLOPE_RANGE_UV + RIVER_SLOPE_MIN_UV;
        slope = vec2(rot.x * slope.x - rot.y * slope.y,
                     rot.y * slope.x + rot.x * slope.y);
        grad += slope * (RIVER_TEX_AMP[j] * WATER_RIVER_GAIN * RIVER_TEX_FREQ[j]);
    }
    normal = normalize(vec3(-grad.x, 1.0, -grad.y));
}

#endif // LIB_WATER_RIVER_TEXTURE_GLSL
