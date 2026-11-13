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

#ifndef LIB_COLOR_TONEMAP_LOTTES_GLSL
#define LIB_COLOR_TONEMAP_LOTTES_GLSL

#include "/lib/core/math_scalar.glsl"

const float LOTTES_CONTRAST = 1.6;
const float LOTTES_SHOULDER = 0.977;
const float LOTTES_HDR_MAX = 8.0;
const float LOTTES_MID_IN = 0.18;
const float LOTTES_MID_OUT = 0.267;
const float LOTTES_B =
    (-pow(LOTTES_MID_IN, LOTTES_CONTRAST) + pow(LOTTES_HDR_MAX, LOTTES_CONTRAST) * LOTTES_MID_OUT)
    / ((pow(LOTTES_HDR_MAX, LOTTES_CONTRAST * LOTTES_SHOULDER)
        - pow(LOTTES_MID_IN, LOTTES_CONTRAST * LOTTES_SHOULDER)) * LOTTES_MID_OUT);
const float LOTTES_C =
    (pow(LOTTES_HDR_MAX, LOTTES_CONTRAST * LOTTES_SHOULDER) * pow(LOTTES_MID_IN, LOTTES_CONTRAST)
        - pow(LOTTES_HDR_MAX, LOTTES_CONTRAST) * pow(LOTTES_MID_IN, LOTTES_CONTRAST * LOTTES_SHOULDER)
        * LOTTES_MID_OUT)
    / ((pow(LOTTES_HDR_MAX, LOTTES_CONTRAST * LOTTES_SHOULDER)
        - pow(LOTTES_MID_IN, LOTTES_CONTRAST * LOTTES_SHOULDER)) * LOTTES_MID_OUT);

// Lottes 2016, "Advanced Techniques and Optimization of HDR Color Pipelines".
vec3 TonemapLottes(vec3 linear_rgb) {
    return saturate(pow(linear_rgb, vec3(LOTTES_CONTRAST))
        / (pow(linear_rgb, vec3(LOTTES_CONTRAST * LOTTES_SHOULDER)) * LOTTES_B + LOTTES_C));
}

#endif // LIB_COLOR_TONEMAP_LOTTES_GLSL
