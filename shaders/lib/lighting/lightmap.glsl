#ifndef LIB_LIGHTING_LIGHTMAP_GLSL
#define LIB_LIGHTING_LIGHTMAP_GLSL

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
    return lm_sky * lm_sky;
}

#endif // LIB_LIGHTING_LIGHTMAP_GLSL
