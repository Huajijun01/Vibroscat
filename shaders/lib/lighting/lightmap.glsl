#ifndef LIB_LIGHTING_LIGHTMAP_GLSL
#define LIB_LIGHTING_LIGHTMAP_GLSL

#include "/lib/core/math_scalar.glsl"

// Vanilla lightmap (blockLight, skyLight) in 0..1 -> lighting weights, shared
// by deferred shading (colortex4.zw) and the forward translucent passes
// (v_texcoord.zw).

float BlockLightFalloff(float lm_block) {
    float d = (1.0 - lm_block) * 15.0 + 1.0;
    return 1.0 / (d * d);
}

float BlockLightFromLm(float lm_block) {
    return lm_block * lm_block * lm_block;
}

float SkyLightFromLm(float lm_sky) {
    float k = lm_sky * lm_sky;
    return k * k;
}

#endif // LIB_LIGHTING_LIGHTMAP_GLSL
