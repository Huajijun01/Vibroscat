# Third-Party Notices

[中文版](THIRD_PARTY_NOTICES.md) | [English](THIRD_PARTY_NOTICES.en.md)

This file is the single declaration point for all third-party code, assets, and algorithm references in Vibroscat. The main license is the GNU GPL v3 in the root `LICENSE` file.

## 1. Photon Shaders (historical reference; current code contains no substantial copies)

Photon Shaders (Copyright © 2021-2025 Benjamin Stott "SixthSurge", custom license) was an early source for two features, both removed and replaced in 2026-08:

- `GetNdotHSquared` in `shaders/lib/lighting/brdf.glsl` (GGX spherical-area light with Newton-iterated bent light direction) was transcribed from Photon's `include/lighting/bsdf.glsl`; it has since been re-transcribed from the Guerrilla Decima Engine public lecture material (Johan Andersson, SIGGRAPH 2017), see section 10, and no longer contains Photon code expression.
- The temporal AO depth/offcenter rejection in `shaders/lib/lighting/temporal_ao.glsl` (GTAO_DEPTH_REJECTION=16.0, GTAO_OFFCENTER_STRENGTH=0.25, matching Photon's `d3_ao.fsh`; the offcenter trick is itself attributed by Photon to Zombye/Jessie) has been fully rewritten as an independent implementation (world-space displacement + normal-consistency rejection, see the file header comment); the original formulas and constants have been deleted.

The redistribution restrictions of Photon's custom license do not apply to the pack's current code. The historical port and cleanup records remain in the Git history.

## 2. AgX (concept; current implementation in section 3)

`TonemapAGX` in `shaders/lib/color/tonemap_agx.glsl` is the HSV hue-repair variant of the AgX family. The AgX concept comes from Troy Sobotka:

- [SOB22] Sobotka, Troy. "AgX". 2022. https://github.com/sobotka/AgX (concept and configuration; upstream repository has no license, referenced for concept only)

The curve, the log shaper and the hue repair now come from DRT Bench; see section 3 for that provenance. Before 2026-10 the pack used linlin's AgX-S2O3 analytic implementation (MIT, https://github.com/bWFuanVzYWth/AgX @ 0796e1b4aa9df94152eff353bae131eae1a4c087); that curve and its implementation were removed with the 2026-10 tone-mapper list change and are no longer distributed.

## 3. DRT tone mapping (GPL-3.0)

`TonemapAGX` (`TONEMAP_MODE == 0`) is ported from DRT Bench (github.com/bWFuanVzYWth/DRT, by linlin), `shaders/agx_hsv.wgsl`, at that tool's `AgxParameters::hsv_default()` curve: the -10 .. +6.5 EV log2 shaper, the sRGB OETF(0.18) output pivot, the 1.55 / 5.2 toe and shoulder powers, the 0.05 gamut compression, and the HSV hue-repair stage that this variant is named for.

The repository is published under `GPL-3.0-only` since 2026-09 (LICENSE added in commit 49e67a3), which is compatible with this pack's main license, GNU GPL v3. The log-domain contrast, the display-domain saturation/gamma, the look presets and the added `TONEMAP_AGX_HIGHLIGHT_HUE` control are Vibroscat's own additions; the reference operator has no such controls.

History: between 2026-08 and 2026-10 the pack also carried ports of this tool's Oklab DRT, Reinhard-Gamut and Reinhard-AgX (used at the time with the author's direct permission, before the repository chose a license). All three were removed in the 2026-10 tone-mapper list change and are no longer distributed.

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

`TonemapGT7` in `shaders/lib/color/tonemap_gt7.glsl` (`TONEMAP_MODE == 5`) is ported
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

## 22. ACES 2.0 Output Transform (Apache-2.0)

`TonemapACES2` in `shaders/lib/color/tonemap_aces2.glsl` (`TONEMAP_MODE == 1`)
is ported from the ACES 2.0 reference implementation:

> Copyright Contributors to the ACES Project.
> SPDX-License-Identifier: Apache-2.0

Upstream: <https://github.com/ampas/aces-core> (version 2.0, 2025-04-04) and
<https://github.com/ampas/aces-output>. Both are released under the Apache
License 2.0 (full text in Appendix A). Retrieved 2026-10-11; source files and
their SHA-256:

