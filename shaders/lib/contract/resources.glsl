#ifndef LIB_CONTRACT_RESOURCES_GLSL
#define LIB_CONTRACT_RESOURCES_GLSL

#include "/lib/contract/settings.glsl"

// Buffer map plus the Iris format/clear directives for every attachment.
// shaders.properties carries the customTexture formats and blend state, not these.
//
//   colortex0   R11F_G11F_B10F   deferred1 writes direct RGB + emission to the
//                                non-selected side (sky discards); the pass flip
//                                promotes it; deferred5 writes completed color;
//                                with CAS, composite21 writes the tonemapped display color
//   colortex1   RGBA8            GBuffer: albedo sRGB / materialID
//   colortex2   RGBA8            deferred2_a half-res AO workspace on alt;
//                                later translucent RGB UNORM16 low bytes/flag,
//                                paired with colortex1 high bytes/material ID
//   colortex3   R11F_G11F_B10F   Unblurred demodulated reflection mean, direct RGB
//   colortex4   RGBA8            Main: geometric world normal RG + lightmap BA;
//                                alt: weather sheet, selected after deferred5
//   colortex5   R11F_G11F_B10F   Persistent scene history H; deferred1 writes the
//                                caustic BRDF to W (suppressed flip, geometry texels
//                                only); composite flips expose W then H; optional SSR mips only on H.
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
//
// TAAU uses a cropped lower-left scene rectangle through composite3, then
// composite4 restores display-sized colortex0/5.

/*
// Format declarations. Iris reads them as raw source text even inside a block
// comment (the format names are not GLSL identifiers), so every line stays at
// column zero.
const int colortex0Format  = R11F_G11F_B10F;
const int colortex1Format  = RGBA8;
const int colortex2Format  = RGBA8;
const int colortex3Format  = R11F_G11F_B10F;
const int colortex4Format  = RGBA8;            // geometric world normal (octahedral RG) + lightmap
const int colortex5Format  = R11F_G11F_B10F;
const int colortex6Format  = RGBA16UI;
const int colortex8Format  = RGBA16F;  // sky: primary/sky weights, T, km; geometry: AO*1020, age, view depth, A=NaN
const int colortex9Format  = RGB16F; // half-res temporal irradiance (deferred4)
const int colortex10Format = RGBA16F; // half-res GI geometry/age history (deferred4)
const int colortex11Format = RGBA16;          // normalized opaque surface packet
const int colortex12Format = RGBA16F;
const int shadowcolor0Format = RGBA8;
*/

// -- Clear flags --
// true = cleared each frame before shader writes. false = carry data across frames.
const bool colortex0Clear  = false;
const bool colortex1Clear  = false;
const bool colortex2Clear  = false;
const bool colortex3Clear  = false;
const bool colortex4Clear  = true;    // weather alt must start transparent
const bool colortex5Clear  = false;
const bool colortex6Clear  = false;
const bool colortex8Clear  = false;   // persistent cloud/AO history
const bool colortex9Clear  = false;
const bool colortex10Clear = false;
const bool colortex11Clear = false;
// colortex12 hands one buffer forward through the frame; every reader overwrites
// its region first, and Iris still clears on allocation and resize.
const bool colortex12Clear = false;

#endif // LIB_CONTRACT_RESOURCES_GLSL
