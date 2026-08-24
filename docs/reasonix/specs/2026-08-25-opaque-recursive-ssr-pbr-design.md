# Opaque Recursive SSR PBR Design

Date: 2026-08-25

Status: approved for autonomous implementation

## Purpose

Add physically based indirect specular lighting for opaque materials. The
screen-space reflection stage reads the previous complete HDR scene from the
front copy of `colortex5`, traces against the current opaque depth buffer,
filters incident radiance before shading, and lets the final deferred pass
perform all material and BRDF integration. Since final TAA writes the current
scene back to `colortex5`, later frames can reflect reflections recursively.

The implementation must preserve the existing water, glass, caustic, cloud,
AO, and TAA contracts.

## Current State

Opaque geometry writes albedo and material ID to `colortex1`, packed shading
data to `colortex2`, and geometric normal plus lightmap to `colortex4`.
`deferred2` currently consumes those buffers, computes direct and diffuse
ambient lighting, clears `colortex2`, writes the lit scene to `colortex0`, and
writes the direct-light BRDF to the back copy of `colortex5` for underwater
caustics.

The front copy of `colortex5` remains the previous TAA scene because
`flip.deferred2.colortex5 = false`. Water and glass read that front copy before
the composite passes temporarily expose the caustic copy. `composite4` writes
the new complete HDR scene history.

The current material decoder is an oldPBR-style approximation. It treats
specular RGB as smoothness, continuous metalness, and emission; it does not
branch on `MC_TEXTURE_FORMAT_LAB_PBR`. Direct lighting already contains Burley
diffuse, GGX, height-correlated Smith visibility, and Schlick Fresnel, but F0
is fixed to `mix(0.04, albedo, metalness)`. Opaque environment specular is
absent and deferred emission is disabled.

## Scope

The first implementation changes opaque deferred rendering in all three
dimensions. It includes:

- minimum LabPBR material decoding required for normal, smoothness, dielectric
  F0, and metal classification;
- an explicit oldPBR fallback;
- stochastic GGX VNDF ray generation for opaque indirect specular;
- current-depth screen-space traversal;
- previous-frame hit reprojection and `colortex5` mip sampling;
- one full-resolution edge-aware spatial filtering pass;
- environment fallback and recursive-history stability controls;
- unified direct, diffuse-indirect, emissive, and specular-indirect PBR
  integration in the final deferred pass;
- quality settings, debug views, static validation, runtime captures, and GPU
  timing.

Water and glass keep their current forward SSR implementation. This work does
not add POM, a Hi-Z pyramid, multiple depth layers, secondary-surface motion
vectors, a dedicated reflection history, reflection moments, or a multiframe
reflection denoiser. Named LabPBR metal optical constants and microfacet
multiple-scattering compensation remain follow-up improvements after the
baseline is measured.

## Pass Schedule

The current opaque shading program moves from `deferred2` to `deferred4`.

```text
opaque gbuffers
  colortex1 = albedo + material ID
  colortex2 = shading normal + AO + material parameters
  colortex4 = geometric normal + lightmap
        |
        v
deferred1 / deferred1_a
  existing cloud and AO history work
        |
        v
deferred2: opaque reflection trace
  read  colortex1/2/4, depthtex1, colortex5 front mip chain
  write colortex3 raw hit radiance
  write colortex11 hit distance + confidence
        |
        v
deferred3: opaque reflection filter
  read  raw colortex3/11 + current depth/normal/roughness
  write filtered colortex3/11 through their alternate copies
        |
        v
deferred4: unified opaque PBR shading
  read  filtered colortex3/11 + colortex1/2/4
  write colortex0 lit opaque scene
  write zero to colortex2 for the translucent payload lifetime
  write direct BRDF to colortex5 back for caustics
        |
        v
translucent and composite passes
  unchanged water/glass SSR and caustic copy exposure
        |
        v
composite4 TAA
  write current complete HDR scene to colortex5
```

