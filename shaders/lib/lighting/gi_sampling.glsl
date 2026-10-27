#ifndef LIB_LIGHTING_GI_SAMPLING_GLSL
#define LIB_LIGHTING_GI_SAMPLING_GLSL

#include "/lib/core/noise.glsl"

// Digitally shifted three-dimensional Sobol net. GI must keep exploring
// after the 64-frame STBN volume repeats. Fixed
// STBN slices supply spatial shifts; they do not determine the temporal period.
vec3 SampleGINoise(ivec2 pixel, int frame) {
    uint index = uint(frame) ^ (uint(frame) >> 1);
    uint sequence_x = bitfieldReverse(index);
    uvec2 sequence_yz = uvec2(0u);
    uint direction_y = 0x80000000u;
    uint direction_z = 0x80000000u;
    uint previous_z = direction_z;
    int bit_index = 0;
    while (index != 0u) {
        if ((index & 1u) != 0u) sequence_yz ^= uvec2(direction_y, direction_z);
        index >>= 1;
        direction_y ^= direction_y >> 1;
        // Dimension three uses x^2+x+1 with initial odd numerators 1,1.
        uint next_z = bit_index == 0 ? 0x40000000u
            : previous_z ^ (previous_z >> 2) ^ direction_z;
        previous_z = direction_z;
        direction_z = next_z;
        ++bit_index;
    }
    uint seed = LowBias32Hash(uint(pixel.x) ^ (uint(pixel.y) * 0x9e3779b9u));
    uvec3 spatial_shift = uvec3(round(vec3(SampleSTBN(pixel, STBN_STREAM_0),
        SampleSTBN(pixel, STBN_STREAM_2), SampleSTBN(pixel, STBN_STREAM_1)) * 255.0)) << 24;
    spatial_shift |= uvec3(seed, LowBias32Hash(seed), LowBias32Hash(seed ^ 0x85ebca6bu)) & 0x00ffffffu;
    return vec3((uvec3(sequence_x, sequence_yz) ^ spatial_shift) >> 8) * (1.0 / 16777216.0);
}

#endif // LIB_LIGHTING_GI_SAMPLING_GLSL
