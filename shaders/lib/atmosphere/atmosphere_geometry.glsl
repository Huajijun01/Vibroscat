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
const float ATM_RCP_H = 1.0 / ATM_H;
const float ATM_ATMO_MINUS_P = ATM_ATMO_R - ATM_PLANET_R;
const float ATM_RCP_ATMO_MINUS_P = 1.0 / ATM_ATMO_MINUS_P;

// Multiscatter LUT bake geometry. The asset's V axis spans the signed bake
// altitude range [-(dip), ATM_ATMO_MINUS_P] linearly, so its 32 row centers
// sit at -6, -2, 2, ..., 118 km. This is the depth the offline baker used, not
// the user's ATM_HORIZON_DIP_SCALE: that setting moves the runtime march
// bound, while this asset addressing must stay fixed. Keep it paired with
// sky-baker pack finalize and the bake manifest.
const float ATM_MS_BAKE_DIP_KM = 8.0;
const float ATM_MS_SPAN_KM = ATM_ATMO_MINUS_P + ATM_MS_BAKE_DIP_KM;
const float ATM_MS_RCP_SPAN = 1.0 / ATM_MS_SPAN_KM;

// Camera position in atmosphere kilometer space (planet-centered, +Y up):
// the camera sits at ATM_PLANET_R + camera altitude above the planet center.
vec3 AtmosphereCameraPosition() {
    return u_atmosphere_camera_pos;
}

// Half-discriminant quadratic form: b = dot(o,d), disc = b*b - c, roots
// -b ± sqrt(disc). Every eliminated factor is an exact power of two, and
// scaling by powers of two commutes with IEEE rounding and sqrt exactly
// (RN(4x) = 4*RN(x), sqrt(4x) = 2*sqrt(x)), so t0/t1 and the disc <= 0
// predicate are bit-identical to the doubled form. Comparisons keep the
// original unscaled thresholds: the half-form roots equal the old values.
bool RayIntersectSphere(vec3 origin, vec3 dir, float radius, out float t0, out float t1) {
    float b = dot(origin, dir);
    float c = dot(origin, origin) - radius * radius;
    float discriminant = b * b - c;
    if (discriminant <= 0.0) return false;

    float root = sqrt(discriminant);
    t0 = -b - root;
    t1 = -b + root;
    return true;
}

// True when `dir` from `origin` (planet-centered, r2 = dot(origin, origin))
// dips below the planet of radius squared `planet_r2`: light from that
// direction is planet-occluded. Near root only (no far root). Same
// half-discriminant form and bit-equivalence argument as RayIntersectSphere;
// the 1.0e-5 threshold applies to the root itself and is unchanged.
bool PlanetHorizonOccluded(vec3 origin, float origin_r2, vec3 dir, float planet_r2) {
    float b = dot(origin, dir);
    float c = origin_r2 - planet_r2;
    float discriminant = b * b - c;
    if (discriminant <= 0.0) return false;

    float ground_near = -b - sqrt(discriminant);
    return ground_near > 1.0e-5;
}

#endif // LIB_ATMOSPHERE_ATMOSPHERE_GEOMETRY_GLSL
