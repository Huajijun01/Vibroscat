# Vibroscat 更新说明

## 未发布（Alpha v0.3.0 工作区）

以下内容均以 `v0.2.0-alpha` 为基线，覆盖从 `v0.2.0-alpha` 到当前工作区的实际代码差异。

### 相较 v0.2.0-alpha 的更新

- **全局光照（GI）**：新增 `deferred3` 着色阶段与 `GI_MODE` 设置（无 / SSGI / 反射阴影贴图）。SSGI 移植自 Mirko Salm 的单向 GT-VBGI 可见性位掩码屏幕空间 GI（CC0 1.0）；RSM 模式复用阴影贴图，在 `shadowcolor0` 中打包 RGB565 反照率与八面体法线，按 Dachsbacher–Stamminger 2005 采样虚拟点光源（阴影投射关闭视锥剔除并纳入方块实体）。两种 GI 未覆盖的方向回退天空 SH；SSGI 会关闭 AO，RSM 保留 AO 并提供"最小天空因子"控制。两种 GI 共享可选的时域累积与空间降噪（SVGF 风格历史校验），历史长度 4–31 帧可调。新增资源：`colortex9`（RGB16F GI 辐照度历史）、`colortex10`（R32UI 深度/法线/年龄元数据历史）。
- **屏幕空间接触阴影**：`deferred4` 在受光面内联向太阳/月球方向对深度缓冲做短程行进，结果作为阴影贴图结果的上界（取 min），只加深阴影贴图漏亮的区域——补全 PCF 接触缝隙并在阴影贴图范围外保持方向光遮蔽。主世界与末地可用；步数、距离、遮挡厚度可调，附带调试视图。
- **GT7 色调映射**（`TONEMAP_MODE = 4`）：移植 Polyphony Digital 随 SIGGRAPH 2025 课程发布的官方样例（MIT）。逐通道 GT Tone Mapping Curve V2 与 ICtCp 色度渐隐路径按官方 0.6 比例混合，经 BT.709 ↔ BT.2020 矩阵进入和返回样例的帧缓冲域（250 nit 纸白），中灰锚点与其他模式一致；提供路径混合与色度渐隐起止点滑条。
- **Reinhard-AgX 色调映射**（`TONEMAP_MODE = 5`）：移植 DRT Bench 的线性暗部与 AgX 对数肩部混合曲线。肩部在归一化对数坐标上取 `z/(1+a·z^p)^(1/p)`，线性段与肩部在交接点同值同切线，系数按设定的高光到达档数解析求解；虚拟原色色域与 HSV 色相修复沿用 Reinhard-Gamut 阶段。中灰 18% 与显示白点锚点与其他模式一致；提供色域扩张、输入缩放、交接点、高光到达、肩部幂与色相保持六项设置（默认值取 DRT 工具：0.04 / 1.2195122 / 0.18 / 8 EV / 5.0 / 0.5）。
- **普尔金涅效应**：改为杆状视觉（暗视觉）蓝灰分级：从 CIE XYZ 估计杆体光谱亮度，暗部像素收敛为单位亮度的蓝灰杆体色，明亮光源保持色相；在后处理曝光之后应用，门控只依赖自动曝光的适应亮度（要求开启 AE），强度可调，默认关闭。
- **自动曝光重写**：曝光统计 SSBO 扩容（268 → 16904 字节），第一阶段收集对数亮度统计与 64 桶直方图，第二阶段由中位数与 P90 百分位导出稳健曝光（中位数剔除离群亮点/暗点，P90 保留高光余量；亮度键参考 Reinhard 2002）。新增 `AE_TARGET_LUMINANCE` 目标亮度设置（默认 0.18 对应中灰）。
- **边界雾**：将加载边界附近的几何体淡入带云天空盒，遮住已加载区域的切断边缘；仅主世界且开启空气雾时，在极线空气雾合成前应用；起始比例、强度、高度衰减可调。
- **大气地平线下沉**：低于地平线的天空射线可下探至地表以下至多 `ATM_HORIZON_DIP_SCALE` km 再终止，使低空稠密 Mie/气溶胶加厚地平线霾；默认开启（8 km）。
- **体积云重做**：分布贴图从 128² 更换为 1024²（R8），3D 侵蚀贴图更换为 Perlin-Worley 版本；分布世界尺度默认 64 → 280 km。云量与降雨直接耦合（降雨时趋向阴天覆盖），移除旧的大尺度云量调制与旧高度渐变曲线；低频侵蚀改为 `(1 - erosion)` 阈值形式并删除细侵蚀死路径。多重散射底深幂/偏置与 phi 强度默认值调整，移除 `MS_BOTTOM_SOFT` 选项，`CLOUD_PHI_OMEGA0` 0.94 → 0.75。时域升采样从棋盘格刷新改为 R2 序列抖动的移动低分辨率点阵，历史年龄上限 `CLOUD_HISTORY_FRAMES` 重定义为 8–48 帧的离散档位（默认 24）。云的太阳光色改用与天空 LUT 相同的 solar→D65 白平衡换算。
- **体积云散射改为多重散射近似**：云内多重散射改用 <https://zhuanlan.zhihu.com/p/457997155> 的近似，即饱和因子 `fms = ω0·(1-exp2(-300σ_t))` 与代表首次以后各阶散射的各向同性几何级数 `fms/(1-fms)`，替换原有的 phi_fwd 扩散场。方向光相位保留本包原有的三 octave 求和（`Σ c_k·P_k/(1+a_k·τ)`，由 `CLOUD_MS_ATTENUATION`、`CLOUD_MS_CONTRIBUTION`、`CLOUD_MS_ECCENTRICITY` 驱动），透射沿用原有的 `1/(1+τ)`，几何级数作为独立一项叠加其上。云密度采样器简化回单返回值。新增 `CLOUD_SINGLE_LIGHT` 开关（默认开启），开启时按 elevation 窗口把日月折叠成单一追踪方向、每采样只追一次，关闭时回到双通道独立追踪；折叠时用 `CloudTwilightWeight` 把太阳颜色保留到地平线以下的火烧云带，等反日点接管后释放。环境光路径维持原样。移除 `CLOUD_MS_DEPTH_POWER`、`CLOUD_MS_DEPTH_BIAS`、`CLOUD_MS_BOUNDARY_CONFIDENCE`、`CLOUD_PHI_INTENSITY`、`CLOUD_PHI_COMPRESSION`，新增 `CLOUD_MS_ALBEDO` 与 `CLOUD_MS_ISOTROPIC`；几何级数的饱和反照率固定在 `CLOUD_MS_FMS_ALBEDO` 常量上，不再由反照率滑条驱动。相位输入保留本包 dual-lobe HG。
- **卷云重做**：三瓣 HG 相函数（前向银衬 + 后向瓣）、平方密度场的单一物理消光、向日密度采样自遮蔽、掠射路径地平增厚；形状改为采样新的 1024² 分布贴图。
- **SSS 开关与低配档瘦身**：新增 `SHADOW_SSS` 开关独立关闭植物次表面散射——透射光照与厚度估计的额外阴影采样一并编译移除，各 SSS 滑条仅在开启时生效。性能预设按档位分层：低、中配（LOW/MEDIUM）关闭 SSS，高、顶配（HIGH/ULTRA）开启；LOW 同时关闭接触阴影，并移除该档下失效的对应参数。
- **云层独立开关**：新增 `CIRRUS` 开关独立控制高层卷云；体积云开关不再连带开关卷云，两层可任意组合。`LOW` 性能预设直接关闭体积云（保留开销极低的卷云壳层）并移除该档下失效的云步数/升采样参数。顺带修正：视角射线未命中体积云壳层时旧实现会连带跳过卷云，现在卷云按自身开关独立渲染。
- **粒子渲染路径重做**：`gbuffers_particles` 改用新的轻量 `solid_simple` 程序，在 G-buffer 阶段直接光照并经 SRC_ALPHA 混合写入半透明工作区（`colortex12`），渲染顺序改为半透明之后；不再走完整 solid G-buffer 路径。同时所有不透明 G-buffer 程序直写 `colortex12`（关闭混合）以清空半透明工作区。
- **SSS 能量守恒**：新增 `SHADOW_SSS_ENERGY`（植物透射可占用的直射光最大份额，默认 0.85），并从直射漫反射中做对应的能量扣除；新增 SSS 调试视图；`SHADOW_SSS_SCALE` 默认 4.0 → 1.0。
- **天空 SH 镜面环境卷积**：SH 环境反射查询增加随粗糙度收敛的低阶卷积（Phong 等效 zonal 核），粗糙表面的 SH 反射不再过散，L0 能量保持不变。
- **SSR 朝向相机的射线**：共享 SSR 投影器支持视线空间朝向相机的反射方向（此前直接跳过），介电反射在粗糙度阈值处平滑渐隐退出。
- **AO 深度来源**：GTAO/SSAO 的深度采样由 `depthtex1` 改为 `depthtex2`（不含半透明与手部）；GTAO 历史权重改在前帧视图空间计算，重投影支持显式区分手部等视图模型（不套用相机位移）。
- **后期**：运动模糊按材质 ID 识别并排除第一人称手（手部无世界空间运动矢量，保持清晰）；DOF 金角螺旋的像素尺度预计算。
- **湿度耦合**：移除自定义 `u_rain_strength`/`u_wetness`，直接使用内置 `rainStrength`/`wetness`；降雨提高空气雾 Mie 散射，湿润地表压暗天空 SH 地面反照。
- **RSM 天空遮蔽开关**：新增 `RSM_SKY_OCCLUSION` 独立开关控制"阴影遮蔽压暗 GI 天光"的编译路径，取代此前 `#if RSM_SKY_OCCLUSION_FLOOR < 1.0` 的浮点预处理比较（GLSL 规范的预处理表达式仅支持整数）。开关默认开启，与原默认 `RSM_SKY_OCCLUSION_FLOOR 0.2` 行为一致；滑条仅在开关开启时生效，关闭开关即彻底编译移除（等价旧的 1.0 档且不付出采样成本）。
- **默认值调整**：`sunPathRotation` -35° → -15°；`OPAQUE_PBR_EMISSION_SCALE` 1 → 10；GTAO 多重反弹（`GTAO_MULTIBOUNCE`）由 true/false 值选项改为独立编译开关并默认关闭。
- **设置界面重构**：主界面与多个子界面改为双列布局；新增"曝光"子界面（自动曝光、目标亮度、手动曝光、普尔金涅）与"全局光照"/"反射阴影贴图"子界面；"天空"并入"环境"页（星空亮度 + 地平线下沉）；阴影页新增接触阴影与 SSS 能量分组。四档性能配置（LOW–ULTRA）统一加入 RSM 采样数与接触阴影步数/距离档位。主界面新增版本/作者栏与"信息"子界面（开源许可证、性能预设说明、设置说明查看方式），并去除主界面与曝光页的占位空槽；色彩抖动强度从后期处理页移入色调映射页。本轮进一步按“一个功能一屏”重排：子界面由 18 个增至 39 个，最大叶屏由 37 项降至 10 项（此前有 5 个叶屏超过 14 项，最长到 37 项）。色调映射拆为 AgX、OKLAB、Reinhard-Gamut、Reinhard-AgX、GT7 五个参数页，总览页只留模式、饱和度、强度与颜色抖动；阴影拆为 PCSS、阴影深度、植物透光、接触阴影；云拆为形态、细节、光照、内部光、质量；水体拆为水面与体积光栅格；环境光遮蔽拆为 GTAO、SSAO 与历史；光照页新增“反射”子页并回归纯导航；三个调试视图集中到“信息 → 调试视图”页。补回此前无法在界面中到达的 `STAR_MAP` 与 `CLOUD_HISTORY_GUIDED_MARCH_END` 开关；`SHADOW_SSS_FADE_START` 与 `CLOUD_FINE_EROSION_STRENGTH` 由循环按钮改为滑条；修正 `CLOUD_VIEW_MIN_STEPS`、`CLOUD_VIEW_MAX_STEPS`、`CLOUD_THICKNESS_KM`、`CLOUD_MS_ALBEDO`、`CLOUD_MS_ISOTROPIC`、`CLOUD_HISTORY_GUIDED_END_SCALE` 与 `CONTACT_SHADOW_MAX_DISTANCE` 七处默认值或档位不在取值列表中的问题（最后一处使 MEDIUM 档的滑条位置与数值不符），并将 `AO_HISTORY_NORMAL_DOT_FLOOR` 的反向滑条改回升序；两处 37 字符以上的标签改为短名，避免在按钮内被截成同一串。
- **STBN 采样统一**：时空蓝噪声（STBN）的全部纹理采样集中到各 pass 的 `main`，库函数一律以参数接收噪声值；`lib/core/noise.glsl` 新增 `STBNFrame()` 时钟（无 TAA 时锁定时间片，避免无时间积累的效果闪烁）与 `STBN_STREAM_*` 时间片流注册表，替换此前散落各处的 `#ifdef TAA` 分支与 +16/+23/+32 魔法数。采样结果保持逐位一致，仅减少同像素重复读取（阴影滤波与接触阴影共享一次 STBN 读取，SSR 每像素 4 次 → 2 次）。
- **许可与出处**：`THIRD_PARTY_NOTICES` 新增 GT-VBGI（CC0 1.0）、RSM/SVGF 算法引用与 GT7（MIT，Polyphony Digital）条目；GI 中早期源自 Sundial-Lite（GPL-3.0）的表达已全部替换为 CC0/MIT 参考实现，仅保留经作者许可的齐次空间屏幕边缘射线截断；DRT 条目补充 Reinhard-AgX 与仓库转为 GPL-3.0 的许可状态。

