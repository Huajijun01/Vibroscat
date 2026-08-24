#ifndef LIB_WATER_OCEAN_GLSL
#define LIB_WATER_OCEAN_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"

// Single-texture value-noise ocean (offline-fitted).
// 8 layers from the 64x64 R8 utex_noise2d_tex (hardware bilinear, repeat);
// per-band layer selection solved against the analytic Phillips band
// features (n=8, low-frequency allocation 3,2,1,1,1). Statically optimized:
// freq pre-multiplied into uv, fitted gain into amplitude. Normals from a
// central-difference gradient.


// Parallax occlusion mapping for the water surface: the normal is
// evaluated at the parallax-corrected position. The WATER_POM option lives
// in contract/settings.glsl (LOW profile disables it; the normal then falls
// back to the plane position).

// POM search mode: 0 = fixed-step linear, 1 = coarse + bisection (same or
// fewer height samples, tighter root; wave field and normals unchanged).
// The step budgets (VALUE_NOISE_POM_COARSE_STEPS / _BISECT_STEPS) are user
// options declared in contract/settings.glsl.
#define POM_BISECTION_ENABLED 1

struct ValueNoiseWave {
    vec4 uv;         // precombined 2x2 uv transform (layer angle + wind
                     // frame cross-wind stretch), row-major, pre-scaled
                     // by freq = 2*pi/lambda
    float amplitude; // fitted height amplitude (m), pre-scaled by gain
    float omega;     // deep-water dispersion: pixel advection speed
};

const int VALUE_NOISE_LAYERS = 8; // full wave table size
const ValueNoiseWave VALUE_NOISE_WAVES[VALUE_NOISE_LAYERS] = ValueNoiseWave[](
    ValueNoiseWave(vec4(0.48383789, 0.06497906, 0.12574129, 0.11980542), 0.419068, 2.23419),
    ValueNoiseWave(vec4(0.38679537, 0.23157128, 0.00831051, 0.21160617), -0.424931, 2.14238),
    ValueNoiseWave(vec4(0.62624209, 0.24421508, 0.09593550, 0.26013725), -0.301118, 2.61903),
    ValueNoiseWave(vec4(0.60644167, 0.20562579, 0.10357081, 0.24136490), -0.315376, 2.55639),
    ValueNoiseWave(vec4(1.98834646, 2.86292616, -1.32892738, 1.76140873), -0.039151, 5.93238),
    ValueNoiseWave(vec4(1.02173311, 1.11223367, -0.62825168, 0.89748953), -0.123701, 3.89348),
    ValueNoiseWave(vec4(4.97572310, 5.81092247, -0.79207427, 3.33275961), 0.005696, 8.82941),
    ValueNoiseWave(vec4(3.64585845, -1.68458698, 1.34745029, 0.11760039), 0.044025, 6.41017));

// Offline normalization gain (fitted std -> target wave table std) and the
// central-difference step, matched to the offline 384-grid (32 m) gradient.
const float VALUE_NOISE_EPS = 0.1; // central-difference step (m)

// Single hardware bilinear fetch with smoothstep-equivalent weights (uv
// pre-distorted: w = f²(3 - 2f)).
float ValueNoiseSample(vec2 pos) {
    vec2 f = fract(pos);
    vec2 p = floor(pos) + f * f * (3.0 - 2.0 * f);
    return texture(utex_noise2d_tex, (p + 0.5) / 64.0).r;
}

// Cheap bilinear fetch for the POM field only (saves ~8 ALU/sample; the
// final normal still uses the smoothstep sample).
float ValueNoiseSampleFast(vec2 pos) {
    return texture(utex_noise2d_tex, (pos + 0.5) / 64.0).r;
}

// Height of a single layer at world XZ.
float OceanLayerHeight(vec2 xz, float time, ValueNoiseWave w) {
    // uv already includes freq: r = (uv * freq) . xz, then advect at omega
    vec2 r = vec2(dot(w.uv.xy, xz), dot(w.uv.zw, xz));
    r.x += w.omega * time;
    return w.amplitude * (ValueNoiseSample(r) - 0.5);
}

float OceanValueNoiseHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int i = 0; i < VALUE_NOISE_LAYERS; ++i) {
        h += OceanLayerHeight(xz, time, VALUE_NOISE_WAVES[i]);
    }
    return h;
}

// World-space normal (y up) from a central-difference gradient (central
// sample omitted when only the normal is needed).
void OceanValueNoiseNormal(vec2 xz, float time, out vec3 normal) {
    float eps = VALUE_NOISE_EPS;
    float hx = OceanValueNoiseHeight(xz + vec2(eps, 0.0), time) - OceanValueNoiseHeight(xz - vec2(eps, 0.0), time);
    float hz = OceanValueNoiseHeight(xz + vec2(0.0, eps), time) - OceanValueNoiseHeight(xz - vec2(0.0, eps), time);
    vec2 grad = vec2(hx, hz) / (2.0 * eps);
    normal = normalize(vec3(-grad.x, 1.0, -grad.y));
}

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
const int VALUE_NOISE_POM_LAYERS = 4;
const int VALUE_NOISE_POM_WAVES[VALUE_NOISE_POM_LAYERS] = int[](1, 0, 3, 2);
const int VALUE_NOISE_POM_STEPS = 8;
const float VALUE_NOISE_POM_MAX_DEPTH = 0.6;  // m, >= max fitted crest (0.433)
const float VALUE_NOISE_POM_MAX_OFFSET = 2.0; // m, clamp grazing offsets
const float VALUE_NOISE_POM_MIN_SHIFT = 0.05; // m, skip invisible shifts

float OceanValueNoisePOMHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int i = 0; i < VALUE_NOISE_POM_LAYERS; ++i) {
        ValueNoiseWave w = VALUE_NOISE_WAVES[VALUE_NOISE_POM_WAVES[i]];
        vec2 r = vec2(dot(w.uv.xy, xz), dot(w.uv.zw, xz));
        r.x += w.omega * time;
        h += w.amplitude * (ValueNoiseSampleFast(r) - 0.5);
    }
    return h;
}

// Ray/surface intersection: for a camera above the water (view.y < 0) the
// visible point satisfies h(xz0 + d·dir) = d (dir = view.xz/view.y toward
// camera; bumps displace toward camera, troughs away). Scan from the camera
// side, interpolate the first crossing; none found → keep the plane sample
// (no over-shift on flat water).
vec2 OceanPOMOffset(vec2 xz, vec3 view_world, float time) {
    if (view_world.y >= 0.0) {
        return xz; // underwater view: no parallax correction
    }
    // viewWorld.y < 0 here, so this points towards the camera
    vec2 dir = view_world.xz / view_world.y;
    float dir_len = length(dir);
    if (dir_len * VALUE_NOISE_POM_MAX_DEPTH < VALUE_NOISE_POM_MIN_SHIFT) {
        return xz; // near-vertical view: parallax shift is invisible
    }
    if (dir_len * VALUE_NOISE_POM_MAX_DEPTH > VALUE_NOISE_POM_MAX_OFFSET) {
        // grazing view: keep the whole search inside the offset budget
        dir *= VALUE_NOISE_POM_MAX_OFFSET / (dir_len * VALUE_NOISE_POM_MAX_DEPTH);
    }
    float step_depth = 2.0 * VALUE_NOISE_POM_MAX_DEPTH / float(VALUE_NOISE_POM_STEPS);
    float depth_prev = VALUE_NOISE_POM_MAX_DEPTH;
    float height_prev = OceanValueNoisePOMHeight(xz + dir * depth_prev, time);
    for (int i = 1; i <= VALUE_NOISE_POM_STEPS; ++i) {
        float depth = VALUE_NOISE_POM_MAX_DEPTH - step_depth * float(i);
        float height = OceanValueNoisePOMHeight(xz + dir * depth, time);
        // The ray enters the water when f = h - d crosses from <= 0 to > 0.
        if (height_prev <= depth_prev && height > depth) {
            float height_diff_prev = height_prev - depth_prev;
            float height_diff_curr = height - depth;
            float t = Saturate(height_diff_prev / (height_diff_prev - height_diff_curr));
            return xz + dir * mix(depth_prev, depth, t);
        }
        depth_prev = depth;
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
    if (dir_len * VALUE_NOISE_POM_MAX_DEPTH < VALUE_NOISE_POM_MIN_SHIFT) {
        return xz;
    }
    if (dir_len * VALUE_NOISE_POM_MAX_DEPTH > VALUE_NOISE_POM_MAX_OFFSET) {
        dir *= VALUE_NOISE_POM_MAX_OFFSET / (dir_len * VALUE_NOISE_POM_MAX_DEPTH);
    }

    float step_depth = 2.0 * VALUE_NOISE_POM_MAX_DEPTH / float(VALUE_NOISE_POM_COARSE_STEPS);
    float depth_a = VALUE_NOISE_POM_MAX_DEPTH;
    float height_a = OceanValueNoisePOMHeight(xz + dir * depth_a, time);
    for (int i = 1; i <= VALUE_NOISE_POM_COARSE_STEPS; ++i) {
        float depth_b = VALUE_NOISE_POM_MAX_DEPTH - step_depth * float(i);
        float height_b = OceanValueNoisePOMHeight(xz + dir * depth_b, time);
        if (height_a <= depth_a && height_b > depth_b) {
            // f(depthA) <= 0, f(depthB) > 0: bisection inside the bracket.
            for (int j = 0; j < VALUE_NOISE_POM_BISECT_STEPS; ++j) {
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
    vec2 xzp = OceanPOMOffsetBisection(xz, view_world, time);
#else
    vec2 xzp = OceanPOMOffset(xz, view_world, time);
#endif
#else
    vec2 xzp = xz;
#endif
    OceanValueNoiseNormal(xzp, time, normal);
}

// Height field + world-space normal (y up). xz is absolute world XZ.
float OceanValueNoise(vec2 xz, float time, out vec3 normal) {
    float h = OceanValueNoiseHeight(xz, time);
    OceanValueNoiseNormal(xz, time, normal);
    return h;
}

#endif