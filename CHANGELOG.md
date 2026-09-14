# Vibroscat 更新说明

## Alpha v0.3.0（未发布）

基线：`v0.2.0-alpha` 发布树。以下内容由 **两棵源码树的逐文件对比**（文件增删、逐行 diff、宏与设置项对照）得出，不含任何由提交历史推断的条目。

### 一、新增功能

- **全局光照（GI）**：新增 `deferred3` 着色阶段（`program/deferred/recursive_gi.fragment`，三个维度各一对 `.fsh`/`.vsh` 包装），渲染目标为新的 `colortex9`（RGB16F，含未覆盖方向 SH 回退的 GI 辐照度）与 `colortex10`（R32UI 元数据：半精度视图深度 [0:15]、oct5 世界法线 [16:25]、年龄 [26:30]、来源位 [31]）。`GI_MODE` 三档：0 = 无（默认）、1 = SSGI、2 = 反射阴影贴图（RSM）。SSGI 移植 Mirko Salm 的单向 GT-VBGI 可见性位掩码屏幕空间 GI（CC0 1.0），预算 `SSGI_STEPS` 16、`SSGI_MARCH_PIXELS` 512 像素、`SSGI_THICKNESS` 0.5 m、`SSGI_RADIANCE_LIMIT` 128；RSM 按 Dachsbacher–Stamminger 2005 采样虚拟点光源，`RSM_SAMPLES` 16、`RSM_RADIUS` 8 m、`RSM_STRENGTH` 3.0。两种 GI 都以 SH 补齐未被覆盖的方向，并共享可选的时域累积与空间降噪（`GI_DENOISE` 默认开启，`GI_HISTORY_FRAMES` 24；历史失效时用 5×5 邻域借用已滤波值 `RepairGIDisocclusion`）。
- **GI 调试视图**：`RSM_DEBUG` 0–4（正常 / 原始辐照度 / 时域辐照度 / 滤波辐照度 / 历史年龄），集中到“信息 → 调试视图”页。
- **屏幕空间接触阴影**：`deferred4` 内联向当前方向光对深度缓冲做短程行进，结果作为阴影贴图结果的上界（取 `min`），补全 PCF 接触缝隙并在阴影贴图范围外保持方向光遮蔽。`CONTACT_SHADOW` 默认开启，`CONTACT_SHADOW_STEPS` 12、`CONTACT_SHADOW_MAX_DISTANCE` 24 m（行进距离视距的 7%，下限 0.12 m）、`CONTACT_SHADOW_THICKNESS` 0.02 m（按距离增长 0.0125 m/m）；主世界与末地可用（下界无方向光），附 `CONTACT_SHADOW_DEBUG` 原始遮罩 / 加暗视图。
- **GT7 色调映射**（`TONEMAP_MODE = 4`，**新默认**）：移植 Polyphony Digital 随 SIGGRAPH 2025 课程发布的官方 MIT 样例，逐通道 GT Tone Mapping Curve V2 与 ICtCp 色度渐隐路径按官方 0.6 比例混合，经 BT.709 ↔ BT.2020 矩阵进出样例的帧缓冲域（250 nit 纸白），中灰 18% 锚点与其他模式一致。样例参数保持官方 SDR 预设，唯一有意偏差是 alpha 取 0（肩部渐近线恰为纸白）。设置：`TONEMAP_GT7_BLEND` 0.6、`TONEMAP_GT7_CHROMA_FADE_START` 0.98、`TONEMAP_GT7_CHROMA_FADE_END` 1.16。
- **Reinhard-AgX 色调映射**（`TONEMAP_MODE = 5`）：移植 DRT Bench 的线性暗部 + AgX 对数肩部混合曲线，虚拟原色色域与 HSV 色相修复沿用 Reinhard-Gamut 路径，提供色域扩张、输入缩放、压缩起点、高光到达（EV）、肩部幂与色相保持六项设置（默认 0.04 / 1.2195122 / 0.18 / 8 EV / 5.0 / 0.5，取自 DRT 工具）。
- **普尔金涅效应**（`PURKINJE_EFFECT`，默认开启，强度 0.8）：杆状视觉蓝灰分级，杆体份额在包络键 0.004–0.04 之间对数渐变，锥体在亮度 0.35 以上重新接管，杆体色为 (0.45, 0.65, 1.0) 单位亮度蓝灰；只依赖自动曝光状态，AE 关闭时整条路径编译移除。
- **自动曝光重写**：曝光统计 SSBO 由 268 字节扩为 16904 字节，第一阶段改为带中心加权的对数亮度统计 + 64 桶直方图（每桶 0.3125 EV，覆盖 −12…+8 EV），采样步长 2 且相位按四帧轮转（约四分之一像素）；第二阶段用几何均值、中位数与 P90 导出稳健曝光。新增 `AE_TARGET_LUMINANCE`（默认 0.18，替代原先硬编码的 0.15）与 `AE_ADAPTATION_STRENGTH`（0.70）；曝光限幅 [1/32, 32]，P90 高光余量 0.80，变亮 4/s、变暗 0.8/s 的非对称适应，`frameTime` 限幅 0.1 s 防卡顿跳变，载入后前两帧直接对齐。`AE` 由默认关闭改为**默认开启**。
- **边界雾**（`BOUNDARY_FOG`，默认开启）：按距视距比例 `BOUNDARY_FOG_START`（0.7）把已加载区域边缘的几何淡入云天空盒，遮挡切断边缘；`BOUNDARY_FOG_STRENGTH` 1.0、`BOUNDARY_FOG_HEIGHT_FADE` 0.8（朝天空方向衰减）。仅主世界且开启空气雾时，在极线空气雾合成前应用。
- **大气地平线下沉**（`ATM_HORIZON_DIP`，默认开启，`ATM_HORIZON_DIP_SCALE` 8 km）：低于地平线的天空射线可下探至地表以下再终止，加厚地平线霾。
- **降雨/降雪可见**：大气雾阶段新增天气面片合成——读取 `colortex11`（首次为其声明 RGBA8 格式与清除标志），按向上天空辐照度做各向同性散射并叠加 HG(0.5) 直射瓣，光学厚度常量 4.0，由天空光照贴图遮罩，洞穴与室内不受影响。
- **星图开关与程序化星场**：新增 `STAR_MAP` 开关。关闭时（LOW/MEDIUM 预设）不再采样未绑定的贴图，改用两层程序化星场（星团聚集、逐星色温、赤经环绕）；开启时仍用 NASA 4K 贴图与双三次采样。
- **卷云独立开关**：`CIRRUS` 独立控制高层卷云，体积云开关不再连带开关卷云，两层可任意组合；天空盒 SH 探针在只开卷云时也会把卷云计入。
- **天空 SH 镜面粗糙度卷积**：`EvalSkyRadiance(direction, perceptual_roughness)` 增加 Phong 等效带谐核，L1/L2 随粗糙度收敛，L0 能量不变；粗糙表面的 SH 反射不再过散。
- **信息界面**：主界面新增版本/作者栏（`ABOUT`）与“信息”子界面（开源许可证、性能预设说明、设置提示用法、调试视图入口），均为只读展示项。

