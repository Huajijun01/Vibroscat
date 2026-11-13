# Third-Party Notices

[English](THIRD_PARTY_NOTICES.en.md)

本文件只声明随包分发且附带许可证义务的第三方代码与资产。主许可证见根目录 `LICENSE`（GNU GPL v3）。

## 1. DRT Bench — AgX-HSV（GPL-3.0）

`shaders/lib/color/tonemap_agx.glsl` 移植自 [DRT Bench](https://github.com/bWFuanVzYWth/DRT) 的 `shaders/agx_hsv.wgsl`（GPL-3.0-only）。依据 GPL-3.0 第 5(a) 条声明：本包对其做了修改——输入为场景线性 Rec.709，输出为显示线性 Rec.709，sRGB OETF 由最终 pass 统一执行。

## 2. AMD FidelityFX CAS（MIT）

`shaders/lib/third_party/fidelityfx/cas.glsl` 是 [AMD FidelityFX CAS](https://github.com/GPUOpen-Effects/FidelityFX-CAS) 的精简 GLSL 改编（Copyright (c) 2017-2019 Advanced Micro Devices, Inc.），MIT 许可全文保留在该文件头部。

## 3. GT7 Tone Mapping（MIT）

`shaders/lib/color/tonemap_gt7.glsl` 移植自随 SIGGRAPH 2025 课程 *Driving Toward Reality: Physically Based Tone Mapping and Perceptual Fidelity in Gran Turismo 7* 发布的官方样例 `gt7_tone_mapping.cpp`。

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

## 4. OpenDRT（GPL-3.0）

`shaders/lib/color/tonemap_opendrt.glsl` 移植自 Jed Smith 的 [OpenDRT](https://github.com/jedypod/open-display-transform) v1.1.0 `display-transforms/opendrt/OpenDRT.dctl`（GPLv3），官方 Standard Look 参数固定为该文件内的不可变常量。依据 GPL-3.0 第 5(a) 条声明：本包对其做了修改——固定 SDR 100 尼特显示目标，输出显示线性 Rec.709，sRGB OETF 由最终 pass 统一执行。

## 5. UE SkyAtmosphere 透射率 LUT（MIT）

`shaders/lib/atmosphere/transmittance.glsl` 的透射率 LUT 采样方案与 UV 参数化（`GetTransmittanceLUTUV`）移植自 Sebastien Hillaire 的 UE SkyAtmosphere 实现（[github.com/sebh/UnrealEngineSkyAtmosphere](https://github.com/sebh/UnrealEngineSkyAtmosphere)，Copyright (c) 2020 Epic Games, Inc.）。

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

## 6. NASA Deep Star Maps 2020（公有领域）

`shaders/textures/starmap_2020_4k_logluv32.dat` 与 `shaders/textures/starmap_2020_256x128_logluv32.dat` 源自 NASA SVS #4851 "Deep Star Maps 2020"。

> Image credit: NASA's Scientific Visualization Studio / ESA-ESO-Sky-Survey
> 来源：<https://svs.gsfc.nasa.gov/4851/>
