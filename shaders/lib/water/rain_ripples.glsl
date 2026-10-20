#ifndef LIB_WATER_RAIN_RIPPLES_GLSL
#define LIB_WATER_RAIN_RIPPLES_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Dense large-drop wave bake: 4 m spatial wrap, 4 s time loop.
// RG stores world-XZ normal slopes in [-0.2, 0.2], with byte 128 exactly
// flat. Affine decoding commutes with filtering. Rain only perturbs normals;
// these slopes do not participate in any parallax height evaluation.
const float RAIN_RIPPLE_PERIOD_M = 4.0;
const float RAIN_RIPPLE_SLOPE_RANGE = 0.2;

vec2 SampleRainRippleSlope(vec2 scene_xz) {
    // Reduce absolute integer coordinates before conversion to float, keeping
    // the tile anchored through Iris cameraPosition resets and large worlds.
    vec2 camera_xz = vec2(cameraPositionInt.xz & ivec2(3)) + cameraPositionFract.xz;
    vec2 uv = (scene_xz + camera_xz) / RAIN_RIPPLE_PERIOD_M;
    // The CPU uniforms reconstruct subframe slopes using the original two
    // slices: a shifted time coordinate plus gain, still one filtered lookup.
    // Explicit LOD permits lookups after divergent material/face rejection.
    return (textureLod(utex_rain_ripples, vec3(uv, u_rain_ripple_time_uv), 0.0).rg - 128.0 / 255.0)
        * ((RAIN_RIPPLE_SLOPE_RANGE * 255.0 / 127.0) * u_rain_ripple_gain);
}

#endif // LIB_WATER_RAIN_RIPPLES_GLSL
