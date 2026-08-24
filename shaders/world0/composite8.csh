#version 430 compatibility
#define WORLD_OVERWORLD
const vec2 workGroupsRender = vec2(0.5, 0.5);
#include "/program/post/bloom_extract.compute"
