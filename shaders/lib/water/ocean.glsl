#ifndef LIB_WATER_OCEAN_GLSL
#define LIB_WATER_OCEAN_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/water/river_texture.glsl"

// Parallax occlusion mapping for the water surface: the normal is
// evaluated at the parallax-corrected position. The WATER_POM option lives
// in contract/settings.glsl (LOW profile disables it; the normal then comes
// from the flat-surface variant without a march).

// The POM search is a coarse march refined by bisection; the step budgets
// (WATER_POM_COARSE_STEPS / _BISECT_STEPS) are user options declared in
// contract/settings.glsl.

// Faces with |world normal.y| above this take the horizontal wave path
// (height field over absolute XZ + POM). At or below, the face is vertical:
// the same wave field is re-parameterized on the face plane through the
// geometry TBN, without POM (its march displaces along world vertical).
// Minecraft water geometry is axis aligned, so 0.5 separates the two.
const float WATER_HORIZONTAL_FACE_MIN_Y = 0.5;

// ---- parallax occlusion mapping ----
// Chase the selected mode's largest-energy height layers: 2 fetches per
// sample for small waves, 3 for medium-large waves. The final normal uses
// all 3 or 5 layers.
// Bound both extrema of the selected POM field at every supported gain.
const float OCEAN_POM_MAX_DEPTH = RIVER_TEX_POM_AMPLITUDE * RIVER_TEX_POM_GAIN
                              * max(RIVER_TEX_CENTER, 1.0 - RIVER_TEX_CENTER);
const float OCEAN_POM_MAX_OFFSET = 2.0; // m, clamp grazing offsets
const float OCEAN_POM_MIN_SHIFT = 0.05; // m, skip invisible shifts

// Ray/surface intersection: for a camera above the water (view.y < 0) the
// visible point satisfies h(xz0 + d*dir) = d (dir = view.xz/view.y toward
// camera; bumps displace toward camera, troughs away). Scan from the camera
// side; none found -> keep the plane sample (no over-shift on flat water).
// Bisection refines the coarse crossing (fewer coarse steps for equal or
// better accuracy than a fixed-step scan).
vec2 OceanPOMOffsetBisection(vec2 xz, vec3 view_world, float time) {
    if (view_world.y >= 0.0) {
        return xz; // underwater view: no parallax correction
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
            // f(depthA) <= 0, f(depthB) > 0: bisection inside the bracket.
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

// World-space normal (y up) at the parallax-corrected position. WATER_POM
// owns the parallax march; without it the flat-surface variant evaluates the
// normal directly at the warped plane position.
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
