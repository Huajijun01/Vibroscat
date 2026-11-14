#ifndef LIB_POST_BLOOM_DOWNSAMPLE_GLSL
#define LIB_POST_BLOOM_DOWNSAMPLE_GLSL

// Alternating rows hold the four interleaved 2x2 boxes of a symmetric 13-tap downsample.
shared uvec2 bloom_down_tile[35][18];

vec3 LoadBloomDownTile(ivec2 coord) {
    uvec2 packed_value = bloom_down_tile[coord.y][coord.x];
    return vec3(unpackHalf2x16(packed_value.x), unpackHalf2x16(packed_value.y).x);
}

void StoreBloomDownTile(ivec2 coord, vec3 value) {
    bloom_down_tile[coord.y][coord.x] = uvec2(packHalf2x16(value.rg), packHalf2x16(vec2(value.b, 0.0)));
}

vec3 FilterBloomDownTile(ivec2 local_coord) {
    ivec2 center = ivec2(local_coord.x, local_coord.y * 2);
    vec3 result = LoadBloomDownTile(center + ivec2(1, 2)) * 0.125;
    result += (LoadBloomDownTile(center + ivec2(0, 1)) + LoadBloomDownTile(center + ivec2(1, 1))
             + LoadBloomDownTile(center + ivec2(0, 3)) + LoadBloomDownTile(center + ivec2(1, 3))) * 0.125;
    result += (LoadBloomDownTile(center + ivec2(1, 0)) + LoadBloomDownTile(center + ivec2(0, 2))
             + LoadBloomDownTile(center + ivec2(2, 2)) + LoadBloomDownTile(center + ivec2(1, 4))) * 0.0625;
    result += (LoadBloomDownTile(center + ivec2(0, 0)) + LoadBloomDownTile(center + ivec2(2, 0))
             + LoadBloomDownTile(center + ivec2(0, 4)) + LoadBloomDownTile(center + ivec2(2, 4))) * 0.03125;
    return result;
}

#endif // LIB_POST_BLOOM_DOWNSAMPLE_GLSL
