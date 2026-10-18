# Vibroscat 更新说明

## Alpha v0.3.0（未发布）

重烘多重散射 LUT 的太阳方向轴，改用地平线加密的有理映射与端点 texel 布局；运行时寻址改为一次倒数与乘加，移除该路径的反正弦和立方根。保留原逐阶多散射求解、32×32 RGBA16F 格式、高度轴与透射 LUT，改善暮光和蓝调区的插值分配。

统一七种 Tonemap 默认外观的暗部、中灰与亮白标定，保留参考算法的色彩与高光形成。自动曝光改用最多 32,768 个分层样本、剔除两端的对数均值、插值高光百分位和匹配各显示变换的高光保护；抑制细小曝光波动，并修正适应强度为零时仍被高光限制改变亮度的问题。沿用现有 pass、缓冲与格式。

优化 Bloom：保留到 1/128 的大范围泛光，融合半分辨率预滤波与首次缩小，并在 1/4 分辨率结束重建，计算调度由 13 次减为 11 次。首级改用分组 Karis，减少移动小亮点的亮度波动；最终重建改为一次三次 B 样条（四次钳制双线性采样），消除窄高光周围露出的 mip 2 网格，并修正图集采样的像素相位与奇数分辨率边界。复用现有缓冲与格式，光源中心的形状和极亮孤立像素的保留量会有所变化。

新增水下极线光柱：沿世界太阳方向积分，在线性场景颜色中直接加性叠加。光源项使用现有焦散的同一频谱、相位与光子追踪路径，烘焙为 64³ R16F 低频纹理，保持相同坐标、平流和动画时钟。起点采用 STBN 抖动，默认 32 步；最大步进距离可在“环境 / 水体 / 水下光柱”设置，默认 12 米，可选 2–32 米。复用现有极线图像与程序，不增加缓冲、pass 或独立时域历史。

新增植物晃动：terrain 与 shadow 共用顶点位移，短草、花、作物和树苗固定根部，双层植物连续弯曲，树叶方块共享顶点保持接缝一致。使用一张 64×64 RGBA16F 贴图预计算湍流气动载荷与阻尼弹性响应，每个运动顶点读取一次；“环境 / 植物”提供开关、风力、草花柔软度与树叶柔软度。甘蔗、竹子、藤蔓和水生植物保守保留为静止。

基线：`v0.2.0-alpha` 发布树。以下内容由 **两棵源码树的逐文件对比**（文件增删、逐行 diff、宏与设置项对照）得出，不含任何由提交历史推断的条目。

最新变更：恢复仅用于空气雾的极线体积光，阴影贴图按等距步长采样；晴天密度随世界高度指数衰减，雨天仅叠加不随高度变化的中性米氏散射与消光，白天密度较低、晨昏和夜间较高。光学厚度与晴天散射保持闭式解；雨天混合介质按独立源项积分，避免增益瑞利散射、臭氧和有色气溶胶吸收。E 保持无量纲散射比值；逐 RGB 通道按实际瑞利／米氏源项归一化，并积分每个等距区间的贡献，修正远段被低估的问题。水体继续使用始终启用的解析水雾。

空气雾默认标高调至 32 米（晴天密度每升高约 22 米减半），晨昏密度 120、雨天常值增益 160，环境散射强度 0.5；增强低处雾层、黄昏光柱对比和雨天浓雾。白天与夜间参考密度分别为 10 和 40。

### 一、新增功能

- **时域超分辨率（TAAU）**：在现有 TAA 阶段重建完整分辨率，默认关闭，需开启 TAA。场景渲染比例可选 50%、59%、67%、75% 和 85%；新增双线性/三次重建、历史权重、裁剪宽度、运动响应、颜色变化响应、锐化与调试设置。几何、AO、云、SSR、接触阴影和折射共用低分辨率坐标，后续曝光、泛光和色调映射保持输出分辨率。复用现有缓冲、程序和格式；没有单独历史深度或累计帧数，遮挡变化的历史拒绝依靠颜色裁剪。

- **雨天水坑与涟漪**：露天朝上的地形面复用云分布图生成水坑，在 G-buffer 内修改粗糙度和着色法线，直接复用现有不透明 PBR 与反射管线。地面随降雨积累和干燥，地面与水面共用一张周期 RG8 坡度贴图生成雨滴涟漪；按天空光、表面朝向、材质、生物群系和降雨提前剔除，不做距离或像素覆盖率淡出。贴图按 50 mm/h 暴雨的雨滴尺寸、终端落速与撞击能量，离线解算有限水深毛细-重力波并烘焙；采用 5 cm 等效水深、4% 波能传递与周期化近似，空间周期 4 m、时间周期 4 秒。为保证圆环可辨认，仅显示稀疏的大雨滴涟漪；精确零坡度编码减少平静区域杂纹。雨滴涟漪只扰动法线，不参与 POM。环境设置新增雨天打湿总开关；关闭水坑后改为全部合格地面打湿；涟漪法线强度默认 4.0，可调 0.0–4.0。无新增渲染阶段、缓冲或自定义图像。

- **雨天群系过渡**：新增平滑群系降雨因子 `u_rain_biome`，地面打湿与水面雨滴涟漪按连续权重过渡，避免玩家穿过降雨、干燥或降雪群系边界时突然出现或消失。

- **降雪群系因子**：新增平滑群系降雪因子 `u_snow_biome`（相机所在群系降雪资格的 [0,1] 连续权重，10 tick 半衰期升降平滑），供后续降雪类效果使用，当前不改变渲染表现。

