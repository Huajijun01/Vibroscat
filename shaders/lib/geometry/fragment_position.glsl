#ifndef LIB_GEOMETRY_FRAGMENT_POSITION_GLSL
#define LIB_GEOMETRY_FRAGMENT_POSITION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// No depth fetch: valid for the world gbuffer projection only (symmetric form, clip.w = -view.z,
// so gl_FragCoord.w recovers view depth). u_render_pixel_size already handles TAAU scaling;
// TAA jitter is subtracted here because the vertex stage added it to clip XY, not the matrix.
vec3 ReconstructGbufferViewPosition(vec4 frag_coord) {
    vec2 ndc_xy = frag_coord.xy * u_render_pixel_size * 2.0 - 1.0;
#ifdef TAA
    ndc_xy -= u_taa_offset;
#endif
    vec2 inverse_diagonal = vec2(gbufferProjectionInverse[0][0],
        gbufferProjectionInverse[1][1]);
    return vec3(ndc_xy * inverse_diagonal, -1.0) / frag_coord.w;
}

#endif // LIB_GEOMETRY_FRAGMENT_POSITION_GLSL