### 设置文本与命名修正（审计落地）

对照 `docs/settings-naming-translation-audit.md` 的盘查结论，修掉了一批设置命名与译名问题。

- **移除两个从未接线的设置**：`CLOUD_DENSITY_MULTIPLIER`（密度倍率）与 `SHADOW_CONTACT_SHARPEN_TEXELS`（接触锐化）自 v0.1.0 起就没有任何着色器代码消费，提示词却描述了具体效果。两条已从界面、滑条列表、设置契约与两份语言文件中删除；同时删掉死标签 `profile.DEFAULT`（Iris 没有名为 DEFAULT 的档案，该键永远读不到）。
- **名实不符的标签与提示词**：半影上限（原名"太阳高度增益"，实现里没有太阳高度项）、方块光亮度（原名"火把亮度"，实际缩放全部方块光）、阴影半影角半径（原名"太阳角半径"，是 PCSS 假定值而非绘制的日轮）、GTAO/SSAO 对比度（原为"强度"，实现是取幂）、AO 变暗淡入速度（原为"变暗减速"，数值方向与字面相反）、极线锐化阈值（原为"边缘锐化"，实现是阈值，值越大锐化越弱）、细节侵蚀爬升高度比（原提示词把方向说反）、云量（补上降雨联动说明）等，均按实现改写并同步两语。
- **前置条件写进界面**：空气雾与边界雾整族标注"仅主世界"，接触阴影标注"仅主世界与末地"，三个调试视图各自补上使能条件（RSM 调试需把全局光照设为反射阴影贴图，SSS 调试需开启植物透光，接触阴影调试需开启接触阴影）。
- **缩写与术语**：TAA、CAS、SSGI、RSM、GTAO、SSAO、PCSS、PCF、SSS 在所属分类的提示词里各补一次全称；"MS"家族统一为 Multi-Scatter；SSS 子项中文统一用"透叶光"前缀；"强度/尺度/起点"等同义多译按类归并；开/关标签统一为"开/关"。
- **单位与量纲**：为 10 个带单位的设置补上 `suffix.*`（千米、米、千米/秒、像素、弧度等），并在标签里写明（千米）、（%）、（EV）、（纹素）等量纲。
- **宏名重命名**（跨文件同步设置契约、properties、两份语言文件与测试）：`SHADOW_SUN_HEIGHT_BOOST` → `SHADOW_PENUMBRA_CAP_BOOST`、`AO_DARKEN_SLOWDOWN` → `AO_DARKEN_FADE_SCALE`、`EPIPOLAR_EDGE_SHARPEN` → `EPIPOLAR_SHARPEN_THRESHOLD`、`AMBIENT_BASE` → `AMBIENT_FLOOR`、`STARMAP` → `STAR_MAP`、`AO_HISTORY_NORMAL_DOT_MIN` → `AO_HISTORY_NORMAL_DOT_FLOOR`。
- **取值组合守卫**：云步数最小/最大、PCF 采样最小/最大、GT7 色度渐隐起止三组滑条都能被配成反序，而 GLSL 的 `clamp`（minVal > maxVal）与 `smoothstep`（edge0 >= edge1）在反序时结果未定义。三处改为先取 `min`/`max` 再传入。
- **GI 调试视图修复**：`RSM_DEBUG` 的"滤波辐照度"一档此前与"时域辐照度"输出同一张图（邻域修复排在调试提前返回之后）。现在邻域修复排在调试分支之前，"滤波"一档输出的是光照路径真正使用的修复值。
- **删掉水雾焦散调制**：`WATER_FOG_CAUSTICS` 与 `WATER_FOG_CAUSTIC_STRENGTH` 只用波浪法线的面积代理去削弱水雾里的阳光散射项（系数恒在 0 与 1 之间，只会变暗不会变亮），且只在"从空中看向水面"这一条分支生效，画面上几乎看不出来。真正的焦散光斑来自 `program/translucent/blend.fragment` 里 256×256×64 的烘焙体积（`utex_caustics`，按折射光路在 1/4/9/16 米四个深度层之间混合），一直不受这两项控制。两项设置、`WaterFogRender` 的 `caustic_factor` 参数与那一段调制代码一并删除，体积焦散保持不变。

