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

float GIApproxAtan2(vec2 direction) {
    float x = abs(direction.x);
    float u = 2.0 + x * (1.27324 + x * (-0.189431 + (0.08204 - 0.0242564 * x) * x));
    float value = direction.y / u;
    if (direction.x < 0.0) value = (direction.y < 0.0 ? -1.0 : 1.0) - value;
    return value;
}

float GIApproxAcos(float x) {
    x = clamp(x, -1.0, 1.0);
    float ax = abs(x);
    float polynomial = 1.5707963267948966
        + (-0.20491203466059038 + 0.04832927023878897 * ax) * ax;
    float value = polynomial * sqrt(1.0 - ax);
    return x < 0.0 ? PI - value : value;
}

vec2 GIRotate2D(vec2 value, vec2 rotation) {
    return vec2(value.x * rotation.x - value.y * rotation.y,
        value.y * rotation.x + value.x * rotation.y);
}

float GIPartialSlice(float x, float sin_view_normal) {
    if (abs(x) >= 1.0 || x == 0.0) return x;
    bool negative = x < 0.0;
    x = abs(x);
    float s = sin_view_normal;
    float o = s - s * s;
    float slope0 = 1.0 / (1.0 + (PI - 1.0) * (s - o * 0.30546));
    float slope1 = 1.0 / (1.0 - (1.0 - exp2(-20.0)) * (s + o * mix(0.5, 0.785, s)));
    float k = mix(0.1, 0.25, s);
    float a = 1.0 - (PI - 2.0) / (PI - 1.0);
    float b = 1.0 / (PI - 1.0);
    float d0 = a - slope0 * b;
    float d1 = 1.0 - slope1;
    float f0 = d0 * (PI * x - (0.5 * PI - GIApproxAcos(x)));
    float f1 = d1 * (x - 1.0);
    float kk = k * k;
    float h0 = sqrt(f0 * f0 + kk) - k;
    float h1 = sqrt(f1 * f1 + kk) - k;
    float hh = (h0 * h1) / max(h0 + h1, 1.0e-6);
    float y = x - sqrt(max(hh * (hh + 2.0 * k), 0.0));
    return negative ? -y : y;
}

vec2 GISampleSliceDirection(vec3 view_space_normal, float random_value) {
    float angle = random_value * TAU;
    vec2 direction = vec2(cos(angle), sin(angle));
    float normal_xy_length = length(view_space_normal.xy);
    if (normal_xy_length > 1.0e-5) {
        vec2 normal_direction = view_space_normal.xy / normal_xy_length;
        direction = GIRotate2D(direction, normal_direction * vec2(1.0, -1.0));
        float slice_angle = GIPartialSlice(GIApproxAtan2(direction), normal_xy_length) * PI;
        direction = GIRotate2D(vec2(cos(slice_angle), sin(slice_angle)), normal_direction);
    }
    return direction;
}

vec4 GIQuaternionFromViewDirection(vec3 view_direction) {
    vec3 xyz = vec3(view_direction.y, -view_direction.x, 0.0);
    float scalar = -view_direction.z;
    float inverse_scale = inversesqrt(max(scalar * 0.5 + 0.5, 0.0));
    return vec4(xyz * inverse_scale * 0.5, 1.0 / inverse_scale);
}

vec3 GIRotateVectorByQuaternion(vec3 value, vec4 quaternion) {
    float cross_term = value.y * quaternion.x - value.x * quaternion.y;
    float scale = 2.0 * (value.z * quaternion.w + cross_term);
    vec3 result;
    result.xy = value.xy + quaternion.yx * vec2(scale, -scale);
    result.z = value.z + 2.0 * (quaternion.w * cross_term
        - value.z * dot(quaternion.xy, quaternion.xy));
    return result;
}

vec3 GIRotateSliceDirectionByQuaternion(vec2 slice_direction, vec4 quaternion) {
    float offset = quaternion.x * slice_direction.y;
    float cross_term = quaternion.y * slice_direction.x;
    vec3 basis = vec3(offset - cross_term, -offset + cross_term, offset - cross_term);
    return vec3(slice_direction, 0.0) + 2.0 * (basis * quaternion.yxw);
}

uint GIVisibilityMaskFromRange(float range_start, float range_end) {
    uvec2 horizontal_int = (uvec2(floatBitsToUint(range_start), floatBitsToUint(range_end))
        >> 17u) & 0x3Fu;
    uint start_bit = horizontal_int.x;
    uint end_bit = horizontal_int.y;
    uint left = start_bit < 32u ? 0xFFFFFFFFu << start_bit : 0u;
    uint right = end_bit != 0u ? 0xFFFFFFFFu >> (32u - end_bit) : 0u;
    return left & right;
}

float GITraceScreenEdge(vec4 origin_projection, vec4 projected_direction, float far_plane) {
    vec2 t1 = (vec2(1.0) * origin_projection.w - origin_projection.xy)
        / (projected_direction.xy - vec2(1.0) * projected_direction.w);
    vec2 t2 = (vec2(-1.0) * origin_projection.w - origin_projection.xy)
        / (projected_direction.xy - vec2(-1.0) * projected_direction.w);
    float edge = far_plane + 32.0;
    if (t1.x > 0.0) edge = min(edge, t1.x);
    if (t1.y > 0.0) edge = min(edge, t1.y);
    if (t2.x > 0.0) edge = min(edge, t2.x);
    if (t2.y > 0.0) edge = min(edge, t2.y);
    return edge;
}

#endif
