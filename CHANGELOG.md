# Vibroscat 更新说明

## Alpha v0.2.0 - 2026-08-29

这是 Vibroscat 面向 Minecraft 26.2 / Iris 的第二个 Alpha 版本。以下内容均以 `v0.1.0-alpha` 为基线，覆盖从 `v0.1.0-alpha` 到本版本的实际代码差异。

### 相较 v0.1.0-alpha 的更新

- 新增基于 Lab PBR 材质数据的金属度、粗糙度和反射响应。
- 新增不透明材质的递归（历史帧）SSR，并复用命中位置对应的可见历史像素，包括屏幕内天空命中。
- 不透明反射方向和 BRDF 改用材质法线；射线起点仍沿几何法线偏移，用于降低近距离 self-intersection 和错误屏幕像素复用风险。
- 增加不透明反射粗糙度控制：默认粗糙度阈值为 `0.5`，阈值下方的 `0.1` 粗糙度区间在 SSR 与 SH 环境反射之间平滑过渡；达到或超过阈值时跳过 SSR 射线追踪并使用 SH 反射。
- 移除不透明反射管线旧的 reflection filter、置信度、路径长度和反射 mip 数据及阶段依赖。
- 统一水面与不透明反射的 SSR 穿越和屏幕边界校验，同时保留两者各自的材质、历史采样与天空回退路径。
- SH 环境反射增加 RGB 逐通道的 SH L0 平均辐亮度下限，并加入偏向漫反射的颜色衰减处理，同时保留 Fresnel 项。
- 体积云加入 HPVolumeCloud 风格的 `phi_fwd` 各向同性多重散射、接收端底部置信度和边界背光置信度；该实现是本项目的近似移植，不宣称与 HP 的源点级实现完全一致。
- `phi_fwd` 改为从接收点向太阳方向正序积分，移除正指数传播链，使传播与吸收项保持非正指数。
- 体积云主视线步进改为均匀线性步进，去除旧版的平方参数化。
- `phi_fwd` 增加可调软压缩，默认压缩参数为 `0.5`。
- 修复退化边界交点，并补充反射合约测试与 `phi_fwd` 积分方向的静态回归检查。
- 新增中英文设置标签，整理资源格式与反射管线配置。

### 已知情况

- 仍处于 Alpha 阶段，部分效果、设置和不同显卡驱动组合可能存在画面瑕疵或性能差异。
- 目标环境为 Minecraft Java 26.2、Fabric Loader 0.19.x、对应版本的 Iris/Sodium 和 Java 21。
- 建议先使用 Medium 画质；性能不足时优先降低云层和阴影质量。

### English Summary

Compared with `v0.1.0-alpha`, Alpha v0.2.0 adds Lab PBR opaque materials, historical recursive SSR, material-normal reflection/BRDF evaluation, roughness-based SSR/SH blending, and explicit screen-boundary validation. It also adds an HPVolumeCloud-style `phi_fwd` approximation with receiver-side integration, bottom/boundary confidence, linear cloud marching, and configurable soft compression. The legacy opaque-reflection filter, confidence/path-length/mip plumbing, and positive-exponent propagation chain were removed.

本说明中的反射和云条目已按 `git diff v0.1.0-alpha..HEAD`、当前 shader/config 和静态测试核对；本版本没有把未经 GPU/游戏画面对比验证的视觉改善写成已测量结论。