### 已知情况

- 当前工作区尚未发布；上述内容为开发中状态，可能在正式版本前继续调整。
- 仍处于 Alpha 阶段，部分效果、设置和不同显卡驱动组合可能存在画面瑕疵或性能差异。
- 目标环境为 Minecraft Java 26.2、Fabric Loader 0.19.x、对应版本的 Iris/Sodium 和 Java 21。
- GI 与接触阴影为新增的高开销特性；性能不足时优先降低 RSM 采样数、接触阴影步数，或选择无 GI 模式。

### English Summary

Compared with `v0.2.0-alpha`, the current workspace adds a full global illumination pass (`deferred3`) with selectable SSGI (GT-VBGI visibility-bitmask port, CC0) or reflective shadow map GI (virtual point lights from a packed `shadowcolor0`), shared optional temporal accumulation, and new `colortex9`/`colortex10` history buffers. Screen-space contact shadows now fill PCF contact seams and extend directional occlusion past the shadow map. Post processing gains the official GT7 tone mapping (MIT, SIGGRAPH 2025 course sample), an optional Purkinje scotopic shift, and a histogram/percentile auto-exposure rewrite with a configurable target luminance. Volumetric clouds switch to 1024² distribution and Perlin-Worley erosion textures with rain-coupled coverage and an R2-jittered temporal lattice; cirrus lighting is rebuilt with a silver-lining triple-lobe phase, and the volumetric layer and cirrus shell gain independent switches (the LOW profile now ships with volumetric clouds off). Particles are now lit directly through a new lightweight `solid_simple` program into the translucent workspace. Further changes include energy-conserving SSS with a debug view, roughness-aware sky SH specular convolution, camera-facing SSR rays, boundary fog, an atmospheric horizon below-dip, wetness coupling, and a reorganized two-column settings UI with updated performance profiles. In-cloud multiple scattering now uses the approximation published at <https://zhuanlan.zhihu.com/p/457997155>, that is a saturation factor `fms = omega*(1-exp2(-300*sigma_t))` and the isotropic geometric series `fms/(1-fms)` for every order past the first, replacing the phi_fwd diffusion field. The pack's three-octave phase sum and its `1/(1+tau)` transmittance stay and the series is added on top of them with a fixed saturation albedo and its own linear strength control, and the density sampler is back to a plain return value. A new `CLOUD_SINGLE_LIGHT` switch (on by default) folds the sun and moon into one traced direction like upstream's, halving the light traces, with the sun's colour held through the fire-cloud band below the horizon; turning it off restores the independent traces. The ambient path is unchanged. The pack's dual-lobe HG remains the phase input and no third-party phase table is imported.