### 二、重做与行为变化

- **体积云多重散射换模型**：改用 <https://zhuanlan.zhihu.com/p/457997155> 的近似——饱和因子 `fms = ω0·(1 − exp2(−参考光学厚度))` 与代表首次以后各阶散射的各向同性几何级数 `fms/(1−fms)`，替换原先的各向同性扩散场（kappa、底部/边界置信度、phi 强度与软压缩整族参数）。参考光学厚度按层持有（体积云 300 m、卷云 1.2 km），饱和反照率同样按层固定（水云 0.99、冰云 0.999）而非由滑条驱动；`CLOUD_MS_ALBEDO`（0.9）改为线性缩放行进辐亮度，新增 `CLOUD_MS_ISOTROPIC`（0.3）与 `CIRRUS_MS_ISOTROPIC`（1.0）分别作为两层几何级数的强度。
- **体积云其它重做**：分布贴图 128² → 1024²（R8），3D 侵蚀贴图换成 Perlin-Worley 版本，分布世界尺度 64 → 280 km；移除大尺度云量调制与高度渐变曲线，云量直接与降雨耦合；低频侵蚀改为 `(1 − erosion)` 阈值形式并在宽相位为零时提前退出；密度采样器简化回单返回值；时域升采样由棋盘格刷新换成 R2 序列抖动的移动低分辨率点阵；历史年龄上限由 240 帧改为 `CLOUD_HISTORY_FRAMES`（默认 24，取值 8–48）；新增 `CLOUD_SINGLE_LIGHT`（默认开启）按 elevation 把日月折叠成单一追踪方向，并用 `CloudTwilightWeight` 把太阳颜色保留到地平线以下的火烧云带；天空光线不再被 180 km 的 `CLOUD_MAX_DISTANCE_KM` 截断（改用 `CLOUD_NO_CLOUD_DISTANCE` 哨兵值）；天空 LUT 的云步数反序守卫改为先取 `min`/`max`；云的太阳/月亮光色改用与天空相同的 Rec.2020 → sRGB 白平衡换算，移除 `MOON_DARKEN 0.4`（月光云亮度约为原来的 2.5 倍）。
- **卷云重做**：形状改由 1024² 分布贴图两个尺度做对比拉伸得到；消光 0.2 → 3.0 km⁻¹；新增向日自遮蔽行进与 `1/(1+τ)` 透过率；视图光学厚度按掠射路径 `H/|cos|`（下限 0.06）缩放；相位改为三瓣 HG（前向银衬 + 中瓣 + 后向瓣）；加入上述多重散射级数；日月在本地地平线以下 0.05 余弦内仍可见；环境光项整体 ×3。
- **植物透光（SSS）改为能量守恒**：新增 `SHADOW_SSS_ENERGY`（默认 0.85，直射光可占用的最大份额），从直射漫反射中按 `energy·saturate(phase·π)` 做对应扣除；透射项改为与阴影滤波同一个覆盖闸门内全量渲染，越过覆盖边界整项直接缺席——不再有天光交接、距离渐变或额外的可用性因子；`SHADOW_SSS_SCALE` 默认 4.0 → 1.0；新增 `SHADOW_SSS_DEBUG` 隔离视图；`SHADOW_SSS` 成为真正的编译开关，关闭时透射光照与厚度估计一并移除（LOW/MEDIUM 预设关闭）。
- **阴影覆盖淡出**：直接阴影此前在覆盖边缘是硬切换，出界瞬间从滤波结果跳成全亮。现在改为单一覆盖置信度曲线（原始未扭曲阴影 clip 空间的 XY 与深度两轴 `smoothstep(SHADOW_SSS_FADE_START, 1.0)` 乘积），直接阴影以 `mix(1, 滤波值, 覆盖率)` 平滑淡出。`SHADOW_SSS_FADE_START`（0.75）此前只出现在 properties、语言文件与设置契约里，**没有被任何着色器使用**，现在真正驱动该曲线。顺带删除此前写在 SSS 上的三个重叠因子（NDC 边缘、保护深度、视距比）。
- **删除半影距离柔化**：PCF 半径不再在 10–120 m 视距内按 `SHADOW_DISTANCE_BOOST`（默认 1.5）额外放大，半影完全由 PCSS 的阻挡层深度间隙 × 太阳角半径决定；该设置与其标签一并移除。半影上限改为不依赖太阳高度（`SHADOW_SUN_HEIGHT_BOOST` → `SHADOW_PENUMBRA_CAP_BOOST`，默认 1.0，上限 24 纹素在任何太阳高度一致）。PCF 采样最小/最大改为先取 `min`/`max` 再传入，反序配置不再触发未定义行为；PCSS 内部不再自行做边界测试与噪声采样，改由 pass 主体传入一次共享的 STBN 抖动（与接触阴影共用同一次读取）。
- **删除水雾焦散调制**：`WATER_FOG_CAUSTICS` 与 `WATER_FOG_CAUSTIC_STRENGTH` 只用波浪法线的面积代理削弱水雾里的阳光散射项，系数恒在 0 与 1 之间且只作用于“从空中看向水面”一条分支；两项设置、`WaterFogRender` 的 `caustic_factor` 参数与调制代码一并删除，体积焦散保持不变。
- **间接镜面反射**：新增粗糙度闸门，介电反射在 `OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD`（0.5）处归零，金属度把截止推向更粗糙的材质；SH 环境反射改用粗糙度卷积，去掉原先的 `mix(1, albedo, 0.8)` 着色与 `pow(skyLight, 16) · AO³` 调制；SSR 与 SH 共用同一个 `SpecularOcclusion`。
- **SSR 射线与回退**：朝向相机的反射方向此前被直接跳过，现在改为构建正确的前向目标并正常追踪；追踪未命中或落在屏幕外时回退到天空/SH 环境（此前直接返回黑色，屏幕边缘会出现黑块）。行进深度统一钳制到 [0,1]；深度穿越判定移到远平面/天空判定之前，此前在远平面附近找到的命中会被当作“射线出屏”直接丢弃。SSR 的随机数由两次 STBN 读取合并为一次配对读取。
- **GBuffer 几何法线改为世界空间**：`colortex4` 的 RG 由视图空间改为世界空间八面体法线，消除视角转动时的 8 位重量化阶梯；所有消费者（AO、AO 历史、接触阴影、阴影 bias、GI、SSR）同步更新，需要视图空间时显式做一次 `mat3(gbufferModelView)` 变换。
- **环境光遮蔽**：深度来源由 `depthtex1` 改为 `depthtex2`（不含半透明与手部），手持物不再遮挡 AO；GTAO 地平线步进补上纹素索引钳制（`uv == 1.0` 时不再越界读取）；AO 的应用数学集中到 `lib/lighting/ambient_occlusion.glsl`，手部像素直接返回无遮蔽；GTAO 多重反弹由 true/false 值选项改为独立编译开关并**默认关闭**；时域重投影改为输出上一帧视图空间接收点，历史权重在上一帧视图空间比较（不再每像素求逆矩阵两次），历史参数改名并修正取值列表（`AO_HISTORY_FRAMES` 补入默认值 48、`AO_HISTORY_DISTANCE_LIMIT` 补入 0.2、`AO_HISTORY_NORMAL_DOT_FLOOR` 反序列表改为升序）。
- **粒子渲染路径重做**：`gbuffers_particles` 改用新的轻量 `solid_simple` 程序（`RENDERTARGETS: 12,2`），在 G-buffer 阶段直接光照并经 SRC_ALPHA 混合写入半透明工作区 `colortex12`，渲染顺序改为半透明之后；粒子按世界朝上表面着色（此前把视图法线硬设为 `(0,1,0)`，等于屏幕朝上，光照随镜头俯仰翻转），且不再读取镜面贴图；所有不透明 G-buffer 程序直写 `colortex12`（关闭混合）以清空半透明工作区，避免残留。
- **水体表面**：垂直水面（池壁、瀑布侧面）此前被无条件赋予水平面波浪法线，现在按面朝向分流——水平面保留 POM 波浪路径，垂直面用几何 TBN 把同一波场重参数化到面平面；`colortex2` 半透明段改存相对平面的波扰动（xzy 交错、0.25 缩放），折射偏移以面自身法线为基准，平整侧面不再产生虚假位移。水波拟合层数 8 → 7（去掉最细的一档），POM 与 SSR 的步数设置改名为 `WATER_POM_COARSE_STEPS`/`WATER_POM_BISECT_STEPS`/`WATER_SSR_STEPS`。
- **极线体积光**：水体与空气的遮挡步数由共用的 `EPIPOLAR_SHADOW_STEPS`（默认 64，档位 16–256）拆成两项独立设置：`WATER_EPIPOLAR_SHADOW_STEPS`（默认 24，档位 8–64）与 `AIR_EPIPOLAR_SHADOW_STEPS`（默认 12，档位 8–64），四档预设依次为水体 16/24/24/32、空气 8/12/12/16；空气列估计器每步权重由 `t_sample` 改为 1（采样点本就按透过率分布，再乘一遍等于把采样密度平方，比值偏向列的远端，且加步数不收敛）；两种介质的水柱/空气柱键值统一改为线性视图深度，抖动改用按屏幕纹素索引的 STBN（TAA 可以平均掉），每调用不变量提到采样循环外；`EPIPOLAR_WATER` 更名为 `EPIPOLAR_VOLUMETRICS`，`EPIPOLAR_EDGE_SHARPEN` 更名为 `EPIPOLAR_SHARPEN_THRESHOLD`。
- **大气与雾**：气溶胶加入吸收项（OPAC 系数折叠）；运行时地面反照率 0.03 → 0.05 并为日月地面项补上显式余弦权重；新增地平线下沉；`AIR_FOG_DENSITY` 换成 `AIR_FOG_DENSITY_DAY`（10.0）/ `AIR_FOG_DENSITY_DUSK`（30.0），按太阳高度角绝对值在约 0.25（≈14.5°）内渐变；空气雾的消光统一为瑞利 + 气溶胶散射与吸收 + 臭氧，湿度额外贡献 `wetness·0.01`，极线空气列直接读同一份介质；米氏相位由单瓣 HG(0.8) 换成与天空/卷云相同的三瓣混合；天空 SH 的地面项按 `(1 − rainStrength·0.9)` 随降雨衰减，并改在 0.2 km 高度采样透射率。
- **日月盘与星图**：不再逐光源采样透射率 LUT，改由调用方传入视线透射率；单盘的“光源在地平线下即剔除”判断被移除，圆盘随视线透射率淡出而不是突然消失；不透明星空列直接跳过星图与圆盘计算。
- **天空 SH 探针并行化**：工作线程 256 → 512（两行条带），隔行取样并以 2 倍权重补偿，图像读取减半，积分规则与输出不变；SSBO 字段由 `skySH_*` 改名为 `sky_sh_*`。
- **STBN 采样统一**：全部时空蓝噪声采样集中到各 pass 的 `main`，库函数一律以参数接收噪声值；`lib/core/noise.glsl` 新增 `STBNFrame()` 时钟（无 TAA 时锁定时间片）与 `STBN_STREAM_*` 时间片流注册表、`SampleSTBNPair()`、`R2Offset()`、`LowBias32Hash()`，替换此前散落各处的 `#ifdef TAA` 分支与 16/23/32 等魔法数。
- **设置界面重构**：子界面由 13 个增至 39 个，最大叶屏由 37 项降至 12 项；主界面与多个子界面改为双列布局。新增“曝光”（自动曝光、目标亮度、适应增益、手动曝光、普尔金涅）、“全局光照”/“SSGI”/“反射阴影贴图”、“信息”→调试视图、“反射”、“接触阴影”、“植物透光”、“影子深度”、“PCSS”等页面；色调映射按算子拆为 AgX / OKLAB / Reinhard-Gamut / Reinhard-AgX / GT7 五页，总览页只留模式、饱和度、强度、颜色抖动；云拆为形态 / 细节 / 光照 / 多重散射 / 质量；AO 拆为 GTAO / SSAO / AO 历史；水体拆为水面与体积光栅格；并去除占位空槽。补回此前无法在界面中到达的 `STAR_MAP` 与 `CLOUD_HISTORY_GUIDED_MARCH_END`；修正“默认值不在自身取值列表中”的问题：对照两版设置契约，v0.2.0-alpha 有 12 项设置的默认值无法被自己的滑条表示（`TONEMAP_AGX_CONTRAST` 0.95、`CLOUD_THICKNESS_KM` 1.5、`CLOUD_EROSION_SCALE_KM` 1.5、`CLOUD_FINE_EROSION_HEIGHT` 0.3、`CLOUD_HISTORY_GUIDED_END_SCALE` 1.2、`SHADOW_SSS_SCALE` 4.0、`SHADOW_SSS_PHASE_G` 0.4、`GTAO_AGE_LIMIT` 48、`GTAO_HISTORY_DISTANCE_LIMIT` 0.2、反序的 `GTAO_HISTORY_NORMAL_DOT_MIN` 0.866，以及随本次改动删除的 `CLOUD_MS_DEPTH_BIAS`、`CLOUD_PHI_INTENSITY`），本版为 0。
- **语言与提示文本全面重写**：两份语言文件由 288 条增至 504 条（新增 269 条、删除 53 条、改写 96 条），提示词改为按实现描述的通俗说明；为 17 个带单位的设置补上 `suffix.*`（千米、米、千米/秒、像素、弧度等）；若干名实不符的标签按实现改写（如“太阳高度增益”→“半影上限提升”，“火把亮度”→“方块光亮度”，“强度”→“对比度”等）。
- **内部结构整理**（无行为变化）：`lib/atmosphere/core.glsl` 拆为 `media.glsl` / `spectral.glsl` / `transmittance.glsl` / `sky_radiance.glsl` / `skybox_uv.glsl`，相位函数集中到 `lib/scattering/phase.glsl`；`lib/color/color.glsl` 拆为 `spaces.glsl` + `tonemap.glsl` + 每算子一个文件（LogLuv32 解码移入 `celestial.glsl`）；`lib/material/core.glsl` 拆为 `model.glsl`（不透明 PBR 解析）与 `legacy.glsl`（前向半透明仍在用的标量金属度路径）；`lib/cloud/render.glsl` 更名为 `composite.glsl`；`lib/core/gbuffer_vertex.glsl` 内联回唯一的消费者 `solid.vertex`；`lib/core/filters.glsl` 抽出共享的 `BsplineWeights()`，阴影用的 `Shadow2DFastBspline` 移入 `lib/shadow/filter.glsl`；`lib/lighting/ambient_light.glsl` 抽出 `lightmap.glsl`；`lib/water/ocean.glsl` 抽出 `value_noise.glsl`；未使用的 `DecodeOldPBR`、`SkyViewLookup`、`Sqr`、`Split2x16`/`Unsplit2x16`、`ScreenDepthFromLinearDepth`、`CLOUD_ACCUMULATION_*`、`CLOUD_CHECKERBOARD_*` 等死代码删除，`SSRFinite` 与 `EpipolarViewZ` 并入共享的 `IsFinite` / `LinearDepthFromScreenDepth`；`centerDepthHalflife` 移入设置契约，新增共享工具 `IsFinite`、`FastAtan2`、`FastAcos`、`Rotate2D`、`GOLDEN_RATIO`、`INV_TWO_PI`、`ClipRayScreenExitT`、`PreviousScreenToView`、`EpipolarScreenTexel`、`EpipolarShadowVisibility`。
- **其它修正**：DOF 中心像素改用 `texelFetch`、修正了一处引用了未声明标识符 `phi` 的写法（改用文件自身的 `golden_ratio`）；运动模糊按材质 ID 识别并排除第一人称手（手部没有世界空间运动矢量，保持清晰）；云步数与 PCF 采样数的反序守卫；GTAO 采样边界钳制；`dither.glsl` 缺失的 `#endif` 守卫修正。

