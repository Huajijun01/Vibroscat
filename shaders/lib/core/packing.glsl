#ifndef LIB_CORE_PACKING_GLSL
#define LIB_CORE_PACKING_GLSL

// Pack two [0,1] values into one 16-bit UNORM channel (8 bits each).
float Pack2x8(float hi, float lo) {
    float hi8 = floor(hi * 255.0);
    float lo8 = floor(lo * 255.0);
    return (hi8 * 256.0 + lo8) * (1.0 / 65535.0);
}

vec2 Unpack2x8(float p16) {
    float v = p16 * 65535.0;
    float hi8 = floor(v / 256.0);
    float lo8 = v - hi8 * 256.0;
    return vec2(hi8 / 255.0, lo8 / 255.0);
}

// Split a [0,1] value across two 16-bit UNORM channels (32-bit fixed point).
vec2 Split2x16(float v) {
    float scaled = v * 65535.0;
    return vec2(floor(scaled) / 65535.0, fract(scaled));
}

float Unsplit2x16(vec2 v) {
    return (v.x * 65535.0 + v.y) * (1.0 / 65535.0);
}

// GBuffer octahedral normal codec; contract for the RG channels of
// colortex4 (geometric view normal).
vec2 EncodeOctahedralNormal(vec3 normal_view) {
    normal_view.xy /= abs(normal_view.x) + abs(normal_view.y) + abs(normal_view.z);
    normal_view.xy = normal_view.z >= 0.0 ? normal_view.xy : (vec2(1.0) - abs(normal_view.yx)) * vec2(normal_view.x >= 0.0 ? 1.0 : -1.0,
            normal_view.y >= 0.0 ? 1.0 : -1.0);
    return normal_view.xy * 0.5 + 0.5;
}

vec3 DecodeOctahedralNormal(vec2 encoded) {
    vec2 oct = encoded * 2.0 - 1.0;
    vec3 normal_view = vec3(oct, 1.0 - abs(oct.x) - abs(oct.y));
    float t = max(-normal_view.z, 0.0);
    normal_view.x += normal_view.x >= 0.0 ? -t : t;
    normal_view.y += normal_view.y >= 0.0 ? -t : t;
    return normalize(normal_view);
}

#endif
