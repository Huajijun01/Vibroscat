# Third-Party Notices

[中文版](THIRD_PARTY_NOTICES.md)

This file declares only the third-party code and assets distributed with this pack that carry license obligations. The main license is the GNU GPL v3 in the root `LICENSE` file.

## 1. DRT Bench — AgX-HSV (GPL-3.0)

`shaders/lib/color/tonemap_agx.glsl` is ported from [DRT Bench](https://github.com/bWFuanVzYWth/DRT), file `shaders/agx_hsv.wgsl` (GPL-3.0-only); this pack modified it.

## 2. AMD FidelityFX CAS (MIT)

`shaders/lib/third_party/fidelityfx/cas.glsl` is a stripped-down GLSL adaptation of [AMD FidelityFX CAS](https://github.com/GPUOpen-Effects/FidelityFX-CAS) (Copyright (c) 2017-2019 Advanced Micro Devices, Inc.); the full MIT license text is preserved in that file's header.

## 3. GT7 Tone Mapping (MIT)

`shaders/lib/color/tonemap_gt7.glsl` is ported from the official sample `gt7_tone_mapping.cpp` released with the SIGGRAPH 2025 course *Driving Toward Reality: Physically Based Tone Mapping and Perceptual Fidelity in Gran Turismo 7*.

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

Source: <https://blog.selfshadow.com/publications/s2025-shading-course/pdi/supplemental/gt7_tone_mapping.cpp>

## 4. OpenDRT (GPL-3.0)

`shaders/lib/color/tonemap_opendrt.glsl` is ported from Jed Smith's [OpenDRT](https://github.com/jedypod/open-display-transform) v1.1.0 `display-transforms/opendrt/OpenDRT.dctl` (GPL-3.0); this pack modified it.

## 5. UE SkyAtmosphere transmittance LUT (MIT)

The transmittance LUT sampling scheme and UV parameterization (`GetTransmittanceLUTUV`) in `shaders/lib/atmosphere/transmittance.glsl` are ported from Sebastien Hillaire's UE SkyAtmosphere implementation ([github.com/sebh/UnrealEngineSkyAtmosphere](https://github.com/sebh/UnrealEngineSkyAtmosphere), Copyright (c) 2020 Epic Games, Inc.).

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

## 6. NASA Deep Star Maps 2020 (public domain)

`shaders/textures/starmap_2020_4k_logluv32.dat` and `shaders/textures/starmap_2020_256x128_logluv32.dat` derive from NASA SVS #4851 "Deep Star Maps 2020".

> Image credit: NASA's Scientific Visualization Studio / ESA-ESO-Sky-Survey
> Source: <https://svs.gsfc.nasa.gov/4851/>

## 7. ACES Fitted (MIT)

`shaders/lib/color/tonemap_aces_fitted.glsl` is adapted from Stephen Hill's ACES fit in
[BakingLab/ACES.hlsl](https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl).
Copyright (c) 2016 MJP. The full MIT license is retained in that file.

## 8. GT-VBGI screen-space GI (CC0 1.0)

The screen-space visibility-bitmask GI in `shaders/program/deferred/recursive_gi.fragment` is ported from Mirko Salm's GT-VBGI reference implementation (Shadertoy: <https://www.shadertoy.com/view/XcdBWf>). That source is dual-licensed under CC0 1.0 Universal and the MIT License; this pack uses it under CC0 1.0 Universal: <https://creativecommons.org/publicdomain/zero/1.0/>
