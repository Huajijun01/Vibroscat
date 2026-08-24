#version 430 compatibility
#define WORLD_NETHER
const vec2 workGroupsRender = vec2(0.125, 0.125);
#define BLOOM_SRC_MIP 3
#define BLOOM_DST_MIP 2
#include "/program/post/bloom_up.compute"