- `aces-core/lib/Lib.Academy.OutputTransform.ctl` - `8bdebd1d7f313fc652c8fc282cb73b6621834e1f760c1af9b305e9b70ad36e9d`
- `aces-core/lib/Lib.Academy.Tonescale.ctl` - `16bf0696f856c5f1b848fbac27be17604d98af4ef280cd61c638ce57049e7823`
- `aces-core/lib/Lib.Academy.ColorSpaces.ctl` - `2bf18df76298232fe7cf456c8469672b5a631d84a9ee884a6e5591fc82ee0f4e`
- `aces-output/d65/displayP3/Output.Academy.Rec709-D65_100nit_in_P3-D65_sRGB-Piecewise.ctl` - `4dc4af31672ddbe900cf5fad6888b01d772d10d1ff203efab44c1e45191c988d`

Port adaptations (under Apache-2.0 section 4(b) this states that the pack
modified the work):

- Ported: the Rec.709(D65) -> ACES2065-1 Bradford adaptation, the AP1 input
  clamp, the Hellwig-2022 CAM forward/inverse JMh conversions, the MM tone
  scale at a 100-nit peak, the hue-dependent chroma compression driven by both
  J and the tone-scaled J, and the Rec.709 display-linear output. Viewing
  conditions are the reference's fixed SDR set (dim surround, L_A = 100,
  Y_b = 20, 100-nit peak, model gamma cz = 1.1370560).
- Not ported: the display-cusp gamut compressor `gamut_compress_fwd` (which
  needs per-hue cusp and upper-hull gamma tables plus the nested solvers
  `find_display_cusp_for_hue` / `make_upper_hull_gamma_table`) and the whole
  inverse transform. This pack clamps in the display-linear domain instead, so
  extremely saturated highlights clip per channel; the chroma compression has
  already rolled those colors off, so common content is unaffected.
- **No lookup table of any kind.** The reference precomputes three 360-entry
  hue tables as a "compute once" optimisation; the only one this port needs,
  the reach limit, is solved per pixel with a bounded bisection (the reference
  table spans 72.5 .. 194.4, the port bisects [50, 250] in 8 steps - no table,
  nothing baked). Against the reference core the output differs by at most
  0.0078 display-linear (mean 0.0005) over 23016 samples.
- Anchoring: the reference maps scene 18% grey to c_d = 10.013 nits = 0.100
  display-linear. `TONEMAP_ACES2_INPUT_SCALE` (default 1.7133450, solved)
  re-anchors it on the 0.18 every other mode in this pack shares; 1.0 is the
  reference's own scale.

## 23. Blender AgX (GPL-2.0-or-later)

`TonemapBlenderAgX` in `shaders/lib/color/tonemap_blender_agx.glsl`
(`TONEMAP_MODE == 2`) is ported from the AgX view transform Blender has shipped
as the default for new files since 4.0 (Blender 4.0 color management release
notes; blender/blender!106355, "AgX View Transform"). Blender is released under
GPL-2.0-or-later, which is compatible with this pack's GNU GPL v3. The AgX
concept itself is Troy Sobotka's (section 2); the configuration Blender ships
is maintained by EaryChow (the `EaryChow-AgX` OCIO config and its
`AgX_LUT_Gen` generator).

Reference chain: `AgX_LUT_Gen/AgXBasesRGB.py`, `AgX_LUT_Gen/sigmoid.py`,
`AgX_LUT_Gen/working_space.py`, and Blender's shipped 57^3 `AgX_Base_sRGB.cube`.
The local snapshot lives under `research/AgX/official/` (development tree, not
distributed).

Port adaptations:

- Blender bakes this imaging chain into `AgX_Base_sRGB.cube`; this pack
  evaluates the same chain in **closed form** instead: linear sRGB -> (the
  Rec.709 -> Rec.2020 matrix folded with the AgX inset into one constant) ->
  the normalized -10 .. +6.5 EV log2 shaper -> the toe/shoulder contrast
  sigmoid (slope 2.4, power 1.5) -> the 2.4-power inverse of the AgX Base
  encoding -> (the AgX outset folded with Rec.2020 -> Rec.709) ->
  display-linear Rec.709. **No LUT, no baked curve, no sampled table.**
- Not ported: the per-channel chroma-angle mixing (40% in the generator) and
  the sRGB guard rails (`compensate_low_side`). Both are a second per-channel
  pass over an already formed image, and Blender's own realtime GLSL port of
  this configuration drops them for the same reason.
- Not ported: the optional contrast looks (Punchy and the other six). They are
  OCIO v2 grading-primary transforms acting in Blender's 25-stop "AgX Log"
  space, which is a different encoding from the 16.5-stop shaper this port (and
  the Base Contrast view transform) uses; the release notes describe them as
  darkening looks, so reproducing one outside its grading space would
  misrepresent it. This mode therefore exposes no operator settings.
