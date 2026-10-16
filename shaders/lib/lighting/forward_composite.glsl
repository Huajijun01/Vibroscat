#ifndef LIB_LIGHTING_FORWARD_COMPOSITE_GLSL
#define LIB_LIGHTING_FORWARD_COMPOSITE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/lighting/lightmap.glsl"

// Forward translucent energy composition: the three BRDF factors returned by
// EvaluateBRDF (lib/lighting/brdf.glsl) weighted by the sun shadow, the sky
// ambient and the torch term. This file owns the single copy of the expression
// shared by the two forward stations: the gbuffers_water non-glass arm
// (program/gbuffer/translucent.fragment) and the hand/particles
// translucent_lite path (program/gbuffer/translucent_lite.fragment).
// deferred_shading.fragment keeps its own variant: its torch term carries an
// extra screen-space AO factor.
//
// The BRDF factors are passed in rather than evaluated here because the two
// call sites legitimately need different EvaluateBRDF overloads (particles must
// never read the specular atlas) and the atlas gate that chooses between them
// is owned by lib/lighting/brdf.glsl. Evaluating the BRDF here would push that
// gate back into both program files as a third and fourth copy, so the helper
// takes exactly the composition's inputs. The torch weight is derived here
// instead: both call sites repeated that lightmap step verbatim.
//
// lm_block is the vanilla lightmap block-light coordinate on [0, 1] after
// RemapVanillaLightmap (v_texcoord.z in the forward passes). All other
// parameters are the outputs of EvaluateBRDF and the per-light weights; N, V
// and L must already share one space (view space in the gbuffer passes).
vec3 ComposeForwardLitSurface(vec3 direct_lighting, vec3 lambert_brdf, vec3 diffuse_reflectance,
        float shadow_visibility, vec3 sun_light_col, vec3 ambient_col, float lm_block) {
    float torch_light = BlockLightFromLm(lm_block);
    return direct_lighting * sun_light_col * shadow_visibility + lambert_brdf * ambient_col
        + diffuse_reflectance * TORCH_LIGHT_COLOR * torch_light;
}

#endif // LIB_LIGHTING_FORWARD_COMPOSITE_GLSL
