#ifndef LIB_CONTRACT_DOF_DATA_GLSL
#define LIB_CONTRACT_DOF_DATA_GLSL

// Binding 2: four scalars, 16 bytes. Focus slots alternate by frame parity;
// the compute reads only the previous slot and publishes only the current.
// Spatial DOF data lives in the existing colortex12 workspace.
layout(std430, binding = 2) buffer DofData {
    float dof_focus_inverse_m[2];
    float dof_focus_change_px;
    uint dof_focus_frame;
};

#endif // LIB_CONTRACT_DOF_DATA_GLSL
