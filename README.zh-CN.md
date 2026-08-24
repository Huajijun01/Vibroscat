# Vibroscat

[English](README.md) | [简体中文](README.zh-CN.md)

Vibroscat 是一款面向 Iris 的高端 Minecraft 光影包。它呈现自然的日光、厚实的云层、清澈的水面、柔和的阴影，画面带一抹恰到好处的电影感，同时保留方块世界的本色。

## 开发状态

Vibroscat 还处于早期开发阶段。不少效果尚未完成，部分代码在质量和可维护性上仍有欠缺。你可能会遇到画面瑕疵、设置不全，以及版本之间的不兼容改动。

代码的大部分由 AI 生成。作者在审阅后做了大量修改，并设计了渲染管线的整体架构。

## 截图

![金合欢树草原，体积云、清澈水面与柔和的日光](screenshots/scene1-sky.jpg)

![水下雾、光柱与焦散](screenshots/scene3-water.jpg)

![分层体积云与大气天空](screenshots/scene4-clouds.jpg)

所有截图均在游戏内以 2560 像素宽、默认配置拍摄。

## 效果

- 分层体积云，密度变化自然、边缘柔和，带阳光与云影
- 完整的昼夜天空，包括日光、日落、月光、星空、地平线雾和距离雾
- 清澈的水面，带波浪、反射、折射、水下雾、光柱和流动的焦散
- 柔和的太阳阴影，加上接触细节、环境明暗和透过树叶的光
- 稳定的抗锯齿、自动曝光、泛光、景深、动态模糊、锐化与胶片色调

## 显卡支持

Vibroscat 面向驱动较新的现代台式机与笔记本显卡。

| 厂商 | 支持范围 | 入门配置 |
| --- | --- | --- |
| NVIDIA | GeForce GTX 900 系列及以上 | GTX 1060 6 GB，1080p 低画质 |
| AMD | Radeon RX 400 系列及以上 | RX 580 8 GB，1080p 低画质 |
| Intel | Arc A 系列及以上 | Arc A380，1080p 低画质 |

GeForce RTX、Radeon RX 5000/6000/7000 与 Intel Arc 是主要目标。Intel 核显（UHD、Iris Xe）和 Radeon 核显（Vega、700M）达不到目标性能。

## 系统要求

- Minecraft Java 版 26.2
- Fabric Loader 0.19.x
- 对应 Minecraft 26.2 的 Iris 与 Sodium
- Java 21
- Windows 或 Linux，显卡驱动保持最新
- 内存至少 8 GB，建议 16 GB
- 显存需求：低画质 4 GB，中/高画质 6 GB，超画质 4K 下 10 GB
- 起步配置建议：Java 堆内存 4 GB，渲染距离 12 至 16 个区块

## 画质配置

| 画质 | 建议硬件与分辨率 |
| --- | --- |
| 低（Low） | GTX 1060 6 GB、RX 580 8 GB 或 Arc A380，1080p |
| 中（Medium） | RTX 2060/3060、RX 6600/7600 或 Arc A580/A750，1080p 或 1440p |
| 高（High） | RTX 3070/4070、RX 6800/7800 XT 或 Arc A770，1440p |
| 超（Ultra） | RTX 4080/4090、RX 7900 XT/XTX 或更新的高端显卡，4K |

建议从 1080p 中画质开始。性能不够时，先降低云和阴影的质量。超画质以全分辨率渲染云层，专为高端显卡准备。

## 安装

下载发布压缩包，放进 `shaderpacks` 目录即可。可以不解压直接放入，也可以解压后放入，只要保证 `shaders` 文件夹直接位于 Vibroscat 目录内。进游戏后，在 Iris 的光影菜单里选中 Vibroscat，再到光影包设置里选择画质。

## 许可证

Vibroscat 以 GPL-3.0 协议开源。详见 [LICENSE](LICENSE) 与[第三方声明](licenses/THIRD_PARTY_NOTICES.md)。