- **半分辨率 GI 重建**：SSGI 与 RSM 复用 `deferred3` 生成并积累未模糊辐照度，历史年龄与 EMA 窗口分别限制为 64／128 帧。GI 使用持续探索的 Sobol 序列与无偏 FP16 舍入；`deferred4` 用对称十二邻居按世界几何法线与接收平面重建，再应用接收材质。GI 拥有独立于最终 TAA 的时域积累；已有 `colortex9`（RGB16F）缩至半宽半高，同尺寸 `colortex10`（RGBA16F）记录压缩法线、亮度二阶矩、深度及历史状态。无新增自定义图像、SSBO、着色程序或计算阶段；空间重建不写回 GI 历史，SSGI 仍读取正常的上一帧场景辐射。SSGI 保留 16 步，RSM 默认采样由 16 降至 8；四档质量预设的采样预算保持各自设置。薄物体若没有匹配代表像素，则使用自身环境光；一般物体运动缺少运动向量，仍有时域误差的可能。降噪质量仍在验证。
- **GI 调试视图**：`RSM_DEBUG` 0–1（正常 / 重建辐照度）。
- **GI 历史偏移修正**：历史重投影与空间权重均使用实际代表像素的位置；坐标完全对应时直接保留自身历史，修正以网格中心插值导致静止表面噪声随时间迁移的问题。
- **GI 移动历史插值修正**：按实际代表点包围目标，并修正奇数分辨率的取整边界；正权重三角插值保持线性光照梯度，减少连续移动中的历史漂移。冲刺动态 FOV 不再触发全屏历史拒绝。
- **屏幕空间接触阴影**：`deferred4` 内联向当前方向光对深度缓冲做短程行进，结果作为阴影贴图结果的上界（取 `min`），补全 PCF 接触缝隙并在阴影贴图范围外保持方向光遮蔽。`CONTACT_SHADOW` 默认开启，`CONTACT_SHADOW_STEPS` 12、`CONTACT_SHADOW_MAX_DISTANCE` 24 m（行进距离视距的 7%，下限 0.12 m）、`CONTACT_SHADOW_THICKNESS` 0.02 m（按距离增长 0.0125 m/m）；主世界与末地可用（下界无方向光），附 `CONTACT_SHADOW_DEBUG` 原始遮罩 / 加暗视图。
- **色调映射列表整体更换**（`TONEMAP_MODE`，**默认改为 0 = AgX**）：列表重排为 0=AgX、1=ACES 2.0、2=Blender AgX、3=OpenDRT、4=AMD LPM、5=GT7，并删除 OKLAB（Ottosson DRT）、ACES 1.0（Narkowicz 拟合曲线）、Reinhard-Gamut、Reinhard-AgX 与短暂存在过的 Khronos PBR Neutral：算子文件（`tonemap_drt_oklab.glsl`、`tonemap_aces.glsl`、`tonemap_reinhard.glsl`、`tonemap_pbr_neutral.glsl`）、设置项、界面页、语言条目与溯源章节一并移除；`spaces.glsl` 中因此失去唯一消费者的 `RGBToOKLAB`/`OKLABToRGB` 也删除。旧存档里的数值含义随之改变，首次进入需要重新选择模式。
- **AgX 换成 AgX-HSV**（`TONEMAP_MODE = 0`，**新默认**）：`tonemap_agx.glsl` 由 linlin 的 AgX-S2O3 曲线改为 DRT Bench 的 `agx_hsv.wgsl` 与它的 `AgxParameters::hsv_default()`（GPL-3.0）：对数范围仍为 −10…+6.5 EV，输出枢轴改为 sRGB OETF(0.18) = 0.46135613，pivot slope 2.4606366、toe/shoulder 幂 1.55/5.2、色域压缩 0.05，末段新增 HSV 色相修复。曲线系数与 DRT Bench 的测试值一致（toe_a = 11.2194730786、shoulder_a = 2568.7503334098）；输出域为 sRGB OETF，末端用本包 `ToLinear` 精确解码，锚点仍是场景 18% 灰 → 18% 显示线性、无需预缩放。中灰以上比被替换的 S2O3 曲线更亮（场景 0.5 / 1.0 / 4.0：0.421 / 0.641 / 0.944，旧曲线 0.378 / 0.547 / 0.847），与 GT7 的差距（场景 1.0 时为其 0.805）来自 AgX 自身的肩部。新增设置 `TONEMAP_AGX_HIGHLIGHT_HUE`（默认 0.5；0 = 交给曲线，1 = 完全保留场景色相）。
- **ACES 2.0 输出变换**（`TONEMAP_MODE = 1`）：按 ACES 2.0 参考 CTL（Apache-2.0，版本 2.0 / 2025-04-04）移植：Rec.709(D65) → ACES2065-1 的 Bradford 色适应、AP1 输入钳制、Hellwig-2022 CAM 的 JMh 正反变换、100 nit 峰值的 MM 色调曲线、色相相关色度压缩，输出 Rec.709 显示线性。**不含任何查找表**：参考实现里三个 360 项 hue 表是"只算一次"的优化，本包唯一需要的 reach 极限改为逐像素 8 步有界二分（区间 [50, 250]，参考表在 72.5…194.4 之间）；与参考核心相比 23016 个采样最大偏差 0.0078、平均 0.0005（显示线性）。未移植显示色域压缩器（依赖 cusp 表与 upper-hull gamma 表及嵌套求解）与全部逆变换，改为显示线性域钳制，代价是极端饱和高光按通道裁切。新增设置 `TONEMAP_ACES2_INPUT_SCALE`（默认 1.7133450 = 数值求解的共享 18% 灰锚点；1.0 = ACES 官方标尺，中灰低约 0.85 档）。
- **Blender AgX**（`TONEMAP_MODE = 2`）：移植 Blender 4.0 起作为默认视图变换的 AgX（GPL-2.0-or-later）。Blender 把该链路烘焙进 57³ `AgX_Base_sRGB.cube`，本包改为**闭式求值**同一条链：Rec.709→Rec.2020 与 AgX inset 合并为单个常量矩阵 → −10…+6.5 EV 归一化 log2 整形 → 六参数 toe/shoulder sigmoid（slope 2.4、power 1.5）→ 2.4 次幂反解出 AgX Base 编码 → AgX outset 与 Rec.2020→Rec.709 合并矩阵 → 显示线性并钳制。与 Blender 发行版 cube 的中性对角线在 −10…+6.5 EV 上最大偏差 1.3e-05（编码域）。未移植逐通道色相角混合（40%）、sRGB guard rails 与可选对比 look（后者作用于 25 档 AgX Log 空间，与本变换的 16.5 档整形空间不同）；变换自带 0.18 锚点（0.18 → 0.180000），因此该模式没有算子设置项。
- **OpenDRT 色调映射**（`TONEMAP_MODE = 3`，编号由 7 迁移）：实现与参数不变——Jed Smith 的 OpenDRT v1.1.0 参考 DCTL（GPL-3.0）Standard look 预设的完整链路，仅 SDR（峰值固定 100 尼特，HDR 相关参数被消去），输出线性交给 `final.fragment` 的 sRGB OETF；九项设置默认取 Standard 预设值，其中 `TONEMAP_ODT_GREY_LUMINANCE` 默认 15.1306824 为数值求解的 18% 灰锚点。逐像素结果与参考 DCTL 的 float64 最大偏差 4e-15（默认参数与十组参数回归验证）。
- **AMD LPM**（`TONEMAP_MODE = 4`）：移植 AMD FidelityFX Luma Preserving Mapper（MIT，`ffx-lpm/ffx_lpm.h`，头标记 `1.20200225`）。参考实现自身即 ALU 版本（其更新记录写明由 LUT 改为 ALU），因此不含也不需要任何查找表。移植 `LpmSetup` 的 toneScaleBias 求解（折成编译期常量）与 `LpmMap` 全链路（比值/亮度分离、比值上的饱和度幂、对**原始**亮度做色调曲线、比值重标定、crosstalk 回入色域、亮度补足），取 `LPM_CONFIG_709_709` + `LPM_COLORS_709_709`；未移植 `soft` 软色域、shoulder 相关分支、con2/scaleOnly 输出变换、FP16 路径与 `LpmSetupOut`，并为参考实现两处未守护的 0/0（纯黑、纯中性到达显示白）补了守护。与 `ffx_lpm.h` 的 Python 转写逐样本比对：28084 个样本最大偏差 6.5e-15，四组设置各自扫描最大 7.2e-15。设置：`TONEMAP_LPM_CONTRAST` 0.15（本包唯一调值，官方头 0.25 与样例 0.0 均在取值列表内）、`TONEMAP_LPM_SATURATION` 1.0（= 参考中性）、`TONEMAP_LPM_HDR_MAX` 1024、`TONEMAP_LPM_EXPOSURE` 10。
- **GT7 色调映射**（`TONEMAP_MODE = 5`，编号由 4 迁移）：实现与参数不变；仅编号、界面页与语言条目随列表更换调整位置。
- **Reinhard-AgX 色调映射**（`TONEMAP_MODE = 6`，重新移植）：取自 DRT Bench 的 `shaders/reinhard_agx.wgsl`（GPL-3.0-only，见「溯源」第 3 节）。先按 0.04 把 Rec.709 工作色域扩张到虚拟色域，逐通道送进「18% 以下线性、以上接 AgX 对数肩部」的曲线——值与该点切线在接点连续，肩部系数按 8 EV 高光触及解出，输出峰值落在显示白；回到 Rec.709 后再在编码域做 HSV 色相修复（保留 0.5）。该工具在 CPU 上按输出峰值求解曲线，本包只有 SDR，故折成常量：斜率 1、肩部范围 0.82、肩部系数 0.9990738451（= 1 − ln(1 + 55.9756097561)^−5）。场景 0.18 映射到显示 0.18，场景 0.5／1.0／4.0 映射到显示线性 0.450／0.732／0.990。没有新增缓冲、pass 或着色程序，设置界面仍只有模式选择器一个入口。把 `curve_for_headroom` 的求解结果与移植常量逐点比对，1e-6…1e6 区间最大偏差 3.4e-12。运行时以 `TONEMAP_MODE=6` 载入 `scene1`：`Shader reload succeeded`、无编译诊断，等待 120 帧后截图正常；同一场景 GT7（模式 5）对照的中位线性亮度为 0.226（Reinhard-AgX 0.222）、平均饱和度 0.402（0.360）、最大通道高于 0.9 的像素占 6.8%（3.0%）。两次截图间隔中云在移动，对照只能定性，且未做 GPU 计时。
- **新列表的运行时验证**：在补丁版 Iris 中逐模式各提交一次 `load_shader` 与一次 60 帧等待 + 截图（共 12 个请求），全部 `Shader reload succeeded`、无编译诊断；`scene1` 在 2560×1600 下六张截图均为有限值、无 NaN/纯白/纯黑帧。同一场景的中位线性亮度比（以 GT7 为 1）：ACES 2.0 1.012、Blender AgX 0.965、OpenDRT 0.984、AMD LPM 0.982、AgX 0.774，与各曲线在中灰之上的斜率差一致。未做 GPU 计时。
- **普尔金涅效应**（`PURKINJE_EFFECT`，默认开启，强度 0.8）：杆状视觉蓝灰分级，杆体份额在包络键 0.004–0.04 之间对数渐变，锥体在亮度 0.35 以上重新接管，杆体色为 (0.45, 0.65, 1.0) 单位亮度蓝灰；只依赖自动曝光状态，AE 关闭时整条路径编译移除。
- **自动曝光重写**：曝光统计 SSBO 由 268 字节扩为 16904 字节，第一阶段改为带中心加权的对数亮度统计 + 64 桶直方图（每桶 0.3125 EV，覆盖 −12…+8 EV），采样步长 2 且相位按四帧轮转（约四分之一像素）；第二阶段用几何均值、中位数与 P90 导出稳健曝光。新增 `AE_TARGET_LUMINANCE`（默认 0.18，替代原先硬编码的 0.15）与 `AE_ADAPTATION_STRENGTH`（0.70）；曝光限幅 [1/32, 32]，P90 高光余量 0.80，变亮 4/s、变暗 0.8/s 的非对称适应，`frameTime` 限幅 0.1 s 防卡顿跳变，载入后前两帧直接对齐。`AE` 由默认关闭改为**默认开启**。
- **边界雾**（`BOUNDARY_FOG`，默认开启）：按距视距比例 `BOUNDARY_FOG_START`（0.7）把已加载区域边缘的几何淡入无云天空 LUT，遮挡切断边缘；`BOUNDARY_FOG_STRENGTH` 1.0、`BOUNDARY_FOG_HEIGHT_FADE` 0.8（朝天空方向衰减）。仅主世界生效，与水雾独立；关闭边界雾后雨雪合成仍然执行。
- **大气地平线下沉**（`ATM_HORIZON_DIP`，默认开启，`ATM_HORIZON_DIP_SCALE` 8 km）：低于地平线的天空射线可下探至地表以下再终止，加厚地平线霾。
- **降雨/降雪可见**：大气雾阶段新增天气面片合成——读取 `colortex11`（首次为其声明 RGBA8 格式与清除标志），按向上天空辐照度做各向同性散射并叠加 HG(0.5) 直射瓣，光学厚度常量 4.0，由天空光照贴图遮罩，洞穴与室内不受影响。
- **NASA 4K 夜空星图**：夜空改用真实 NASA Deep Star Maps 2020 4K 贴图绘制（LogLuv32 RGBA8 编码、5 tap Catmull-Rom 双三次采样、赤经环绕），贴图对全部质量档无条件声明并始终采样，星空亮度仍由 `STAR_MAP_INTENSITY` 控制；v0.2.0 的两层程序化星场整体删除（见「五、被移除的设置与功能」）。
- **卷云独立开关**：`CIRRUS` 独立控制高层卷云，体积云开关不再连带开关卷云，两层可任意组合；天空盒 SH 探针在只开卷云时也会把卷云计入。
- **天空 SH 镜面粗糙度卷积**：`EvalSkyRadiance(direction, perceptual_roughness)` 增加 Phong 等效带谐核，L1/L2 随粗糙度收敛，L0 能量不变；粗糙表面的 SH 反射不再过散。
- **信息界面**：主界面新增版本/作者栏（`ABOUT`）与“信息”子界面（开源许可证、性能预设说明、设置提示用法、调试视图入口），均为只读展示项。

