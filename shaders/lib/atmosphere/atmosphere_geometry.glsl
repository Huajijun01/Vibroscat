#ifndef LIB_ATMOSPHERE_ATMOSPHERE_GEOMETRY_GLSL
#define LIB_ATMOSPHERE_ATMOSPHERE_GEOMETRY_GLSL

#include "/lib/contract/uniforms.glsl"

// Shared kilometer-space geometry contract for atmosphere and volumetric media.
const float ATM_PLANET_R = 6360.0;
const float ATM_ATMO_R = 6480.0;
const float ATM_PLANET_R2 = ATM_PLANET_R * ATM_PLANET_R;
const float ATM_ATMO_R2 = ATM_ATMO_R * ATM_ATMO_R;
// Shell thickness and derived reciprocals used by the density and LUT's geometry.
const float ATM_H = sqrt(ATM_ATMO_R2 - ATM_PLANET_R2);
const float ATM_ATMO_MINUS_P = ATM_ATMO_R - ATM_PLANET_R;
const float ATM_RCP_ATMO_MINUS_P = 1.0 / ATM_ATMO_MINUS_P;

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

// True when `dir` from `origin` (planet-centered, r2 = dot(origin, origin))
// dips below the planet of radius squared `planet_r2`: light from that
// direction is planet-occluded. Near root only (no far root).
bool PlanetHorizonOccluded(vec3 origin, float origin_r2, vec3 dir, float planet_r2) {
    float b = 2.0 * dot(origin, dir);
    float c = origin_r2 - planet_r2;
    float discriminant = b * b - 4.0 * c;
    if (discriminant <= 0.0) return false;

    float ground_near = 0.5 * (-b - sqrt(discriminant));
    return ground_near > 1.0e-5;
}

#endif // LIB_ATMOSPHERE_ATMOSPHERE_GEOMETRY_GLSL
