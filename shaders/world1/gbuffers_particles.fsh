#version 430 compatibility
#define WORLD_END
#define PROGRAM_GBUFFERS_PARTICLES
#include "/lib/contract/settings.glsl"
#ifdef PARTICLE_FORWARD
#include "/program/gbuffer/solid_lite.fragment"
#else
#define USE_DISCARD
#include "/program/gbuffer/solid.fragment"
#endif