`deferred2.fsh` declares `const bool colortex5MipmapEnabled = true;` in each
world wrapper. Iris therefore builds the mip chain from the readable front
history immediately before tracing. The trace pass does not render to
`colortex5`, so it cannot disturb either physical copy.

The false flip directive moves to `flip.deferred4.colortex5 = false`, following
the caustic BRDF writer. The existing `flip.composite.colortex5` and
`flip.composite1.colortex5` directives do not change.

## Transient Resource Contract

`colortex3` becomes a full-resolution `R11F_G11F_B10F` transient reflection
radiance buffer. It stores non-negative previous-frame hit radiance before and
after filtering. The format matches the scene history and avoids spending an
alpha channel on metadata.

`colortex11` becomes a full-resolution `RG16F` transient metadata buffer.
The red channel stores the view-space path length from the ray origin to the
accepted hit, in blocks/metres. The green channel stores confidence in `[0, 1]`.
The trace and filter passes write
every pixel, so stale contents are never consumed while opaque SSR is enabled.

Both resources use normal colortex ping-pong behavior. `deferred2` writes raw
data and flips; `deferred3` reads raw data, writes filtered data, and flips;
`deferred4` reads the filtered front copies. They are not persistent histories.

The reflection direction is not stored. The trace and shading passes call the
same deterministic random function and GGX VNDF sampler with pixel position,
`frameCounter`, shading normal, view direction, and perceptual roughness. They
therefore reconstruct the same direction without another attachment.

## Material Contract

The G-buffer writer normalizes LabPBR and oldPBR inputs into one packed opaque
contract:

```text
colortex1.rgb = base color in the existing sRGB storage convention
colortex1.a   = material ID

colortex2.r bytes = shading normal X, combined vertex/material AO
colortex2.g bytes = shading normal Y, shading normal Z
colortex2.b bytes = perceptual roughness, raw specular selector
colortex2.a bytes = emission, porosity-or-SSS auxiliary value

colortex4.rg = geometric normal
colortex4.ba = block and sky lightmap
```

For LabPBR, specular R is converted from perceptual smoothness to perceptual
roughness. Specular G remains an exact eight-bit selector through the G-buffer.
Values 0 through 229 decode as scalar dielectric F0. Values 230 through 255
decode as metals with zero diffuse weight; the baseline uses base color as F0
for every encoded metal, which satisfies minimum metal classification without
claiming named-metal optical constants. Normal B contributes material AO.
Specular B is decoded as the standard porosity-or-SSS range rather than
emission. Specular A owns emission and honors the no-emission sentinel.

For oldPBR, R remains smoothness, G remains continuous metalness, B remains
emission, and A remains auxiliary. Deferred decoding maps it to
`F0 = mix(0.04, albedo, metalness)` and diffuse weight `1 - metalness`.

The deferred material value exposes perceptual roughness, microfacet alpha,
RGB F0, diffuse weight, emission, AO, and the optional auxiliary value. BRDF
helpers consume F0 and diffuse weight directly; they do not reconstruct a
generic material through a scalar metalness after this point.

## Reflection Trace

The trace pass runs once for each opaque surface pixel. Sky pixels and invalid
G-buffer pixels write zero radiance, zero distance, and zero confidence.

The pass reconstructs the current world and view position using the same TAA
jitter convention as opaque shading. It decodes both shading and geometric
normals. The shading normal controls the GGX lobe; the geometric normal controls
origin offset and rejects sampled directions below the actual surface.

Two decorrelated scalar samples come from the bundled STBN volume. Pixel
position selects XY, `frameCounter` selects Z, and a fixed wrapped offset
produces the second component. The implementation uses the Dupuy and Heitz
2023 spherical-cap visible-GGX sampler unless GLSL validation exposes a
numerical or instruction-count regression relative to Heitz 2018.

Microfacet alpha is `max(perceptualRoughness^2, 0.002)`. The sampler returns a
visible half vector and the pass reflects the view vector around it. Rays below
the geometric hemisphere are rejected to the environment fallback. A small
geometric-normal and view-depth bias prevents immediate self-intersection.

