#version 430 compatibility
#define WORLD_OVERWORLD
const vec2 workGroupsRender = vec2(0.015625, 0.015625);
#define BLOOM_SRC_MIP 6
#define BLOOM_DST_MIP 5
#include "/program/post/bloom_up.compute"
