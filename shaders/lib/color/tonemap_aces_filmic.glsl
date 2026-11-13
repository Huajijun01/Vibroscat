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

#ifndef LIB_COLOR_TONEMAP_ACES_FILMIC_GLSL
#define LIB_COLOR_TONEMAP_ACES_FILMIC_GLSL

#include "/lib/core/math_scalar.glsl"

// Narkowicz 2015, "ACES Filmic Tone Mapping Curve".
vec3 TonemapACESFilmic(vec3 linear_rgb) {
    return saturate((linear_rgb * (2.51 * linear_rgb + 0.03))
        / (linear_rgb * (2.43 * linear_rgb + 0.59) + 0.14));
}

#endif // LIB_COLOR_TONEMAP_ACES_FILMIC_GLSL
