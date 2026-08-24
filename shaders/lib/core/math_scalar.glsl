#ifndef LIB_CORE_MATH_SCALAR_GLSL
#define LIB_CORE_MATH_SCALAR_GLSL

const float centerDepthHalflife = 1.0;

#define PI 3.14159265358979323846
#define TAU (2.0 * PI)

float Sqr(float x) { return x * x; }
float Max0(float x) { return max(x, 0.0); }

float Saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 Saturate(vec2 x) { return clamp(x, 0.0, 1.0); }
vec3 Saturate(vec3 x) { return clamp(x, 0.0, 1.0); }
vec4 Saturate(vec4 x) { return clamp(x, 0.0, 1.0); }

float Pow4(float x) { x = x * x; return x * x; }

float Pow5(float x) { float x2 = x * x; return x2 * x2 * x; }

// Base-2 radical inverse (van der Corput) via one bitfield reversal: the
// basis of Hammersley sampling.
float RadicalInverse(int i) {
    return float(bitfieldReverse(uint(i))) * 2.3283064365386963e-10;
}

// Cheap sine on [0, 2pi): Bhaskara I approximation, pure ALU (no branch, no
// SFU), ~0.4% max error. Replaces the SFU sin/cos per disk sample.
float FastSin(float x) {
    x = fract(x * (1.0 / TAU)) * TAU;
    float fold = step(PI, x);
    x = mix(x, TAU - x, fold);
    float sgn = 1.0 - 2.0 * fold;
    float xpi = x * (PI - x);
    return sgn * 16.0 * xpi / (5.0 * PI * PI - 4.0 * xpi);
}

float FastCos(float x) {
    return FastSin(x + PI * 0.5);
}

#endif