Opaque traversal uses a new function separate from the water/glass helper. It
implements perspective-correct pixel-space DDA based on McGuire and Mara 2014,
with explicit maximum distance, pixel stride, depth thickness, screen bounds,
and binary refinement. It samples the current opaque depth buffer and accepts
only a front-facing depth crossing within the distance-scaled thickness.

An accepted current-frame hit is converted to a previous-frame UV using the
hit depth and existing previous camera matrices. History acceptance multiplies
the following confidence terms:

- current trace thickness agreement;
- distance fade;
- screen-edge fade at both current hit and previous UV;
- current hit-surface normal facing;
- previous UV bounds;
- camera continuity;
- first-frame or reload validity.

There is no previous depth, normal, material, or secondary-object transform in
`colortex5`; those checks cannot be performed. Animated entity motion and
disocclusion are handled conservatively through confidence, radiance clamping,
and final TAA rather than claimed as exact reprojection.

The previous scene is sampled with explicit mip level. The level is derived
from projected GGX cone radius, hit distance, roughness, and screen resolution,
then clamped to the generated chain. Polished rays use mip zero. This is a
roughness and footprint approximation, not a prefiltered reflection history.

The trace output contains only history hit radiance. Misses write zero
confidence. Environment radiance is evaluated later in unified shading so it
is never temporally attenuated or blurred into the hit buffer.

## Reflection Filter

`deferred3` performs one full-resolution nine-tap cross-bilateral gather. The
center plus eight fixed ring offsets preserve isotropy better than a horizontal
only pass while keeping the first implementation to one extra filter pass.

The radius grows from zero for mirror-like materials to a bounded multi-pixel
radius for rough materials. Hit distance expands the projected footprint. Each
sample weight combines spatial kernel weight, linear-depth similarity,
geometric-normal similarity, shading-normal similarity, perceptual-roughness
similarity, hit-distance similarity, and source confidence.

Radiance is accumulated as confidence-weighted incident radiance. Confidence
is accumulated separately and normalized by compatible geometric weight. If
the radiance weight is too small, the filter writes zero history radiance and
zero confidence. It never fills a miss with unrelated sky or a sample across a
depth or normal discontinuity.

Very smooth surfaces retain the center trace to avoid softening mirror detail.
If runtime captures show unresolved rough noise at acceptable trace quality, a
second filter pass may be added later and unified shading moves to `deferred5`.
That extension is outside the baseline implementation and is justified only by
measured captures.

## Unified PBR Shading

The existing `deferred_shading.fragment` becomes the `deferred4` implementation.
Its sky path, shadows, plant transmission, cloud sky, lightmap, and caustic BRDF
output remain behaviorally intact.

Surface shading decodes the normalized material contract once. Direct light
uses Burley diffuse and the existing GGX distribution and correlated Smith
visibility, now with material RGB F0 and diffuse weight. Sky SH and block light
continue to feed diffuse irradiance only. Correct LabPBR emission is enabled
with a bounded shader setting rather than multiplied by zero.

The pass regenerates the trace direction deterministically. It samples the
current clouded directional environment along that direction and combines it
with filtered history:

```text
Li = mix(environmentRadiance,
         recursionDecay * sanitizedFilteredHistory,
         filteredConfidence)

indirectSpecular = Li * F(V,H,F0) * G2(V,L,H) / G1(V,H)
```

The `F * G2 / G1` estimator follows visible-normal importance sampling. The
geometry ratio is bounded by its physically valid range and degenerate dot
products return zero. Indirect specular receives conservative specular
occlusion derived from AO, view angle, and roughness. It is added once because
the current opaque pipeline has no environment specular term to replace.

Only the history branch uses `recursionDecay`, initially `0.92` and hard
clamped below `0.99`. History RGB is rejected when non-finite or negative.
Luminance is bounded relative to `smooth_lum` from the existing exposure SSBO
plus a fixed emergency ceiling, preventing a pair of facing reflectors from
amplifying quantization or stale highlights without clipping normal daylight.

