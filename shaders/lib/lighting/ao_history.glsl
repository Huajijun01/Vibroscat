#ifndef LIB_LIGHTING_AO_HISTORY_GLSL
#define LIB_LIGHTING_AO_HISTORY_GLSL

// Geometry-only colortex8 R codec. Four bilinear weights on the half-res
// lattice reconstruct quarter steps of an UNORM8 value. Integers 0..1020
// preserve those steps exactly in RGBA16F, avoiding biased format conversion
// on every trip through the temporal feedback loop. Sky keeps cloud radiance.
float EncodeAOHistory(float ao) {
    return floor(clamp(ao, 0.0, 1.0) * 1020.0 + 0.5);
}

float DecodeAOHistory(float encoded) {
    return encoded * (1.0 / 1020.0);
}

#endif // LIB_LIGHTING_AO_HISTORY_GLSL