### 二、重做与行为变化

- **水下焦散重烘**：根据当前小波水面的三层强度、方向和运动统计，独立生成更丰富的水面，使用随机相位与延伸短波烘焙四个深度；覆盖区域缩至 8×8 米以提高细节，忽略水面坐标扰动，使用四秒周期近似，并重新校准过滤后的平均亮度。
- **设置开关统一为布尔选项**：`CONTACT_SHADOW`、`OPAQUE_REFLECTION`、`ATM_HORIZON_DIP` 由 0/1 值选项转为真正的布尔开关（质量预设同步改用 `!选项` 语法，语言文件删除对应的"开/关"值标签）；滑条与枚举选择器保留取值列表，内部常量不再带表。`settings.glsl` 末尾新增统一的 Iris 选项注册区块——Iris 只有在包含分量内出现纯 `#ifdef`／`#ifndef` 引用时才把裸布尔 define 注册为设置项，此前该确认散落在任意调用点，一次重构就可能让选项从设置界面静默消失（DOF／MOTION_BLUR 皆踩过此坑）；现在识别锚定在 settings.glsl 内部，消费代码可自由使用 `#if defined(...)` 等任意形式。派生内部宏（`*_ACTIVE`、GTAO／SSAO 等）集中到派生区块并以 `defined()` 判定；GTAO／SSAO 因被 `program.*.enabled` 表达式按名求值而保留注册。设置文件本体按渲染管线重排为编号分区（天空→云→雾→阴影→GI→AO→光照→水体→后处理→只读展示项→派生状态→注册区块）。

