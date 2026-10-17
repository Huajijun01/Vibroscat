# Third-Party Notices

[中文版](THIRD_PARTY_NOTICES.md) | [English](THIRD_PARTY_NOTICES.en.md)

本文件是 Vibroscat 全部第三方代码、资产与算法引用的单一声明点。主许可证见根目录 `LICENSE`（GNU GPL v3）。

## 1. Photon Shaders（历史参考；当前代码不含实质副本）

Photon Shaders（Copyright © 2021-2025 Benjamin Stott "SixthSurge"，自定义许可协议）曾是两个功能的早期来源，均已于 2026-08 移除并替换：

- `shaders/lib/lighting/brdf.glsl` 的 `GetNdotHSquared`（GGX 球形区域光，Newton 迭代弯曲光方向）曾转录自 Photon 的 `include/lighting/bsdf.glsl`；现已按 Guerrilla Decima Engine 公开讲座材料（Johan Andersson, SIGGRAPH 2017）重新转录，见第 10 节，不再包含 Photon 代码表达。
- `shaders/lib/lighting/temporal_ao.glsl` 的时序 AO 深度/offcenter 拒绝（GTAO_DEPTH_REJECTION=16.0、GTAO_OFFCENTER_STRENGTH=0.25，与 Photon `d3_ao.fsh` 相同；offcenter 技巧由 Photon 自身标注源自 Zombye/Jessie）已整体重写为独立实现（世界位移 + 法线一致性拒绝，见该文件头注释），原公式与常量已全部删除。

Photon 自定义许可协议中的再分发限制不适用于本包当前代码。历史移植与清理记录保留在 Git 历史中。

## 2. AgX（概念；当前实现见第 3 节）

`shaders/lib/color/tonemap_agx.glsl` 的 `TonemapAGX` 是 AgX 家族的 HSV 色相修复变体。AgX 概念来源为 Troy Sobotka：

- [SOB22] Sobotka, Troy. "AgX". 2022. https://github.com/sobotka/AgX （概念与配置；上游仓库无许可证，仅作概念引用）

曲线、对数整形与色相修复的出处见第 3 节（DRT Bench）。2026-10 之前本包使用 linlin 的 AgX-S2O3 解析实现（MIT，https://github.com/bWFuanVzYWth/AgX @ 0796e1b4aa9df94152eff353bae131eae1a4c087）；该曲线与实现已随 2026-10 的模式列表更换一并移除，不再随包分发。

## 3. DRT 色调映射（GPL-3.0）

`TonemapAGX`（`TONEMAP_MODE == 0`）移植自 DRT Bench（github.com/bWFuanVzYWth/DRT，作者 linlin）的 `shaders/agx_hsv.wgsl`，采用该工具的 `AgxParameters::hsv_default()` 曲线：−10…+6.5 EV 的对数编码范围、sRGB OETF(0.18) 输出枢轴、1.55 / 5.2 的 toe 与 shoulder 幂、0.05 的色域压缩，以及该变体得名的 HSV 色相修复阶段。

该仓库自 2026-09 起以 `GPL-3.0-only` 发布（commit 49e67a3 加入 LICENSE），与本包 GPLv3
兼容。算子使用参考实现的固定默认值，包括黑端/白端色相保留 1.0/0.5。原先本包额外叠加的
对比度、伽马、饱和度与自行编造的 look 已移除。参考实现的最终显示信号钳制之后，解码 sRGB
以供本包显示线性后处理使用。此 HSV 变体的参考实现不提供艺术风格预设；Blender AgX 官方
look 属于下文的模式 2。

历史：2026-08 至 2026-10 期间本包还移植过该工具的 Oklab DRT、Reinhard-Gamut 与 Reinhard-AgX（当时该仓库尚未选择许可证，按作者直接授权使用）。三者在 2026-10 的模式列表更换中全部移除，不再随包分发。

## 4. AMD FidelityFX CAS（MIT）

`shaders/lib/third_party/fidelityfx/cas.glsl` 是 AMD FidelityFX Contrast Adaptive Sharpening 的精简 GLSL 改编（Copyright (c) 2017-2019 Advanced Micro Devices, Inc.），MIT 许可全文保留在该文件头部。原始来源：https://github.com/GPUOpen-Effects/FidelityFX-CAS

## 5. Intel Outdoor Light Scattering（Apache-2.0，概念与框架）

`shaders/lib/volume/epipolar_core.glsl` 的 epipolar 切片/扇形参数化跟随 Intel Outdoor Light Scattering Sample（Intel，Apache-2.0）。另参考 Yusov, Egor. "Practical Implementation of Light Scattering Effects Using Epipolar Sampling and 1D Min/Max Binary Trees". GDC 2013。本包实现为独立表达，未逐行复制。Apache-2.0 全文见本文件附录 A。

## 6. Unreal Engine Sky Atmosphere（MIT，算法引用）

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

