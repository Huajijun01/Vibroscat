#version 430 compatibility
#define WORLD_NETHER
const vec2 workGroupsRender = vec2(0.0625, 0.0625);
#define BLOOM_SRC_MIP 4
#define BLOOM_DST_MIP 3
#include "/program/post/bloom_up.compute"
