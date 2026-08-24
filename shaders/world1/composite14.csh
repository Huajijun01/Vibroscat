#version 430 compatibility
#define WORLD_END
const vec2 workGroupsRender = vec2(0.0078125, 0.0078125);
#define BLOOM_SRC_MIP 6
#define BLOOM_DST_MIP 7
#include "/program/post/bloom_down.compute"
