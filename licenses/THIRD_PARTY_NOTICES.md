# Third-Party Notices

[中文版](THIRD_PARTY_NOTICES.md) | [English](THIRD_PARTY_NOTICES.en.md)

本文件是 Vibroscat 全部第三方代码、资产与算法引用的单一声明点。主许可证见根目录 `LICENSE`（GNU GPL v3）。

## 1. Photon Shaders（历史参考；当前代码不含实质副本）

Photon Shaders（Copyright © 2021-2025 Benjamin Stott "SixthSurge"，自定义许可协议）曾是两个功能的早期来源，均已于 2026-08 移除并替换：

- `shaders/lib/lighting/brdf.glsl` 的 `GetNdotHSquared`（GGX 球形区域光，Newton 迭代弯曲光方向）曾转录自 Photon 的 `include/lighting/bsdf.glsl`；现已按 Guerrilla Decima Engine 公开讲座材料（Johan Andersson, SIGGRAPH 2017）重新转录，见第 11 节，不再包含 Photon 代码表达。
- `shaders/lib/lighting/temporal_ao.glsl` 的时序 AO 深度/offcenter 拒绝（GTAO_DEPTH_REJECTION=16.0、GTAO_OFFCENTER_STRENGTH=0.25，与 Photon `d3_ao.fsh` 相同；offcenter 技巧由 Photon 自身标注源自 Zombye/Jessie）已整体重写为独立实现（世界位移 + 法线一致性拒绝，见该文件头注释），原公式与常量已全部删除。

Photon 自定义许可协议中的再分发限制不适用于本包当前代码。历史移植与清理记录保留在 Git 历史中。

## 2. 体积云多重散射的早期参考（历史；当前代码不含派生代码）

本包体积云散射的早期实现曾参考 HanPi Volume Cloud（AshenOneArt，MIT 许可并附额外署名要求），其中的 phi_fwd 各向同性多重散射场位于 `shaders/lib/cloud/volumetric.glsl`。该场及其许可声明已于 2026-09 整体移除，当前体积云改用第 19 节记录的近似；本节不再附带该项目的许可条款，历史移植与清理记录保留在 Git 历史中。

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

## 4. DRT 色调映射（作者直接授权；GPL-3.0）

`TonemapOklabDRT`（Björn Ottosson "A display rendering transform", 2021）、`TonemapReinhardGamut`（`TONEMAP_MODE == 3`）与 `TonemapReinhardAgx`（`TONEMAP_MODE == 5`）移植自 DRT Bench（github.com/bWFuanVzYWth/DRT，作者 linlin）。虚拟原色色域、Reinhard 曲线、AgX 对数肩部与 HSV 色相修复均为该工具的设计；Oklab 概念与公式来自 Björn Ottosson 的公开文章。

2026-08 移植 Oklab 与 Reinhard-Gamut 时该仓库尚未选择开源协议（publish=false），作者已直接授权 Vibroscat 使用（如需书面确认可向 linlin 索取）。该仓库自 2026-09 起以 `GPL-3.0-only` 发布（commit 49e67a3 加入 LICENSE），与本包主许可证 GNU GPL v3 兼容。

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
- `celestial.glsl` 程序化点星的 `StarHashUint`：Wellons, Chris. “Prospecting for Hash Functions” 的 lowbias32 常量（作者声明为公有领域）

## 15. 大气模型出处说明

`lib/atmosphere/core.glsl` 的 4-波谱大气模型（410/480/560/630 nm）为包作者的离线拟合实现（HSPEAtmosCreator 工具，不入库），密度/相位函数参考 Hillaire 2020（见第 7 节）。此前注释中 "sky-tracer" 字样指向来源未记录的参考渲染器，已从代码注释移除；若作者确认具体来源与许可，追加到本节。

## 16. GT-VBGI / ReferenceGI（CC0 1.0）

`shaders/program/deferred/recursive_gi.fragment` 的屏幕空间可见性位掩码 GI 移植自
Mirko Salm 的单向 GT-VBGI 参考实现。该参考源码声明可在 CC0 1.0 Universal
或 MIT License 中任选其一；本包依据 CC0 1.0 Universal 使用：
https://creativecommons.org/publicdomain/zero/1.0/ 。参考实现：
https://www.shadertoy.com/view/XcdBWf （双向变体：https://www.shadertoy.com/view/lfdBWn ）。
参考源码中的快速反正切近似另标注来源为 https://www.shadertoy.com/view/lXBfWm 。

溯源更正（2026-09-09）：该 GI 的早期适配曾借用 Sundial-Lite（GPL-3.0，
Copyright © 2026 GeForceLegend）移植版中的若干表达：切片相对 CDF 的内联
简化与 [w0,1] 偏移重映射形式、`floatBitsToUint` 扇区量化、随距离缩放的
几何厚度项。本次变更已将其全部替换为上述 CC0/MIT 参考实现中的对应形式，
仅保留齐次空间屏幕边缘射线截断（含 `far + 32.0` 上限）一项，经 Sundial
作者口头许可继续使用（2026-09）。

