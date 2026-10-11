# Third-Party Notices

[中文版](THIRD_PARTY_NOTICES.md) | [English](THIRD_PARTY_NOTICES.en.md)

This file is the single declaration point for all third-party code, assets, and algorithm references in Vibroscat. The main license is the GNU GPL v3 in the root `LICENSE` file.

## 1. Photon Shaders (historical reference; current code contains no substantial copies)

Photon Shaders (Copyright © 2021-2025 Benjamin Stott "SixthSurge", custom license) was an early source for two features, both removed and replaced in 2026-08:

- `GetNdotHSquared` in `shaders/lib/lighting/brdf.glsl` (GGX spherical-area light with Newton-iterated bent light direction) was transcribed from Photon's `include/lighting/bsdf.glsl`; it has since been re-transcribed from the Guerrilla Decima Engine public lecture material (Johan Andersson, SIGGRAPH 2017), see section 10, and no longer contains Photon code expression.
- The temporal AO depth/offcenter rejection in `shaders/lib/lighting/temporal_ao.glsl` (GTAO_DEPTH_REJECTION=16.0, GTAO_OFFCENTER_STRENGTH=0.25, matching Photon's `d3_ao.fsh`; the offcenter trick is itself attributed by Photon to Zombye/Jessie) has been fully rewritten as an independent implementation (world-space displacement + normal-consistency rejection, see the file header comment); the original formulas and constants have been deleted.

The redistribution restrictions of Photon's custom license do not apply to the pack's current code. The historical port and cleanup records remain in the Git history.

## 2. AgX (concept + MIT implementation)

`TonemapAGX` in `shaders/lib/color/color.glsl` is based on the AgX-S2O3 analytic curve (linlin, MIT), with the AgX concept from Troy Sobotka:

- [SOB22] Sobotka, Troy. "AgX". 2022. https://github.com/sobotka/AgX (concept and configuration; upstream repository has no license, referenced for concept only)
- [LIN24] linlin, "AgX". 2024. MIT License. Copyright (c) 2024 linlin. Upstream: https://github.com/bWFuanVzYWth/AgX @ 0796e1b4aa9df94152eff353bae131eae1a4c087

> AgX-S2O3
> Upstream: https://github.com/bWFuanVzYWth/AgX
> Revision: 0796e1b4aa9df94152eff353bae131eae1a4c087
>
> MIT License
>
> Copyright (c) 2024 linlin
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## 3. DRT tone mapping (direct author permission; GPL-3.0)

`TonemapOklabDRT` (Björn Ottosson "A display rendering transform", 2021), `TonemapReinhardGamut` (`TONEMAP_MODE == 3`) and `TonemapReinhardAgx` (`TONEMAP_MODE == 5`) are ported from DRT Bench (github.com/bWFuanVzYWth/DRT, by linlin). The virtual-primary gamut, the Reinhard curve, the AgX log shoulder and the HSV hue repair are that tool's designs; the Oklab concept and formulas come from Björn Ottosson's public articles.

When Oklab and Reinhard-Gamut were ported in 2026-08 the repository had not selected an open-source license (publish=false), and the author granted Vibroscat permission directly (written confirmation available from linlin on request). Since 2026-09 the repository is published under `GPL-3.0-only` (LICENSE added in commit 49e67a3), which is compatible with this pack's main license, GNU GPL v3.

## 4. AMD FidelityFX CAS (MIT)

`shaders/lib/third_party/fidelityfx/cas.glsl` is a trimmed GLSL adaptation of AMD FidelityFX Contrast Adaptive Sharpening (Copyright (c) 2017-2019 Advanced Micro Devices, Inc.), with the full MIT license retained in the file header. Original source: https://github.com/GPUOpen-Effects/FidelityFX-CAS

## 5. Intel Outdoor Light Scattering (Apache-2.0, concept and framework)

The epipolar slice/fan parameterization in `shaders/lib/volume/epipolar_core.glsl` follows the Intel Outdoor Light Scattering Sample (Intel, Apache-2.0). Also referenced: Yusov, Egor. "Practical Implementation of Light Scattering Effects Using Epipolar Sampling and 1D Min/Max Binary Trees". GDC 2013. The pack's implementation is an independent expression and does not copy lines. The full Apache-2.0 text is in Appendix A of this file.

## 6. Unreal Engine Sky Atmosphere (MIT, algorithmic reference)

The atmospheric transmittance LUT reconstruction (GetTransmittance scheme in cloud/render.glsl) and the volumetric cloud noise layout (TileableVolumeNoise) reference Sebastien Hillaire's UE4 SkyAtmosphere implementation (Epic Games, MIT):

> MIT License
>
> Copyright (c) 2020 Epic Games, Inc.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

Also referenced (concept): Bruneton & Neyret, "Precomputed Atmospheric Scattering", CGF 27(4), 2008.

## 7. NASA Deep Star Maps 2020 (public domain)

`shaders/textures/starmap_2020_4k_logluv32.png` is baked from the linear EXR of NASA SVS #4851 "Deep Star Maps 2020" (Plate Carrée projection, LogLuv32 encoding).

> Image credit: NASA's Scientific Visualization Studio / ESA-ESO-Sky-Survey
> Source: https://svs.gsfc.nasa.gov/4851/ . NASA material is a work of the US government and is in the public domain.

## 8. Spatiotemporal blue noise STBN (algorithmic reference)

`shaders/textures/stbn_scalar_128x128x64.dat` is independently generated with the void-and-cluster algorithm; algorithm and default parameters from: Wolfe, Morrical, Akenine-Möller, Ramamoorthi. "Scalar Spatiotemporal Blue Noise Masks". 2022. (preceded by Heitz, Belcour, Ostromoukhov. "Spatiotemporal Blue Noise Masks". ACM TOG 2019.)

## 9. LogLuv32 encoding (algorithmic reference)

LogLuv32 decoding (`LogLuv32ToLinear` in color.glsl) follows: Ericson, Christer. "Converting RGB to LogLuv in a fragment shader". 2007. The matrix stream matches Alpha Piscium v1.9.1 (GPLv3); GPLv3 is compatible with the pack's main license.

## 10. Guerrilla Decima Engine (algorithmic reference)

The GGX spherical-area light approximation in `GetNdotHSquared` (including Newton-iterated bent light direction) is from: Andersson, Johan. "Decima Engine: Advances in Lighting and AA". SIGGRAPH 2017 Advances in Real-Time Rendering in Games. https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa (PDF: https://www.realtimerendering.com/advances/s2017/DecimaSiggraph2017.pdf)

## 11. Blender EEVEE (GPL-2.0-or-later, algorithmic reference)

The index-of-refraction recovery in `F0ToIOR` uses the Blender EEVEE approximation (GPL-2.0-or-later, compatible with GPLv3).

## 12. SSR lineage and independent rewrite (chocapic13)

The original implementation of `lib/raytrace/ssr.glsl` was of chocapic13 lineage (an earlier source label was corrected). The current file has been fully rewritten as an independent implementation: linear-depth hit criterion, constant-step march covering screen edges or the far plane, interval bisection refinement; no original structure, constants, or wording are retained. The rewrite record remains in the Git history.

## 13. Other mathematical/convention references

- `FastSin`: Bhaskara I sine approximation (circa 12th century, public-domain mathematics)
- TAA jitter R2 sequence: Roberts, Martin. "The Unreasonable Effectiveness of Quasirandom Sequences" (public constants 1.3247179572 / 1.7548776662)
- `LowBias32Hash` in `lib/core/noise.glsl`: lowbias32 constants from Wellons, Chris. "Prospecting for Hash Functions" (released by the author as public domain)
- specular channel convention in `material/core.glsl`: oldPBR/seusPBR specifications (data-format convention, not code)

## 14. Atmosphere model provenance note

The 4-wave spectral atmosphere model (410/480/560/630 nm) in `lib/atmosphere/core.glsl` is the pack author's offline-fit implementation (the HSPEAtmosCreator tool is not shipped), with density/phase functions referencing Hillaire 2020 (see section 6). A previous "sky-tracer" comment pointing to an undocumented reference renderer has been removed from the code comments; if the author confirms the specific source and license, it will be appended to this section.

## 15. GT-VBGI / ReferenceGI (CC0 1.0)

The screen-space visibility-bitmask GI in
`shaders/program/deferred/recursive_gi.fragment` is ported from Mirko Salm's
unidirectional GT-VBGI reference implementation. That source offers a choice of
CC0 1.0 Universal or the MIT License; this pack uses it under CC0 1.0
Universal: https://creativecommons.org/publicdomain/zero/1.0/. Reference:
https://www.shadertoy.com/view/XcdBWf (bidirectional variant:
https://www.shadertoy.com/view/lfdBWn). The fast arctangent approximation in
the reference source separately cites https://www.shadertoy.com/view/lXBfWm.

Provenance correction (2026-09-09): an earlier adaptation of this GI borrowed
several expressions from the Sundial-Lite (GPL-3.0, Copyright © 2026
GeForceLegend) port: the inlined slice-relative CDF simplification with its
[w0, 1] offset remap form, the `floatBitsToUint` sector quantization, and the
distance-scaled geometry thickness term. All of them were replaced with the
corresponding forms of the CC0/MIT reference above. Addendum (2026-09-12): the
last retained item, the homogeneous screen-edge ray clamp with its `far + 32.0`
limit, was also replaced by the pack's own solver `ClipRayScreenExitT` in
`lib/core/coordinates.glsl` (per-axis positive-t slab semantics, independently
written; the `far + 32.0` fallback limit is kept as a caller argument). No
Sundial-Lite expression remains in this pack. The temporal reconstruction in
`gi_denoise.glsl` is an independent SVGF-style implementation; its
design-level comparison uses a 2x2 history pattern.

## 16. Reflective Shadow Maps and temporal reconstruction (algorithmic references)

The RSM source encoding, sampling and reconstruction in
`shaders/lib/lighting/rsm_data.glsl`, `reflective_shadow_map.glsl` and
`gi_history.glsl` and `gi_denoise.glsl` are independent implementations for Vibroscat.

- Carsten Dachsbacher and Marc Stamminger, *Reflective Shadow Maps*, I3D 2005,
  [DOI: 10.1145/1053427.1053460](https://doi.org/10.1145/1053427.1053460):
  virtual point lights from the light-visible surfaces.
- Christoph Schied et al., *Spatiotemporal Variance-Guided Filtering:
  Real-Time Reconstruction for Path-Traced Global Illumination*, HPG 2017,
  [author publication and paper](https://research.nvidia.com/publication/2017-07_spatiotemporal-variance-guided-filtering-real-time-reconstruction-path-traced),
  [DOI: 10.1145/3105762.3105770](https://doi.org/10.1145/3105762.3105770):
  demodulated irradiance, independently validated history taps, and edge-aware
  reconstruction. This pack does not implement the full SVGF filter.
- iterationT 3.2.0 (`GlobalIllumination.glsl` and shadow outputs) was examined
  for architecture comparison only. Its redistribution permission was not
  established. No source or assets from that pack are included in this change.

### ReBLUR diffuse denoising (algorithmic reference)

`gi_reblur*.glsl` and the corresponding compute stages are independently written
GLSL implementations for Vibroscat. References are NVIDIA's
[ReBLUR overview](https://developer.nvidia.com/rtx/ray-tracing/rt-denoisers) and the
[NRD 4.17.3 documentation](https://cdn.jsdelivr.net/gh/NVIDIA-RTX/NRD@4.17.3/README.md):
long/fast histories, history repair, adaptive blur and spatial feedback. This
reduced adaptation uses the pack's geometry and distance encoding.
It includes no NRD SDK, HLSL source or runtime. Revelation (Apache-2.0) and Alpha
Piscium (GPL-3.0) were architecture comparisons; no source or assets were copied.

## 17. GT7 Tone Mapping (MIT, ported from the official Polyphony Digital sample)

`TonemapGT7` in `shaders/lib/color/color.glsl` (`TONEMAP_MODE == 4`) is ported
from the official sample implementation `gt7_tone_mapping.cpp` released by
Polyphony Digital with the SIGGRAPH 2025 course material *Driving Toward
Reality: Physically Based Tone Mapping and Perceptual Fidelity in Gran Turismo 7*
(Kentaro Suzuki, Kenichiro Yasutomi). The sample code is explicitly MIT
licensed:

> gt7_tone_mapping.cpp is licensed under the MIT license.
>
> Copyright (c) 2025 Polyphony Digital Inc.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

Source: <https://blog.selfshadow.com/publications/s2025-shading-course/pdi/>
(course slides `s2025_pbs_pdi_slides_v1.1.pdf` and the companion
`gt7_tone_mapping.cpp`).

Porting adaptations:

- The sample's linear Rec.2020 frame-buffer domain (1.0 = 100 nits) is entered
  and left through linear BT.709 <-> BT.2020 matrices derived from the
  primaries, matching the pack's linear sRGB convention.
- A `GT7_MID_GREY_SCALE` input prescale (numerically solved from
  0.4*curve(2.50832*0.18) = 0.18) re-anchors 18% grey, the anchor shared with
  the other tonemap modes; the curve keeps the official SDR preset (peak 2.5,
  gray point 0.538, linear section 0.444, toe strength 1.28, blend 0.6,
  chroma fade 0.98-1.16) with one deliberate deviation: alpha is 0 (a legal
  sample parameter) instead of 0.25, so the shoulder converges exactly to
  paper white — this pack's pipeline lacks GT7's in-engine exposure
  normalization, and the sample's overshooting shoulder hard-clipped roughly
  half a stop of highlights above scene white.
- The UCS is the sample default ICtCp (ITU-R BT.2124, Rec.2020); the ICtCp
  inverse matrix is an exact-by-definition constant.
- Exposed settings: `TONEMAP_GT7_BLEND`, `TONEMAP_GT7_CHROMA_FADE_START`,
  `TONEMAP_GT7_CHROMA_FADE_END` (defaults are the official sample values).

## 18. Cloud multiple-scattering approximation (algorithm source)

This pack's in-cloud multiple-scattering approximation comes from

<https://zhuanlan.zhihu.com/p/457997155>

that is, a saturation factor and the isotropic geometric series standing for
every order past the first. The source writes it as
`fms = omega * (1 - exp2(-300 * sigma_t))`, driven by the extinction in m^-1.
This pack rewrites the argument as a DIMENSIONLESS reference optical depth whose
knee is one optical depth over a reference length owned by the layer itself: 300 m
for the volumetric layer, which is equivalent to its previous value, and 0.5 km
for the cirrus shell, which is that deck's own scale. It is not a shareable
constant, because the 300 in `300 * sigma_t` carries a length: a length
calibrated on a 100 km^-1 medium never reaches its knee in a 3 km^-1 shell, and
the series then contributes nothing.

The `omega` in that formula is per-layer as well: it is the medium's
single-scattering albedo, and water and ice are not the same medium. The
volumetric layer uses 0.99, pinned rather than driven by its CLOUD_MS_ALBEDO
control, and the cirrus uses 0.999.

`shaders/lib/cloud/multiple_scattering.glsl` is the single owner of that
dimensionless form and both cloud layers include it. Both layers add the series
to the sun and moon direct terms; the ambient path does not go through it. The
volumetric layer additionally folds the sun and moon into one traced direction,
and the cirrus layer does not fold them.

The file header and the constant comments record the values and the
implementation choices this pack makes around them. The three-octave directional
phase sum and the `1 / (1 + tau)` light transmittance that `volumetric.glsl`
also documents are this pack's own choices and are not part of this entry.

## 19. Rain ripples (independent implementation and generated asset)

Rain ripples use an offline periodic slope texture. The design comparison
studied Zavie / Ctrl-Alt-Test's [Rain drops](https://www.shadertoy.com/view/ldfyzl)
and spatial/time-periodic field ideas as conceptual references only.
The runtime code and `rain_ripples_rg8_256x256x64.dat` are independently created:
drop-size distributions, terminal fall speeds and impact-energy cavity modeling,
a finite-depth linear wave spectrum, Fourier height derivatives and linear slope
encoding. The fall-speed relation follows Atlas, Srivastava and Sekhon (1973),
[doi:10.1029/RG011i001p00001](https://doi.org/10.1029/RG011i001p00001).
Phase and group velocities follow the standard capillary-gravity dispersion
relation. Equivalent depth, wave-energy coupling and periodization are modeling
approximations; this is not a complete fluid simulation.
For readable circular ripples, the texture retains sparse large-drop impacts
and omits the dense small-drop wave field. Individual impacts still evolve
under the model above. Runtime rain ripples perturb normals without POM.
No reference code, hashes, baker, decoder or texture was copied. The generated
asset uses this pack's GPL-3.0 license.

## 20. Analytic water fog (measured coastal optics and independent implementation)

`shaders/lib/water/fog.glsl` always independently implements
Beer-Lambert transmission and closed-form single scattering in a homogeneous
medium. Visual and pipeline comparisons studied iterationT 3.2.0
`shaders/composite1.fsh` (restrained blue-green distance fog) and Photon v1.3b
`shaders/include/fog/simple_fog.glsl` (analytic integration).
iterationT's redistribution permission is unconfirmed and Photon uses a custom
license. Both were used for observational and conceptual comparison only;
no source, distinctive expressions, constants or assets were transferred.
The references' multiple-scattering boosts are not used.

Optical constants are adapted from Giuseppe Zibordi and Jean-François Berthon
(2024), [CoASTS-BiOMaP](https://doi.org/10.1594/PANGAEA.971945), licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
([methods paper](https://doi.org/10.5194/essd-16-5477-2024)).
The selected sample is `V770201`, Acqua Alta Oceanographic Tower, northern
Adriatic coastal waters: 2007-06-14 08:40:52, 45.31390 N / 12.50830 E,
optical measurements at approximately 1 m depth, temperature 23.207 C and
salinity 36.831. Both AC9 `a_t-w` and `c_t-w` exclude pure seawater;
particulate scattering is derived as `b_p = c_t-w - a_t-w`.
The pack uses effective RGB wavelengths of 650/550/450 nm: 650 is measured
directly; 550 is linearly interpolated between 510/555, and 450 between 440/488.

Pure-water absorption uses the integrating-cavity measurements of Pope and
Fry (1997), [doi:10.1364/AO.36.008710](https://doi.org/10.1364/AO.36.008710)
([OMLC numerical table](https://omlc.org/spectra/water/data/pope97.dat)).
Multiplying its cm^-1 values by 100 gives RGB `(0.34000, 0.05650, 0.00922) m^-1`.
Molecular seawater scattering is evaluated at the sample's temperature and
salinity using Zhang, Hu and He (2009),
[doi:10.1364/OE.17.005698](https://doi.org/10.1364/OE.17.005698),
and the [author's calculation method](https://www.oceanopticsbook.info/packages/iws_l2h/conversion/files/betasw_ZHH2009.m)
published by Ocean Optics Web Book under
[CC BY 2.0](https://creativecommons.org/licenses/by/2.0/).
Its RGB contribution is `(0.00085607, 0.00171818, 0.00400705) m^-1`.
Final absorption is `(0.341030, 0.065223, 0.054923) m^-1`, and total scattering
is `(0.130766, 0.140677, 0.147750) m^-1`. These optical coefficients are not
artificially scaled. Backscattering `bb` and diffuse attenuation `Kd` are not
substituted for total scattering or extinction.

Three effective RGB wavelengths, a homogeneous medium, Cornette-Shanks
parameter 0.15, directional weight 0.25, neutral source weight 0.10,
sky-brightness and wet-weather weights are analytic rendering approximations,
not measurements of the sample's full phase function or underwater light field.
The source weight restrains unshadowed fog lighting without changing measured
extinction or single-scattering albedo. Incident direct light uses measured
extinction for Beer-Lambert attenuation; diffuse sky light uses absorption
as an approximation for angular redistribution. Representative column depth
uses the same sky-brightness proxy as caustics, `(1 - skylight) * 15 m`, with
a 1 m minimum. This depth and uniform source are not per-pixel column
measurements. Occlusion integration, multiple scattering and full spectral
transport are not implemented; this does not claim to reproduce every aspect
of the measured water color.

## 21. TAAU (extension of the existing TAA)

TAAU extends `shaders/program/post/taa.fragment` and reuses its closest-depth
sampling, reprojection, neighborhood AABB clipping, blend weighting, and HDR
compression. Cubic reconstruction reuses `FastCatmullRom5Tap`, with bounds for
the cropped scene. `shaders/lib/core/render_scale.glsl` owns the render rectangle.
Design study covered Photon v1.3b's
`shaders/program/c3_taau_prep.fsh`, `c4_taa_exposure.fsh`, and cropped-scene/full-size
history layout, plus Revelation-dev's `shaders/program/post/TemporalAA.frag`.
Photon's custom license permits examination and learning; Revelation is Apache-2.0.
Only data flow and general algorithms were studied. No reference source was copied
or closely translated. Upstreams: https://github.com/sixthsurge/photon and
https://github.com/HaringPro/Revelation .

Temporal reconstruction references Yang, Liu, and Salvi,
"A Survey of Temporal Antialiasing Techniques" (2020). The extension retains
the pack's existing RGB bounds and HDRCompress/HDRDecompress round-trip.
Final sharpening reuses the pack's existing AMD FidelityFX CAS (section 4).

## 22. Khronos PBR Neutral Tone Mapper (Apache-2.0)

`TonemapPBRNeutral` in `shaders/lib/color/tonemap_pbr_neutral.glsl`
(`TONEMAP_MODE == 6`) is ported from the Khronos Group reference implementation
`PBR_Neutral/pbrNeutral.glsl`:

> Copyright 2024 The Khronos Group Inc.
> SPDX-License-Identifier: Apache-2.0

Upstream: <https://github.com/KhronosGroup/ToneMapping> (`PBR_Neutral/`).
The license is the Apache License 2.0 (full text in Appendix A). The
repository's `.reuse/dep5` declares `License: Apache-2.0` for
`PBR_Neutral/pbrNeutral.glsl`; the README and specification in that directory
are CC-BY-4.0. Retrieved 2026-10-11, source file SHA-256
`087a1542c8d12d2d0fb89f570057e4e8365cc04eee5bff76c6e365cfa69f3734`. The
reference implementation is the Khronos PBR Neutral specification itself
(the F90 = 0.04, Ks = 0.8 - F90 and Kd = 0.15 equations); this pack rewrites
the function body from those equations and documents where each constant
comes from. No other implementation was used.

Port adaptations:

- Under Apache-2.0 section 4(b), `tonemap_pbr_neutral.glsl` is a modified
  version of the work: the function is renamed `TonemapPBRNeutral`, the inline
  constants become named constants, the pre-scale comes from the pack's
  `TONEMAP_PBRN_INPUT_SCALE` option, and the input is clamped to non-negative.
- The specification's own scale takes 1.0 as the brightest scene value, so its
  F90 subtraction lands scene 18% grey on 0.14 display-linear, 0.36 EV below
  the 18% anchor the other modes in this pack share. The default
  `TONEMAP_PBRN_INPUT_SCALE` of (0.18 + F90)/0.18 = 1.2222222 re-anchors 18%
  grey on 18%; the value 1.0 is the reference's own scale.
- Not used: the repository's `config.ocio`, `pbrNeutral.cube` LUT and
  `lut-writer.mjs`. Only the GLSL reference implementation was ported.
- The operator is designed for a well-exposed scene whose values above 1.0 are
  small specular highlights. Handed this pack's sun, sky and emissive
  radiance, it maps them into the top 20% of the display range. That is the
  operator's designed behavior rather than a port defect, and both the source
  comment and the setting tooltip say so.

## 23. OpenDRT (GPL-3.0)

`TonemapOpenDRT` in `shaders/lib/color/tonemap_opendrt.glsl`
(`TONEMAP_MODE == 7`) is ported from Jed Smith's OpenDRT (Open Display
Rendering Transform) reference DCTL `display-transforms/opendrt/OpenDRT.dctl`
(its header identifies OpenDRT v1.1.0, GPLv3):

> OpenDRT v1.1.0
> Written by Jed Smith
> https://github.com/jedypod/open-display-transform
> License: GPLv3

Upstream: <https://github.com/jedypod/open-display-transform>. The repository
root `LICENSE` is the GNU GPL v3, the same license as this pack, so the port
keeps the attribution; under GPL-3.0 section 5(a) this notice states that the
pack modified the work (see below). Retrieved 2026-10-11, source file SHA-256
`645ba89745691742c5403f8de5964b5934cd1c59bf06fb1f1a1f6b45f54830a1`.

Ported scope: the complete `transform()` chain at `look_preset = 0`
(Standard look), `tonescale_preset = 0` (follow the look preset),
`display_encoding_preset = 0` (Rec.1886 / Rec.709), `clamp = 1` and linear
input - render-space desaturation, the tone-scale constraint solve, brilliance,
hyperbolic compression, the hue windows / hue contrast / two hue-shift stages,
purity compression with mid-range purity, inverse render space, display gamut
and whitepoint, post brilliance, purity softclip and the final toe. Per-pixel
results match the reference DCTL to a maximum deviation of 4e-15 in float64
over the default parameters and ten parameter regressions.

Port adaptations:

- SDR only: the peak luminance is fixed at 100 nits, so the display scale
  `ts_dsc` is 1, the HDR grey-boost term is `log2(1) = 0`, and the HDR purity
  lerp has zero weight (which collapses the reference's `tsn_pt` and
  `tsn_const` onto one curve). `tn_Lp`, `tn_gb` and `pt_hdr` are therefore not
  parameters here.
- The output feeds this pack's sRGB OETF in `post/final.fragment`, so the
  reference's inverse display EOTF is omitted, and the surround compensation
  uses the tool's "sRGB Display" preset (`tn_su = 2`, bright surround) rather
  than its default Rec.1886 preset, matching a 2.2-power encode in a bright
  viewing environment.
- Input and display gamut are fixed to Rec.709, so the reference's two-step
  conversions (Rec.709 -> XYZ D65 -> P3D65 and its inverse) fold into one
  constant matrix each; the Standard preset's creative whitepoint is D65,
  where that stage is the identity and is omitted.
- The default `TONEMAP_ODT_GREY_LUMINANCE` of 15.1306824 is the display grey
  luminance solved for "scene 18% grey -> 18% display-linear" at the default
  tone-scale parameters, not the tool's own default of 10.0. That reference
  default remains in the option's value list.
- Exposed as settings: `TONEMAP_ODT_GREY_LUMINANCE`, `TONEMAP_ODT_CONTRAST`,
  `TONEMAP_ODT_SHOULDER_CLIP`, `TONEMAP_ODT_TOE`, `TONEMAP_ODT_OFFSET`,
  `TONEMAP_ODT_RENDER_SATURATION`, `TONEMAP_ODT_PURITY_LOW`,
  `TONEMAP_ODT_PURITY_HIGH` and `TONEMAP_ODT_BRILLIANCE`, all defaulting to
  the Standard preset values except the grey luminance above. The remaining
  preset modules (the other look presets, Contrast Low/High, the creative
  whitepoint, and the per-channel hue-shift and brilliance subdivisions) are
  not ported: they are fixed to the Standard preset values, which the source
  comments state.

## Appendix A: Apache License 2.0 (full text)

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

## Appendix B: GNU GPL v3 note

The pack's main license is the root LICENSE file (full GPL-3.0 text). The third-party MIT/Apache-2.0 components are compatible with GPLv3; the Photon history recorded in section 1 adds no distribution conditions to the current source.
