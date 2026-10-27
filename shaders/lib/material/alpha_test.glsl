#ifndef LIB_MATERIAL_ALPHA_TEST_GLSL
#define LIB_MATERIAL_ALPHA_TEST_GLSL

#include "/lib/contract/uniforms.glsl"

// Iris never injects an alpha test into a fragment shader that writes its
// outputs through explicit out variables; the alphaTest.<program> directive
// then only selects the reference value that the alphaTestRef uniform carries
// (contract/uniforms.glsl). Every alpha-tested gbuffer fragment applies this
// helper to the sampled texture alpha alone: the texture's alpha channel is
// the coverage mask the reference was set for, and the vertex color is a tint
// that must never scale the tested value.
//
// The floor argument keeps alpha == 0 texels culled when the effective test is
// off (reference 0.0). The clamp guards the vertex-alpha entity variant, whose
// reference Iris reports as FLT_MAX.
void DiscardBelowAlphaTest(float texture_alpha, float reference_floor) {
    if (texture_alpha < max(reference_floor, min(alphaTestRef, 1.0))) discard;
}

#endif
