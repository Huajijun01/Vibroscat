# Third-Party Notices

[中文版](THIRD_PARTY_NOTICES.md) | [English](THIRD_PARTY_NOTICES.en.md)

This file is the single declaration point for all third-party code, assets, and algorithm references in Vibroscat. The main license is the GNU GPL v3 in the root `LICENSE` file.

## 1. Photon Shaders (historical reference; current code contains no substantial copies)

Photon Shaders (Copyright © 2021-2025 Benjamin Stott "SixthSurge", custom license) was an early source for two features, both removed and replaced in 2026-08:

- `GetNdotHSquared` in `shaders/lib/lighting/brdf.glsl` (GGX spherical-area light with Newton-iterated bent light direction) was transcribed from Photon's `include/lighting/bsdf.glsl`; it has since been re-transcribed from the Guerrilla Decima Engine public lecture material (Johan Andersson, SIGGRAPH 2017), see section 11, and no longer contains Photon code expression.
- The temporal AO depth/offcenter rejection in `shaders/lib/lighting/temporal_ao.glsl` (GTAO_DEPTH_REJECTION=16.0, GTAO_OFFCENTER_STRENGTH=0.25, matching Photon's `d3_ao.fsh`; the offcenter trick is itself attributed by Photon to Zombye/Jessie) has been fully rewritten as an independent implementation (world-space displacement + normal-consistency rejection, see the file header comment); the original formulas and constants have been deleted.

The redistribution restrictions of Photon's custom license do not apply to the pack's current code. The historical port and cleanup records remain in the Git history.

## 2. HanPi Volume Cloud (derived code, MIT + additional attribution)

The volumetric-cloud dual-lobe HG phase function in `shaders/lib/scattering/phase.glsl`, and the three-octave directional multiple-scattering sum in `shaders/lib/cloud/volumetric.glsl` (`sum c_k*P_k/(1 + a_k*tau)`, driven by `CLOUD_MS_ATTENUATION`, `CLOUD_MS_CONTRIBUTION` and `CLOUD_MS_ECCENTRICITY`), are derived from HanPi Volume Cloud (AshenOneArt), MIT licensed with an additional attribution requirement. The isotropic multiple-scattering field (phi_fwd) from the same source lived in the same file until 2026-09, when it was replaced by Revelation's HaringPro model (see section 19); no phi_fwd code expression remains:

> MIT License
>
> Copyright (c) 2026 AshenOneArt
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
>
> Additional Attribution Requirement
>
> Any use, modification, or redistribution of this Software (in source or
> binary form), including incorporation into other projects, must include
> visible attribution to "HanPi Volume Cloud" / AshenOneArt and a link to:
> https://github.com/AshenOneArt/HPVolumeCloud
>
> Acceptable locations include: project README, documentation, credits screen,
> or third-party notices file shipped with the product.

Source: https://github.com/AshenOneArt/HPVolumeCloud (its Docs/PhiFwd_FromRTE.md is kept as a local reference and is not distributed with the pack).

## 3. AgX (concept + MIT implementation)

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

## 4. DRT tone mapping (direct author permission; GPL-3.0)

`TonemapOklabDRT` (Björn Ottosson "A display rendering transform", 2021), `TonemapReinhardGamut` (`TONEMAP_MODE == 3`) and `TonemapReinhardAgx` (`TONEMAP_MODE == 5`) are ported from DRT Bench (github.com/bWFuanVzYWth/DRT, by linlin). The virtual-primary gamut, the Reinhard curve, the AgX log shoulder and the HSV hue repair are that tool's designs; the Oklab concept and formulas come from Björn Ottosson's public articles.

When Oklab and Reinhard-Gamut were ported in 2026-08 the repository had not selected an open-source license (publish=false), and the author granted Vibroscat permission directly (written confirmation available from linlin on request). Since 2026-09 the repository is published under `GPL-3.0-only` (LICENSE added in commit 49e67a3), which is compatible with this pack's main license, GNU GPL v3.

## 5. AMD FidelityFX CAS (MIT)

`shaders/lib/third_party/fidelityfx/cas.glsl` is a trimmed GLSL adaptation of AMD FidelityFX Contrast Adaptive Sharpening (Copyright (c) 2017-2019 Advanced Micro Devices, Inc.), with the full MIT license retained in the file header. Original source: https://github.com/GPUOpen-Effects/FidelityFX-CAS

## 6. Intel Outdoor Light Scattering (Apache-2.0, concept and framework)

The epipolar slice/fan parameterization in `shaders/lib/volume/epipolar_core.glsl` follows the Intel Outdoor Light Scattering Sample (Intel, Apache-2.0). Also referenced: Yusov, Egor. "Practical Implementation of Light Scattering Effects Using Epipolar Sampling and 1D Min/Max Binary Trees". GDC 2013. The pack's implementation is an independent expression and does not copy lines. The full Apache-2.0 text is in Appendix A of this file.

## 7. Unreal Engine Sky Atmosphere (MIT, algorithmic reference)

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

## 8. NASA Deep Star Maps 2020 (public domain)

`shaders/textures/starmap_2020_4k_logluv32.png` is baked from the linear EXR of NASA SVS #4851 "Deep Star Maps 2020" (Plate Carrée projection, LogLuv32 encoding).

> Image credit: NASA's Scientific Visualization Studio / ESA-ESO-Sky-Survey
> Source: https://svs.gsfc.nasa.gov/4851/ . NASA material is a work of the US government and is in the public domain.

## 9. Spatiotemporal blue noise STBN (algorithmic reference)

`shaders/textures/stbn_scalar_128x128x64.dat` is independently generated with the void-and-cluster algorithm; algorithm and default parameters from: Wolfe, Morrical, Akenine-Möller, Ramamoorthi. "Scalar Spatiotemporal Blue Noise Masks". 2022. (preceded by Heitz, Belcour, Ostromoukhov. "Spatiotemporal Blue Noise Masks". ACM TOG 2019.)

## 10. LogLuv32 encoding (algorithmic reference)

LogLuv32 decoding (`LogLuv32ToLinear` in color.glsl) follows: Ericson, Christer. "Converting RGB to LogLuv in a fragment shader". 2007. The matrix stream matches Alpha Piscium v1.9.1 (GPLv3); GPLv3 is compatible with the pack's main license.

## 11. Guerrilla Decima Engine (algorithmic reference)

The GGX spherical-area light approximation in `GetNdotHSquared` (including Newton-iterated bent light direction) is from: Andersson, Johan. "Decima Engine: Advances in Lighting and AA". SIGGRAPH 2017 Advances in Real-Time Rendering in Games. https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa (PDF: https://www.realtimerendering.com/advances/s2017/DecimaSiggraph2017.pdf)

## 12. Blender EEVEE (GPL-2.0-or-later, algorithmic reference)

The index-of-refraction recovery in `F0ToIOR` uses the Blender EEVEE approximation (GPL-2.0-or-later, compatible with GPLv3).

## 13. SSR lineage and independent rewrite (chocapic13)

The original implementation of `lib/raytrace/ssr.glsl` was of chocapic13 lineage (an earlier source label was corrected). The current file has been fully rewritten as an independent implementation: linear-depth hit criterion, constant-step march covering screen edges or the far plane, interval bisection refinement; no original structure, constants, or wording are retained. The rewrite record remains in the Git history.

## 14. Other mathematical/convention references

- `FastSin`: Bhaskara I sine approximation (circa 12th century, public-domain mathematics)
- TAA jitter R2 sequence: Roberts, Martin. "The Unreasonable Effectiveness of Quasirandom Sequences" (public constants 1.3247179572 / 1.7548776662)
- `StarHashUint` in `celestial.glsl` (procedural star field): lowbias32 constants from Wellons, Chris. "Prospecting for Hash Functions" (released by the author as public domain)
- specular channel convention in `material/core.glsl`: oldPBR/seusPBR specifications (data-format convention, not code)

## 15. Atmosphere model provenance note

The 4-wave spectral atmosphere model (410/480/560/630 nm) in `lib/atmosphere/core.glsl` is the pack author's offline-fit implementation (the HSPEAtmosCreator tool is not shipped), with density/phase functions referencing Hillaire 2020 (see section 7). A previous "sky-tracer" comment pointing to an undocumented reference renderer has been removed from the code comments; if the author confirms the specific source and license, it will be appended to this section.

## 16. GT-VBGI / ReferenceGI (CC0 1.0)

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
distance-scaled geometry thickness term. All of them have been replaced with
the corresponding forms of the CC0/MIT reference above. Only the homogeneous
screen-edge ray clamp (including its `far + 32.0` limit) is retained from
Sundial-Lite with that author's explicit permission (verbal, 2026-09).
Sundial-Lite is no longer an expression source for the GI trace in this file.
The temporal reconstruction in `gi_denoise.glsl` remains an independent
SVGF-style implementation; the design-level comparison of its 2x2 history
pattern is recorded in `docs/recursive-gi-denoising-plan.md`.

## 17. Reflective Shadow Maps and temporal reconstruction (algorithmic references)

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
- iterationT 3.2.0 (`GlobalIllumination.glsl` and shadow outputs) and Revelation
  (`diffuse/Accumulate.frag`) were examined for architecture comparison only.
  iterationT's redistribution permission was not established; Revelation is
  Apache-2.0. No source or assets from either pack are included in this change.

## 18. GT7 Tone Mapping (MIT, ported from the official Polyphony Digital sample)

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

## 19. Revelation (Apache-2.0, volumetric-cloud scattering port)

The volumetric-cloud scattering model in `shaders/lib/cloud/volumetric.glsl` is
ported from Revelation (Apache-2.0), `shaders/lib/atmosphere/clouds/Render.glsl`,
specifically the directional component of `CloudMultiScatteringApproxHaringPro`,
evaluated once per light channel for both this pack's sun and its moon: the
the `1/4pi * fms/(1-fms)` isotropic geometric-series multiple-scattering
term. Upstream's `msVolume / (1 + 0.5*tau)` volume term, its ground bounce and its
skylight component are all unported. The directional phase octave
sum comes from this pack's own implementation, see section 2. The
multiple-scattering approximation itself comes from <https://zhuanlan.zhihu.com/p/457997155>.

Porting adaptations (this pack's changes relative to upstream):

- The phase input stays this pack's dual-lobe HG (section 2); Revelation's baked
  `CloudPhaseLut.bin` Mie phase table is not imported, so no third-party
  texture enters the pack.
- Upstream folds the sun and the moon into a single light direction and routes
  the second component of `CloudMultiScatteringApproxHaringPro` (its skylight
  term) through the sky irradiance. This pack reproduces the fold behind the
  `CLOUD_SINGLE_LIGHT` switch (on by default) and falls back to independent sun
  and moon traces when it is off; the ambient path is this pack's own, so only
  the function's directional component is ported and the skylight component is
  not.
- For the light colour, upstream sums both illuminances and relies on the
  earth-shadow term in its transmittance LUT to cut the sun off below the
  horizon. This pack has no such term, so `CloudTwilightWeight` holds the sun's
  colour through the fire-cloud band below the horizon and releases it once the
  antisolar side has fully taken over.
- The two packs use different radiance units: `CLOUD_MS_ALBEDO` and
  `CLOUD_MS_ISOTROPIC` are this pack's calibration parameters for quantities
  upstream hardcodes. Upstream drives both the geometric series' saturation and
  the final radiance scale from one layer albedo; this pack pins the saturation
  to the `CLOUD_MS_FMS_ALBEDO` constant and lets `CLOUD_MS_ALBEDO` scale the
  radiance linearly, because the `omega / (1 - omega)` mapping turns one slider
  step into a two-order-of-magnitude swing.
- Upstream weights its light optical-depth samples by `density * (i + 0.5)` and
  rescales globally; this pack keeps the same quadratic stratification with
  exact interval weights.
- Upstream transmits the direct term with Beer `exp(-tau)`; this pack keeps its
  own `1 / (1 + tau)` transmittance.
- Upstream has a single phase term; this pack keeps its three-octave HanPi sum
  and carries the HaringPro isotropic series as a separate added term rather
  than a replacement.

The full Apache-2.0 text is in Appendix A.

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
