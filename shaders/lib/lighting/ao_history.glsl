#ifndef LIB_LIGHTING_AO_HISTORY_GLSL
#define LIB_LIGHTING_AO_HISTORY_GLSL

#include "/lib/core/math_scalar.glsl"

// colortex8 R codec: integers 0..1020 in RGBA16F keep quarter steps of UNORM8
// exact through the temporal feedback loop; sky stores cloud radiance.
float EncodeAOHistory(float ao) {
    return floor(saturate(ao) * 1020.0 + 0.5);
}

float DecodeAOHistory(float encoded) {
    return encoded * (1.0 / 1020.0);
}

#endif // LIB_LIGHTING_AO_HISTORY_GLSL
