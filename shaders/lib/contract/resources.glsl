#ifndef LIB_CONTRACT_RESOURCES_GLSL
#define LIB_CONTRACT_RESOURCES_GLSL

#include "/lib/contract/settings.glsl"

// ============================================================================
// Buffer declarations: this file carries the Iris format and clear directives
// for every colortex and shadowcolor attachment. shaders.properties carries
// the customTexture formats and the blend state, not these.
// ============================================================================
//
// Buffer map (deferred pipeline):
//   colortex0   R11F_G11F_B10F   Scene color (post-processed) / TAA input
//   colortex1   RGBA8            GBuffer: albedo sRGB / materialID
//   colortex2   RGBA8            Opaque roughness/selector/emission/AO on main;
//                                deferred1 borrows alt R for half-res current AO
//                                and flips back to main for SSR/GI/shading; then low
//                                bytes of translucent RGB UNORM16 surface data;
//                                colortex1 RGB carries the high bytes while its
//                                material-ID alpha survives. A = water flag.
//   colortex3   R11F_G11F_B10F   Opaque reflection incident radiance transient
//   colortex4   RGBA8            Opaque geometric world normal (RG, octahedral) +
//                                lightmap (BA) (solid -> deferred4)
//   colortex5   R11F_G11F_B10F   TAA history
//   colortex8   RGBA16F          Cloud history frame (sun, moon, T, distance);
//                                merged with the AO history: geometry pixels
//                                carry (ao, age, encoded view depth, A=NaN "not cloud")
//   shadowcolor0 RGBA8           RSM: RGB565 reflectance (RG), oct8 shadow-view normal (BA)
//   colortex9   RGB16F           Half-res unblurred temporal GI irradiance,
//                                including uncovered SH; deferred3 flip history
//   colortex10  RGBA16F          Half-res GI history: oct6 normal/change count,
//                                luminance second moment, view depth,
//                                packed real age/receiver selector/source
//   colortex11  RGBA8            Weather sheet: coverage (A) and radiance premultiplied
//                                by coverage (RGB; the gbuffers SRC_ALPHA blend applies
//                                it on write); written by gbuffers_weather, composited
//                                by air fog
//   colortex12  RGBA16F          Sequential workspace:
//                                opaque main RG = oct shading world normal;
//                                deferred1 alt = low-res cloud current frame;
//                                flip back to main for deferred2/3/4 normals;
//                                deferred4 clears alt and flips, then
//                                1. translucent premultiplied-over color + alpha
//                                2. composite1 refracts, fogs and over-composites once
//                                3. bloom pyramid workspace
//                                4. tonemapped LDR scene consumed by final/CAS
//
// TAAU uses a cropped lower-left scene rectangle through composite3, then
// composite4 restores display-sized colortex0/5. Allocations/formats stay the same.
// This ledger documents existing ownership only. Allocation, clear, flip, and
// pass scheduling remain defined by Iris declarations and shaders.properties.

/*
// Format declarations. Iris reads them as raw source text
// (ConstDirectiveParser.findDirectives matches any line that starts with
// "const"), so they stay effective inside a block comment. The format names
// are not GLSL identifiers, which is why the lines cannot be live code; the
// block also keeps every line at column zero, and a trailing comment after
// the semicolon is tolerated by the parser.
const int colortex0Format  = R11F_G11F_B10F;
const int colortex1Format  = RGBA8;
const int colortex2Format  = RGBA8;
const int colortex3Format  = R11F_G11F_B10F;
const int colortex4Format  = RGBA8;            // geometric world normal (octahedral RG) + lightmap
const int colortex5Format  = R11F_G11F_B10F;
const int colortex8Format  = RGBA16F;  // cloud history frame: sunRad, moonRad, transmittance, distance_km; AO history merged on geometry pixels (ao, age, encoded view depth, A=NaN)
const int colortex9Format  = RGB16F; // half-res temporal irradiance (deferred3)
const int colortex10Format = RGBA16F; // half-res GI geometry/age history (deferred3)
const int colortex11Format = RGBA8;           // weather texture
const int colortex12Format = RGBA16F;
const int shadowcolor0Format = RGBA8;
*/

// -- Clear flags --
// true = cleared each frame before shader writes. false = carry data across frames.
const bool colortex0Clear  = false;   // scene output
const bool colortex1Clear  = false;   // GBuffer albedo
const bool colortex2Clear  = false;   // GBuffer scalars, then translucent low bytes/flag
const bool colortex3Clear  = false;   // opaque reflection incident radiance transient
const bool colortex4Clear  = false;   // opaque geometric world normal + lightmap
const bool colortex5Clear  = false;  // TAA history
const bool colortex8Clear  = false;   // cloud history frame (persistent; GTAO history merged on geometry pixels)
const bool colortex9Clear  = false;   // unblurred temporal GI history
const bool colortex10Clear = false;   // actual previous GI receiver geometry/age
const bool colortex11Clear = true;   // weather texture
const bool colortex12Clear = true;   // normal/cloud current, translucent, bloom, and tonemap workspace

#endif // LIB_CONTRACT_RESOURCES_GLSL
