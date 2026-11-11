#version 430 compatibility
#define WORLD_NETHER
const vec2 workGroupsRender = vec2(0.03125, 0.03125);
#define BLOOM_SRC_MIP 6
#define BLOOM_DST_MIP 5
#include "/program/post/bloom_up.compute"
