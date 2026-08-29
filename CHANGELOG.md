# Vibroscat 更新说明

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
