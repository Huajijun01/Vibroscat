#ifndef LIB_CONTRACT_RESOURCES_GLSL
#define LIB_CONTRACT_RESOURCES_GLSL

// ════════════════════════════════════════════════════════════════════════════
// Buffer declarations — format declarations are in shaders.properties section
// ════════════════════════════════════════════════════════════════════════════
//
// Buffer map (deferred pipeline):
//   colortex0   R11F_G11F_B10F   Scene color (post-processed) / TAA input
//   colortex1   RGBA8            GBuffer: albedo sRGB / materialID
//   colortex2   RGBA16           Opaque gbuffer (normal/AO/roughness/metalness/emission), then
//                                translucent surface data after deferred clears it:
//                                RG = refraction normal.xy, B = normal.z, A = water flag;
//                                blend off (nearest translucent surface wins)
//   colortex3   R11F_G11F_B10F   Opaque reflection radiance trace transient
//   colortex4   RGBA8            Opaque geometric normal (RG) + lightmap (BA) (solid -> deferred2)
//   colortex5   R11F_G11F_B10F   TAA history
//   colortex8   RGBA16F          Cloud history frame (sun, moon, T, distance);
//                                merged with the AO history: geometry pixels
//                                carry (ao, age, 1-depth, A=NaN "not cloud")
//   colortex12  RGBA16F          Translucent layer (premultiplied color + alpha):
//                                1. translucent gbuffers blend off = nearest surface wins
//                                2. composite1 refracts, fogs and over-composites once
//                                3. bloom pyramid workspace
//                                4. tonemapped LDR scene consumed by final/CAS
//
// This ledger documents existing ownership only. Allocation, clear, flip, and
// pass scheduling remain defined by Iris declarations and shaders.properties.

/*
// Format declarations: Iris reads these declarations as text before
// compiling the shader, so the buffer formats stay effective even though
// the block is commented out (the same constants are also injected by Iris
// at compile time, which is why they cannot be declared live).
const int colortex0Format  = R11F_G11F_B10F;
const int colortex1Format  = RGBA8;
const int colortex2Format  = RGBA16;
const int colortex3Format  = R11F_G11F_B10F;
const int colortex4Format  = RGBA8;
const int colortex5Format  = R11F_G11F_B10F;
const int colortex8Format  = RGBA16F;  // cloud history frame: sunRad, moonRad, transmittance, distance_km; AO history merged on geometry pixels (ao, age, 1-depth, A=NaN)
const int colortex12Format = RGBA16F;
*/

// ── Clear flags ──
// true = cleared each frame before shader writes. false = carry data across frames.
const bool colortex0Clear  = false;   // scene output
const bool colortex1Clear  = false;   // GBuffer albedo
const bool colortex2Clear  = false;   // GBuffer merged data
const bool colortex3Clear  = false;   // opaque reflection radiance transient
const bool colortex4Clear  = false;   // opaque geometric normal + lightmap
const bool colortex5Clear  = false;  // TAA history
const bool colortex8Clear  = false;   // cloud history frame (persistent; GTAO history merged on geometry pixels)
const bool colortex12Clear = true;   // sequential GBuffer, bloom, and tonemap workspace

#endif // LIB_CONTRACT_RESOURCES_GLSL