### 三、性能与开销（源码层面的成本变化）

以下全部是**结构性成本变化**——步数、采样次数、纹理读取次数、pass 开关与默认预算，来自代码本身；本工作区没有跑过 profiling，本节不给毫秒或百分比结论。

**采样预算直接下调**

- 极线体积光的遮影步数：水体由共用的 64 降到 `WATER_EPIPOLAR_SHADOW_STEPS` 24（档位由 16–256 收窄到 8–64），空气获得独立预算 `AIR_EPIPOLAR_SHADOW_STEPS` 12（原与水体共用 64）——空气光柱的遮挡行进次数约为原来的五分之一。
- 体积云默认预算：`CLOUD_VIEW_MIN_STEPS` 32 → 20、`CLOUD_VIEW_MAX_STEPS` 128 → 40、`CLOUD_LIGHT_STEPS` 8 → 6；LOW 档直接关闭体积云层，只保留开销极低的卷云壳层。
- `CLOUD_SINGLE_LIGHT`（默认开启）：每个云采样只追一条折叠后的日月方向，光照行进次数减半。
- 水波拟合层数 8 → 7：源码注明被删掉的最细一档只贡献法线斜率方差的 0.4%，却占用 32 次采样中的 4 次（`lib/water/value_noise.glsl:9-12`）。
- 自动曝光统计：第一阶段改为跨步采样（步长 2、相位按四帧轮转），参与统计的像素降到四分之一；行主序增量下标替换了每像素一次整数除法；线程数 256 → 512。
- 天空 SH 探针：隔行取样（stride 2）加 2 倍权重补偿，LUT 图像读取减半；线程 256 → 512，多出的车道只用于把更多 warp 压到同一个 SM。
- GTAO 多重反弹默认关闭，少一次逐通道多项式能量回收。