The complete surface result is written once to `colortex0`. The pass clears
`colortex2` exactly where the current shader does and writes the direct-light
BRDF to the back copy of `colortex5`. Later TAA records the finished opaque SSR
inside the complete scene history, creating recursion on the next frame.

## Settings And Profiles

Opaque reflection settings use their own names and do not change the water SSR
step count. The initial public controls are an enable switch and a quality
level; detailed thresholds remain internal constants until profiling shows a
real user-facing tradeoff.

LOW disables opaque SSR and uses directional environment specular only.
MEDIUM uses 24 DDA steps and a four-pixel maximum filter radius. HIGH uses 40
steps and a six-pixel radius. ULTRA uses 64 steps and an eight-pixel radius.
All enabled tiers use six binary-refinement iterations and the same physical
material contract.

Debug compile options expose raw hit radiance, confidence, hit distance,
selected history mip, filtered radiance, decoded F0, roughness, and final
indirect-specular energy. They are not placed on the public settings screen.

## Failure Handling

Invalid directions, non-finite coordinates, traversal misses, rejected
history, and camera discontinuities return environment-only indirect specular.
No failure path returns uninitialized attachment data. Every trace and filter
pixel writes both transient outputs.

Shader reload and initial frames force history confidence to zero. Large camera
translation rejects history. Exact window-resize detection is not available
from the current persistent state; Iris buffer recreation plus first valid TAA
frames provide recovery, and resize is included in runtime validation.

The history contains translucent rendering, air fog, and DOF because TAA runs
after those stages. This can blur or contaminate recursive opaque reflections
when DOF is enabled. Post-processing order is outside the opaque-only scope, so
the first release documents and visually tests this limitation rather than
moving TAA or changing water and glass.

## Implementation Ownership

Material decoding is owned by `shaders/lib/material/core.glsl`, the solid
G-buffer writer, and BRDF helpers. Opaque tracing and filtering receive new
program files under `shaders/program/deferred/` and focused helpers under
`shaders/lib/raytrace/`. Shared uniforms, resource formats, settings, profiles,
and pass flips stay in their existing contract files.

All three `shaders/world*` wrapper trees receive matching `deferred2`,
`deferred3`, and `deferred4` wrappers. Wrapper parity is checked mechanically.
The water/glass programs and their existing SSR helper are not edited except
for any compile-only signature adaptation forced by the normalized material
contract; such an adaptation must preserve their rendered behavior.

## Validation

Static validation checks shader includes, resource declarations, draw target
locations, world-wrapper parity, settings references, exact LabPBR byte
boundaries, and whitespace errors. Patched Iris shaders are inspected after
reload for all three deferred programs and all three dimensions.

Runtime captures cover a smooth dielectric, rough dielectric, generic metal,
encoded metal, emissive surface, foliage, mirror pair, screen edge, off-screen
miss, disocclusion, moving entity, camera teleport, resize, shader reload,
rain/wetness, underwater caustics, water, and glass. Captures compare opaque SSR
off, raw trace, filtered trace, and final PBR output.

GPU traces measure the new trace pass, filter pass, moved shading pass, total
deferred interval, and total frame on MEDIUM, HIGH, and ULTRA. The baseline is
captured at commit `f416ab56a6d6114f30793d9001f57943a5c443fd` with the same
scene, resolution, camera, profile, warm-up, and capture duration. Acceptance
requires no material or pass-order regressions, stable recursive feedback, and
a recorded quality-versus-cost result; advanced traversal or another filter
pass is considered only after these measurements.

## Rollback And Commit Policy

Development occurs on `codex/opaque-recursive-ssr-pbr`. `main` and tag
`v0.1.0-alpha` retain the clean baseline commit
`f416ab56a6d6114f30793d9001f57943a5c443fd`.

Implementation is split into reviewable commits for the material contract,
transient resources and pass scheduling, trace, filter, PBR integration,
runtime fixes, and performance tuning. Each commit must pass the available
static checks before the next begins. Generated captures, GPU traces, patched
shaders, and downloaded papers remain ignored local artifacts and are never
mixed into source commits.
