# Third-Party Notices

[中文版](THIRD_PARTY_NOTICES.md) | [English](THIRD_PARTY_NOTICES.en.md)

本文件是 Vibroscat 全部第三方代码、资产与算法引用的单一声明点。主许可证见根目录 `LICENSE`（GNU GPL v3）。

## 1. Photon Shaders（历史参考；当前代码不含实质副本）

Photon Shaders（Copyright © 2021-2025 Benjamin Stott "SixthSurge"，自定义许可协议）曾是两个功能的早期来源，均已于 2026-08 移除并替换：

- `shaders/lib/lighting/brdf.glsl` 的 `GetNdotHSquared`（GGX 球形区域光，Newton 迭代弯曲光方向）曾转录自 Photon 的 `include/lighting/bsdf.glsl`；现已按 Guerrilla Decima Engine 公开讲座材料（Johan Andersson, SIGGRAPH 2017）重新转录，见第 11 节，不再包含 Photon 代码表达。
- `shaders/lib/lighting/temporal_ao.glsl` 的时序 AO 深度/offcenter 拒绝（GTAO_DEPTH_REJECTION=16.0、GTAO_OFFCENTER_STRENGTH=0.25，与 Photon `d3_ao.fsh` 相同；offcenter 技巧由 Photon 自身标注源自 Zombye/Jessie）已整体重写为独立实现（世界位移 + 法线一致性拒绝，见该文件头注释），原公式与常量已全部删除。

当前源码中保留的 "Photon-style" / "Photon default" 注释仅为参数与概念来源标注，不构成 Photon 代码副本；Photon 自定义许可协议中的再分发限制不适用于本包当前代码。历史移植与清理记录保留在 Git 历史中。

## 2. HanPi Volume Cloud（派生代码，MIT + 附加署名）

`shaders/lib/cloud/volumetric.glsl` 的各向同性多重散射场（phi_fwd）派生自 HanPi Volume Cloud（AshenOneArt），MIT 许可并附额外署名要求：

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

来源：https://github.com/AshenOneArt/HPVolumeCloud （其中的 Docs/PhiFwd_FromRTE.md 为本地参考，不随发布物分发）。

## 3. AgX（概念 + MIT 实现）

`shaders/lib/color/color.glsl` 的 `TonemapAGX` 基于 AgX-S2O3 解析曲线（linlin, MIT），概念来源为 Troy Sobotka 的 AgX：

- [SOB22] Sobotka, Troy. "AgX". 2022. https://github.com/sobotka/AgX （概念与配置；上游仓库无许可证，仅作概念引用）
- [LIN24] linlin, "AgX". 2024. MIT License. Copyright (c) 2024 linlin. 上游：https://github.com/bWFuanVzYWth/AgX @ 0796e1b4aa9df94152eff353bae131eae1a4c087

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

## 4. DRT 色调映射（作者直接授权）

`TonemapOklabDRT`（Björn Ottosson "A display rendering transform", 2021）与 `TonemapReinhardGamut` 移植自 DRT Bench（github.com/bWFuanVzYWth/DRT，作者 linlin）。DRT Bench 仓库尚未选择开源协议（publish=false），但作者已直接授权 Vibroscat 使用（2026-08；如需书面确认可向 linlin 索取）。Oklab 概念与公式来自 Björn Ottosson 的公开文章。

## 5. AMD FidelityFX CAS（MIT）

`shaders/lib/third_party/fidelityfx/cas.glsl` 是 AMD FidelityFX Contrast Adaptive Sharpening 的精简 GLSL 改编（Copyright (c) 2017-2019 Advanced Micro Devices, Inc.），MIT 许可全文保留在该文件头部。原始来源：https://github.com/GPUOpen-Effects/FidelityFX-CAS

## 6. Intel Outdoor Light Scattering（Apache-2.0，概念与框架）

`shaders/lib/volume/epipolar_core.glsl` 的 epipolar 切片/扇形参数化跟随 Intel Outdoor Light Scattering Sample（Intel，Apache-2.0）。另参考 Yusov, Egor. "Practical Implementation of Light Scattering Effects Using Epipolar Sampling and 1D Min/Max Binary Trees". GDC 2013。本包实现为独立表达，未逐行复制。Apache-2.0 全文见本文件附录 A。

