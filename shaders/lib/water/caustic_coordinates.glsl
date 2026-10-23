#ifndef LIB_WATER_CAUSTIC_COORDINATES_GLSL
#define LIB_WATER_CAUSTIC_COORDINATES_GLSL

// Shared by the full-resolution receiver caustics and their low-pass volume
// sibling. Generated from the same Phillips waves: 8 m cell, 4 s evolution,
// river layer 2 carrier. The fixed plane anchors columns as the camera moves.
const mat2 CAUSTIC_ABSOLUTE_TO_UV = mat2(0.125, 0.0, 0.0, 0.125);
const vec2 CAUSTIC_ADVECTION_MPS = vec2(0.86140636021, 0.23905094417);
const float CAUSTIC_PLANE_Y = 64.0;

#endif // LIB_WATER_CAUSTIC_COORDINATES_GLSL
