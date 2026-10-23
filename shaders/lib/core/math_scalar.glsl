#ifndef LIB_CORE_MATH_SCALAR_GLSL
#define LIB_CORE_MATH_SCALAR_GLSL

#define PI 3.14159265358979323846
#define TAU (2.0 * PI)
#define INV_TWO_PI (0.5 / PI)

// Additive low-discrepancy increment (R1 sequence, the golden-ratio conjugate
// 1/phi); the 2D analogue is R2Offset in noise.glsl.
const float GOLDEN_RATIO = 0.61803398875;


float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 saturate(vec2 x) { return clamp(x, 0.0, 1.0); }
vec3 saturate(vec3 x) { return clamp(x, 0.0, 1.0); }
vec4 saturate(vec4 x) { return clamp(x, 0.0, 1.0); }

float Pow4(float x) { x = x * x; return x * x; }

float Pow5(float x) { float x2 = x * x; return x2 * x2 * x; }

float FastAdjust(float x, float c) {
    return (c + 1.0) * x / (c * x + 1.0);
}

// True when every component is neither NaN nor infinite.
bool IsFinite(vec3 value) {
    return !any(isnan(value)) && !any(isinf(value));
}


float FastAtan2(vec2 direction) {
    float x = abs(direction.x);
    float u = 2.0 + x * (1.27324 + x * (-0.189431 + (0.08204 - 0.0242564 * x) * x));
    float value = direction.y / u;
    if (direction.x < 0.0) value = (direction.y < 0.0 ? -1.0 : 1.0) - value;
    return value;
}

float FastAcos(float x) {
    x = clamp(x, -1.0, 1.0);
    float ax = abs(x);
    float polynomial = 1.5707963267948966
        + (-0.20491203466059038 + 0.04832927023878897 * ax) * ax;
    float value = polynomial * sqrt(1.0 - ax);
    return x < 0.0 ? PI - value : value;
}

vec2 Rotate2D(vec2 value, vec2 rotation) {
    return vec2(value.x * rotation.x - value.y * rotation.y,
        value.y * rotation.x + value.x * rotation.y);
}

#endif // LIB_CORE_MATH_SCALAR_GLSL
