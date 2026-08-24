#version 430 compatibility
#define WORLD_END
const vec2 workGroupsRender = vec2(0.25, 0.25);
#define BLOOM_SRC_MIP 1
#define BLOOM_DST_MIP 2
#include "/program/post/bloom_down.compute"
