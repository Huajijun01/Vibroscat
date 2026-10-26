#ifndef LIB_GEOMETRY_FRAGMENT_POSITION_GLSL
#define LIB_GEOMETRY_FRAGMENT_POSITION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Reconstructs the current fragment's gbuffer view-space position from its
// window coordinates alone; no depth texture is read. The pack's world
// projection is the symmetric perspective form documented in
// lib/core/coordinates.glsl with clip.w = -view.z, so gl_FragCoord.w (the
// reciprocal clip w) recovers the view depth without a depth fetch:
// view = (ndc * inverse projection diagonal, -1) / frag_coord.w.
// u_render_pixel_size already maps the TAAU active scene rectangle onto
// projection UVs, so render-pixel NDC needs no extra render-scale division.
// The TAA jitter is subtracted once here because the vertex stage added it to
// clip XY directly, never to the matrix. Valid for the world gbuffer
// projection only: the hand keeps a full projection product and the shadow
// pass is orthographic with warped XY.
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