- **GI 历史响应与冷启动降噪**：SSGI／RSM 历史窗口分别限制为 64／128 帧，取消成熟后的额外长窗口。光照变化检查采用时域方差与连续同向残差，适用于几何未变的阴影变化；变化计数独立于真实年龄，修复普通噪声造成年龄回退、迟迟不收敛后突然变干净的问题。继续使用现有半分辨率历史与十二点上采样。
- **掠射角 GI 历史稳定性**：历史几何检查改为验证采样射线与接收平面的深度残差，消除远处方块侧面因沿面采样间距增大而错误刷新的问题；历史平面恢复 RGBA8 编码误差范围内的轴向法线，避免极浅视角放大法线量化误差。保留异面、深度遮挡与初始化邻域限制。

- **快速水雾**：始终使用解析水雾，水上、水下、焦散吸收和水下反射回退共用近海介质；不提供开关。独立 `const` 光学参数采用 CoASTS–BiOMaP 北亚得里亚海实测样本 `V770201`，补入 Pope–Fry 纯水吸收与 Zhang–Hu–He 海水分子散射，呈现蓝绿色并缩短可视距离；单独降低解析入射光权重以控制亮度，不缩放实测系数。旧空气雾、旧水雾、极线体积光及其全部设置和专用资源已移除。

