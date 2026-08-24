#version 430 compatibility
#define WORLD_END
const vec2 workGroupsRender = vec2(0.03125, 0.03125);
#define BLOOM_SRC_MIP 5
#define BLOOM_DST_MIP 4
#include "/program/post/bloom_up.compute"
