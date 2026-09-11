#ifndef LIB_WATER_OCEAN_GLSL
#define LIB_WATER_OCEAN_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"

// Single-texture value-noise ocean (offline-fitted).
// 7 layers from the 64x64 R8 utex_noise2d_tex (hardware bilinear, repeat);
// per-band layer selection solved against the analytic Phillips band
// features (n=8, low-frequency allocation 3,2,1,1,1). The finest fitted band
// (lambda 0.131 m, amplitude 0.0057) was dropped: the VALUE_NOISE_EPS central
// difference has its first zero at 2*eps = 0.2 m, so that band held 0.4% of
// the normal's slope variance while costing 4 of its 32 fetches.
// Statically optimized: freq pre-multiplied into uv, fitted gain into
// amplitude. Normals from a central-difference gradient.
//
// WATER_ANALYTIC_WAVES moves the three finest remaining bands (table indices
// 4..6) out of the texture path; see the analytic high band below.


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

const int VALUE_NOISE_LAYERS = 7; // full wave table size
const ValueNoiseWave VALUE_NOISE_WAVES[VALUE_NOISE_LAYERS] = ValueNoiseWave[](
    ValueNoiseWave(vec4(0.48383789, 0.06497906, 0.12574129, 0.11980542), 0.419068, 2.23419),
    ValueNoiseWave(vec4(0.38679537, 0.23157128, 0.00831051, 0.21160617), -0.424931, 2.14238),
    ValueNoiseWave(vec4(0.62624209, 0.24421508, 0.09593550, 0.26013725), -0.301118, 2.61903),
    ValueNoiseWave(vec4(0.60644167, 0.20562579, 0.10357081, 0.24136490), -0.315376, 2.55639),
    ValueNoiseWave(vec4(1.98834646, 2.86292616, -1.32892738, 1.76140873), -0.039151, 5.93238),
    ValueNoiseWave(vec4(1.02173311, 1.11223367, -0.62825168, 0.89748953), -0.123701, 3.89348),
    ValueNoiseWave(vec4(3.64585845, -1.68458698, 1.34745029, 0.11760039), 0.044025, 6.41017));

// Offline normalization gain (fitted std -> target wave table std) and the
// central-difference step, matched to the offline 384-grid (32 m) gradient.
const float VALUE_NOISE_EPS = 0.1; // central-difference step (m)

// Texture-sampled band count: the whole table, or the four low bands when the
// analytic high band replaces indices 4..6.
#ifdef WATER_ANALYTIC_WAVES
const int VALUE_NOISE_TEXTURED_LAYERS = 4;
#else
const int VALUE_NOISE_TEXTURED_LAYERS = VALUE_NOISE_LAYERS;
#endif

#ifdef WATER_ANALYTIC_WAVES
// Analytic high band: each of the three finest bands becomes a pair of
// directional triangle waves set +-30 deg about that band's own wind axis.
// tri(u) = 1 - 2*|fract(u) - 0.5| is piecewise linear, so its derivative is
// the square wave +2/-2 and the band needs no finite difference: the water
// normal drops from 7*4 texture fetches to 4*4 and the high band costs six ALU
// waves. Only the gradient is evaluated; the band height is never summed,
// because the POM relight reads the four low bands.
//
// The pair, rather than one wave per band, exists to break ridge coherence.
// One wave per band matches the slope but reads as strong striping: anisotropy
// 5.41 against the layered field's 3.86, with ridges correlated over 1.72 m
// against 0.92 m. The +-30 deg pair lands at 4.07 and 1.27 m, both inside the
// spread a same-method re-roll of the noise lattice produces (4.56 and 1.66 m).
// Rotating the bands' own axes instead of spreading about them is worse (6.01
// even at zero spread), because the high band's job includes cancelling the
// low band's own anisotropy.
//
// Offline fit against the layered field at the same eps: each pair keeps its
// band's angular frequency and advection, and the pair gains are fitted to that
// band's central-difference slope, then scaled 0.9435 so the total slopeRMS
// matches. Result: slopeRMS 1.00x, slope concentration 1.84 against 1.87, and a
// local normal within 8.1 deg rms / 15.5 deg p95, against the 13.2 deg /
// 27.0 deg a re-roll produces.
struct TriangleWave {
    vec2 axis;   // ridge direction * angular frequency (rad/m)
    float gain;  // fitted triangle height amplitude (m)
    float omega; // deep-water dispersion: ridge phase speed (rad/s)
    float phase; // fixed offset so the six ridges do not share crest lines
};

const int TRIANGLE_WAVE_LAYERS = 6;
const TriangleWave TRIANGLE_WAVES[TRIANGLE_WAVE_LAYERS] = TriangleWave[](
    TriangleWave(vec2(3.15342163, 1.48519355), 0.00540941, 5.93238, 0.311000),  // table[4], 0.287 m cell, -30 deg
    TriangleWave(vec2(0.29049547, 3.47354001), 0.00540941, 5.93238, 0.681000),  // table[4], 0.287 m cell, +30 deg
    TriangleWave(vec2(1.44096366, 0.45235606), 0.01838549, 3.89348, 0.577000),  // table[5], 0.662 m cell, -30 deg
    TriangleWave(vec2(0.32872999, 1.47408917), 0.01838549, 3.89348, 0.947000),  // table[5], 0.662 m cell, +30 deg
    TriangleWave(vec2(2.31511255, -3.28182434), 0.00590774, 6.41017, 0.829000), // table[6], 0.249 m cell, -30 deg
    TriangleWave(vec2(3.99969953, 0.36403411), 0.00590774, 6.41017, 1.199000)); // table[6], 0.249 m cell, +30 deg
#endif

// Single hardware bilinear fetch with smoothstep-equivalent weights (uv
// pre-distorted: w = f2(3 - 2f)).
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

// Height of the texture-sampled bands only; the analytic high band adds a
// gradient and is not summed here.
float OceanValueNoiseHeight(vec2 xz, float time) {
    float h = 0.0;
    for (int i = 0; i < VALUE_NOISE_TEXTURED_LAYERS; ++i) {
        h += OceanLayerHeight(xz, time, VALUE_NOISE_WAVES[i]);
    }
    return h;
}

#ifdef WATER_ANALYTIC_WAVES
// World-XZ gradient of the analytic high band.
vec2 OceanHighBandGradient(vec2 xz, float time) {
    vec2 grad = vec2(0.0);
    for (int i = 0; i < TRIANGLE_WAVE_LAYERS; ++i) {
        TriangleWave w = TRIANGLE_WAVES[i];
        float side = fract(dot(w.axis, xz) + w.omega * time + w.phase) - 0.5;
        grad += (side < 0.0 ? 2.0 : -2.0) * w.gain * w.axis;
    }
    return grad;
}
#endif

// World-space normal (y up) from a central-difference gradient (central
// sample omitted when only the normal is needed). The analytic high band adds
// its exact gradient instead of four more taps per layer.
void OceanValueNoiseNormal(vec2 xz, float time, out vec3 normal) {
    float eps = VALUE_NOISE_EPS;
    float hx = OceanValueNoiseHeight(xz + vec2(eps, 0.0), time) - OceanValueNoiseHeight(xz - vec2(eps, 0.0), time);
    float hz = OceanValueNoiseHeight(xz + vec2(0.0, eps), time) - OceanValueNoiseHeight(xz - vec2(0.0, eps), time);
    vec2 grad = vec2(hx, hz) / (2.0 * eps);
#ifdef WATER_ANALYTIC_WAVES
    grad += OceanHighBandGradient(xz, time);
#endif
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

#endif
