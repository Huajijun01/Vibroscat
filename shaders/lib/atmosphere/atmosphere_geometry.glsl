#ifndef LIB_ATMOSPHERE_ATMOSPHERE_GEOMETRY_GLSL
#define LIB_ATMOSPHERE_ATMOSPHERE_GEOMETRY_GLSL

#include "/lib/contract/uniforms.glsl"

// Shared kilometer-space geometry contract for atmosphere and volumetric media.
const float ATM_PLANET_R = 6360.0;
const float ATM_ATMO_R = 6480.0;
const float ATM_PLANET_R2 = ATM_PLANET_R * ATM_PLANET_R;
const float ATM_ATMO_R2 = ATM_ATMO_R * ATM_ATMO_R;

// Camera position in atmosphere kilometer space (planet-centered, +Y up):
// the camera sits at ATM_PLANET_R + camera altitude above the planet center.
vec3 AtmosphereCameraPosition() {
    return vec3(0.0, ATM_PLANET_R + u_cam_altitude, 0.0);
}

bool RayIntersectSphere(vec3 origin, vec3 dir, float radius, out float t0, out float t1) {
    float b = 2.0 * dot(origin, dir);
    float c = dot(origin, origin) - radius * radius;
    float discriminant = b * b - 4.0 * c;
    if (discriminant <= 0.0) return false;

    float root = sqrt(discriminant);
    t0 = 0.5 * (-b - root);
    t1 = 0.5 * (-b + root);
    return true;
}

#endif
