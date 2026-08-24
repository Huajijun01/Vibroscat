#version 430 compatibility
#define WORLD_END
const vec2 workGroupsRender = vec2(0.125, 0.125);
#define BLOOM_SRC_MIP 2
#define BLOOM_DST_MIP 3
#include "/program/post/bloom_down.compute"
