#ifndef LIB_CORE_RENDER_SCALE_GLSL
#define LIB_CORE_RENDER_SCALE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Before composite4, screen attachments use the lower-left render rectangle
// of their unchanged display-sized allocation. Projection UVs remain [0, 1].
vec2 SceneTextureUV(vec2 screen_uv) {
#ifdef TAAU_ACTIVE
    return clamp(screen_uv * u_render_scale, 0.5 * u_view_pixel_size,
        (u_render_res - 0.5) * u_view_pixel_size);
#else
    return screen_uv;
#endif
}

vec2 SceneImageUV(vec2 screen_uv, vec2 allocation_size, float image_scale) {
#ifdef TAAU_ACTIVE
    vec2 active_size = max(floor(u_render_res * image_scale), vec2(1.0));
    return clamp(screen_uv * active_size, vec2(0.5), active_size - 0.5) / allocation_size;
#else
    return screen_uv;
#endif
}

vec4 ScaleSceneClipPosition(vec4 clip_position) {
#ifdef TAAU_ACTIVE
    clip_position.xy = (clip_position.xy + clip_position.w) * u_render_scale - clip_position.w;
#endif
    return clip_position;
}

bool OutsideSceneRender(vec2 pixel_position) {
#ifdef TAAU_ACTIVE
    return any(greaterThanEqual(pixel_position, u_render_res));
#else
    return false;
#endif
}

#endif // LIB_CORE_RENDER_SCALE_GLSL
