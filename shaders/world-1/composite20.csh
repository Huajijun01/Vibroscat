#version 430 compatibility
#define WORLD_NETHER
const vec2 workGroupsRender = vec2(0.25, 0.25);
#define BLOOM_SRC_MIP 2
#define BLOOM_DST_MIP 1
#include "/program/post/bloom_up.compute"