**合并重复读取 / 提前退出**

- 同一次 STBN 读取喂给多个消费者：PCSS 抖动与接触阴影共用一次读取（原先各自采样），SSR 的 GGX 采样与行进抖动合并为一次配对读取（原先两次），AO 用一次 `SampleSTBNPair` 取代原先两处采样，天空盒的云行进与卷云光照共用一次读取。
- 云密度：宏观相位提前退出放在细侵蚀 3D 纹理读取之前——采样被宏观相位抹掉时不再付一次 3D 读取；同时删除大尺度云量读取与高度相关的顶/底曲线。
- 半透明合成：极线取数、视线重建、两个相位与天空 SH 求值现在只在水面/水下像素执行，陆地与天空像素整组跳过（原先对所有像素无条件计算）。
- 不透明反射：天空/SH 环境回退采样从 deferred 着色移到追踪 pass，未命中像素不再在逐像素路径上多采一次。
- 星图与日月盘：云透过率为零时整段跳过。接触阴影：背面与弱直射像素跳过行进。水面 POM 场改用一次廉价双线性取数（注释：每采样省约 8 条 ALU），最终法线仍用平滑步进采样。

**循环不变量外提与重复求值消除**

- 两个极线积分 compute 把介质常量（水体 `per_metre`/`extinction`、空气起点与消光）由每采样一次改为每次调用一次。
- PCSS 把 `blocker_offset_scale`、`filter_radius`、`filter_offset_scale` 提出循环；AO 时域重投影不再每像素求逆两次矩阵；GTAO 法线变换每像素一次、`slice_angle_base` 提出切片循环；DOF 的 `blur_pixel_scale` 提出 12 次抽头循环；天空盒云的 `sun_dir` 与相机大气位置提出逐纹素循环。
- deferred 着色：`diffuse_reflectance` 只求值一次（原先火把项与 SSS 各一次）、`SpecularOcclusion` 只求值一次（原先 SH 与 SSR 各一次）、`sh_reflection_ndotv` 复用已有的 `ndotv`。
- 空气雾的消光改为单一出处，极线空气列直接读同一份介质，不再第二次求解。

