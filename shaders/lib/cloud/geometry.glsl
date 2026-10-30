#ifndef LIB_CLOUD_GEOMETRY_GLSL
#define LIB_CLOUD_GEOMETRY_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"

bool CloudShellInterval(vec3 origin_km, vec3 direction_world, out float march_start_km, out float march_end_km
) {
    float inner_radius = ATM_PLANET_R + CLOUD_BASE_ALTITUDE;
    float outer_radius = ATM_PLANET_R + CLOUD_TOP_ALTITUDE;
    // The three RayIntersectSphere solves below share b and dot(origin_km,
    // origin_km); each solve keeps that function's exact operation sequence, so
    // every output stays bit-identical while both dot products run once.
    float b = 2.0 * dot(origin_km, direction_world);
    float origin_r2 = dot(origin_km, origin_km);

    float outer_c = origin_r2 - outer_radius * outer_radius;
    float outer_discriminant = b * b - 4.0 * outer_c;
    if (outer_discriminant <= 0.0) {
        return false;
    }
    float outer_root = sqrt(outer_discriminant);
    float outer_near = 0.5 * (-b - outer_root);
    float outer_far = 0.5 * (-b + outer_root);
    march_start_km = max(outer_near, 0.0);
    march_end_km = outer_far;

    float inner_r2 = inner_radius * inner_radius;
    float inner_c = origin_r2 - inner_r2;
    float inner_discriminant = b * b - 4.0 * inner_c;
    if (inner_discriminant > 0.0) {
        float inner_root = sqrt(inner_discriminant);
        float inner_near = 0.5 * (-b - inner_root);
        float inner_far = 0.5 * (-b + inner_root);
        // Non-negative radii: the squared form selects identically and the
        // side comparison is not part of the root sequence above.
        if (origin_r2 < inner_r2) {
            march_start_km = max(march_start_km, inner_far);
        } else if (inner_near > march_start_km) {
            march_end_km = min(march_end_km, inner_near);
        }
    }

    float ground_c = origin_r2 - ATM_PLANET_R * ATM_PLANET_R;
    float ground_discriminant = b * b - 4.0 * ground_c;
    if (ground_discriminant > 0.0) {
        float ground_root = sqrt(ground_discriminant);
        float ground_near = 0.5 * (-b - ground_root);
        float ground_far = 0.5 * (-b + ground_root);
        if (ground_near > 0.0) {
            march_end_km = min(march_end_km, ground_near);
        }
    }

    return march_end_km > march_start_km + 1.0e-5;
}

float CloudDistanceToShellExit(vec3 position_km, vec3 direction_world) {
    // The two shell solves share b and dot(position_km, position_km); per-sphere
    // operations match RayIntersectSphere exactly, so the sweep is
    // bit-identical to the separate calls (the fused form does not compute
    // the unused inner far root).
    float b = 2.0 * dot(position_km, direction_world);
    float origin_r2 = dot(position_km, position_km);
    float outer_radius = ATM_PLANET_R + CLOUD_TOP_ALTITUDE;
    float outer_c = origin_r2 - outer_radius * outer_radius;
    float outer_discriminant = b * b - 4.0 * outer_c;
    if (outer_discriminant <= 0.0) {
        return 0.0;
    }
    float outer_root = sqrt(outer_discriminant);
    float outer_far = 0.5 * (-b + outer_root);
    float distance_to_exit = max(outer_far, 0.0);

    float inner_radius = ATM_PLANET_R + CLOUD_BASE_ALTITUDE;
    float inner_c = origin_r2 - inner_radius * inner_radius;
    float inner_discriminant = b * b - 4.0 * inner_c;
    if (inner_discriminant > 0.0) {
        float inner_root = sqrt(inner_discriminant);
        float inner_near = 0.5 * (-b - inner_root);
        if (inner_near > 1.0e-5) {
            distance_to_exit = min(distance_to_exit, inner_near);
        }
    }
    return distance_to_exit;
}

#endif // LIB_CLOUD_GEOMETRY_GLSL