## Alpha v0.2.0 - 2026-08-29

这是 Vibroscat 面向 Minecraft 26.2 / Iris 的第二个 Alpha 版本。以下内容均以 `v0.1.0-alpha` 为基线，覆盖从 `v0.1.0-alpha` 到本版本的实际代码差异。

### 相较 v0.1.0-alpha 的更新

- 按 Lab PBR 语义重构不透明材质解码和反射响应，正确处理感知粗糙度、F0/金属选择、发光通道和材质 AO。
- 新增不透明材质的递归（历史帧）SSR，并复用命中位置对应的可见历史像素，包括屏幕内天空命中。
- 不透明反射方向和 BRDF 改用材质法线；射线起点仍沿几何法线偏移，用于降低近距离 self-intersection 和错误屏幕像素复用风险。
- 增加不透明反射粗糙度控制：默认粗糙度阈值为 `0.5`，阈值下方的 `0.1` 粗糙度区间在 SSR 与 SH 环境反射之间平滑过渡；达到或超过阈值时跳过 SSR 射线追踪并使用 SH 反射。
- 统一水面与不透明反射的 SSR 穿越和屏幕边界校验，同时保留两者各自的材质、历史采样与天空回退路径。
- SH 环境反射增加 RGB 逐通道的 SH L0 平均辐亮度下限，并加入偏向漫反射的颜色衰减处理，同时保留 Fresnel 项。
- 将已有 `phi_fwd` 的置信度处理改为 HPVolumeCloud 风格的接收端底部置信度，并新增边界背光置信度；该实现是本项目的近似移植，不宣称与 HP 的源点级公式完全一致。
- `phi_fwd` 改为从接收点向太阳方向正序积分，移除正指数传播链，使传播与吸收项保持非正指数。
- 体积云主视线步进改为均匀线性步进，去除旧版的平方参数化。
- 将已有 `phi_fwd` 软压缩的默认参数从 `0.0` 调整为 `0.5`。
- 修复极线散射中的退化边界交点。
- 新增中英文不透明反射与云参数标签，并配置不透明反射追踪使用的 `colortex3` 资源和着色阶段。

### 已知情况

- 仍处于 Alpha 阶段，部分效果、设置和不同显卡驱动组合可能存在画面瑕疵或性能差异。
- 目标环境为 Minecraft Java 26.2、Fabric Loader 0.19.x、对应版本的 Iris/Sodium 和 Java 21。
- 建议先使用 Medium 画质；性能不足时优先降低云层和阴影质量。

### English Summary

Compared with `v0.1.0-alpha`, Alpha v0.2.0 corrects opaque Lab PBR decoding and adds historical recursive SSR, material-normal reflection/BRDF evaluation, roughness-based SSR/SH blending, and explicit screen-boundary validation. It also reworks the existing `phi_fwd` path with receiver-side integration, HPVolumeCloud-style bottom/boundary confidence, linear cloud marching, and soft compression enabled by default. Degenerate epipolar boundary intersections are now handled explicitly.