**整段编译移除 / 逐帧开销**

- `GI_MODE == 1`（SSGI）时 AO 生成 pass `deferred1_a` 整体禁用；RSM 的载荷写入与采样只在 `GI_MODE == 2` 存在（默认 0 不付成本）；`SHADOW_SSS`、`CIRRUS`、`STAR_MAP`、`RSM_SKY_OCCLUSION`、`COLOR_DITHER` 关闭时对应采样与分支整体编译移除。
- 粒子改走轻量 `solid_simple` 路径，不再经过完整不透明 G-buffer（无 PBR 解码、无 POM/TBN、无镜面贴图），写入目标由 1/2/4 减为 12/2。
- 移除 10 条由 Iris 逐帧平滑求值的派生 uniform（6 条 `u_time_*`、`u_eye_blocklight`、`u_eye_skylight`、`u_rain_strength`、`u_wetness`），改读内置 `rainStrength`/`wetness`。
- 曝光统计的共享内存与树形归约按 512 线程重排；SH 归约首步同时配对两条带。

**为开销而做的默认值/档位取舍**

- 四档预设把新增的 GI/接触阴影纳入分层：LOW 关闭体积云、植物透光与接触阴影，MEDIUM 关闭植物透光；`RSM_SAMPLES` 按 8/16/32/64 分层，接触阴影步数与距离按档位递增。
- `CLOUD_SKY_LIGHT_STRENGTH` 上限扩展到 8.0：配合新的多重散射解析级数，云内部亮度由"多采样"改为单次求值。