- **体积云多重散射换模型**：改用 <https://zhuanlan.zhihu.com/p/457997155> 的近似——饱和因子 `fms = ω0·(1 − exp2(−参考光学厚度))` 与代表首次以后各阶散射的各向同性几何级数 `fms/(1−fms)`，替换原先的各向同性扩散场（kappa、底部/边界置信度、phi 强度与软压缩整族参数）。参考光学厚度按层持有（体积云 300 m、卷云 1.2 km），饱和反照率同样按层固定（水云 0.99、冰云 0.999）而非由滑条驱动；`CLOUD_MS_ALBEDO`（0.9）改为线性缩放行进辐亮度，新增 `CLOUD_MS_ISOTROPIC`（0.3）与 `CIRRUS_MS_ISOTROPIC`（1.0）分别作为两层几何级数的强度。
- **体积云其它重做**：分布贴图 128² → 1024²（R8），3D 侵蚀贴图换成 Perlin-Worley 版本，分布世界尺度 64 → 280 km；移除大尺度云量调制与高度渐变曲线，云量直接与降雨耦合；低频侵蚀改为 `(1 − erosion)` 阈值形式并在宽相位为零时提前退出；密度采样器简化回单返回值；时域升采样由棋盘格刷新换成 R2 序列抖动的移动低分辨率点阵；历史年龄上限由 240 帧改为 `CLOUD_HISTORY_FRAMES`（默认 24，取值 8–48）；新增 `CLOUD_SINGLE_LIGHT`（默认开启）按 elevation 把日月折叠成单一追踪方向，并用 `CloudTwilightWeight` 把太阳颜色保留到地平线以下的火烧云带；天空光线不再被 180 km 的 `CLOUD_MAX_DISTANCE_KM` 截断（改用 `CLOUD_NO_CLOUD_DISTANCE` 哨兵值）；天空 LUT 的云步数反序守卫改为先取 `min`/`max`；云的太阳/月亮光色改用与天空相同的 Rec.2020 → sRGB 白平衡换算，移除 `MOON_DARKEN 0.4`（月光云亮度约为原来的 2.5 倍）。
- **卷云重做**：形状改由 1024² 分布贴图两个尺度做对比拉伸得到；消光 0.2 → 3.0 km⁻¹；新增向日自遮蔽行进与 `1/(1+τ)` 透过率；视图光学厚度按掠射路径 `H/|cos|`（下限 0.06）缩放；相位改为三瓣 HG（前向银衬 + 中瓣 + 后向瓣）；加入上述多重散射级数；日月在本地地平线以下 0.05 余弦内仍可见；环境光项整体 ×3。
- **植物透光（SSS）改为能量守恒**：新增 `SHADOW_SSS_ENERGY`（默认 0.85，直射光可占用的最大份额），从直射漫反射中按 `energy·saturate(phase·π)` 做对应扣除；透射项改为与阴影滤波同一个覆盖闸门内全量渲染，越过覆盖边界整项直接缺席——不再有天光交接、距离渐变或额外的可用性因子；`SHADOW_SSS_SCALE` 默认 4.0 → 1.0；新增 `SHADOW_SSS_DEBUG` 隔离视图；`SHADOW_SSS` 成为真正的编译开关，关闭时透射光照与厚度估计一并移除（LOW/MEDIUM 预设关闭）。
- **阴影覆盖淡出**：直接阴影此前在覆盖边缘是硬切换，出界瞬间从滤波结果跳成全亮。现在改为单一覆盖置信度曲线（原始未扭曲阴影 clip 空间的 XY 与深度两轴 `smoothstep(SHADOW_SSS_FADE_START, 1.0)` 乘积），直接阴影以 `mix(1, 滤波值, 覆盖率)` 平滑淡出。`SHADOW_SSS_FADE_START`（0.75）此前只出现在 properties、语言文件与设置契约里，**没有被任何着色器使用**，现在真正驱动该曲线。顺带删除此前写在 SSS 上的三个重叠因子（NDC 边缘、保护深度、视距比）。
- **删除半影距离柔化**：PCF 半径不再在 10–120 m 视距内按 `SHADOW_DISTANCE_BOOST`（默认 1.5）额外放大，半影完全由 PCSS 的阻挡层深度间隙 × 太阳角半径决定；该设置与其标签一并移除。半影上限改为不依赖太阳高度（`SHADOW_SUN_HEIGHT_BOOST` → `SHADOW_PENUMBRA_CAP_BOOST`，默认 1.0，上限 24 纹素在任何太阳高度一致）。PCF 采样最小/最大改为先取 `min`/`max` 再传入，反序配置不再触发未定义行为；PCSS 内部不再自行做边界测试与噪声采样，改由 pass 主体传入一次共享的 STBN 抖动（与接触阴影共用同一次读取）。
- **删除水雾焦散调制**：`WATER_FOG_CAUSTICS` 与 `WATER_FOG_CAUSTIC_STRENGTH` 只用波浪法线的面积代理削弱水雾里的阳光散射项，系数恒在 0 与 1 之间且只作用于“从空中看向水面”一条分支；两项设置、`WaterFogRender` 的 `caustic_factor` 参数与调制代码一并删除，体积焦散保持不变。
- **间接镜面反射**：新增粗糙度闸门，介电反射在 `OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD`（0.5）处归零，金属度把截止推向更粗糙的材质；SH 环境反射改用粗糙度卷积，去掉原先的 `mix(1, albedo, 0.8)` 着色与 `pow(skyLight, 16) · AO³` 调制；SSR 与 SH 共用同一个 `SpecularOcclusion`。
- **SSR 射线与回退**：朝向相机的反射方向此前被直接跳过，现在改为构建正确的前向目标并正常追踪；追踪未命中或落在屏幕外时回退到天空/SH 环境（此前直接返回黑色，屏幕边缘会出现黑块）。行进深度统一钳制到 [0,1]；深度穿越判定移到远平面/天空判定之前，此前在远平面附近找到的命中会被当作“射线出屏”直接丢弃。SSR 的随机数由两次 STBN 读取合并为一次配对读取。
- **SSR 追踪拆分**：不透明反射（deferred2）与半透明反射（水面/玻璃）拆为两套独立追踪入口（`TraceOpaqueSSR`/`TraceTranslucentSSR`），投影弦、行进、插值细化与天空分类下沉为共享底层模块；删除按编译单元切换行为的 `SSR_OPAQUE_TRACE` 宏与 `WATER_SSR_ENABLED` 别名，行进步数直接由设置宏（`OPAQUE_SSR_STEPS`/`WATER_SSR_STEPS`）驱动。不透明 SSR 的“反射质量”枚举（仅环境/中/高/极高）拆为独立参数；命中点细化合并为共享的 `SSR_INTERPOLATION` 开关（默认开启）：在行进括弧内以 `OPAQUE_SSR_BISECT_STEPS`/`WATER_SSR_BISECT_STEPS`（各 4 次）二分定位首次深度交叉，再按二分位置做一次表面深度校正，平面上保持解析精确、轮廓处命中落在翻转侧；关闭后直接输出行进采样点的裸追踪结果，不再细化。
- **GBuffer 几何法线改为世界空间**：`colortex4` 的 RG 由视图空间改为世界空间八面体法线，消除视角转动时的 8 位重量化阶梯；所有消费者（AO、AO 历史、接触阴影、阴影 bias、GI、SSR）同步更新，需要视图空间时显式做一次 `mat3(gbufferModelView)` 变换。
- **环境光遮蔽**：深度来源由 `depthtex1` 改为 `depthtex2`（不含半透明与手部），手持物不再遮挡 AO；GTAO 地平线步进补上纹素索引钳制（`uv == 1.0` 时不再越界读取）；AO 的应用数学集中到 `lib/lighting/ambient_occlusion.glsl`，手部像素直接返回无遮蔽；GTAO 多重反弹由 true/false 值选项改为独立编译开关并**默认关闭**；时域重投影改为输出上一帧视图空间接收点，历史权重在上一帧视图空间比较（不再每像素求逆矩阵两次），历史参数改名并修正取值列表（`AO_HISTORY_FRAMES` 补入默认值 48、`AO_HISTORY_DISTANCE_LIMIT` 补入 0.2、`AO_HISTORY_NORMAL_DOT_FLOOR` 反序列表改为升序）；时域累积改为由 `AO_HISTORY_FRAMES` 封顶的累计平均（前 N−1 帧等权、随后保持 1/N，与云累积同律），移除与该设置脱钩的 4 帧定长 box 启动相位和 0.2 固定 EMA 稳态——稳态降噪深度由 `AO_HISTORY_FRAMES` 直接控制。
- **粒子渲染路径重做**：不透明 quad 粒子（`gbuffers_particles`）并入普通不透明 G-buffer 程序 `solid.*`，写完整 GBuffer（albedo、材质标量、世界空间几何与着色法线、光照贴图）并交由 `deferred4` 延迟着色；粒子按世界朝上表面着色（此前把视图法线硬设为 `(0,1,0)`，等于屏幕朝上，光照随镜头俯仰翻转），材质取粗糙、非金属、无自发光的介电默认值，AO 固定为 1，不读取法线/镜面贴图，也不参与雨天打湿；`gbuffers_particles` 不再向 `colortex12` 混合，透明粒子仍由 `gbuffers_particles_translucent` 前向着色并混合。MC 26.2 的新 quad 粒子路径把不透明粒子提交在 `deferred` 之前、透明粒子提交在透明地形之后，`particles.ordering` 在该版本已不参与调度；`shaders.properties` 改为 `particles.ordering = mixed`，让仍读取该属性的宿主得到同一分流。
- **水体表面**：垂直水面（池壁、瀑布侧面）此前被无条件赋予水平面波浪法线，现在按面朝向分流——水平面保留 POM 波浪路径，垂直面用几何 TBN 把同一波场重参数化到面平面；`colortex2` 半透明段改存相对平面的波扰动（xzy 交错、0.25 缩放），折射偏移以面自身法线为基准，平整侧面不再产生虚假位移。水波拟合层数 8 → 7（去掉最细的一档），POM 与 SSR 的步数设置改名为 `WATER_POM_COARSE_STEPS`/`WATER_POM_BISECT_STEPS`/`WATER_SSR_STEPS`。
- **极线体积光**：水体与空气的遮挡步数由共用的 `EPIPOLAR_SHADOW_STEPS`（默认 64，档位 16–256）拆成两项独立设置：`WATER_EPIPOLAR_SHADOW_STEPS`（默认 24，档位 8–64）与 `AIR_EPIPOLAR_SHADOW_STEPS`（默认 12，档位 8–64），四档预设依次为水体 16/24/24/32、空气 8/12/12/16；空气列估计器每步权重由 `t_sample` 改为 1（采样点本就按透过率分布，再乘一遍等于把采样密度平方，比值偏向列的远端，且加步数不收敛）；两种介质的水柱/空气柱键值统一改为线性视图深度，抖动改用按屏幕纹素索引的 STBN（TAA 可以平均掉），每调用不变量提到采样循环外；`EPIPOLAR_WATER` 更名为 `EPIPOLAR_VOLUMETRICS`，`EPIPOLAR_EDGE_SHARPEN` 更名为 `EPIPOLAR_SHARPEN_THRESHOLD`。
- **大气与雾**：气溶胶加入吸收项（OPAC 系数折叠）；运行时地面反照率 0.03 → 0.05 并为日月地面项补上显式余弦权重；新增地平线下沉；`AIR_FOG_DENSITY` 换成 `AIR_FOG_DENSITY_DAY`（10.0）/ `AIR_FOG_DENSITY_DUSK`（30.0），按太阳高度角绝对值在约 0.25（≈14.5°）内渐变；空气雾的消光统一为瑞利 + 气溶胶散射与吸收 + 臭氧，湿度额外贡献 `wetness·0.01`，极线空气列直接读同一份介质；米氏相位由单瓣 HG(0.8) 换成与天空/卷云相同的三瓣混合；天空 SH 的地面项按 `(1 − rainStrength·0.9)` 随降雨衰减，并改在 0.2 km 高度采样透射率。
- **日月盘与星图**：不再逐光源采样透射率 LUT，改由调用方传入视线透射率；单盘的“光源在地平线下即剔除”判断被移除，圆盘随视线透射率淡出而不是突然消失；不透明星空列直接跳过星图与圆盘计算。
- **天空 SH 探针并行化**：工作线程 256 → 512（两行条带），隔行取样并以 2 倍权重补偿，图像读取减半，积分规则与输出不变；SSBO 字段由 `skySH_*` 改名为 `sky_sh_*`。
- **STBN 采样统一**：全部时空蓝噪声采样集中到各 pass 的 `main`，库函数一律以参数接收噪声值；`lib/core/noise.glsl` 新增 `STBNFrame()` 时钟（无 TAA 时锁定时间片）与 `STBN_STREAM_*` 时间片流注册表、`SampleSTBNPair()`、`R2Offset()`、`LowBias32Hash()`，替换此前散落各处的 `#ifdef TAA` 分支与 16/23/32 等魔法数。
- **设置界面重构**：子界面由 13 个增至 39 个，最大叶屏由 37 项降至 12 项；主界面与多个子界面改为双列布局。新增“曝光”（自动曝光、目标亮度、适应增益、手动曝光、普尔金涅）、“全局光照”/“SSGI”/“反射阴影贴图”、“信息”→调试视图、“反射”、“接触阴影”、“植物透光”、“影子深度”、“PCSS”等页面；色调映射按算子拆为 AgX / ACES 2.0 / OpenDRT / AMD LPM / GT7 五页（Blender AgX 无可调项，故无独立页），总览页只留模式、饱和度、强度、颜色抖动；云拆为形态 / 细节 / 光照 / 多重散射 / 质量；AO 拆为 GTAO / SSAO / AO 历史；水体拆为水面与体积光栅格；并去除占位空槽。补回此前无法在界面中到达的 `CLOUD_HISTORY_GUIDED_MARCH_END`；修正“默认值不在自身取值列表中”的问题：对照两版设置契约，v0.2.0-alpha 有 12 项设置的默认值无法被自己的滑条表示（`TONEMAP_AGX_CONTRAST` 0.95、`CLOUD_THICKNESS_KM` 1.5、`CLOUD_EROSION_SCALE_KM` 1.5、`CLOUD_FINE_EROSION_HEIGHT` 0.3、`CLOUD_HISTORY_GUIDED_END_SCALE` 1.2、`SHADOW_SSS_SCALE` 4.0、`SHADOW_SSS_PHASE_G` 0.4、`GTAO_AGE_LIMIT` 48、`GTAO_HISTORY_DISTANCE_LIMIT` 0.2、反序的 `GTAO_HISTORY_NORMAL_DOT_MIN` 0.866，以及随本次改动删除的 `CLOUD_MS_DEPTH_BIAS`、`CLOUD_PHI_INTENSITY`），本版为 0。
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
- 不透明 SSR 默认行进步数：HIGH 档由 40（`OPAQUE_SSR_QUALITY` 2）降为 `OPAQUE_SSR_STEPS` 8，ULTRA 档由 64 降为 8；水面 SSR 由 16 降为 8。默认整条反射射线共 9 次深度采样（8 次行进 + 1 次插值），插值细化默认开启，把命中点拉向实际表面。

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

