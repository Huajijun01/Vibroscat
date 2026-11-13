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
//   colortex0   R11F_G11F_B10F   deferred1 fragment writes direct RGB + emission
//                                to the non-selected side (geometry texels only;
//                                sky discards); the pass flip promotes it; deferred5
//                                writes completed color to the opposite side
//   colortex1   RGBA8            GBuffer: albedo sRGB / materialID
//   colortex2   RGBA8            deferred2_a half-res AO workspace on alt;
//                                later translucent RGB UNORM16 low bytes/flag,
//                                paired with colortex1 high bytes/material ID
//   colortex3   R11F_G11F_B10F   Unblurred demodulated reflection mean, direct RGB
//   colortex4   RGBA8            Main: geometric world normal RG + lightmap BA;
//                                alt: weather sheet, selected after deferred5
//   colortex5   R11F_G11F_B10F   Persistent scene history H; the deferred1 direct
//                                fragment writes the caustic BRDF to W (suppressed
//                                flip, geometry texels only); composite flips
//                                expose W then H. Optional SSR mips are generated
//                                only on H.
//   colortex6   RGBA16UI         SSR depth16/rough8/selector8/unused8/age5/state3/
//                                log-variance16; no historical normal or M
//   colortex8   RGBA16F          Cloud history frame (primary, sky, T, distance);
//                                merged with the AO history: geometry pixels
//                                carry (AO*1020 integer, age, encoded view depth,
//                                A=NaN "not cloud") while GI is disabled
//   shadowcolor0 RGBA8           RSM: RGB565 reflectance (RG), oct8 shadow-view normal (BA)
//   colortex9   RGB16F           Half-res unblurred temporal GI irradiance,
//                                including uncovered SH; deferred4 flip history
//   colortex10  RGBA16F          Half-res GI history: oct6 normal/change count,
//                                luminance second moment, view depth,
//                                packed real age/receiver selector/source
//   colortex11  RGBA16          Opaque surface: RG oct8 world shading normal;
//                                B rough8/selector8, A emission8/AO8, UNORM16 pairs
//   colortex12  RGBA16F          Sequential workspace:
//                                deferred2 alt = low-res cloud current frame;
//                                deferred5 clears alt for translucency, then
//                                1. translucent premultiplied-over color + alpha
//                                2. composite1 refracts, fogs and over-composites once
//                                3. optional DOF (HDR RGB, 1/z; hand=-1)
//                                4. bloom pyramid workspace
//                                5. tonemapped LDR scene consumed by final/CAS
//
// TAAU uses a cropped lower-left scene rectangle through composite3, then
// composite4 restores display-sized colortex0/5.

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
const int colortex8Format  = RGBA16F;  // sky: primary/sky weights, T, km; geometry: AO*1020, age, view depth, A=NaN
const int colortex9Format  = RGB16F; // half-res temporal irradiance (deferred4)
const int colortex10Format = RGBA16F; // half-res GI geometry/age history (deferred4)
const int colortex11Format = RGBA16;          // normalized opaque surface packet
const int colortex12Format = RGBA16F;
const int shadowcolor0Format = RGBA8;
*/

#if defined(OPAQUE_SSR) && OPAQUE_SSR_FILTER > 0
/*
const int colortex6Format = RGBA16UI;
*/
const bool colortex6Clear = false;
#endif

// -- Clear flags --
// true = cleared each frame before shader writes. false = carry data across frames.
const bool colortex0Clear  = false;   // scene output
const bool colortex1Clear  = false;   // GBuffer albedo
const bool colortex2Clear  = false;   // AO scratch, then translucent low bytes/flag
const bool colortex3Clear  = false;   // unblurred opaque reflection history
const bool colortex4Clear  = true;    // weather alt must start transparent
const bool colortex5Clear  = false;  // TAA history
const bool colortex8Clear  = false;   // cloud history frame (persistent; GTAO history merged on geometry pixels)
const bool colortex9Clear  = false;   // unblurred temporal GI history
const bool colortex10Clear = false;   // actual previous GI receiver geometry/age
const bool colortex11Clear = false;  // opaque geometry overwrites before depth-valid reads
// colortex12 hands one buffer forward through the frame: clouds use alt,
// deferred5 zero-fills the active scene before translucency,
// optional DOF overwrites the active scene metadata before its gather,
// bloom rewrites each atlas tile before sampling it, and tonemap rewrites the
// whole display rect. TAAU's inactive margin is never read, and Iris still
// clears on allocation and resize, so the recurring clear only re-zeroes
// regions that every reader overwrites first.
const bool colortex12Clear = false;  // sequential workspace

#endif // LIB_CONTRACT_RESOURCES_GLSL