### 四、默认值变化

| 设置 | v0.2.0-alpha | Alpha v0.3.0 |
| --- | --- | --- |
| `TONEMAP_MODE` | 3（Reinhard-Gamut） | 4（GT7），取值扩展为 0–5 |
| `AE` | 关闭 | 开启 |
| `COLOR_DITHER` | 无开关（恒定开启） | 新增开关，默认关闭 |
| `GTAO_MULTIBOUNCE` | true（值选项） | 独立开关，默认关闭 |
| `sunPathRotation` | −35° | −15° |
| `AMBIENT_BASE` → `AMBIENT_FLOOR` | 0.06 | 0.03 |
| `OPAQUE_PBR_EMISSION_SCALE` | 1.0 | 10.0 |
| `SHADOW_SSS_SCALE` | 4.0 | 1.0 |
| `CLOUD_DISTRIBUTION_SCALE_KM` | 64 km | 280 km（取值上限同步扩展） |
| `CLOUD_THICKNESS_KM` | 1.5 km | 1.3 km |
| `CLOUD_VIEW_MIN_STEPS` | 32 | 20 |
| `CLOUD_VIEW_MAX_STEPS` | 128 | 40 |
| `CLOUD_LIGHT_STEPS` | 8 | 6 |
| `CLOUD_SKY_LIGHT_STRENGTH` | 1.0 | 8.0（取值上限同步扩展） |
| `ATM_GROUND_ALBEDO`（内部常量） | 0.03 | 0.05 |
| `CIRRUS_SCATTERING`/`CIRRUS_EXTINCTION`（内部常量） | 0.2 km⁻¹ | 3.0 km⁻¹ |
| 曝光统计目标亮度（内部常量 → 设置） | 0.15 硬编码 | `AE_TARGET_LUMINANCE` 0.18 |
| 云历史年龄上限 | 240 帧 | `CLOUD_HISTORY_FRAMES` 24 帧 |
| 水波拟合层数 | 8 | 7 |

各性能预设（LOW / MEDIUM / HIGH / ULTRA）内容同步改写：四档加入 `STAR_MAP`、`WATER_EPIPOLAR_SHADOW_STEPS`、`AIR_EPIPOLAR_SHADOW_STEPS`、`RSM_SAMPLES` 与接触阴影步数/距离档位；LOW 额外关闭体积云（保留卷云壳层）、植物透光与接触阴影，MEDIUM 关闭植物透光，HIGH/ULTRA 开启植物透光。

### 五、被移除的设置与功能

