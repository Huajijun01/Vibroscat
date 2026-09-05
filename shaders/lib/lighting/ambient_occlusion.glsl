#ifndef LIB_LIGHTING_AMBIENT_OCCLUSION_GLSL
#define LIB_LIGHTING_AMBIENT_OCCLUSION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Shared by GI generation and deferred lighting. The RGB result controls
// the sky's directional blend and final diffuse AO; scalar AO lights torches.
vec3 ResolveSurfaceAO(ivec2 texel, vec3 albedo, float vertex_ao, bool is_hand, out float screen_ao) {
    screen_ao = 1.0;
    if (is_hand) return vec3(1.0);
#if defined(GTAO) || defined(SSAO)
    screen_ao = clamp(texelFetch(colortex8, texel, 0).r, 0.0, 1.0);
#ifdef SSAO
    screen_ao = pow(screen_ao, SSAO_STRENGTH);
#else
    screen_ao = pow(screen_ao, GTAO_STRENGTH);
#endif
    if (GTAO_MULTIBOUNCE) {
        // Jimenez et al. 2016, albedo-dependent multiple-bounce AO.
        vec3 a = 2.0404 * albedo - 0.3324;
        vec3 b = -4.7951 * albedo + 0.6417;
        vec3 c = 2.7552 * albedo + 0.6903;
        return max(vec3(screen_ao), ((screen_ao * a + b) * screen_ao + c) * screen_ao);
    }
    return vec3(screen_ao);
#else
    return vec3(vertex_ao);
#endif
}

#endif // LIB_LIGHTING_AMBIENT_OCCLUSION_GLSL
