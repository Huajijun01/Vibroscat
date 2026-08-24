//_____________________________________________________________/\_______________________________________________________________
//==============================================================================================================================
//
//                                 [CAS] FIDELITY FX - CONTRAST ADAPTIVE SHARPENING 1.20190610
//
//==============================================================================================================================
// LICENSE
// =======
// Copyright (c) 2017-2019 Advanced Micro Devices, Inc. All rights reserved.
// -------
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
// -------
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
// Software.
// -------
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//------------------------------------------------------------------------------------------------------------------------------
//
// This is a stripped-down GLSL fragment shader adaptation of the official AMD FidelityFX CAS.
// Original: https://github.com/GPUOpen-Effects/FidelityFX-CAS
//
// Sharpen-only mode (no scaling). Designed for post-tonemap application in a fullscreen quad FS.
//
#ifndef VIBROSCAT_FIDELITYFX_CAS_GLSL
#define VIBROSCAT_FIDELITYFX_CAS_GLSL

// FidelityFX CAS — Contrast Adaptive Sharpening.
// Sharpen-only GLSL adaptation used after tonemapping. The luma helper uses
// the pack-wide Rec.709 Luminance from color/color.glsl (identical to the
// original CAS dot product).
#include "/lib/color/color.glsl"

vec3 CASSharpen(sampler2D source, vec2 uv, vec2 pixel_size, float sharpness) {
    vec3 center = texture(source, uv).rgb;
    vec3 north = texture(source, uv + vec2(0.0, -pixel_size.y)).rgb;
    vec3 south = texture(source, uv + vec2(0.0, pixel_size.y)).rgb;
    vec3 west = texture(source, uv + vec2(-pixel_size.x, 0.0)).rgb;
    vec3 east = texture(source, uv + vec2(pixel_size.x, 0.0)).rgb;

    float center_luma = Luminance(center);
    float north_luma = Luminance(north);
    float south_luma = Luminance(south);
    float west_luma = Luminance(west);
    float east_luma = Luminance(east);
    float min_luma = min(min(min(center_luma, north_luma), min(south_luma, west_luma)), east_luma);
    float max_luma = max(max(max(center_luma, north_luma), max(south_luma, west_luma)), east_luma);
    float amplitude = sqrt(clamp(min(min_luma, 1.0 - max_luma) / max(max_luma, 1.0e-6), 0.0, 1.0));
    float weight = amplitude * sharpness;
    vec3 sharpened = center * (1.0 + 4.0 * weight) - (north + south + west + east) * weight;
    vec3 minimum = min(min(min(north, south), min(west, east)), center);
    vec3 maximum = max(max(max(north, south), max(west, east)), center);
    return clamp(sharpened, minimum, maximum);
}

#endif // VIBROSCAT_FIDELITYFX_CAS_GLSL