- 移除的设置：`AIR_FOG_DENSITY`、`AMBIENT_BASE`、`AO_DARKEN_SLOWDOWN`、`CLOUD_DENSITY_MULTIPLIER`、`CLOUD_MS_DEPTH_POWER`、`CLOUD_MS_DEPTH_BIAS`、`CLOUD_MS_BOTTOM_SOFT`、`CLOUD_MS_BOUNDARY_CONFIDENCE`、`CLOUD_PHI_INTENSITY`、`CLOUD_PHI_COMPRESSION`、`EPIPOLAR_EDGE_SHARPEN`（改名）、`EPIPOLAR_SHADOW_STEPS`（拆分）、`EPIPOLAR_WATER`（改名）、`GTAO_AGE_LIMIT`、`GTAO_HISTORY_DISTANCE_LIMIT`、`GTAO_HISTORY_NORMAL_DOT_MIN`、`GTAO_TEMPORAL`、`GTAO_MULTIBOUNCE`（值选项）、`SHADOW_BLOCKER_DEPTH_TOLERANCE_METERS`（改名）、`SHADOW_CONTACT_SHARPEN_TEXELS`、`SHADOW_DISTANCE_BOOST`、`SHADOW_SUN_HEIGHT_BOOST`（改名）、`SSR_STEPS`（改名）、`VALUE_NOISE_POM_COARSE_STEPS`/`_BISECT_STEPS`（改名）、`WATER_FOG_CAUSTICS`/`WATER_FOG_CAUSTIC_STRENGTH`、无效键 `profile.DEFAULT`。
- 移除或失效的渲染行为：水雾焦散调制、半影距离柔化、GTAO 多重反弹的能量回收（默认关闭）、棋盘格时域升采样、180 km 云层行进截断、`MOON_DARKEN` 月光压暗、自定义 `u_rain_strength`/`u_wetness`（改用内置 `rainStrength`/`wetness`）与 `u_time_*`/`u_eye_*` 派生 uniform，以及两条从未被任何着色器读取的设置宏 `CLOUD_DENSITY_MULTIPLIER` 与 `SHADOW_CONTACT_SHARPEN_TEXELS`。
- 改名映射：`SHADOW_SUN_HEIGHT_BOOST` → `SHADOW_PENUMBRA_CAP_BOOST`；`AO_DARKEN_SLOWDOWN` → `AO_DARKEN_FADE_SCALE`；`EPIPOLAR_EDGE_SHARPEN` → `EPIPOLAR_SHARPEN_THRESHOLD`；`AMBIENT_BASE` → `AMBIENT_FLOOR`；`STARMAP`（旧宏名）→ `STAR_MAP`；`AO_HISTORY_NORMAL_DOT_MIN` → `AO_HISTORY_NORMAL_DOT_FLOOR`；`SHADOW_BLOCKER_DEPTH_TOLERANCE_METERS` → `SHADOW_BLOCKER_DEPTH_TOLERANCE_M`；`SSR_STEPS` → `WATER_SSR_STEPS`；`VALUE_NOISE_POM_*` → `WATER_POM_*`；`EPIPOLAR_WATER` → `EPIPOLAR_VOLUMETRICS`；`uimg_skylut_cloud` → `uimg_sky_radiance`；`CLOUD_HISTORY_NO_DATA` → `HISTORY_NO_CLOUD_DATA`；`CLOUD_SKYBOX_SIZE` → `SKY_RADIANCE_LUT_SIZE`；`skySH_*` → `sky_sh_*`。旧名称的存档值随之失效，首次进入需要重新选择。

### 六、资源与文件

- **新增缓冲**：`colortex9`（RGB16F，GI 辐照度历史）、`colortex10`（R32UI，GI 深度/法线/年龄/来源历史）、`colortex11`（RGBA8，天气面片，补上格式声明与清除标志）、`shadowcolor0`（RGBA8，RSM 的 RGB565 反照率 + 八面体法线，此前完全未使用）。
- **SSBO**：`bufferObject.0` 268 → 16904 字节（曝光统计）；`bufferObject.1` 保持 160 字节。
- **自定义图像**：`uimg_skylut_cloud` 更名为 `uimg_sky_radiance`（仍为 256×256 RGBA16F）。
- **贴图**：新增 `cloud_distribution_worley_fbm_1024.dat`、`cloud_distribution_worley_fbm_512.dat`、`cloud_erosion_perlin_worley_r8_64.dat`；重新烘焙 `transmittance_lut.dat`（数值与旧版基本一致）、`multiscatter_lut.dat`（各通道能量约为旧版的 1.5–2.8 倍，对应新的气溶胶吸收与地面反照率）与 `cloud_distribution_worley_fbm_128.dat`（整图重新生成）。`cloud_distribution_worley_fbm_128.dat`、`cloud_distribution_worley_fbm_512.dat` 与 `cloud_erosion_composite_r8_64.dat` 仍随包分发，但已没有任何 properties 声明引用它们；六个既有 `.mcmeta` 仅换行符不同，过滤与环绕设置未变。
- **新增源文件**：`lib/atmosphere/{media,spectral,transmittance,sky_radiance,skybox_uv}.glsl`、`lib/scattering/phase.glsl`、`lib/cloud/{composite,multiple_scattering}.glsl`、`lib/color/{spaces,tonemap,tonemap_aces,tonemap_agx,tonemap_drt_oklab,tonemap_gt7,tonemap_reinhard,purkinje}.glsl`、`lib/lighting/{lightmap,ambient_occlusion,gi_history,gi_denoise}.glsl`、`lib/material/{model,legacy}.glsl`、`lib/shadow/{filter,contact_shadow,reflective_shadow_map,rsm_data}.glsl`、`lib/water/value_noise.glsl`、`program/deferred/recursive_gi.fragment`、`program/gbuffer/solid_simple.{fragment,vertex}`，以及 `world-1|world0|world1/deferred3.{fsh,vsh}`。
- **删除源文件**：`lib/atmosphere/core.glsl`、`lib/cloud/checkerboard.glsl`、`lib/cloud/render.glsl`（更名）、`lib/color/color.glsl`、`lib/core/gbuffer_vertex.glsl`、`lib/material/core.glsl`（拆分）。
- **许可与出处**（`licenses/THIRD_PARTY_NOTICES.md` 与英文版）：新增 GT-VBGI / ReferenceGI（CC0 1.0，含早期适配借用 Sundial-Lite 表达已全部替换的溯源更正）、RSM 与 SVGF 算法引用、GT7 色调映射（MIT，Polyphony Digital，含移植适配说明）、云内多重散射近似出处；移除 HanPi Volume Cloud 派生代码条目（该实现已被替换）；DRT 色调映射条目补充 Reinhard-AgX 与仓库转为 GPL-3.0 的许可状态；各节重新编号。
- **README**：Effects 列表新增全局光照一条；移除“代码大部分由 AI 生成”的声明段落。

