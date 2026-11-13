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

#ifndef LIB_COLOR_TONEMAP_HEJL2015_GLSL
#define LIB_COLOR_TONEMAP_HEJL2015_GLSL

#include "/lib/core/math_scalar.glsl"

const float HEJL2015_WHITE_POINT = 11.2;

// Jim Hejl 2015: display-linear output, with scene white normalized to one.
vec3 TonemapHejl2015(vec3 linear_rgb) {
    vec4 working = vec4(linear_rgb, HEJL2015_WHITE_POINT);
    vec4 curve = 1.425 * working + 0.05;
    vec4 mapped = (working * curve + 0.004) / (working * (curve + 0.55) + 0.0491) - 0.0821;
    return saturate(mapped.rgb / mapped.w);
}

#endif // LIB_COLOR_TONEMAP_HEJL2015_GLSL