- `GI_MODE == 1`（SSGI）时 AO 生成 pass `deferred1_a` 整体禁用；RSM 的载荷写入与采样只在 `GI_MODE == 2` 存在（默认 0 不付成本）；`SHADOW_SSS`、`CIRRUS`、`COLOR_DITHER` 关闭时对应采样与分支整体编译移除。
- 不透明粒子回到普通不透明 G-buffer 路径：每个粒子写 1/2/4/12 四个目标（先前的轻量粒子路径为 12/2），但跳过 TBN、法线/镜面贴图采样与打湿计算，材质直接取固定介电默认值。
- 移除 10 条由 Iris 逐帧平滑求值的派生 uniform（6 条 `u_time_*`、`u_eye_blocklight`、`u_eye_skylight`、`u_rain_strength`、`u_wetness`），改读内置 `rainStrength`/`wetness`。
- 曝光统计的共享内存与树形归约按 512 线程重排；SH 归约首步同时配对两条带。

**为开销而做的默认值/档位取舍**

- 四档预设把新增的 GI/接触阴影纳入分层：LOW 关闭体积云、植物透光与接触阴影，MEDIUM 关闭植物透光；`RSM_SAMPLES` 按 8/16/32/64 分层，接触阴影步数与距离按档位递增。
- `CLOUD_SKY_LIGHT_STRENGTH` 上限扩展到 8.0：配合新的多重散射解析级数，云内部亮度由"多采样"改为单次求值。

### 四、默认值变化

| 设置 | v0.2.0-alpha | Alpha v0.3.0 |
| --- | --- | --- |
| `TONEMAP_MODE` | 3（Reinhard-Gamut） | **0（AgX）**，列表整体更换为 0=AgX 1=ACES 2.0 2=Blender AgX 3=OpenDRT 4=AMD LPM 5=GT7 |
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
| `OPAQUE_SSR_QUALITY` → `OPAQUE_SSR_STEPS` | 2（40 步） | 12 步（总采样 = 12 行进 + 4 二分 + 1 校正） |
| `WATER_SSR_STEPS` | 16 | 12（总采样 = 12 行进 + 4 二分 + 1 校正） |
| `SSR_BISECTION_REFINE` | 关闭（两路共享） | 改为共享插值开关 `SSR_INTERPOLATION`，默认开启 |
| `ATM_GROUND_ALBEDO`（内部常量） | 0.03 | 0.05 |
| `CIRRUS_SCATTERING`/`CIRRUS_EXTINCTION`（内部常量） | 0.2 km⁻¹ | 3.0 km⁻¹ |
| 曝光统计目标亮度（内部常量 → 设置） | 0.15 硬编码 | `AE_TARGET_LUMINANCE` 0.18 |
| 云历史年龄上限 | 240 帧 | `CLOUD_HISTORY_FRAMES` 24 帧 |
| 水波拟合层数 | 8 | 7 |

