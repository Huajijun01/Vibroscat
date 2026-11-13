// MIT License
//
// Copyright (c) 2016 MJP
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#ifndef LIB_THIRD_PARTY_ACES_GLSL
#define LIB_THIRD_PARTY_ACES_GLSL

#include "/lib/core/math_scalar.glsl"

// Stephen Hill's ACES fit, BakingLab/ACES.hlsl (MIT).
// Linear Rec.709 -> XYZ -> D65 to D60 -> AP1 -> RRT saturation.
const mat3 ACES_INPUT_MAT = mat3(
    vec3(0.59719, 0.07600, 0.02840),
    vec3(0.35458, 0.90834, 0.13383),
    vec3(0.04823, 0.01566, 0.83777));

// ODT saturation -> XYZ -> D60 to D65 -> linear Rec.709.
const mat3 ACES_OUTPUT_MAT = mat3(
    vec3(1.60475, -0.10208, -0.00327),
    vec3(-0.53108, 1.10813, -0.07276),
    vec3(-0.07367, -0.00605, 1.07602));

vec3 TonemapACESFitted(vec3 linear_rgb) {
    vec3 working = ACES_INPUT_MAT * linear_rgb;
    vec3 numerator = working * (working + 0.0245786) - 0.000090537;
    vec3 denominator = working * (0.983729 * working + 0.4329510) + 0.238081;
    return saturate(ACES_OUTPUT_MAT * (numerator / denominator));
}

#endif // LIB_THIRD_PARTY_ACES_GLSL
