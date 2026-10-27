#ifndef LIB_GEOMETRY_NORMAL_CLAMP_GLSL
#define LIB_GEOMETRY_NORMAL_CLAMP_GLSL

#include "/lib/core/math_scalar.glsl"

// Soft-clamps a shading normal against the view ray: ndotv below
// SHADING_NORMAL_CLAMP_KNEE is remapped through a C1 quadratic knee (slope 1
// at the knee, slope 0 at the floor), so the view-facing component of the
// returned normal never drops below SHADING_NORMAL_MIN_NDOTV while the
// component perpendicular to the view ray keeps its direction. The remap is
// active for ndotv in
// [2 * SHADING_NORMAL_MIN_NDOTV - SHADING_NORMAL_CLAMP_KNEE,
//  SHADING_NORMAL_CLAMP_KNEE] and the identity outside it. shading_normal
// and view_to_eye are unit vectors in one shared space.
const float SHADING_NORMAL_CLAMP_KNEE = 0.375;
const float SHADING_NORMAL_MIN_NDOTV = 1.0 / 64.0;

vec3 SoftClampShadingNormalToView(vec3 shading_normal, vec3 view_to_eye) {
    float knee_to_floor = SHADING_NORMAL_CLAMP_KNEE - SHADING_NORMAL_MIN_NDOTV;
    float ndotv = dot(shading_normal, view_to_eye);
    float t = saturate((ndotv + knee_to_floor - SHADING_NORMAL_MIN_NDOTV)
        * (0.5 / knee_to_floor));
    float ndotv_clamped = max(ndotv,
        SHADING_NORMAL_MIN_NDOTV + knee_to_floor * (t * t));
    return normalize(shading_normal + view_to_eye * (ndotv_clamped - ndotv));
}

#endif // LIB_GEOMETRY_NORMAL_CLAMP_GLSL