## 7. NASA Deep Star Maps 2020（公有领域）

`shaders/textures/starmap_2020_4k_logluv32.png` 由 NASA SVS #4851 "Deep Star Maps 2020" 线性 EXR 烘焙而来（Plate Carrée 投影，LogLuv32 编码）。
`shaders/textures/starmap_2020_256x128_logluv32.png` 是同一素材的 16x16 盒式降采样衍生（线性空间块均值后按运行时解码器的精确逆重新编码 LogLuv32），供大面积光源消费端使用。

> Image credit: NASA's Scientific Visualization Studio / ESA-ESO-Sky-Survey
> 来源：https://svs.gsfc.nasa.gov/4851/ 。NASA 素材为美国政府作品，属于公有领域。

## 8. 时空蓝噪声 STBN（算法引用）

`shaders/textures/stbn_scalar_128x128x64.dat` 按 void-and-cluster 算法独立生成，算法与默认参数来自：Wolfe, Morrical, Akenine-Möller, Ramamoorthi. "Scalar Spatiotemporal Blue Noise Masks". 2022. （前身为 Heitz, Belcour, Ostromoukhov. "Spatiotemporal Blue Noise Masks". ACM TOG 2019.）

## 9. LogLuv32 编码（算法引用）

LogLuv32 解码（color.glsl 的 `LogLuv32ToLinear`）遵循：Ericson, Christer. "Converting RGB to LogLuv in a fragment shader". 2007. 矩阵流与 Alpha Piscium v1.9.1（GPLv3）一致；GPLv3 与包主许可证兼容。

## 10. Guerrilla Decima Engine（算法引用）

`GetNdotHSquared` 的 GGX 球形区域光近似（含 Newton 迭代弯曲光方向）来自：Andersson, Johan. "Decima Engine: Advances in Lighting and AA". SIGGRAPH 2017 Advances in Real-Time Rendering in Games. https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa （PDF：https://www.realtimerendering.com/advances/s2017/DecimaSiggraph2017.pdf）

## 11. Blender EEVEE（GPL-2.0-or-later，算法引用）

`F0ToIOR` 的折射率恢复采用 Blender EEVEE 的近似（GPL-2.0-or-later，与 GPLv3 兼容）。

## 12. SSR 血统与独立重写（chocapic13）

`lib/raytrace/ssr.glsl` 原实现属 chocapic13 血统（早期来源标注有误，已更正）。当前文件已整体重写为独立实现：线性深度命中判据、覆盖屏幕边界或远平面的常数步长、区间折半细化，未沿用原结构、常量或写法。重写记录保留在 Git 历史中。

## 13. 其它数学/惯例引用

- `FastSin`：Bhaskara I 正弦近似（约 12 世纪，公有领域数学）
- R2 序列（lib/core/noise.glsl 的 R2Offset，用于云等时间累积的连续抖动）：Roberts, Martin. "The Unreasonable Effectiveness of Quasirandom Sequences"（公开常数 1.3247179572 / 1.7548776662）
- `material/core.glsl` 的 specular 通道约定：oldPBR/seusPBR 规格（数据格式约定，非代码）
- `lib/core/noise.glsl` 的 `LowBias32Hash`：Wellons, Chris. “Prospecting for Hash Functions” 的 lowbias32 常量（作者声明为公有领域）

## 14. 大气模型出处说明

`lib/atmosphere/` 的 4-波谱大气模型自 2026-10 起改用包作者研究项目 sky-tracer（research/ 内 Rust/wgpu 仓库，GPL-3.0）的 OPAC/libRadtran 输入表：波长 450/510/580/650 nm，介质为 US-standard 空气、臭氧与 inso/waso/soot/suso 四种气溶胶的分段线性剖面，密度/相位模型参考 Hillaire 2020（见第 6 节）。透射与多重散射 LUT 由 sky-baker `pack` 子命令在 GPU 上以逐阶迭代多散射解烘焙（含 8 km 地平线下探几何），替换了此前 HSPEAtmosCreator 工具（不入库）的 fms 不动点近似烘焙。运行时直射单散射仍使用包作者调参的三叶 HG Mie 混合相位；烘焙内部使用 sky-tracer 的逐物种 1024-bin Mie 相位表。

## 15. GT-VBGI / ReferenceGI（CC0 1.0）

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
设计层面采用 2×2 历史模式比较。

## 16. Reflective Shadow Maps 与时域重建（算法引用）

`shaders/lib/lighting/rsm_data.glsl`、`reflective_shadow_map.glsl` 和
`gi_history.glsl`、`gi_denoise.glsl` 中的 RSM 数据编码、采样与 GI 重建为 Vibroscat 独立实现。
`gi_sampling.glsl` 独立实现三维数字平移 Sobol 序列，方向数通过二进制递推生成；
未复制外部方向数表或采样代码。历史的重心插值由平面三角形面积独立推导。

