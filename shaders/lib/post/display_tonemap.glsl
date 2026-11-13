#ifndef LIB_POST_DISPLAY_TONEMAP_GLSL
#define LIB_POST_DISPLAY_TONEMAP_GLSL

#include "/lib/contract/exposure_data.glsl"
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/color/purkinje.glsl"
#include "/lib/color/tonemap.glsl"

// Shared display mapping for the composite21 and fused final callers. Returns
// the display-linear result of the selected operator; storage or output
// jitter and the sRGB OETF stay with each caller.
vec3 ApplyDisplayTonemap(vec2 uv) {
    // Motion blur leaves the display color in colortex0; otherwise it exists
    // only in colortex5.
#ifdef MOTION_BLUR
    vec3 hdr = texture(colortex0, uv).rgb;
#else
    vec3 hdr = texture(colortex5, uv).rgb;
#endif

#ifdef BLOOM
    // One final bilinear fetch, aligned with the half-resolution tent chain.
    // Clamp to tile centers so adjacent atlas tiles cannot bleed in.
    vec2 bloom_uv = uv * 0.5;
    bloom_uv = clamp(bloom_uv, 0.5 * u_view_pixel_size, u_bloom_max_uv);
    hdr += texture(colortex12, bloom_uv).rgb * BLOOM_STRENGTH * (1.0 / 7.0);
#endif
    hdr *= exp2(TONEMAP_EXPOSURE);
#ifdef AE
    hdr *= exposure;
#endif
// The scotopic shift requires AE. PURKINJE_EFFECT is registered in settings.glsl.
#ifdef PURKINJE_EFFECT
#ifdef AE
    float adapted_key_lum = AE_TARGET_LUMINANCE * exp2(-adapted_exposure_ev);
    hdr = ApplyPurkinjeEffect(hdr, adapted_key_lum);
#endif
#endif
    return Tonemap(hdr);
}

#endif // LIB_POST_DISPLAY_TONEMAP_GLSL