追记（2026-09-12）：最后保留的该项也已替换为 `lib/core/coordinates.glsl`
的自有求解器 `ClipRayScreenExitT`（逐轴正 t slab 语义，独立编写，SSR 与
GI 共用；`far + 32.0` 回退上限作为调用方实参保留）。Sundial-Lite 的表达
自此不在本包残留；`gi_denoise.glsl` 的时域重建为独立 SVGF 风格实现，其
设计层面的 2×2 历史模式比较记录见 `docs/recursive-gi-denoising-plan.md`。

## 17. Reflective Shadow Maps 与时域重建（算法引用）

`shaders/lib/lighting/rsm_data.glsl`、`reflective_shadow_map.glsl` 和
`gi_history.glsl`、`gi_denoise.glsl` 中的 RSM 数据编码、采样与 GI 重建为 Vibroscat 独立实现。

- Carsten Dachsbacher、Marc Stamminger，*Reflective Shadow Maps*，I3D 2005，
  [DOI: 10.1145/1053427.1053460](https://doi.org/10.1145/1053427.1053460)：
  从光源可见表面构造虚拟点光源。
- Christoph Schied 等，*Spatiotemporal Variance-Guided Filtering:
  Real-Time Reconstruction for Path-Traced Global Illumination*，HPG 2017，
  [作者发布页及论文](https://research.nvidia.com/publication/2017-07_spatiotemporal-variance-guided-filtering-real-time-reconstruction-path-traced)，
  [DOI: 10.1145/3105762.3105770](https://doi.org/10.1145/3105762.3105770)：
  去除材质调制的辐照度、逐采样历史有效性检查和边缘感知重建。本包并未实现完整 SVGF。
- iterationT 3.2.0（`GlobalIllumination.glsl` 与阴影输出）及 Revelation
  （`diffuse/Accumulate.frag`）仅用于架构比较。iterationT 的再分发许可未经确认，
  Revelation 为 Apache-2.0。本次变更未复制上述两包的源码或资产。

## 18. GT7 Tone Mapping（MIT，Polyphony Digital 官方样例移植）

`shaders/lib/color/color.glsl` 的 `TonemapGT7`（`TONEMAP_MODE == 4`）移植自
Polyphony Digital 随 SIGGRAPH 2025 课程材料发布的官方样例实现
`gt7_tone_mapping.cpp`，课程为 *Driving Toward Reality: Physically Based Tone
Mapping and Perceptual Fidelity in Gran Turismo 7*（Kentaro Suzuki、Kenichiro
Yasutomi），样例代码明确以 MIT 许可发布：

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

来源：<https://blog.selfshadow.com/publications/s2025-shading-course/pdi/>
（课程幻灯片 `s2025_pbs_pdi_slides_v1.1.pdf` 及配套 `gt7_tone_mapping.cpp`）。

移植适配说明：

- 输入/输出域由样例的线性 Rec.2020 frame-buffer（1.0 = 100 nits）经
  BT.709 ↔ BT.2020 线性矩阵转换为本包的线性 sRGB 约定；矩阵常量由原色推导。
- 加入 `GT7_MID_GREY_SCALE` 中灰锚定预缩放（数值求解 0.4·curve(2.50832·0.18) =
  0.18），与其他色调映射模式共享 18% 灰锚点；曲线参数保持官方 SDR 预设
  （peak 2.5、gray point 0.538、linear section 0.444、toe strength 1.28、
  blend 0.6、chroma fade 0.98–1.16），仅一处有意偏差：alpha 取 0（官方样例的
  合法参数）而非 0.25，使肩部渐近线恰为纸白——本包管线没有 GT7 引擎的曝光
  归一化，样例的过冲肩部会把场景白色以上约半档的内容硬裁成纯白。
- UCS 采用样例默认的 ICtCp（ITU-R BT.2124，Rec.2020）；ICtCp 逆矩阵为按定义
  精确求逆的常量。
- 暴露为设置的参数：`TONEMAP_GT7_BLEND`、`TONEMAP_GT7_CHROMA_FADE_START`、
  `TONEMAP_GT7_CHROMA_FADE_END`（默认值均为官方样例值）。

## 19. 云内多重散射近似（算法出处）

本包的云内多重散射近似出自

<https://zhuanlan.zhihu.com/p/457997155>

即饱和因子与代表首次以后各阶散射的各向同性几何级数。出处写作 `fms = ω0 · (1 - exp2(-300 · σ_t))`，
自变量是每米消光。本包把该自变量改写成**无量纲的参考光学厚度**，膝点落在"该层自身参考长度上一个
光学厚度"处，参考长度由各层自己持有：体积云为 300 m（与其原有取值等价），卷云为 0.5 km（该壳层
自身的尺度）。这不是可共用的常量，因为 `300 · σ_t` 里的 300 带长度单位，为 100 km⁻¹ 的介质标定
的长度套到 3 km⁻¹ 的壳上时，膝点根本到不了，级数等于不出力。

`shaders/lib/cloud/multiple_scattering.glsl` 是这条无量纲形式的唯一归属，体积云与卷云两个云层
共同包含它。两个层都把它加在日月的直射项上；环境光路径不经过它。体积云另加把日月折叠成
单一方向的光照追踪，卷云不折叠。

文件头与常量注释记录了本包在这些环节上的取值与实现方式。`volumetric.glsl` 同样记录在案的
三 octave 方向相位求和与 `1 / (1 + τ)` 光路透过率是本包自己的选择，不属于本节出处。

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