各性能预设（LOW / MEDIUM / HIGH / ULTRA）内容同步改写：四档加入 `WATER_EPIPOLAR_SHADOW_STEPS`、`AIR_EPIPOLAR_SHADOW_STEPS`、`RSM_SAMPLES` 与接触阴影步数/距离档位；LOW 额外关闭体积云（保留卷云壳层）、植物透光与接触阴影，MEDIUM 关闭植物透光，HIGH/ULTRA 开启植物透光。HIGH/ULTRA 的不透明反射行进预算统一为 `OPAQUE_SSR_STEPS` 8（总采样 9）。

### 五、被移除的设置与功能

- 移除的设置：`AIR_FOG_DENSITY`、`AMBIENT_BASE`、`AO_DARKEN_SLOWDOWN`、`CLOUD_DENSITY_MULTIPLIER`、`CLOUD_MS_DEPTH_POWER`、`CLOUD_MS_DEPTH_BIAS`、`CLOUD_MS_BOTTOM_SOFT`、`CLOUD_MS_BOUNDARY_CONFIDENCE`、`CLOUD_PHI_INTENSITY`、`CLOUD_PHI_COMPRESSION`、`EPIPOLAR_EDGE_SHARPEN`（改名）、`EPIPOLAR_SHADOW_STEPS`（拆分）、`EPIPOLAR_WATER`（改名）、`GTAO_AGE_LIMIT`、`GTAO_HISTORY_DISTANCE_LIMIT`、`GTAO_HISTORY_NORMAL_DOT_MIN`、`GTAO_TEMPORAL`、`GTAO_MULTIBOUNCE`（值选项）、`OPAQUE_SSR_QUALITY`（拆分）、`SHADOW_BLOCKER_DEPTH_TOLERANCE_METERS`（改名）、`SHADOW_CONTACT_SHARPEN_TEXELS`、`SHADOW_DISTANCE_BOOST`、`SHADOW_SUN_HEIGHT_BOOST`（改名）、`SSR_BISECTION_REFINE`（改名）、`SSR_STEPS`（改名）、`STAR_MAP`（开关）、`VALUE_NOISE_POM_COARSE_STEPS`/`_BISECT_STEPS`（改名）、`WATER_FOG_CAUSTICS`/`WATER_FOG_CAUSTIC_STRENGTH`、无效键 `profile.DEFAULT`。
- 移除或失效的渲染行为：水雾焦散调制、半影距离柔化、AO 变暗淡入减速、GTAO 多重反弹的能量回收（默认关闭）、棋盘格时域升采样、180 km 云层行进截断、`MOON_DARKEN` 月光压暗、两层程序化星场（夜空恒用 NASA 4K 星图）、自定义 `u_rain_strength`/`u_wetness`（改用内置 `rainStrength`/`wetness`）与 `u_time_*`/`u_eye_*` 派生 uniform、SSR 二分法命中复查（改为步长内插值），以及两条从未被任何着色器读取的设置宏 `CLOUD_DENSITY_MULTIPLIER` 与 `SHADOW_CONTACT_SHARPEN_TEXELS`。
- 改名映射：`SHADOW_SUN_HEIGHT_BOOST` → `SHADOW_PENUMBRA_CAP_BOOST`；`EPIPOLAR_EDGE_SHARPEN` → `EPIPOLAR_SHARPEN_THRESHOLD`；`AMBIENT_BASE` → `AMBIENT_FLOOR`；`STARMAP`（旧宏名）→ `STAR_MAP`（随后随程序化星场一并移除，夜空恒用 NASA 4K 星图）；`AO_HISTORY_NORMAL_DOT_MIN` → `AO_HISTORY_NORMAL_DOT_FLOOR`；`SHADOW_BLOCKER_DEPTH_TOLERANCE_METERS` → `SHADOW_BLOCKER_DEPTH_TOLERANCE_M`；`SSR_STEPS` → `WATER_SSR_STEPS`；`OPAQUE_SSR_QUALITY` → `OPAQUE_SSR_STEPS`；`SSR_BISECTION_REFINE` → `SSR_INTERPOLATION`；`VALUE_NOISE_POM_*` → `WATER_POM_*`；`EPIPOLAR_WATER` → `EPIPOLAR_VOLUMETRICS`；`uimg_skylut_cloud` → `uimg_sky_radiance`；`CLOUD_HISTORY_NO_DATA` → `HISTORY_NO_CLOUD_DATA`；`CLOUD_SKYBOX_SIZE` → `SKY_RADIANCE_LUT_SIZE`；`skySH_*` → `sky_sh_*`。旧名称的存档值随之失效，首次进入需要重新选择。

### 六、资源与文件

