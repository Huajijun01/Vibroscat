// Copyright (C) 2019 Damien Seguin
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#ifndef LIB_COLOR_TONEMAP_HABLE_GLSL
#define LIB_COLOR_TONEMAP_HABLE_GLSL

#include "/lib/core/math_scalar.glsl"

const float HABLE_EXPOSURE_BIAS = 2.0;
const float HABLE_WHITE_POINT = 11.2;

// Hable's Uncharted 2 curve; W shares the RGB evaluation for white normalization.
vec3 TonemapHable(vec3 linear_rgb) {
    vec4 working = vec4(linear_rgb * HABLE_EXPOSURE_BIAS, HABLE_WHITE_POINT);
    vec4 mapped = (working * (0.15 * working + 0.05) + 0.004)
        / (working * (0.15 * working + 0.50) + 0.06) - 0.02 / 0.30;
    return saturate(mapped.rgb / mapped.w);
}

#endif // LIB_COLOR_TONEMAP_HABLE_GLSL
