#version 430 compatibility
#define WORLD_NETHER
#define PROGRAM_GBUFFERS_PARTICLES
#include "/lib/contract/settings.glsl"
#ifdef PARTICLE_FORWARD
#include "/program/gbuffer/solid_lite.vertex"
#else
#include "/program/gbuffer/solid.vertex"
#endif