## 7. Unreal Engine Sky Atmosphere（MIT，算法引用）

大气透射率 LUT 重建（cloud/render.glsl 的 GetTransmittance 方案）与云体积噪声布局（TileableVolumeNoise）参考 Sebastien Hillaire 的 UE4 SkyAtmosphere 实现（Epic Games, MIT）：

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

另引用 Bruneton & Neyret, "Precomputed Atmospheric Scattering", CGF 27(4), 2008（概念）。

## 8. NASA Deep Star Maps 2020（公有领域）

`shaders/textures/starmap_2020_4k_logluv32.png` 由 NASA SVS #4851 "Deep Star Maps 2020" 线性 EXR 烘焙而来（Plate Carrée 投影，LogLuv32 编码）。

> Image credit: NASA's Scientific Visualization Studio / ESA-ESO-Sky-Survey
> 来源：https://svs.gsfc.nasa.gov/4851/ 。NASA 素材为美国政府作品，属于公有领域。

## 9. 时空蓝噪声 STBN（算法引用）

`shaders/textures/stbn_scalar_128x128x64.dat` 按 void-and-cluster 算法独立生成，算法与默认参数来自：Wolfe, Morrical, Akenine-Möller, Ramamoorthi. "Scalar Spatiotemporal Blue Noise Masks". 2022. （前身为 Heitz, Belcour, Ostromoukhov. "Spatiotemporal Blue Noise Masks". ACM TOG 2019.）

## 10. LogLuv32 编码（算法引用）

LogLuv32 解码（color.glsl 的 `LogLuv32ToLinear`）遵循：Ericson, Christer. "Converting RGB to LogLuv in a fragment shader". 2007. 矩阵流与 Alpha Piscium v1.9.1（GPLv3）一致；GPLv3 与包主许可证兼容。

## 11. Guerrilla Decima Engine（算法引用）

`GetNdotHSquared` 的 GGX 球形区域光近似（含 Newton 迭代弯曲光方向）来自：Andersson, Johan. "Decima Engine: Advances in Lighting and AA". SIGGRAPH 2017 Advances in Real-Time Rendering in Games. https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa （PDF：https://www.realtimerendering.com/advances/s2017/DecimaSiggraph2017.pdf）

## 12. Blender EEVEE（GPL-2.0-or-later，算法引用）

`F0ToIOR` 的折射率恢复采用 Blender EEVEE 的近似（GPL-2.0-or-later，与 GPLv3 兼容）。

## 13. SSR 血统与独立重写（chocapic13）

`lib/raytrace/ssr.glsl` 原实现属 chocapic13 血统（早期来源标注有误，已更正）。当前文件已整体重写为独立实现：线性深度命中判据、覆盖屏幕边界或远平面的常数步长、区间折半细化，未沿用原结构、常量或写法。重写记录保留在 Git 历史中。

## 14. 其它数学/惯例引用

- `FastSin`：Bhaskara I 正弦近似（约 12 世纪，公有领域数学）
- TAA 抖动 R2 序列：Roberts, Martin. "The Unreasonable Effectiveness of Quasirandom Sequences"（公开常数 1.3247179572 / 1.7548776662）
- `material/core.glsl` 的 specular 通道约定：oldPBR/seusPBR 规格（数据格式约定，非代码）

## 15. 大气模型出处说明

`lib/atmosphere/core.glsl` 的 4-波谱大气模型（410/480/560/630 nm）为包作者的离线拟合实现（HSPEAtmosCreator 工具，不入库），密度/相位函数参考 Hillaire 2020（见第 7 节）。此前注释中 "sky-tracer" 字样指向来源未记录的参考渲染器，已从代码注释移除；若作者确认具体来源与许可，追加到本节。

## 附录 A：Apache License 2.0 全文

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

## 附录 B：GNU GPL v3 说明

包主许可证见根目录 LICENSE（GPL-3.0 全文）。第三方 MIT/Apache-2.0 组件与 GPLv3 兼容；第 1 节记录的 Photon 历史不向当前源码附加分发条件。
