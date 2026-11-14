#ifndef LIB_GEOMETRY_NORMAL_CLAMP_GLSL
#define LIB_GEOMETRY_NORMAL_CLAMP_GLSL

#include "/lib/core/math_scalar.glsl"

// C1 quadratic knee (slope 1 at the knee, 0 at the floor): ndotv never drops below
// SHADING_NORMAL_MIN_NDOTV, identity outside the knee interval. Inputs are unit vectors, one space.
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
