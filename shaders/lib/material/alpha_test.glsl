#ifndef LIB_MATERIAL_ALPHA_TEST_GLSL
#define LIB_MATERIAL_ALPHA_TEST_GLSL

#include "/lib/contract/uniforms.glsl"

// Iris does not inject an alpha test into fragment shaders with explicit out variables, so
// alphaTestRef (contract/uniforms.glsl) is the reference. Callers test texture alpha only,
// never the vertex-color tint; min(..., 1.0) guards the entity variant whose reference is FLT_MAX.
void DiscardBelowAlphaTest(float texture_alpha, float reference_floor) {
    if (texture_alpha < max(reference_floor, min(alphaTestRef, 1.0))) discard;
}

#endif
