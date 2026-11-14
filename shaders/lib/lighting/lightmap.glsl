#ifndef LIB_LIGHTING_LIGHTMAP_GLSL
#define LIB_LIGHTING_LIGHTMAP_GLSL

#include "/lib/core/math_scalar.glsl"

// Input: vanilla lightmap components in 0..1. Consumed via colortex4.zw
// (deferred) and v_texcoord.zw (forward translucent).

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
