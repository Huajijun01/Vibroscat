#ifndef LIB_WATER_RAIN_RIPPLES_GLSL
#define LIB_WATER_RAIN_RIPPLES_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Sparse large-drop wave bake: 4 m spatial wrap, 4 s time loop.
// RG stores world-XZ normal slopes in [-0.15, 0.15], with byte 128 exactly
// flat. Affine decoding commutes with filtering. Rain only perturbs normals;
// these slopes do not participate in any parallax height evaluation.
const float RAIN_RIPPLE_PERIOD_M = 4.0;
const float RAIN_RIPPLE_LOOP_SECONDS = 4.0;
const float RAIN_RIPPLE_SLOPE_RANGE = 0.15;

vec2 SampleRainRippleSlope(vec2 scene_xz) {
    // Reduce absolute integer coordinates before conversion to float, keeping
    // the tile anchored through Iris cameraPosition resets and large worlds.
    vec2 camera_xz = vec2(cameraPositionInt.xz & ivec2(3)) + cameraPositionFract.xz;
    vec2 uv = (scene_xz + camera_xz) / RAIN_RIPPLE_PERIOD_M;
    // Bake frames are at i/64. The half texel aligns time zero with frame 0.
    float time_uv = frameTimeCounter / RAIN_RIPPLE_LOOP_SECONDS + 0.5 / 64.0;
    // Explicit LOD permits lookups after divergent material/face rejection.
    return (textureLod(utex_rain_ripples, vec3(uv, time_uv), 0.0).rg - 128.0 / 255.0)
        * (RAIN_RIPPLE_SLOPE_RANGE * 255.0 / 127.0);
}

#endif // LIB_WATER_RAIN_RIPPLES_GLSL
