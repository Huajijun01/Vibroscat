#ifndef LIB_CONTRACT_DOF_DATA_GLSL
#define LIB_CONTRACT_DOF_DATA_GLSL

// Binding 2: four scalars, 16 bytes. Only autofocus is persistent here;
// spatial DOF data lives in the existing colortex12 workspace.
layout(std430, binding = 2) buffer DofData {
    float dof_focus_inverse_m;
    float dof_focus_change_px;
    float dof_target_inverse_m;
    uint dof_focus_frame;
};

#endif // LIB_CONTRACT_DOF_DATA_GLSL