- Anchor: the shaper puts scene 0.18 at 10/16.5 EV, which is the curve's own x
  pivot, and the curve satisfies curve(x_pivot) = y_pivot with y_pivot^2.4 =
  0.18; both matrices keep neutrals fixed (their rows sum to 1 within 1e-15).
  Scene 18% grey therefore lands on 18% display-linear with no pre-scale.
- Verification: the closed-form port was compared against the neutral diagonal
  of Blender's shipped `AgX_Base_sRGB.cube` over -10 .. +6.5 EV, agreeing to
  1.3e-05 in the encoded domain (6.6e-07 at -10 EV).

## 24. AMD FidelityFX LPM (MIT)

`TonemapLPM` in `shaders/lib/color/tonemap_lpm.glsl` (`TONEMAP_MODE == 4`) is
ported from AMD's FidelityFX Luma Preserving Mapper, `ffx-lpm/ffx_lpm.h`
(header tag `[LPM] LUMA PRESERVING MAPPER 1.20200225`):

> Copyright (c) 2017-2019 Advanced Micro Devices, Inc. All rights reserved.
> (the repository's `NOTICES.txt` records the same MIT code as "AMD copyrighted
> code (MIT) / Copyright (c) 2020 Advanced Micro Devices, Inc. All rights
> reserved."; the full MIT text is in that file)

Upstream: <https://github.com/GPUOpen-Effects/FidelityFX-LPM>. Retrieved
2026-10-11; source file SHA-256
`7a7c0f376c89bcecd51fe8a5d8ba3b34ec59841e9915cb5b3e16ee87e9448c4d`.

The reference is itself the ALU version (its changelog records "Switched from
using LUTs to doing the full mapping in ALU"), so **this port contains and needs
no lookup table**.

Port adaptations:

- Ported: `LpmSetup`'s toneScaleBias solve (`tone(x) = x^contrast / (x^shoulder
  * bias.x + bias.y)`, pinned by tone(midIn) = 0.18 and tone(hdrMax) = 1.0;
  folded into compile-time constants here) and the whole `LpmMap` chain: the
  ratio/luma split, the saturation power on the ratio, the tone curve applied
  to the luma of the *original* color (which is what makes the map luma
  preserving), the ratio re-scale, the crosstalk walk back into gamut and the
  final luma make-up.
- `LPM_CONFIG_709_709` with `LPM_COLORS_709_709`: working, output and container
  gamut are all Rec.709 D65, so the reference's `con`/`con2` matrices are
  identity and omitted, and its `clip` and `scaleOnly` paths are dead.
- Not ported: `soft` gamut mapping (the reference needs `con` alongside it and
  only reaches it when the working and output gamuts differ),
  `shoulder`/`shoulderContrast` (the reference's own value is 1.0 and its
  example disables it), the con2/scaleOnly output transforms (FS2, HDR10,
  scRGB), the FP16 packed path and `LpmSetupOut`. This pack returns
  display-linear Rec.709 and applies its sRGB OETF in `post/final.fragment`.
- Two guards cover inputs the reference documents as outside its contract
  ({0 .. hdrMax}) but can still receive: color == 0 makes its `1/max(rgb)` a
  division by zero (this port returns black), and once the tone-mapped luma
  reaches 1.0 every crosstalk cap term is 0, making its `lumaAdd/dot(cap,
  lumaT)` a 0/0 (this port takes the limit t = 0).
- Anchor: LPM's curve already maps midIn to 0.18, and every official preset
  uses exposure = log2(hdrMax), so the defaults (hdrMax 1024, exposure 10, from
  the FidelityFX sample) keep 18% grey in place. `TONEMAP_LPM_CONTRAST` defaults
  to 0.15, this port's one tuned value (the reference header's 0.25 and the
  sample's 0.0 are both selectable); `TONEMAP_LPM_SATURATION` defaults to 1.0,
  which corresponds to the reference's own neutral saturation value (this port
  re-expresses the reference's additive parameter as 1.0 = neutral).
- Verification: compared sample by sample against a Python transcription of
  `ffx_lpm.h` over 28084 samples (neutrals, primaries, secondaries and HDR
  noise across [0, 1024]), maximum deviation 6.5e-15; seven contrast and seven
  saturation settings each agreed to 7.1e-15; the neutral-grey response matches
  the reference point for point (0.18 -> 0.180000).

## 25. OpenDRT (GPL-3.0)

`TonemapOpenDRT` in `shaders/lib/color/tonemap_opendrt.glsl`
(`TONEMAP_MODE == 3`) is ported from Jed Smith's OpenDRT (Open Display
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
