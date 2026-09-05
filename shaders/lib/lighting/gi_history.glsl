#ifndef LIB_LIGHTING_GI_HISTORY_GLSL
#define LIB_LIGHTING_GI_HISTORY_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/packing.glsl"

// R32UI: half linear view depth [0:15], oct5 world normal [16:25],
// age [26:30], source [31] (0=SSGI, 1=RSM). Age zero is invalid.
uint EncodeGIHistory(float depth_view, vec3 normal_world, float age) {
    uvec2 normal_bits = uvec2(round(EncodeOctahedralNormal(normal_world) * 31.0));
    uint depth_bits = packHalf2x16(vec2(min(depth_view, 65000.0), 0.0)) & 65535u;
    uint source_bit = uint(GI_MODE == 2) << 31u;
    return source_bit | (uint(clamp(age, 1.0, 31.0)) << 26u)
        | (normal_bits.y << 21u) | (normal_bits.x << 16u) | depth_bits;
}

float GIHistoryAge(uint metadata) {
    return (metadata >> 31u) == uint(GI_MODE == 2) ? float((metadata >> 26u) & 31u) : 0.0;
}

float GIHistoryDepth(uint metadata) {
    return unpackHalf2x16(metadata & 65535u).x;
}

vec3 GIHistoryNormal(uint metadata) {
    return DecodeOctahedralNormal(vec2((metadata >> 16u) & 31u, (metadata >> 21u) & 31u) / 31.0);
}

#endif // LIB_LIGHTING_GI_HISTORY_GLSL
