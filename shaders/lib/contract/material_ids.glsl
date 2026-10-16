#ifndef LIB_CONTRACT_MATERIAL_IDS_GLSL
#define LIB_CONTRACT_MATERIAL_IDS_GLSL

// ============================================================================
// Material-ID protocol
// ============================================================================
//
// solid.vertex packs the material ID into the low byte of the gbuf1 alpha
// channel (colortex1.a = float(id) / 255.0) and every decoder recovers it with
// int(a * 255.0 + 0.5). This file names the class anchors that producer and
// consumers share. The per-class ranges and the per-block/per-entity
// assignments stay with their owners: shaders/block.properties,
// shaders/entity.properties, and lib/material/model.glsl (SSS 128-134).
//
// The anchors are `const int` rather than `#define` because every consumer
// uses them inside an int expression (the flat int varying, int equality
// tests, and entityId - MATERIAL_ID_ENTITY_BASE), so a typed constant keeps
// that arithmetic and those comparisons int-typed and stays an ordinary GLSL
// constant instead of a preprocessor option.

const int MATERIAL_ID_GENERIC = 0;         // basic/line/textured/textured_lit/particles
const int MATERIAL_ID_HAND = 64;           // hand/held item; also the shared hand test in taa/motionblur/gi/deferred
const int MATERIAL_ID_EMISSIVE = 112;      // beaconbeam, spidereyes (emissive class 112-127)
const int MATERIAL_ID_ENTITY_BASE = 10000; // entityId offset; see shaders/entity.properties

#endif // LIB_CONTRACT_MATERIAL_IDS_GLSL
