# Third-Party Notices

[中文版](THIRD_PARTY_NOTICES.md) | [English](THIRD_PARTY_NOTICES.en.md)

This file is the single declaration point for all third-party code, assets, and algorithm references in Vibroscat. The main license is the GNU GPL v3 in the root `LICENSE` file.

## 1. Photon Shaders (historical reference; current code contains no substantial copies)

Photon Shaders (Copyright © 2021-2025 Benjamin Stott "SixthSurge", custom license) was an early source for two features, both removed and replaced in 2026-08:

- `GetNdotHSquared` in `shaders/lib/lighting/brdf.glsl` was originally transcribed from Photon's `include/lighting/bsdf.glsl`, then replaced using the Guerrilla Decima Engine public lecture (Johan Andersson, SIGGRAPH 2017). The current small-disc approximation uses reflection-chord shrinkage without Newton iteration; see section 10. It contains no Photon code expression.
- The temporal AO depth/offcenter rejection in `shaders/lib/lighting/temporal_ao.glsl` (GTAO_DEPTH_REJECTION=16.0, GTAO_OFFCENTER_STRENGTH=0.25, matching Photon's `d3_ao.fsh`; the offcenter trick is itself attributed by Photon to Zombye/Jessie) has been fully rewritten as an independent implementation (world-space displacement + normal-consistency rejection, see the file header comment); the original formulas and constants have been deleted.

The redistribution restrictions of Photon's custom license do not apply to the pack's current code.

## 2. AgX (concept; current implementation in section 3)

`TonemapAGX` in `shaders/lib/color/tonemap_agx.glsl` is the HSV hue-repair variant of the AgX family. The AgX concept comes from Troy Sobotka:

- [SOB22] Sobotka, Troy. "AgX". 2022. https://github.com/sobotka/AgX (concept and configuration; upstream repository has no license, referenced for concept only)

The curve, the log shaper and the hue repair now come from DRT Bench; see section 3 for that provenance. Before 2026-10 the pack used linlin's AgX-S2O3 analytic implementation (MIT, https://github.com/bWFuanVzYWth/AgX @ 0796e1b4aa9df94152eff353bae131eae1a4c087); that curve and its implementation were removed with the 2026-10 tone-mapper list change and are no longer distributed.

## 3. DRT tone mapping (GPL-3.0)

`TonemapAGX` (`TONEMAP_MODE == 0`) is ported from DRT Bench (github.com/bWFuanVzYWth/DRT, by linlin), `shaders/agx_hsv.wgsl`, at that tool's `AgxParameters::hsv_default()` curve: the -10 .. +6.5 EV log2 shaper, the sRGB OETF(0.18) output pivot, the 1.55 / 5.2 toe and shoulder powers, the 0.05 gamut compression, and the HSV hue-repair stage that this variant is named for.

The repository is published under `GPL-3.0-only` since 2026-09 (LICENSE
added in commit 49e67a3), compatible with this pack's GPLv3. The operator uses
the reference's fixed defaults, including black/white hue retention 1.0/0.5.
The former pack contrast, gamma, saturation and invented looks were removed.
The reference's final display-signal clamp is followed by sRGB decoding for
the pack's display-linear post-processing. No artistic preset is supplied
for this HSV variant by the reference; Blender AgX's official looks belong
to mode 2, below.

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

`shaders/textures/starmap_2020_4k_logluv32.dat` is baked from the linear EXR of NASA SVS #4851 "Deep Star Maps 2020" (Plate Carrée projection, LogLuv32 encoding, raw RGBA8).

> Image credit: NASA's Scientific Visualization Studio / ESA-ESO-Sky-Survey
> Source: https://svs.gsfc.nasa.gov/4851/ . NASA material is a work of the US government and is in the public domain.

## 8. Spatiotemporal blue noise STBN (algorithmic reference)

`shaders/textures/stbn_scalar_128x128x64.dat` is independently generated with the void-and-cluster algorithm; algorithm and default parameters from: Wolfe, Morrical, Akenine-Möller, Ramamoorthi. "Scalar Spatiotemporal Blue Noise Masks". 2022. (preceded by Heitz, Belcour, Ostromoukhov. "Spatiotemporal Blue Noise Masks". ACM TOG 2019.)

## 9. LogLuv32 encoding (algorithmic reference)

LogLuv32 decoding (`LogLuv32ToLinear` in color.glsl) follows: Ericson, Christer. "Converting RGB to LogLuv in a fragment shader". 2007. The matrix stream matches Alpha Piscium v1.9.1 (GPLv3); GPLv3 is compatible with the pack's main license.

## 10. Guerrilla Decima Engine (algorithmic reference)

The reference for the spherical-area highlight target in `GetNdotHSquared` is Andersson, Johan. "Decima Engine: Advances in Lighting and AA". SIGGRAPH 2017 Advances in Real-Time Rendering in Games. https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa (PDF: https://www.realtimerendering.com/advances/s2017/DecimaSiggraph2017.pdf). The current implementation approximates the small sun/moon discs by shrinking the half-vector angular distance using the reflection-to-light chord; it does not retain the lecture's bent-light Newton solve.

## 11. Blender EEVEE (GPL-2.0-or-later, algorithmic reference)

The index-of-refraction recovery in `F0ToIOR` uses the Blender EEVEE approximation (GPL-2.0-or-later, compatible with GPLv3).

## 12. SSR lineage and independent rewrite (chocapic13)

The original implementation of `lib/raytrace/ssr.glsl` was of chocapic13 lineage (an earlier source label was corrected). The current file has been fully rewritten as an independent implementation: linear-depth hit criterion, constant-step march covering screen edges or the far plane, interval bisection refinement; no original structure, constants, or wording are retained.

## 13. Other mathematical/convention references

- `FastSin`: Bhaskara I sine approximation (circa 12th century, public-domain mathematics)
- R2 sequence (R2Offset in lib/core/noise.glsl, continuous jitter for cloud and other temporal accumulators): Roberts, Martin. "The Unreasonable Effectiveness of Quasirandom Sequences" (public constants 1.3247179572 / 1.7548776662)
- `LowBias32Hash` in `lib/core/noise.glsl`: lowbias32 constants from Wellons, Chris. "Prospecting for Hash Functions" (released by the author as public domain)
- specular channel convention in `material/core.glsl`: oldPBR/seusPBR specifications (data-format convention, not code)

## 14. Atmosphere model provenance note

The four-wave atmosphere model in `lib/atmosphere/` uses OPAC/libRadtran input tables: 450/510/580/650 nm, US-standard air and ozone, and piecewise-linear profiles for the inso/waso/soot/suso aerosols. Density/phase models reference Hillaire 2020 (section 6). The remaining model, fits, and bakes are this pack's own implementation.

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

Addendum (2026-10-24): the optional directional sky visibility of the SSGI
fallback (`lib/lighting/ssgi_sky_visibility.glsl`, `SSGI_DIRECTIONAL_SKY`) is
this pack's own mathematics, not part of the GT-VBGI reference: it reduces the
trace's occupancy bitmask to a directional moment through eight conditional
four-bit group means combined by a Walsh transform, and scales the sky SH's L2
band by the visible mass. The coefficients are fitted offline by this project;
the underlying SH diffuse transport follows Ramamoorthi & Hanrahan 2001 as
cited in `lib/atmosphere/sky_light.glsl`.

## 16. Reflective Shadow Maps and temporal reconstruction (algorithmic references)

The RSM source encoding, sampling and reconstruction in
`shaders/lib/lighting/rsm_data.glsl`, `reflective_shadow_map.glsl` and
`gi_history.glsl` and `gi_denoise.glsl` are independent implementations for Vibroscat.
`gi_sampling.glsl` independently implements a digitally shifted 3D Sobol sequence
with binary direction-number recurrences; no external direction table or sampling
code was copied. History barycentric weights are independently derived from
planar triangle areas.

- Carsten Dachsbacher and Marc Stamminger, *Reflective Shadow Maps*, I3D 2005,
  [DOI: 10.1145/1053427.1053460](https://doi.org/10.1145/1053427.1053460):
  virtual point lights from the light-visible surfaces.
- I. M. Sobol, *On the distribution of points in a cube and the approximate
  evaluation of integrals*, 1967: algorithmic reference for digital low-discrepancy sequences.
- Christoph Schied et al., *Spatiotemporal Variance-Guided Filtering:
  Real-Time Reconstruction for Path-Traced Global Illumination*, HPG 2017,
  [author publication and paper](https://research.nvidia.com/publication/2017-07_spatiotemporal-variance-guided-filtering-real-time-reconstruction-path-traced),
  [DOI: 10.1145/3105762.3105770](https://doi.org/10.1145/3105762.3105770):
  demodulated irradiance, independently validated history taps, and edge-aware
  reconstruction. This pack does not implement the full SVGF filter.
- iterationT 3.2.0 (`GlobalIllumination.glsl` and shadow outputs) was examined
  for architecture comparison only. Its redistribution permission was not
  established. No source or assets from that pack are included in this change.

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

Source: <https://blog.selfshadow.com/publications/s2025-shading-course/pdi/supplemental/gt7_tone_mapping.cpp>
(version 1.0, 2025-08-10)
(course slides `s2025_pbs_pdi_slides_v1.1.pdf` and the companion
`gt7_tone_mapping.cpp`).

Porting adaptations:

- Linear Rec.709 input/output is converted to/from the sample's Rec.2020
  framebuffer domain (1.0 = 100 nits). Restores the pack's pre-rewrite input
  scale of 2.508318700610, mapping 18% scene gray to 18% display gray.
- Retains the official SDR peak 2.5, gray point 0.538, linear section 0.444,
  toe strength 1.28, blend 0.6 and chroma fade 0.98-1.16. Restores the pack's
  alpha-0 shoulder (sample: 0.25), smoothly approaching paper white.
  Parameters are fixed; this SDR adaptation is the pack's default mapper.
- Uses the default ICtCp UCS, with the ITU forward matrix and its inverse.
  PQ decoding clamps its signal to [0,1] as in the sample. The final SDR
  clamp follows Rec.2020-to-Rec.709 conversion so sharpening receives
  display-range color.
- The sample offers SDR/HDR display targets and an alternative JzAzBz
  internal color space, not a collection of artistic looks. This SDR pack
  fixes the default ICtCp path and exposes no numerical GT7 settings.
- GPU output is checked against frozen pre-rewrite GT7 output from this pack.
  Different float32 rounding through ST2084 is allowed within 5e-4 of display
  white. This adaptation does not claim exact official SDR output.

## 18. Cloud multiple-scattering approximation (algorithm source)

This pack's in-cloud multiple-scattering approximation comes from

<https://zhuanlan.zhihu.com/p/457997155>

that is, a saturation factor and the isotropic geometric series standing for
every order past the first. The source writes it as
`fms = omega * (1 - exp2(-300 * sigma_t))`, driven by the extinction in m^-1.
This pack rewrites the argument as a DIMENSIONLESS reference optical depth whose
knee is one optical depth over a reference length owned by the layer itself: 300 m
for the volumetric layer and 0.5 km for cirrus, half of its 1 km thickness.
Cirrus uses `tau_vertical * 0.5 km / 1 km` with a default series strength of 1.0.
These lengths and strengths are per-layer calibrations. They do not replace
view-path extinction or multiply the first scattering by density again.

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

## 21. TAA and temporal upscaling

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

The unified history path introduced in 2026-10 shares settings across native
and reduced scene resolutions. RGB neighborhood confidence, symmetric color
scales, and a smooth motion ceiling are independently designed for this pack.
Concept study compared the general history-limiting ideas in Playdead's public
TemporalReprojection (MIT, https://github.com/playdeadgames/temporal ) and Unity
HDRP TemporalAntialiasing (https://github.com/Unity-Technologies/Graphics ).
No source was copied or closely translated. Variance clipping from Salvi's
*An Excursion in Temporal Supersampling* (GDC 2016) was an experimental
comparison only and is not part of the shipped implementation.

## 22. ACES 2.0 Output Transform (Apache-2.0 / BSD-3-Clause)

`TonemapACES2` in `shaders/lib/color/tonemap_aces2.glsl` (`TONEMAP_MODE == 1`)
adapts the complete ACES 2.0 SDR 100-nit Rec.709 output transform. The
Academy reference and the input chromatic adaptation are from
<https://github.com/ampas/aces-core> (2.0, 2025-04-04) and
<https://github.com/ampas/aces-output>, under Apache-2.0 (Appendix A):

> Copyright Contributors to the ACES Project.
> SPDX-License-Identifier: Apache-2.0

The GPU transform in `shaders/lib/third_party/opencolorio/aces2_output.glsl`
is generated by OpenColorIO 2.6.0's official built-in
`ACES-OUTPUT - ACES2065-1_to_CIE-XYZ-D65 - SDR-100nit-REC709_2.0`:

- Upstream: <https://github.com/AcademySoftwareFoundation/OpenColorIO/tree/v2.6.0>.
- License: BSD-3-Clause; copyright Contributors to the OpenColorIO Project.
  The complete copyright, conditions, and disclaimer are retained in that
  distributed GLSL file.
- GPU generator: `src/OpenColorIO/ops/fixedfunction/FixedFunctionOpGPU.cpp`.

Modifications and integration:

- Rec.709/D65 scene input is converted to AP0 with Bradford adaptation.
  The official AP1 clamp follows that conversion; source RGB is not clipped
  first, which would change signed out-of-gamut hues.
- The complete forward transform includes Hellwig-2022 JMh, the MM tone
  scale, chroma compression, and display-cusp gamut compression. SDR viewing
  conditions and gamut boundaries are the official built-in's constants.
- OpenColorIO's reach and cusp/gamma textures are represented by immutable
  GLSL arrays, with the original hue interpolation. These are gamut-boundary
  tables, not sampled tone curves. No texture, custom image, buffer, or pass
  is added to the pack.
- The final Rec.709-to-XYZ conversion is omitted: the pack consumes
  display-linear Rec.709 and applies the sRGB OETF once in the final pass.
  The inverse output transform is not included.
- Uses the reference exposure, without a middle-gray calibration or player
  scale option. ACES output transforms specify display targets rather than
  artistic looks; the fixed target is SDR 100-nit Rec.709.
- Actual GLSL is compared with the complete OpenColorIO CPU transform on
  12,276 neutral, saturated, random HDR and signed inputs, within 5e-5 of
  display-linear white.

## 23. Blender AgX (GPL-2.0-or-later / BSD-3-Clause)

`TonemapBlenderAGX` in `shaders/lib/color/tonemap_blender_agx.glsl`
(`TONEMAP_MODE == 2`) reconstructs the Base Contrast formation represented
by Blender 4.0's AgX view transform. Blender is GPL-2.0-or-later, compatible
with this pack's GPLv3. AgX is Troy Sobotka's concept (section 2); this
configuration is EaryChow's and its sigmoid is Jed Smith's.

Authoritative distribution:
<https://github.com/blender/blender/tree/v4.0.0/release/datafiles/colormanagement>
(`config.ocio` and `luts/AgX_Base_sRGB.cube`). Mathematical references are
<https://github.com/EaryChow/AgX_LUT_Gen> (`AgXBasesRGB.py`,
`AgXBaseRec2020.py`, `working_space.py`, `sigmoid.py`, and the two lower
guard-rail generators). No generator Python source is distributed here.
The guard rails are independently reconstructed algebraically: with
unit-sum luminance weights the opponent compensation reduces to `2*Y-min`.

Formation and adaptations:

- Linear Rec.709 -> Rec.2020 -> lower input guard rail -> rotated/inset
  working gamut -> -10 .. +6.5 EV log shaper -> toe/shoulder sigmoid
  (slope 2.4, powers 1.5) -> power 2.4 linearization -> shortest-arc hue
  interpolation, 40% from original to formed hue -> outset/Rec.709 ->
  lower output guard rail -> display clamp.
- The guard-rail luminance weights match Blender 4.0's shipped LUT. The
  generator's June 2025 D65-weight revision changes saturated colors and is
  not substituted for the distribution being reproduced.
- The transform is evaluated analytically rather than through a sampled
  LUT. Between lattice nodes it therefore differs from Blender's tetrahedral
  interpolation. No exact match to interpolated LUT output is claimed.
- The upper guard rail is disabled in the generator and remains disabled.
- `TONEMAP_BLENDER_AGX_LOOK` selects Blender v4.0.0's actual nine looks:
  Base Contrast, Punchy, Greyscale, Very High Contrast, High Contrast,
  Medium High Contrast, Medium Low Contrast, Low Contrast and Very Low
  Contrast. The default is Base Contrast. The complete preset transforms
  run in the official 25-stop AgX Log process space before view formation.
- `shaders/lib/third_party/opencolorio/blender_agx_looks.glsl` is generated
  by OpenColorIO 2.6.0 from those `config.ocio` look transforms. Copyright
  Contributors to the OpenColorIO Project, BSD-3-Clause; the full license
  is retained in that file. Punchy includes the actual grading-tone and CDL
  stages. No look is approximated by a display-gamma/saturation shortcut.
- Every look is checked against the official OCIO CPU look transform with
  lossless optimization, followed by the independent analytical formation.
  The CPU's default approximate grading math is disabled in that oracle.
- Scene 18% grey maps to 18% display-linear without an input prescale.
- Validation against 5,000 exact lattice nodes of Blender 4.0's distributed
  57-cubed LUT, including colors with negative Rec.709 components, gave a
  maximum display-linear error of 1.1e-6. The complete analytical generator
  comparison on 12,248 valid neutral/HDR/signed inputs stayed below 1e-6.

## 24. AMD FidelityFX LPM (MIT; removed in V0.4.0)

`TonemapLPM` in `shaders/lib/color/tonemap_lpm.glsl` (`TONEMAP_MODE == 4`) was
ported from AMD's FidelityFX Luma Preserving Mapper, `ffx-lpm/ffx_lpm.h`
(header tag `[LPM] LUMA PRESERVING MAPPER 1.20200225`, MIT). Upstream:
<https://github.com/GPUOpen-Effects/FidelityFX-LPM> (retrieved 2026-10-11).
The mode was removed with the V0.4.0 tonemap mode list and is no longer
distributed; removing the code leaves no remaining distribution obligation.

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

Ported scope: the complete SDR formation for all seven enabled official
look presets (Standard, Arriba, Sylvan, Colorful, Aery, Dystopic, Umbra),
and all fourteen tonescale selections, including USE LOOK PRESET. The
developer-only Base look disabled in the upstream UI is not a player option.
`tonemap_opendrt_presets.glsl` contains the original complete parameter sets;
Look selects the set and Tonescale optionally overrides only its curve.
All raw parameters are fixed. Contrast Low/High, per-channel hue-shift
ranges and creative-white adaptation are included.

Port adaptations:

- Rec.709 scene-linear input, Rec.709 display-linear output, SDR peak 100
  nits, reference gray 10 nits and sRGB Display surround (`tn_su = 2`).
  The pack's final pass owns the sRGB OETF; DCTL signal encoding is omitted.
  No middle-gray alignment to another mapper is applied.
- At 100 nits, HDR gray boost is zero and HDR purity interpolation collapses
  the two purity curves. No HDR controls or display-format switches are
  exposed in this SDR pipeline.
- Fixed gamut matrices are folded, including P3D65 -> XYZ -> creative-white
  CAT -> Rec.709. The official range blend and normalization are preserved,
  including Aery's D75, Dystopic's D60 and Umbra's D50 creative whites.
- Signed RGB reaches the rendering space unchanged. A zero opponent vector
  selects a zero angle, avoiding undefined GLSL `atan(0,0)` while matching
  the reference neutral path.
- Actual GLSL is compared with the compiled official DCTL, with only host
  vector/math adapters and final signal-encoding bypass. All looks, all
  tonescales and cross-look overrides are checked on 12,276 HDR/signed
  samples each, within 2e-5 of display-linear white. All 98 Look/Tonescale
  combinations additionally receive finite/range checks.

## 26. Air fog density model (concept study)

Restored epipolar geometry retains the provenance and license in section 5. Height density, time-of-day modulation and weather response were studied read-only in iterationT 3.2.0 `shaders/Lib/IndividualFounctions/VolumetricFog.glsl` and Photon v1.3b `shaders/include/weather/fog.glsl`, `shaders/include/fog/overworld/{analytic,raymarched,constants}.glsl`. iterationT has no pack-level license in the snapshot and is treated as reserved; Photon explicitly permits examination and learning (upstream https://github.com/sixthsurge/photon). No source, close translation, distinctive expression, constant or asset was transferred.

The pack independently derives exponential-height clear density and a separate uniform, neutral rain Mie increment. Optical depth and dry-air scattering are closed form; mixed rain/clear source integration is independently derived and numerically evaluated. Rain increases neither Rayleigh scattering nor ozone/aerosol absorption. The pack retains its own four-band medium and phase functions, the dimensionless shadowed/unshadowed scattering ratio E, and uniform stratified shadow marching. Density defaults, reference height and scale height are independently authored.

## 27. Plant wind (concept study and independently generated asset)

Read-only study of Photon v1.3b `shaders/include/vertex/displacement.glsl`
and `shaders/block.properties` (custom license explicitly permitting examination
and learning; https://github.com/sixthsurge/photon), and MakeUp UltraFast 9.5c
`shaders/src/position_vertex.glsl`, `shaders/lib/vector_utils.glsl`,
`shaders/lib/config.glsl`, and `shaders/block.properties` (LGPL-3.0;
https://github.com/javiergcim/MakeUpUltraFast). The study informed attachment
points, double-plant state classes, full leaf cubes and stationary cane.
No source, close translation, distinctive formula, constant or texture was copied.

`lib/geometry/plant_wind.glsl` and `textures/plant_wind_rgba16f_64.dat` are
independently implemented/generated: divergence-free Fourier turbulence with
a von Karman-like spectrum, Taylor frozen advection, quadratic aerodynamic
drag, frequency-domain forced damped oscillators, and an Euler-Bernoulli
cantilever bending shape. These are classical physical/mathematical models;
no third-party solver was ported. Effective frequencies, damping, scales and
seed are independently authored; no obstacle-aware CFD or measured species
response is claimed.

## 28. Underwater epipolar shafts (concept study and generated asset)

The Intel/Yusov epipolar parameterization in section 5 is retained. Read-only
architecture study compared Alpha Piscium v1.9.1's `shaders/composite18.csh`
(GPL-3.0; https://github.com/Luna5ama/Alpha-Piscium) with Photon v1.3b's
`shaders/include/fog/overworld/raymarched.glsl` and `shaders/program/c0_vl.fsh`
(custom license allowing examination and learning; https://github.com/sixthsurge/photon).
No source, constants or textures from either pack were copied or closely translated.

`lib/volume/water_epipolar.glsl` is an independent implementation. The low-frequency
source `textures/godray_caustics_r16f_64x64x64.dat` is independently generated using
the same Phillips spectrum, seed, phases, analytic normals and Snell photon tracer
as this pack's existing caustics, at the 9 m focal layer with periodic spatial and
temporal low-pass filtering. It is not a third-party texture. Runtime projection
and integration follow the unrefracted world sun direction and add artistic
radiance to the scene; this does not claim full underwater volume transport.

## 29. Plant transmission and screen-space attenuation (concept study)

Read-only comparison studied iterationT 3.2.0's
`shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl` and `shaders/composite.fsh`
(no package license found; treated as reserved rights;
https://minegraph.cn/shaderpacks/12), and Photon v1.3b's
`shaders/include/lighting/diffuse_lighting.glsl` and
`shaders/include/lighting/shadows/ssrt.glsl` (custom license permitting
examination and learning; https://github.com/sixthsurge/photon). Concepts
studied include broad transmission, colored absorption, receiver-based plant
screen shadows, and estimates beyond shadow-map coverage. No source,
distinctive expressions, constants or assets were copied or closely translated.

`lib/lighting/plant_subsurface.glsl` and the changes to the existing shadow
paths are independent implementations using this pack's surface-normalized
HG helper, plant classes, diffuse reflectance and depth march. Thin-plant
angular compensation, map softness/bias, receiver extinction and continuous
map-to-screen confidence are independently chosen. Grass uses screen
attenuation at all distances; nearby leaf cubes trust map shelter and add
screen attenuation as map confidence falls. Both ordinary diffuse light and
its foliage enhancement share directional occlusion. The screen march reads
depth only, without classifying sampled blocker materials. Map, skylight and
vertex AO constrain missing screen evidence approximately; this does not
reconstruct physical leaf thickness or full light transport.

## 30. Two water surface modes (concepts and independently generated assets)

Low water surface quality preserves the original small waves. High quality's
`textures/mother_medium_large_r8_128.dat` and
`textures/mother_medium_large_slope_rg8_128.dat` are independently baked
128x128 R8 height and RG8 UV slope assets, not third-party textures. The
Phillips spectrum, Fourier synthesis and deep-water dispersion concepts
reference Jerry Tessendorf, *Simulating Ocean Water* (SIGGRAPH 2001).
The continuous invertible trochoidal compression, analytic derivatives,
bilinear least-squares projection and shared mother-basis fit are independent
project implementations; no third-party generator, code or asset was ported.
High quality reuses the same mother texels for five normal layers and three
POM height layers. Per-layer translations approximate dispersion rather than
providing per-mode FFT animation. Generated assets use the pack's GPL-3.0 license.

## 31. Opaque reflection material demodulation (concept only)

The signal convention of dividing a correctly weighted specular sample by a
stable integrated material factor before denoising, then restoring the current
factor, references NVIDIA NRD v4.18.0's README, "MATERIAL DEMODULATION":
https://github.com/NVIDIA-RTX/NRD . The inspected snapshot uses the NVIDIA RTX
SDKs LICENSE, not MIT. No NRD source, helper, fit coefficients or assets are
included. The project's `lib/lighting/specular_material_factor.glsl` rational
approximation is independently fitted to numerical integration of this pack's
GGX VNDF and Smith model. Reflection history, compact mean storage, current-frame
normal estimation, reconstruction and outlier suppression are independently
implemented for this pack and distributed under its GPL-3.0 license.

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
