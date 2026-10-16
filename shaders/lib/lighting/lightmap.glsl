#ifndef LIB_LIGHTING_LIGHTMAP_GLSL
#define LIB_LIGHTING_LIGHTMAP_GLSL

#include "/lib/core/math_scalar.glsl"

// Vanilla lightmap (blockLight, skyLight) in 0..1 -> lighting weights, shared
// by deferred shading (colortex4.zw) and the forward translucent passes
// (v_texcoord.zw).

// Block light: steep power curve for high dynamic range (torches are bright).
float BlockLightFalloff(float lm_block) {
    float d = (1.0 - lm_block) * 15.0 + 1.5;
    return 1.0 / (d * d);
}

float BlockLightFromLm(float lm_block) {
    float light = BlockLightFalloff(lm_block);
    float light_zero = BlockLightFalloff(0.0);
    return (light - light_zero) / (1.0 - light_zero);
}

// Sky light: quadratic falloff - outdoor areas ramp quickly with sky access.
float SkyLightFromLm(float lm_sky) {
    return FastAdjust(lm_sky, -0.9);
}

// Vanilla lightmap remap. The lightmap matrix emits UV inside a 32-texel atlas
// with a 2-texel border, so the useful range is [2/32, 31/32] = 29/32 wide,
// while the curves above are anchored on [0, 1]. Scale and offset are the
// decimal literals the pack has always used: written as 32.0/29.0 and 2.0/29.0
// they would round to the neighbouring float (1.10344827 vs 1.10344899,
// 0.06896552 vs 0.06896560), so the shortened forms stay to keep existing
// vertex results bit-identical.
const float VANILLA_LIGHTMAP_SCALE = 1.103449;
const float VANILLA_LIGHTMAP_OFFSET = 0.0689656;

vec2 RemapVanillaLightmap(vec2 lm) {
    return clamp(lm * VANILLA_LIGHTMAP_SCALE - VANILLA_LIGHTMAP_OFFSET, 0.0, 1.0);
}

#endif // LIB_LIGHTING_LIGHTMAP_GLSL
