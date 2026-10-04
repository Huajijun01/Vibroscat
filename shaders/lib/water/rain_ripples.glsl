#ifndef LIB_WATER_RAIN_RIPPLES_GLSL
#define LIB_WATER_RAIN_RIPPLES_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Rain-driven finite-depth wave bake: 4 m spatial wrap, 4 s time loop.
// RG stores linear signed world-XZ normal slopes in [-0.5, 0.5]. Filtering
// before this affine decode commutes with filtering the original slopes.
const float RAIN_RIPPLE_PERIOD_M = 4.0;
const float RAIN_RIPPLE_LOOP_SECONDS = 4.0;
const float RAIN_RIPPLE_SLOPE_RANGE = 0.5;

vec2 SampleRainRippleSlope(vec2 scene_xz) {
    // Reduce absolute integer coordinates before conversion to float, keeping
    // the tile anchored through Iris cameraPosition resets and large worlds.
    vec2 camera_xz = vec2(cameraPositionInt.xz & ivec2(3)) + cameraPositionFract.xz;
    vec2 uv = (scene_xz + camera_xz) / RAIN_RIPPLE_PERIOD_M;
    // Bake frames are at i/64. The half texel aligns time zero with frame 0.
    float time_uv = frameTimeCounter / RAIN_RIPPLE_LOOP_SECONDS + 0.5 / 64.0;
    // Explicit LOD permits lookups after divergent material/face rejection.
    return (textureLod(utex_rain_ripples, vec3(uv, time_uv), 0.0).rg * 2.0 - 1.0)
        * RAIN_RIPPLE_SLOPE_RANGE;
}

#endif // LIB_WATER_RAIN_RIPPLES_GLSL