- Carsten Dachsbacher、Marc Stamminger，*Reflective Shadow Maps*，I3D 2005，
  [DOI: 10.1145/1053427.1053460](https://doi.org/10.1145/1053427.1053460)：
  从光源可见表面构造虚拟点光源。
- I. M. Sobol，*On the distribution of points in a cube and the approximate
  evaluation of integrals*，1967：低差异数字序列的算法参考。
- Christoph Schied 等，*Spatiotemporal Variance-Guided Filtering:
  Real-Time Reconstruction for Path-Traced Global Illumination*，HPG 2017，
  [作者发布页及论文](https://research.nvidia.com/publication/2017-07_spatiotemporal-variance-guided-filtering-real-time-reconstruction-path-traced)，
  [DOI: 10.1145/3105762.3105770](https://doi.org/10.1145/3105762.3105770)：
  去除材质调制的辐照度、逐采样历史有效性检查和边缘感知重建。本包并未实现完整 SVGF。
- iterationT 3.2.0（`GlobalIllumination.glsl` 与阴影输出）仅用于架构比较。其再分发许可
  未经确认。本次变更未复制该包的源码或资产。

## 17. GT7 Tone Mapping（MIT，Polyphony Digital 官方样例移植）

`shaders/lib/color/tonemap_gt7.glsl` 的 `TonemapGT7`（`TONEMAP_MODE == 5`）移植自
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

来源：<https://blog.selfshadow.com/publications/s2025-shading-course/pdi/supplemental/gt7_tone_mapping.cpp>
（版本 1.0，2025-08-10）
（课程幻灯片 `s2025_pbs_pdi_slides_v1.1.pdf` 及配套 `gt7_tone_mapping.cpp`）。

移植适配说明：

- 线性 Rec.709 输入/输出与样例 Rec.2020 framebuffer（1.0 = 100 nits）之间转换。
  恢复本包改写前的 2.508318700610 倍输入校准，使 18% 场景中灰映射为 18% 显示中灰。
- 保留官方 SDR 的 peak 2.5、gray point 0.538、linear section 0.444、toe strength
  1.28、blend 0.6、chroma fade 0.98–1.16；恢复本包原有 alpha 0 高光曲线（样例为
  0.25），使高光平滑趋近白点。参数固定；此 SDR 适配为本包默认色调映射。
- 采用默认 ICtCp UCS 及 ITU 正/逆矩阵；PQ 解码按样例钳制 [0,1]。最终 SDR 钳制在
  Rec.2020→Rec.709 转换之后执行，使锐化收到合法显示范围。
- 官方样例提供 SDR/HDR 显示目标和另一内部色彩空间 JzAzBz，并非一组艺术 look。
  本包的 SDR 路径固定默认 ICtCp，不开放 GT7 数值调节项。
- 实际 GLSL 与改写前本包 GT7 的固定 GPU 输出比对；允许 ST2084 float32 舍入差异，
  显示白归一化误差预算为 5e-4。此适配不宣称与官方 SDR 输出完全一致。

## 18. 云内多重散射近似（算法出处）

本包的云内多重散射近似出自

<https://zhuanlan.zhihu.com/p/457997155>

即饱和因子与代表首次以后各阶散射的各向同性几何级数。出处写作 `fms = ω0 · (1 - exp2(-300 · σ_t))`，
自变量是每米消光。本包把该自变量改写成**无量纲的参考光学厚度**，膝点落在"该层自身参考长度上一个
光学厚度"处，参考长度由各层自己持有：体积云为 300 m（与其原有取值等价），卷云为 0.5 km（该壳层
自身的尺度）。这不是可共用的常量，因为 `300 · σ_t` 里的 300 带长度单位，为 100 km⁻¹ 的介质标定
的长度套到 3 km⁻¹ 的壳上时，膝点根本到不了，级数等于不出力。

公式里的 `ω0` 同样按层持有：它是介质的单次散射反照率，水云与冰云不是同一种介质。本包体积云取
0.99（固定值，不跟 `CLOUD_MS_ALBEDO` 滑条走），卷云取 0.999。

`shaders/lib/cloud/multiple_scattering.glsl` 是这条无量纲形式的唯一归属，体积云与卷云两个云层
共同包含它。两个层都把它加在日月的直射项上；环境光路径不经过它。体积云另加把日月折叠成
单一方向的光照追踪，卷云不折叠。

文件头与常量注释记录了本包在这些环节上的取值与实现方式。`volumetric.glsl` 同样记录在案的
三 octave 方向相位求和与 `1 / (1 + τ)` 光路透过率是本包自己的选择，不属于本节出处。

## 19. 雨滴涟漪（独立实现与自生成资产）

雨滴涟漪采用离线生成周期坡度贴图的思路。设计比较参考了
Zavie / Ctrl-Alt-Test 的 [Rain drops](https://www.shadertoy.com/view/ldfyzl)
研究效果及其空间、时间循环方案，仅作为概念研究。
本包的运行时代码与 `rain_ripples_rg8_256x256x64.dat` 均为独立实现：
使用雨滴尺寸分布、终端落速与撞击能量驱动的空腔近似，以及有限水深线性水波的
频谱解、傅里叶高度导数和线性坡度编码。落速参考 Atlas、Srivastava 和 Sekhon (1973)
的通用经验关系（[doi:10.1029/RG011i001p00001](https://doi.org/10.1029/RG011i001p00001)）；
相速度与群速度由通用毛细-重力波色散关系计算。等效水深、冲击能量传递率及周期化
为本包的建模近似，不宣称完整流体模拟。
为保持圆形涟漪可辨认，贴图只保留稀疏的大雨滴落点，省略小雨滴叠加形成的密集波场；
单个落点仍按上述模型传播。运行时只扰动法线，不执行雨滴涟漪 POM。
未复制上述参考的代码、哈希、烘焙程序、解码器或贴图；自生成资产适用本包 GPL-3.0 许可。

## 20. 解析水雾（近海实测光学数据与独立实现）

`shaders/lib/water/fog.glsl` 始终使用均匀介质的
Beer–Lambert 透射与闭式单次散射积分，由本包独立实现。
观感与流程比较参考 iterationT 3.2.0 的 `shaders/composite1.fsh`
（蓝绿色、低亮度的距离雾）以及 Photon v1.3b 的
`shaders/include/fog/simple_fog.glsl`（解析积分）。
iterationT 的再分发许可未经确认，Photon 为自定义许可；两者仅用于观察与
概念比较，未复制源码、独特表达、常量或资产，不包含参考包的多重散射增强项。

光学常量改编自 Giuseppe Zibordi 与 Jean-François Berthon (2024) 的
[CoASTS–BiOMaP 数据集](https://doi.org/10.1594/PANGAEA.971945)
（[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)，
[方法论文](https://doi.org/10.5194/essd-16-5477-2024)）。
选用北亚得里亚海 Acqua Alta Oceanographic Tower 近海站点样本 `V770201`：
2007-06-14 08:40:52，45.31390°N、12.50830°E，光学测量深度约 1 m，
水温 23.207 °C、盐度 36.831。AC9 的 `a_t-w` 与 `c_t-w` 均不含纯海水；
非水散射按 `b_p = c_t-w - a_t-w` 求得。650 nm 直接取样，550 nm 在
510/555 nm 间、450 nm 在 440/488 nm 间线性插值，作为本包的有效 RGB 波长。

纯水吸收使用 Pope 与 Fry (1997) 的积分腔实测值
（[doi:10.1364/AO.36.008710](https://doi.org/10.1364/AO.36.008710)，
[OMLC 数值表](https://omlc.org/spectra/water/data/pope97.dat)），
将表中 cm⁻¹ 乘以 100 换成 m⁻¹：RGB 为 `(0.34000, 0.05650, 0.00922)`。
海水分子散射按 Zhang、Hu 与 He (2009) 的温盐模型在该样本条件下计算
（[doi:10.1364/OE.17.005698](https://doi.org/10.1364/OE.17.005698)，
[作者计算方法](https://www.oceanopticsbook.info/packages/iws_l2h/conversion/files/betasw_ZHH2009.m)，
Ocean Optics Web Book，[CC BY 2.0](https://creativecommons.org/licenses/by/2.0/)），
RGB 为 `(0.00085607, 0.00171818, 0.00400705) m⁻¹`。
最终吸收为 `(0.341030, 0.065223, 0.054923) m⁻¹`，总散射为
`(0.130766, 0.140677, 0.147750) m⁻¹`，未人为缩放这些光学系数。
没有将后向散射 `bb` 或漫射衰减 `Kd` 当作总散射或消光。

三波长 RGB、均匀介质、Cornette–Shanks 参数 0.15、方向光权重 0.25、
中性入射光权重 0.10，以及天空亮度和雨天权重均为本包的解析渲染近似，
不是该样本实测的完整相位函数或水下光场。入射光权重控制没有遮挡追踪的
解析雾亮度，不改变实测消光或单次散射反照率。入射直射光用实测消光作
Beer–Lambert 衰减，漫射天空光以吸收衰减近似角度再分配；代表水深采用
与焦散相同的天空亮度代理 `(1 - skylight) * 15 m`，最小 1 m。
该深度和均匀光源不是逐像素水柱测量，未实现遮挡积分、多重散射或完整
光谱输运；不宣称重现全部实测水色。

## 21. TAA 与时域超分辨率

TAAU 扩展 `shaders/program/post/taa.fragment`，复用其中的最近深度采样、
重投影、邻域 AABB 裁剪、混合权重与 HDR 压缩。三次重建复用现有
`FastCatmullRom5Tap`，补充场景边界限制；`shaders/lib/core/render_scale.glsl`
负责渲染矩形的坐标映射。
设计研究了 Photon v1.3b 的 `shaders/program/c3_taau_prep.fsh`、
`c4_taa_exposure.fsh` 及其低分辨率场景/全分辨率历史布局，以及 Revelation-dev 的
`shaders/program/post/TemporalAA.frag`。Photon 自定义许可允许学习与检视，
Revelation 采用 Apache-2.0；本次仅研究数据流与通用算法，没有复制或近似翻译其源码。
上游：https://github.com/sixthsurge/photon 与 https://github.com/HaringPro/Revelation 。

时域重建参考 Yang、Liu、Salvi 的 "A Survey of Temporal Antialiasing
Techniques"（2020）。扩展沿用本包现有的 RGB 边界与 HDRCompress/HDRDecompress。
最终锐化复用本包现有 AMD FidelityFX CAS（第 4 节）。

2026-10 的统一历史路径共用原生与低分辨率设置；RGB 邻域越界可信度、
双侧颜色尺度及平滑运动上限为本包独立设计。对照研究了 Playdead 的公开
TemporalReprojection（MIT，https://github.com/playdeadgames/temporal ）和 Unity
HDRP TemporalAntialiasing（https://github.com/Unity-Technologies/Graphics ）的通用
历史限制思路，未复制或近似翻译其源码。Salvi 的 *An Excursion in Temporal
Supersampling*（GDC 2016）方差裁剪仅作为实验对照，未并入发布实现。

## 22. ACES 2.0 Output Transform（Apache-2.0 / BSD-3-Clause）

`shaders/lib/color/tonemap_aces2.glsl` 的 `TonemapACES2`（`TONEMAP_MODE == 1`）
适配完整的 ACES 2.0 SDR 100 nit Rec.709 输出变换。Academy 参考实现与输入色适应来自
<https://github.com/ampas/aces-core>（2.0，2025-04-04）和
<https://github.com/ampas/aces-output>，采用 Apache-2.0（全文见附录 A）：

> Copyright Contributors to the ACES Project.
> SPDX-License-Identifier: Apache-2.0

`shaders/lib/third_party/opencolorio/aces2_output.glsl` 由 OpenColorIO 2.6.0 的官方内置变换
`ACES-OUTPUT - ACES2065-1_to_CIE-XYZ-D65 - SDR-100nit-REC709_2.0` 生成：

- 上游：<https://github.com/AcademySoftwareFoundation/OpenColorIO/tree/v2.6.0>。
- 许可证：BSD-3-Clause；版权归 Contributors to the OpenColorIO Project。
  完整版权、许可条件和免责声明保留在随包分发的上述 GLSL 文件中。
- GPU 生成器：`src/OpenColorIO/ops/fixedfunction/FixedFunctionOpGPU.cpp`。

修改与集成说明：

- 场景 Rec.709/D65 先经 Bradford 色适应转换为 AP0，再由官方变换在 AP1 内钳制。
  不预先裁切源 RGB，避免改变带负分量的超色域颜色的色相。
- 完整正向变换包含 Hellwig-2022 JMh、MM 色调曲线、色度压缩和显示 cusp 色域压缩。
  SDR 观看条件及色域边界均采用官方内置变换的常量。
- OpenColorIO 的 reach 和 cusp/gamma 纹理改为不可变 GLSL 常量数组，保持原有色相插值。
  这些是色域边界表，不是采样色调曲线；本包没有新增纹理、自定义图像、缓冲区或 pass。
- 去掉末尾 Rec.709→XYZ 转换，直接返回显示线性 Rec.709；sRGB OETF 由最终 pass 统一执行一次。
  不包含逆向输出变换。
- 使用官方参考曝光，不添加中灰校准或用户输入缩放。ACES 输出变换是显示目标配置，
  并非艺术风格预设；本包固定 SDR 100 nit Rec.709。
- 实际 GLSL 与完整 OpenColorIO CPU 变换比较 12,276 个中性、饱和、随机 HDR 和
  带负分量输入，显示线性误差预算为 5e-5。

## 23. Blender AgX（GPL-2.0-or-later / BSD-3-Clause）

`shaders/lib/color/tonemap_blender_agx.glsl` 的 `TonemapBlenderAGX`（`TONEMAP_MODE == 2`）
重建 Blender 4.0 AgX 视图变换的 Base Contrast 成像。Blender 采用 GPL-2.0-or-later，
与本包 GPLv3 兼容。AgX 概念来自 Troy Sobotka（第 2 节），该配置来自 EaryChow，sigmoid 来自 Jed Smith。

发行版标准：<https://github.com/blender/blender/tree/v4.0.0/release/datafiles/colormanagement>
中的 `config.ocio` 和 `luts/AgX_Base_sRGB.cube`。数学参考为
<https://github.com/EaryChow/AgX_LUT_Gen> 中的 `AgXBasesRGB.py`、`AgXBaseRec2020.py`、
`working_space.py`、`sigmoid.py` 和两份下侧 guard rail 生成器。本包不分发生成器 Python 源码；
guard rail 采用独立代数重建：亮度权重之和为 1 时，对手色补偿可化简为 `2*Y-min`。

成像与适配说明：

- 线性 Rec.709 → Rec.2020 → 下侧输入 guard rail → 旋转/inset 工作色域 → −10…+6.5 EV log 整形
  → toe/shoulder sigmoid（slope 2.4、power 1.5）→ 2.4 次幂线性化 → 原始色相向成形色相的
  40% 最短弧插值 → outset/Rec.709 → 下侧输出 guard rail → 显示钳制。
- guard rail 亮度权重以 Blender 4.0 随包 LUT 为准，不替换为上游生成器 2025 年 6 月更新的
  D65 权重；该更新会改变饱和颜色。
- 本包使用解析求值，网格点之间与 Blender 的四面体 LUT 插值存在差别，不声称逐像素等同于
  插值 LUT 输出。
- 上侧 guard rail 在生成器中禁用，本包同样禁用。
- `TONEMAP_BLENDER_AGX_LOOK` 提供 Blender v4.0.0 的九个真实 look：Base Contrast、
  Punchy、Greyscale、Very High Contrast、High Contrast、Medium High Contrast、
  Medium Low Contrast、Low Contrast、Very Low Contrast，默认 Base Contrast。
  完整预设变换在官方 25 档 AgX Log 处理空间内执行，然后进行视图成像。
- `shaders/lib/third_party/opencolorio/blender_agx_looks.glsl` 由 OpenColorIO 2.6.0 从
  `config.ocio` 的 look 生成，版权归 Contributors to the OpenColorIO Project，采用
  BSD-3-Clause，完整许可保留在该文件中。Punchy 包含真正的 grading-tone 和 CDL 阶段，
  不以显示伽马/饱和度捷径模拟。
- 每个 look 均对照官方 OCIO CPU 预设变换及独立解析成像测试；参考 CPU 使用无损优化，
  关闭默认的近似 grading 运算。
- 场景 18% 灰无需预缩放即映射为 18% 显示线性。
- 与 Blender 4.0 随包的 57³ LUT 比较了 5,000 个精确网格点，包括带负 Rec.709 分量的颜色，
  最大显示线性误差为 1.1e-6；与完整解析生成器比较 12,248 个有效中性/HDR/带负分量输入，
  误差低于 1e-6。

## 24. AMD FidelityFX LPM（MIT）

`shaders/lib/color/tonemap_lpm.glsl` 的 `TonemapLPM`（`TONEMAP_MODE == 4`）移植自 AMD 的
FidelityFX Luma Preserving Mapper，`ffx-lpm/ffx_lpm.h`（文件头标记
`[LPM] LUMA PRESERVING MAPPER 1.20200225`）：

> Copyright (c) 2017-2019 Advanced Micro Devices, Inc. All rights reserved.
> （仓库 `NOTICES.txt` 记为 "AMD copyrighted code (MIT) / Copyright (c) 2020 Advanced Micro
> Devices, Inc. All rights reserved."，MIT 许可全文见该文件）

上游：<https://github.com/GPUOpen-Effects/FidelityFX-LPM>。取用日期 2026-10-11，源文件 SHA-256
`7a7c0f376c89bcecd51fe8a5d8ba3b34ec59841e9915cb5b3e16ee87e9448c4d`。

参考实现本身就是 ALU 版本（其更新记录写明 "Switched from using LUTs to doing the full mapping
in ALU"），因此**本移植不含、也不需要任何查找表**。

移植适配说明：

- 移植：`LpmSetup` 的 toneScaleBias 求解（`tone(x) = x^contrast / (x^shoulder * bias.x + bias.y)`，
  以 tone(midIn) = 0.18 与 tone(hdrMax) = 1.0 约束；本包把该求解折成编译期常量），以及
  `LpmMap` 的完整链路：比值/亮度分离、比值上的饱和度幂、对**原始颜色**亮度做色调曲线
  （这正是"亮度保持"的来源）、比值重标定、crosstalk 回入色域、最终亮度补足。
- 取 `LPM_CONFIG_709_709` + `LPM_COLORS_709_709`：工作、输出与容器色域均为 Rec.709 D65，
  故参考实现的 `con`/`con2` 矩阵均为单位矩阵并被省略，`clip` 与 `scaleOnly` 分支为死代码。
- 未移植：`soft` 软色域映射（参考实现要求同时提供 `con`，且仅在工作色域与输出色域不同时生效）、
  `shoulder`/`shoulderContrast`（参考实现自身取 1.0，示例亦不启用）、con2/scaleOnly 输出变换
  （FS2、HDR10、scRGB）、FP16 打包路径与 `LpmSetupOut`。本包返回显示线性 Rec.709，
  sRGB OETF 由 `post/final.fragment` 施加。
- 两处守护覆盖参考实现契约（{0..hdrMax}）之外但仍可能收到的输入：颜色为 0 时其 `1/max(rgb)`
  除零（本包返回黑），以及色调后亮度达到 1.0 时 `cap` 全为 0、其 `lumaAdd/dot(cap, lumaT)` 为
  0/0（本包取其极限 t = 0）。
- 固定使用官方头文件的 Rec.709 配置样例：hdrMax 256、exposure 8、contrast 0.25、
  shoulderContrast 1、saturation 0、crosstalk (1, 0.5, 1/32)。这些是内容制作/集成参数，
  不开放给玩家。`LPM_CONFIG_*` 是显示格式和色域转换配置，并非艺术 look。
- 实际 GLSL 对照完整参考映射的独立转写，覆盖 12,276 个中性、原色、随机 HDR 与带负分量
  输入，显示线性误差预算为 1e-5。

## 25. OpenDRT（GPL-3.0）

`shaders/lib/color/tonemap_opendrt.glsl` 的 `TonemapOpenDRT`（`TONEMAP_MODE == 3`）
移植自 Jed Smith 的 OpenDRT（Open Display Rendering Transform）参考 DCTL
`display-transforms/opendrt/OpenDRT.dctl`（文件头标注 OpenDRT v1.1.0，GPLv3）：

> OpenDRT v1.1.0
> Written by Jed Smith
> https://github.com/jedypod/open-display-transform
> License: GPLv3

上游：<https://github.com/jedypod/open-display-transform>。仓库根 `LICENSE` 为
GNU GPL v3，与本包主许可证一致，故按 GPL-3.0 移植并保留署名；依据 GPL-3.0
第 5(a) 条在此声明本包对其作了修改（修改内容见下）。取用日期 2026-10-11，
源文件 SHA-256 `645ba89745691742c5403f8de5964b5934cd1c59bf06fb1f1a1f6b45f54830a1`。

移植范围：七个官方默认启用的 Look（Standard、Arriba、Sylvan、Colorful、Aery、Dystopic、
Umbra）和全部十四种 Tonescale 选择，包含 USE LOOK PRESET。上游 UI 默认禁用的开发者
Base look 不作为玩家选项。`tonemap_opendrt_presets.glsl` 保存原始完整参数组；Look 选择整组，
Tonescale 可单独覆盖曲线。原始数值全部固定，包含 Contrast Low/High、逐通道色相范围和
创意白点适应。

移植适配说明：

- 输入为场景线性 Rec.709，输出为显示线性 Rec.709，固定 SDR 峰值 100 尼特、官方中灰
  10 尼特和 sRGB Display 环境（`tn_su = 2`）。最终 pass 负责 sRGB OETF，省略 DCTL 信号
  编码，不添加与其他算子的中灰对齐。
- 100 尼特时 HDR 中灰提升为零，HDR 色纯度插值合为同一条曲线，不开放 HDR 数值或显示格式
  开关。
- 固定色域矩阵折叠，包含 P3D65→XYZ→创意白点 CAT→Rec.709；保留官方范围混合及归一化，
  包含 Aery 的 D75、Dystopic 的 D60、Umbra 的 D50 白点。
- 带负分量 RGB 不预裁切；对手色向量为零时取零角度，匹配参考中性路径并避开 GLSL
  未定义的 `atan(0,0)`。
- 实际 GLSL 对照编译执行的官方 DCTL；仅适配宿主向量/数学接口并绕过最终信号编码。
  所有 Look、所有 Tonescale 和交叉覆盖均以每组 12,276 个 HDR/带负分量样本测试，
  显示线性误差预算为 2e-5；另检查全部 98 种 Look/Tonescale 组合的有限值及显示范围。

## 26. 空气雾密度模型（概念研究）

恢复的极线几何来源及许可证见第 5 节。指数高度密度、昼夜调节和天气响应的概念比较参考 iterationT 3.2.0 的 `shaders/Lib/IndividualFounctions/VolumetricFog.glsl`，以及 Photon v1.3b 的 `shaders/include/weather/fog.glsl`、`shaders/include/fog/overworld/{analytic,raymarched,constants}.glsl`。iterationT 未提供包级许可证，按保留权利处理；Photon 自定义许可证明确允许检视和学习（上游 https://github.com/sixthsurge/photon）。两者只作只读概念参考，没有移植或近似翻译源代码、特征表达式、常数或资源。

本包独立推导晴天指数高度密度和单独的中性雨天米氏常值增益。光学厚度与晴天散射保持闭式解，混合雨雾的独立源项积分经推导后数值求值；雨天不增益瑞利散射、臭氧或有色气溶胶吸收。沿用本包四波段介质及相函数，E 为无量纲的有阴影／无阴影散射比值，采用均匀分层阴影步进。默认密度、参考高度与标高为本包独立调节值。

## 27. 植物风场（概念研究与独立生成资产）

只读研究 Photon v1.3b 的 `shaders/include/vertex/displacement.glsl` 与
`shaders/block.properties`（自定义许可证，明确允许检视和学习；
https://github.com/sixthsurge/photon），以及 MakeUp UltraFast 9.5c 的
`shaders/src/position_vertex.glsl`、`shaders/lib/vector_utils.glsl`、
`shaders/lib/config.glsl` 与 `shaders/block.properties`（LGPL-3.0；
https://github.com/javiergcim/MakeUpUltraFast）。借鉴植物附着点、双层植物
状态分类、完整树叶方块以及静止甘蔗的处理原则；没有复制或近似翻译源码、
特征公式、常数或贴图。

`lib/geometry/plant_wind.glsl` 和 `textures/plant_wind_rgba16f_64.dat`
为独立实现及自生成资产：傅里叶无散度湍流与 von Karman 型能谱、Taylor
冻结湍流平流、二次气动阻力、阻尼振子的频域强迫响应，以及 Euler-Bernoulli
悬臂梁的静态弯曲形状。上述为经典数学和物理模型；未移植第三方求解器。
本包的有效频率、阻尼、尺度和随机种子均独立选定，不宣称模拟障碍物绕流
或实测植物物种。

## 28. 水下极线光柱（概念研究与独立生成资产）

沿用第 5 节的 Intel/Yusov 极线参数化。架构只读比较 Alpha Piscium v1.9.1
的 `shaders/composite18.csh`（GPL-3.0；
https://github.com/Luna5ama/Alpha-Piscium）与 Photon v1.3b 的
`shaders/include/fog/overworld/raymarched.glsl` 和 `shaders/program/c0_vl.fsh`
（自定义许可证，允许检视与学习；https://github.com/sixthsurge/photon）。
没有复制或近似翻译上述光影包的源码、常数或纹理。

`lib/volume/water_epipolar.glsl` 为独立实现。低频源纹理
`textures/godray_caustics_r16f_64x64x64.dat` 使用本包现有焦散的相同 Phillips
频谱、种子、相位、解析法线与 Snell 光子追踪路径独立生成，输出 9 米焦深层，
再作周期空间与时间低通；它不是第三方贴图。运行时沿未折射的世界太阳方向
投影并积分，以艺术化亮度直接加到画面，不宣称完整模拟水下体积光输运。

## 29. 植物透光与屏幕空间衰减（概念研究）

只读比较 iterationT 3.2.0 的 `shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl`
与 `shaders/composite.fsh`（未发现包级许可证，按保留权利处理；
https://minegraph.cn/shaderpacks/12），以及 Photon v1.3b 的
`shaders/include/lighting/diffuse_lighting.glsl` 与
`shaders/include/lighting/shadows/ssrt.glsl`（自定义许可允许检视和学习；
https://github.com/sixthsurge/photon）。研究宽角度透光、带颜色的吸收、
植物接收面的屏幕空间衰减以及阴影贴图范围外的近似处理。
近景树叶软影另对照 Photon 的 `shaders/include/lighting/shadows/pcss.glsl`，
独立实现按世界距离约束的树叶最小扩散范围，并保留搜索未命中时的叶片滤波。
没有复制或近似翻译其源码、特有表达式、常数或资产。

`lib/lighting/plant_subsurface.glsl` 与现有阴影路径的修改为独立实现：
复用本包的表面归一化 HG 函数、植物分类、漫反射率与深度步进。
薄片植物角度补偿、贴图柔化与偏移、接收面吸收和连续的贴图到屏幕可信度
均独立选定。草始终使用屏幕衰减，近处树叶方块依靠贴图遮蔽，随贴图
可信度降低再加入屏幕衰减。普通漫反射和植物受光增强量共同接受方向遮挡。
屏幕步进只读取深度，不逐采样判别遮挡物材质；贴图、天空光和顶点 AO
近似约束屏幕无法提供的遮挡，不宣称恢复真实叶片厚度或完整光输运。

## 30. 双档水面母基函数（概念与独立生成资产）

水面质量的低档保留原有小波；高档的
`textures/mother_medium_large_r8_128.dat` 与
`textures/mother_medium_large_slope_rg8_128.dat` 是本项目独立烘焙的高度与 UV 斜率，
分别为 128×128 R8 / RG8，不是第三方贴图。算法概念参考 Jerry Tessendorf，
《Simulating Ocean Water》(SIGGRAPH 2001)：Phillips 频谱、Fourier 合成与深水色散。
本项目独立实现连续可逆摆线压缩、解析导数、双线性最小二乘投影及单母图分层拟合，
没有移植第三方生成器、代码或资产。高档复用同一份母图采样 5 层法线和 3 层 POM 高度；
按层平移仅近似色散，不是逐模式 FFT 动画。独立生成资产按本包 GPL-3.0 使用。

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
