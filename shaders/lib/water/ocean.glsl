#ifndef LIB_WATER_OCEAN_GLSL
#define LIB_WATER_OCEAN_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/water/river_texture.glsl"

// Faces with |world normal.y| above this take the height-field + POM path, vertical faces
// re-parameterize the same field via the geometry TBN (axis-aligned geometry, so 0.5 splits).
const float WATER_HORIZONTAL_FACE_MIN_Y = 0.5;

// Bounds both extrema of the selected POM field at every supported gain.
const float OCEAN_POM_MAX_DEPTH = RIVER_TEX_POM_AMPLITUDE * RIVER_TEX_POM_GAIN
                              * max(RIVER_TEX_CENTER, 1.0 - RIVER_TEX_CENTER);
const float OCEAN_POM_MAX_OFFSET = 2.0; // m, clamp grazing offsets
const float OCEAN_POM_MIN_SHIFT = 0.05; // m, skip invisible shifts

// First crossing of h(xz + d*dir) = d, scanning from the camera side; bumps
// displace toward the camera.
vec2 OceanPOMOffsetBisection(vec2 xz, vec3 view_world, float time) {
    if (view_world.y >= 0.0) {
        return xz; // underwater view
    }
    vec2 dir = view_world.xz / view_world.y;
    float dir_len = length(dir);
    if (dir_len * OCEAN_POM_MAX_DEPTH < OCEAN_POM_MIN_SHIFT) {
        return xz;
    }
    if (dir_len * OCEAN_POM_MAX_DEPTH > OCEAN_POM_MAX_OFFSET) {
        dir *= OCEAN_POM_MAX_OFFSET / (dir_len * OCEAN_POM_MAX_DEPTH);
    }

    float step_depth = 2.0 * OCEAN_POM_MAX_DEPTH / float(WATER_POM_COARSE_STEPS);
    float depth_a = OCEAN_POM_MAX_DEPTH;
    float height_a = RiverTexturePOMHeight(xz + dir * depth_a, time);
    for (int i = 1; i <= WATER_POM_COARSE_STEPS; ++i) {
        float depth_b = OCEAN_POM_MAX_DEPTH - step_depth * float(i);
        float height_b = RiverTexturePOMHeight(xz + dir * depth_b, time);
        if (height_a <= depth_a && height_b > depth_b) {
            for (int j = 0; j < WATER_POM_BISECT_STEPS; ++j) {
                float depth_m = 0.5 * (depth_a + depth_b);
                float height_m = RiverTexturePOMHeight(xz + dir * depth_m, time);
                if (height_m <= depth_m) {
                    depth_a = depth_m;
                    height_a = height_m;
                } else {
                    depth_b = depth_m;
                    height_b = height_m;
                }
            }
            float f_a = height_a - depth_a;
            float f_b = height_b - depth_b;
            float t = saturate(f_a / (f_a - f_b));
            return xz + dir * mix(depth_a, depth_b, t);
        }
        depth_a = depth_b;
        height_a = height_b;
    }
    return xz;
}

#ifdef WATER_POM
void OceanSurfacePOM(vec2 xz, vec3 view_world, float time, out vec3 normal) {
    xz = RiverTextureWarpPosition(xz);
    vec2 xz_offset = OceanPOMOffsetBisection(xz, view_world, time);
    RiverTextureNormal(xz_offset, time, normal);
}
#else
void OceanFlatNormal(vec2 xz, float time, out vec3 normal) {
    xz = RiverTextureWarpPosition(xz);
    RiverTextureNormal(xz, time, normal);
}
#endif

#endif // LIB_WATER_OCEAN_GLSL
