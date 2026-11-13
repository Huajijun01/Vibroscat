#ifndef LIB_CORE_PACKING_GLSL
#define LIB_CORE_PACKING_GLSL

#include "/lib/core/math_scalar.glsl"

float Pack2x8(float hi, float lo) {
    float hi8 = floor(hi * 255.0);
    float lo8 = floor(lo * 255.0);
    return (hi8 * 256.0 + lo8) * (1.0 / 65535.0);
}


// Octahedral normal codec. The caller owns the space: colortex4 RG carries
// the geometric world normal, shadowcolor0 BA the shadow-view RSM normal, and
// GI history packs the receiver's world normal in colortex10 R.
vec2 EncodeOctahedralNormal(vec3 unit_normal) {
    unit_normal.xy /= abs(unit_normal.x) + abs(unit_normal.y) + abs(unit_normal.z);
    unit_normal.xy = unit_normal.z >= 0.0 ? unit_normal.xy : (vec2(1.0) - abs(unit_normal.yx)) * vec2(unit_normal.x >= 0.0 ? 1.0 : -1.0,
            unit_normal.y >= 0.0 ? 1.0 : -1.0);
    return unit_normal.xy * 0.5 + 0.5;
}

vec3 DecodeOctahedralNormal(vec2 encoded) {
    vec2 oct = encoded * 2.0 - 1.0;
    vec3 unit_normal = vec3(oct, 1.0 - abs(oct.x) - abs(oct.y));
    // encoded is [0,1], so each |oct| component stays <= 1 and t <= 1.
    float t = saturate(-unit_normal.z);
    unit_normal.x += unit_normal.x >= 0.0 ? -t : t;
    unit_normal.y += unit_normal.y >= 0.0 ? -t : t;
    return normalize(unit_normal);
}

#endif // LIB_CORE_PACKING_GLSL
