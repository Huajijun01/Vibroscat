#ifndef LIB_WATER_OCEAN_GLSL
#define LIB_WATER_OCEAN_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/water/value_noise.glsl"

// Parallax occlusion mapping for the water surface: the normal is
// evaluated at the parallax-corrected position. The WATER_POM option lives
// in contract/settings.glsl (LOW profile disables it; the normal then falls
// back to the plane position).

// POM search mode: 0 = fixed-step linear, 1 = coarse + bisection (same or
// fewer height samples, tighter root; wave field and normals unchanged).
// The step budgets (WATER_POM_COARSE_STEPS / _BISECT_STEPS) are user
// options declared in contract/settings.glsl.
#define POM_BISECTION_ENABLED 1

// Soft-clamp the normal toward the camera (no hard clamp): avoids
// grazing-angle flips and degenerate reflection/refraction cases.
const float WATER_NORMAL_CLAMP_RANGE = 0.25;
const float WATER_NORMAL_CLAMP_STRENGTH = 0.75;
vec3 SoftClampWaterNormal(vec3 normal, vec3 to_camera) {
    float ndotv = dot(normal, to_camera);
    float t = smoothstep(0.0, WATER_NORMAL_CLAMP_RANGE, -ndotv);
    return normalize(mix(normal, to_camera, t * WATER_NORMAL_CLAMP_STRENGTH));
}

// ---- parallax occlusion mapping ----
// Bounded height chase on the 4 largest-amplitude waves (cheap bilinear
// fetch); the final normal uses the full 8-layer field. Linear crossing by
// default; POM_BISECTION_ENABLED refines with bisection.
const int OCEAN_POM_LAYERS = 4;
const int OCEAN_POM_WAVES[OCEAN_POM_LAYERS] = int[](1, 0, 3, 2);
const int OCEAN_POM_STEPS = 8;
const float OCEAN_POM_MAX_DEPTH = 0.6;  // m, >= max fitted crest (0.433)
const float OCEAN_POM_MAX_OFFSET = 2.0; // m, clamp grazing offsets
const float OCEAN_POM_MIN_SHIFT = 0.05; // m, skip invisible shifts

float OceanValueNoisePOMHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int i = 0; i < OCEAN_POM_LAYERS; ++i) {
        OceanWave w = OCEAN_WAVES[OCEAN_POM_WAVES[i]];
        vec2 r = vec2(dot(w.uv.xy, xz), dot(w.uv.zw, xz));
        r.x += w.omega * time;
        h += w.amplitude * (OceanWaveNoiseFast(r) - 0.5);
    }
    return h;
}

// Ray/surface intersection: for a camera above the water (view.y < 0) the
// visible point satisfies h(xz0 + d*dir) = d (dir = view.xz/view.y toward
// camera; bumps displace toward camera, troughs away). Scan from the camera
// side, interpolate the first crossing; none found -> keep the plane sample
// (no over-shift on flat water).
vec2 OceanPOMOffset(vec2 xz, vec3 view_world, float time) {
    if (view_world.y >= 0.0) {
        return xz; // underwater view: no parallax correction
    }
    // viewWorld.y < 0 here, so this points towards the camera
    vec2 dir = view_world.xz / view_world.y;
    float dir_len = length(dir);
    if (dir_len * OCEAN_POM_MAX_DEPTH < OCEAN_POM_MIN_SHIFT) {
        return xz; // near-vertical view: parallax shift is invisible
    }
    if (dir_len * OCEAN_POM_MAX_DEPTH > OCEAN_POM_MAX_OFFSET) {
        // grazing view: keep the whole search inside the offset budget
        dir *= OCEAN_POM_MAX_OFFSET / (dir_len * OCEAN_POM_MAX_DEPTH);
    }
    float step_depth = 2.0 * OCEAN_POM_MAX_DEPTH / float(OCEAN_POM_STEPS);
    float depth_prev = OCEAN_POM_MAX_DEPTH;
    float height_prev = OceanValueNoisePOMHeight(xz + dir * depth_prev, time);
    for (int i = 1; i <= OCEAN_POM_STEPS; ++i) {
        float pom_depth = OCEAN_POM_MAX_DEPTH - step_depth * float(i);
        float height = OceanValueNoisePOMHeight(xz + dir * pom_depth, time);
        // The ray enters the water when f = h - d crosses from <= 0 to > 0.
        if (height_prev <= depth_prev && height > pom_depth) {
            float height_diff_prev = height_prev - depth_prev;
            float height_diff_curr = height - pom_depth;
            float t = Saturate(height_diff_prev / (height_diff_prev - height_diff_curr));
            return xz + dir * mix(depth_prev, pom_depth, t);
        }
        depth_prev = pom_depth;
        height_prev = height;
    }
    return xz;
}

#if POM_BISECTION_ENABLED
// Same early-outs and bracket semantics; bisection refines the crossing
// (fewer coarse steps for equal/better accuracy).
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
    float height_a = OceanValueNoisePOMHeight(xz + dir * depth_a, time);
    for (int i = 1; i <= WATER_POM_COARSE_STEPS; ++i) {
        float depth_b = OCEAN_POM_MAX_DEPTH - step_depth * float(i);
        float height_b = OceanValueNoisePOMHeight(xz + dir * depth_b, time);
        if (height_a <= depth_a && height_b > depth_b) {
            // f(depthA) <= 0, f(depthB) > 0: bisection inside the bracket.
            for (int j = 0; j < WATER_POM_BISECT_STEPS; ++j) {
                float depth_m = 0.5 * (depth_a + depth_b);
                float height_m = OceanValueNoisePOMHeight(xz + dir * depth_m, time);
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
            float t = Saturate(f_a / (f_a - f_b));
            return xz + dir * mix(depth_a, depth_b, t);
        }
        depth_a = depth_b;
        height_a = height_b;
    }
    return xz;
}
#endif

// World-space normal (y up) at the parallax-corrected position (central
// sample omitted).
void OceanValueNoisePOM(vec2 xz, vec3 view_world, float time, out vec3 normal) {
#ifdef WATER_POM
#if POM_BISECTION_ENABLED
    vec2 xz_offset = OceanPOMOffsetBisection(xz, view_world, time);
#else
    vec2 xz_offset = OceanPOMOffset(xz, view_world, time);
#endif
#else
    vec2 xz_offset = xz;
#endif
    OceanValueNoiseNormal(xz_offset, time, normal);
}

#endif // LIB_WATER_OCEAN_GLSL