### 七、已知情况

- 当前工作区尚未发布；上述内容为开发中状态，可能在正式版本前继续调整。
- 本文件由 `v0.2.0-alpha` 发布树与当前工作区的源码逐文件对比得出，未做运行时验证（未编译、未在 Iris 中重载、未做性能测量）。文中出现的数值均为代码中的常量、默认值或设置项，不构成实测结论。
- 仍处于 Alpha 阶段，部分效果、设置和不同显卡驱动组合可能存在画面瑕疵或性能差异。
- 目标环境为 Minecraft Java 26.2、Fabric Loader 0.19.x、对应版本的 Iris/Sodium 和 Java 21。
- GI（`deferred3`）与接触阴影为新增的高开销特性，且 `GI_MODE` 默认关闭；性能不足时优先降低 RSM 采样数、接触阴影步数，或维持无 GI 模式。
- 第三节“性能与开销”记录的是**结构性成本**（步数、采样与纹理读取次数、pass 开关、默认预算），不是实测数据；本工作区没有跑过 profiling，因此没有毫秒或百分比结论。
- 若干处代码注释与实际取值不一致（例如卷云自遮蔽的注释仍写着旧的 0.4 km 步长与 8 步上限，实际为 0.2 km 与 3 步），这些注释尚未同步。

### English Summary

Compared with `v0.2.0-alpha`, Alpha v0.3.0 adds a full global illumination pass (`deferred3`/`recursive_gi.fragment`) with selectable SSGI (a CC0 port of the GT-VBGI visibility-bitmask tracer) or reflective shadow map GI, both sharing an optional temporal denoiser, a `colortex9` RGB16F irradiance history and a `colortex10` R32UI metadata history. Screen-space contact shadows now bound the shadow map in the Overworld and End. The default tone mapper becomes the official GT7 sample (MIT, SIGGRAPH 2025) and a Reinhard-AgX mode is added; auto-exposure is rewritten around a weighted log-average plus a 64-bin EV histogram with median/P90 percentiles and a configurable target luminance, and ships enabled. A Purkinje scotopic night grade, boundary fog, an atmospheric horizon dip, a visible weather sheet, a star-map switch with a procedural fallback, an independent cirrus switch and roughness-convolved sky SH complete the new feature set. Volumetric clouds switch to a 1024² distribution texture with Perlin-Worley erosion and a saturated-geometric-series multiple-scattering model, cirrus is rebuilt with a silver-lining triple-lobe phase and self-shadowing, plant SSS becomes an energy-conserving redistribution of the diffuse budget with a single coverage-fade curve, PCSS loses its distance softening, and the GBuffer geometric normal moves to world space. Indirect specular gains a real roughness gate, SSR traces camera-facing rays and falls back to the sky instead of black, particles move to a lightweight lit path, and the settings UI grows from 13 to 39 subscreens with both language files rewritten. The previous water-fog caustic controls, distance-based penumbra softening, checkerboard cloud upsampling and several never-wired settings are gone. A dedicated section documents the cost side of the release: epipolar shadow marches cut (water 64 to 24, air 64 to a new 12), lower volumetric-cloud step and light-step defaults, the single-light cloud trace, one STBN read shared by several consumers instead of one each, cloud and PSO early-outs placed before the expensive fetch, loop invariants hoisted out of sample and tap loops, whole passes compiled out when their feature is off, and ten derived per-frame Iris uniforms deleted. Those are structural cost changes read from the source; no profiling was run, so no timings or percentages are claimed. This changelog was derived from a file-by-file comparison of the two source trees; no runtime validation was performed.
