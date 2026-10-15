#ifndef LIB_LIGHTING_AMBIENT_OCCLUSION_GLSL
#define LIB_LIGHTING_AMBIENT_OCCLUSION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/lighting/ao_history.glsl"

// Shared response for standalone AO and RSM's receiver-local estimate.
// Accumulate the standalone raw field first; RSM filters AO-weighted sky
// irradiance together with its bounce instead of filtering AO separately.
vec3 ApplySurfaceAO(inout float screen_ao, vec3 albedo) {
    screen_ao = clamp(screen_ao, 0.0, 1.0);
    // The strengths are setting literals: at the default 1.0 the pow is an
    // SFU round trip on the identity, so gate it on the constant instead.
#if AO_MODE == 2
    if (SSAO_STRENGTH != 1.0) screen_ao = pow(screen_ao, SSAO_STRENGTH);
#else
    if (GTAO_STRENGTH != 1.0) screen_ao = pow(screen_ao, GTAO_STRENGTH);
#endif
#ifdef GTAO_MULTIBOUNCE
    // Jimenez et al. 2016, albedo-dependent multiple-bounce AO.
    vec3 a = 2.0404 * albedo - 0.3324;
    vec3 b = -4.7951 * albedo + 0.6417;
    vec3 c = 2.7552 * albedo + 0.6903;
    return max(vec3(screen_ao), ((screen_ao * a + b) * screen_ao + c) * screen_ao);
#endif
    return vec3(screen_ao);
}

// GI owns diffuse visibility. Its lighting must not sample the standalone
// AO history, apply vertex AO again, or attenuate the reconstructed bounce.
vec3 ResolveSurfaceAO(ivec2 texel, vec3 albedo, float vertex_ao, bool is_hand, out float screen_ao) {
    screen_ao = 1.0;
#if GI_MODE != 0
    return vec3(1.0);
#else
    if (is_hand) return vec3(1.0);
#if defined(GTAO) || defined(SSAO)
    screen_ao = DecodeAOHistory(texelFetch(colortex8, texel, 0).r);
    return ApplySurfaceAO(screen_ao, albedo);
#else
    return vec3(vertex_ao);
#endif
#endif
}

#endif // LIB_LIGHTING_AMBIENT_OCCLUSION_GLSL
