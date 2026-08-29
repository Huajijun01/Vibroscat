# Vibroscat 更新说明

## Alpha v0.2.0 - 2026-08-29

这是 Vibroscat 面向 Minecraft 26.2 / Iris 的第二个 Alpha 版本。以下内容均以 `v0.1.0-alpha` 为基线，覆盖从 `v0.1.0-alpha` 到本版本的实际代码差异。

### 相较 v0.1.0-alpha 的更新

- 新增基于 Lab PBR 材质数据的金属度、粗糙度和反射响应。
- 新增不透明材质的递归 SSR，并复用可见历史帧与天空像素。
- 不透明反射改用材质法线，修复靠近墙面时的 self-intersection 和反射手部/屏幕纹理问题。
- 增加不透明反射粗糙度控制：默认粗糙度阈值为 `0.5`，阈值以下在 SSR 与 SH 环境反射之间平滑过渡，过渡跨度默认为 `0.1`；高于阈值时跳过 SSR 并使用 SH 反射。
- 移除旧的 reflection filter、置信度、路径长度和反射 mip 依赖，简化反射资源与着色阶段。
- 修复屏幕外命中点的 UV 判断，避免错误复用屏幕像素；水面和不透明反射分别保留各自的 SSR 处理。
- SH 环境反射增加 RGB 逐通道的平均辐亮度下限，减少反射泛白，同时保留 Fresnel 质感。
- 体积云加入 HPVolumeCloud 风格的 `phi_fwd` 各向同性多重散射、底部置信度和边界背光置信度。
- `phi_fwd` 改为从接收点向太阳方向正序积分，移除会放大近场源的正指数传播链，降低低步数下的过亮和数值溢出风险。
- 体积云主视线步进恢复为均匀线性步进，避免旧版的平方步进在低步数下造成采样分布失衡。
- `phi_fwd` 增加可调软压缩，默认压缩参数为 `0.5`。
- 修复退化边界交点，并补充反射/`phi_fwd` 合约回归测试。
- 新增 `pack.mcmeta` 和中英文设置标签，整理资源格式与反射管线配置。

### 已知情况

- 仍处于 Alpha 阶段，部分效果、设置和不同显卡驱动组合可能存在画面瑕疵或性能差异。
- 目标环境为 Minecraft Java 26.2、Fabric Loader 0.19.x、对应版本的 Iris/Sodium 和 Java 21。
- 建议先使用 Medium 画质；性能不足时优先降低云层和阴影质量。

### English Summary

Compared with `v0.1.0-alpha`, Alpha v0.2.0 adds Lab PBR opaque materials, recursive SSR, material-normal reflection stability, roughness-based SSR/SH blending, and correct screen-boundary handling. It also ports HPVolumeCloud-style `phi_fwd` multiple scattering with receiver-side integration, bottom/boundary confidence, linear cloud marching, and configurable soft compression. The legacy reflection filter, confidence/path-length/mip plumbing, and unstable positive-exponent propagation chain were removed.