- **新增缓冲**：`colortex9`（RGB16F，GI 辐照度历史）、`colortex10`（RGBA16F，半分辨率 GI 几何/年龄/来源历史）、`colortex11`（RGBA8，天气面片，补上格式声明与清除标志）、`shadowcolor0`（RGBA8，RSM 的 RGB565 反照率 + 八面体法线，此前完全未使用）。
- **SSBO**：`bufferObject.0` 268 → 16904 字节（曝光统计）；`bufferObject.1` 保持 160 字节。
- **自定义图像**：`uimg_skylut_cloud` 更名为 `uimg_sky_radiance`（仍为 256×256 RGBA16F）。
- **贴图**：新增 `cloud_distribution_worley_fbm_1024.dat`、`cloud_distribution_worley_fbm_512.dat`、`cloud_erosion_perlin_worley_r8_64.dat`；重新烘焙 `transmittance_lut.dat`（数值与旧版基本一致）、`multiscatter_lut.dat`（各通道能量约为旧版的 1.5–2.8 倍，对应新的气溶胶吸收与地面反照率）与 `cloud_distribution_worley_fbm_128.dat`（整图重新生成）。`cloud_distribution_worley_fbm_128.dat`、`cloud_distribution_worley_fbm_512.dat` 与 `cloud_erosion_composite_r8_64.dat` 仍随包分发，但已没有任何 properties 声明引用它们；六个既有 `.mcmeta` 仅换行符不同，过滤与环绕设置未变。
- **新增源文件**：`lib/atmosphere/{media,spectral,transmittance,sky_radiance,skybox_uv}.glsl`、`lib/scattering/phase.glsl`、`lib/cloud/{composite,multiple_scattering}.glsl`、`lib/color/{spaces,tonemap,tonemap_aces2,tonemap_agx,tonemap_blender_agx,tonemap_gt7,tonemap_lpm,tonemap_opendrt,purkinje}.glsl`、`lib/lighting/{lightmap,ambient_occlusion,gi_history,gi_denoise}.glsl`、`lib/material/{model,legacy}.glsl`、`lib/shadow/{filter,contact_shadow,reflective_shadow_map,rsm_data}.glsl`、`lib/water/value_noise.glsl`、`program/deferred/recursive_gi.fragment`，以及 `world-1|world0|world1/deferred3.{fsh,vsh}`。
- **删除源文件**：`lib/atmosphere/core.glsl`、`lib/cloud/checkerboard.glsl`、`lib/cloud/render.glsl`（更名）、`lib/color/color.glsl`、`lib/core/gbuffer_vertex.glsl`、`lib/material/core.glsl`（拆分）。
- **许可与出处**（`licenses/THIRD_PARTY_NOTICES.md` 与英文版）：新增 GT-VBGI / ReferenceGI（CC0 1.0，含早期适配借用 Sundial-Lite 表达已全部替换的溯源更正）、RSM 与 SVGF 算法引用、GT7 色调映射（MIT，Polyphony Digital，含移植适配说明）、ACES 2.0 输出变换（Apache-2.0，含修改声明、未移植阶段与无表说明）、Blender AgX（GPL-2.0-or-later，含与发行版 cube 的比对结果）、AMD FidelityFX LPM（MIT，含未移植阶段与守护说明）、OpenDRT 色调映射（GPL-3.0，含 GPL-3.0 第 5(a) 条修改声明与移植范围）、云内多重散射近似出处；第 2、3 节改写为 AgX-HSV（DRT Bench）的现行出处，并移除已不再分发的 AgX-S2O3（MIT）与 Khronos PBR Neutral（Apache-2.0）章节，各节重新编号；移除 HanPi Volume Cloud 派生代码条目（该实现已被替换）；各节重新编号。
- **README**：Effects 列表新增全局光照一条；移除“代码大部分由 AI 生成”的声明段落。

### 七、已知情况

- 当前工作区尚未发布；上述内容为开发中状态，可能在正式版本前继续调整。
- 本文件由 `v0.2.0-alpha` 发布树与当前工作区的源码逐文件对比得出，未做运行时验证（未编译、未在 Iris 中重载、未做性能测量）；唯一例外是本节新增的 Khronos PBR Neutral 与 OpenDRT 两个色调映射模式，其重载、截图与设置覆盖验证记录在「一、新增功能」对应条目下。文中出现的数值均为代码中的常量、默认值或设置项，不构成实测结论（上述验证条目中的亮度比值为截图测量值）。
- 仍处于 Alpha 阶段，部分效果、设置和不同显卡驱动组合可能存在画面瑕疵或性能差异。
- 目标环境为 Minecraft Java 26.2、Fabric Loader 0.19.x、对应版本的 Iris/Sodium 和 Java 21。
- GI（`deferred3`）与接触阴影为新增的高开销特性，且 `GI_MODE` 默认关闭；性能不足时优先降低 RSM 采样数、接触阴影步数，或维持无 GI 模式。
- 第三节“性能与开销”记录的是**结构性成本**（步数、采样与纹理读取次数、pass 开关、默认预算），不是实测数据；本工作区没有跑过 profiling，因此没有毫秒或百分比结论。
- 若干处代码注释与实际取值不一致（例如卷云自遮蔽的注释仍写着旧的 0.4 km 步长与 8 步上限，实际为 0.2 km 与 3 步），这些注释尚未同步。

### English Summary

Compared with `v0.2.0-alpha`, Alpha v0.3.0 adds a full global illumination pass (`deferred3`/`recursive_gi.fragment`) with selectable SSGI (a CC0 port of the GT-VBGI visibility-bitmask tracer) or reflective shadow map GI, both sharing an optional temporal denoiser, a `colortex9` RGB16F irradiance history and a `colortex10` R32UI metadata history. Screen-space contact shadows now bound the shadow map in the Overworld and End. The tone-mapper list is replaced wholesale: AgX becomes DRT Bench's AgX-HSV variant and is the new default, joined by the ACES 2.0 output transform (Apache-2.0, ported in closed form with the reference's hue tables replaced by a bounded per-pixel reach solve), Blender's AgX view transform (GPL-2.0-or-later, evaluated closed-form in place of its baked cube), AMD's FidelityFX Luma Preserving Mapper (MIT, itself the ALU version), Jed Smith's OpenDRT (GPL-3.0) and GT7 (MIT, SIGGRAPH 2025); each is anchored on the shared 18% grey, and OKLAB, ACES 1.0, Reinhard-Gamut, Reinhard-AgX and Khronos PBR Neutral are removed. auto-exposure is rewritten around a weighted log-average plus a 64-bin EV histogram with median/P90 percentiles and a configurable target luminance, and ships enabled. A Purkinje scotopic night grade, boundary fog, an atmospheric horizon dip, a visible weather sheet, a night sky drawn from a 4K NASA star map (the v0.2.0 procedural star field is removed), an independent cirrus switch and roughness-convolved sky SH complete the new feature set. Volumetric clouds switch to a 1024² distribution texture with Perlin-Worley erosion and a saturated-geometric-series multiple-scattering model, cirrus is rebuilt with a silver-lining triple-lobe phase and self-shadowing, plant SSS becomes an energy-conserving redistribution of the diffuse budget with a single coverage-fade curve, PCSS loses its distance softening, and the GBuffer geometric normal moves to world space. Indirect specular gains a real roughness gate, SSR traces camera-facing rays and falls back to the sky instead of black, particles move into the opaque G-buffer and the deferred lighting pass, and the settings UI grows from 13 to 39 subscreens with both language files rewritten. The previous water-fog caustic controls, distance-based penumbra softening, checkerboard cloud upsampling and several never-wired settings are gone. A dedicated section documents the cost side of the release: epipolar shadow marches cut (water 64 to 24, air 64 to a new 12), lower volumetric-cloud step and light-step defaults, the single-light cloud trace, one STBN read shared by several consumers instead of one each, cloud and PSO early-outs placed before the expensive fetch, loop invariants hoisted out of sample and tap loops, whole passes compiled out when their feature is off, and ten derived per-frame Iris uniforms deleted. Those are structural cost changes read from the source; no profiling was run, so no timings or percentages are claimed. This changelog was derived from a file-by-file comparison of the two source trees; no runtime validation was performed.
