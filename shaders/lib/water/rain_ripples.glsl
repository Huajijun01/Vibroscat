#ifndef LIB_WATER_RAIN_RIPPLES_GLSL
#define LIB_WATER_RAIN_RIPPLES_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Dense large-drop wave bake: RG = world-XZ normal slopes in [-0.2, 0.2], byte 128
// exactly flat; affine decoding commutes with filtering. Normals only, never a height source.
const float RAIN_RIPPLE_PERIOD_M = 4.0;
const float RAIN_RIPPLE_SLOPE_RANGE = 0.2;

vec2 SampleRainRippleSlope(vec2 world_xz) {
    // Integer mask before float conversion keeps the tile anchored through camera resets
    // and large worlds.
    vec2 camera_xz = vec2(cameraPositionInt.xz & ivec2(3)) + cameraPositionFract.xz;
    vec2 uv = (world_xz + camera_xz) / RAIN_RIPPLE_PERIOD_M;
    // u_rain_ripple_time_uv encodes CPU-side subframe reconstruction (shifted time + gain);
    // explicit LOD is required after divergent material/face rejection.
    return (textureLod(utex_rain_ripples, vec3(uv, u_rain_ripple_time_uv), 0.0).rg - 128.0 / 255.0)
        * ((RAIN_RIPPLE_SLOPE_RANGE * 255.0 / 127.0) * u_rain_ripple_gain);
}

#endif // LIB_WATER_RAIN_RIPPLES_GLSL
