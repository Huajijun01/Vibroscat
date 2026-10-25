#ifndef LIB_CORE_RENDER_SCALE_GLSL
#define LIB_CORE_RENDER_SCALE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// TAAU renders the scene into the lower-left rectangle of the display-sized
// allocations while projection UVs stay [0, 1]. The helpers below exist only
// under TAAU_ACTIVE; without TAAU the scene fills the whole allocation, so
// every consumer skips the call and uses its coordinate directly.

#if defined(TAAU_ACTIVE)

vec2 SceneTextureUV(vec2 screen_uv) {
    return clamp(screen_uv * u_render_scale, 0.5 * u_view_pixel_size,
        (u_render_res - 0.5) * u_view_pixel_size);
}

vec2 SceneImageUV(vec2 screen_uv, vec2 allocation_size, float image_scale) {
    vec2 active_size = max(floor(u_render_res * image_scale), vec2(1.0));
    return clamp(screen_uv * active_size, vec2(0.5), active_size - 0.5) / allocation_size;
}

vec4 ScaleSceneClipPosition(vec4 clip_position) {
    clip_position.xy = (clip_position.xy + clip_position.w) * u_render_scale - clip_position.w;
    return clip_position;
}

bool OutsideSceneRender(vec2 pixel_position) {
    return any(greaterThanEqual(pixel_position, u_render_res));
}

#endif // TAAU_ACTIVE

#endif // LIB_CORE_RENDER_SCALE_GLSL
