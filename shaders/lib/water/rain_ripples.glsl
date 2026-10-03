#ifndef LIB_WATER_RAIN_RIPPLES_GLSL
#define LIB_WATER_RAIN_RIPPLES_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Independent damped radial wave bake: 2 m spatial wrap, 2 s time loop.
// RG stores linear signed world-XZ normal slopes in [-0.4, 0.4]. Filtering
// before this affine decode commutes with filtering the original slopes.
const float RAIN_RIPPLE_PERIOD_M = 2.0;
const float RAIN_RIPPLE_LOOP_SECONDS = 2.0;
const float RAIN_RIPPLE_SLOPE_RANGE = 0.4;

// Call in uniform control flow before discard/material/face rejection.
// No mip chain: fade wavelengths that fall below a few screen pixels rather
// than sampling an aliased normal field on distant or grazing surfaces.
float RainRippleVisibility(vec2 scene_xz) {
    if (rainStrength <= 0.001 || biome_precipitation != 1) return 0.0;
    vec2 dx = dFdx(scene_xz);
    vec2 dy = dFdy(scene_xz);
    float footprint_squared = max(dot(dx, dx), dot(dy, dy));
    return (1.0 - smoothstep(0.0001, 0.0009, footprint_squared))
        * rainStrength * RAIN_RIPPLE_STRENGTH;
}

vec2 SampleRainRippleSlope(vec2 scene_xz) {
    // Reduce absolute integer coordinates before conversion to float, keeping
    // the tile anchored through Iris cameraPosition resets and large worlds.
    vec2 camera_xz = vec2(cameraPositionInt.xz & ivec2(1)) + cameraPositionFract.xz;
    vec2 uv = (scene_xz + camera_xz) / RAIN_RIPPLE_PERIOD_M;
    // Bake frames are at i/64. The half texel aligns time zero with frame 0.
    float time_uv = frameTimeCounter / RAIN_RIPPLE_LOOP_SECONDS + 0.5 / 64.0;
    return (textureLod(utex_rain_ripples, vec3(uv, time_uv), 0.0).rg * 2.0 - 1.0)
        * RAIN_RIPPLE_SLOPE_RANGE;
}

#endif // LIB_WATER_RAIN_RIPPLES_GLSL
