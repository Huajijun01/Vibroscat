#ifndef LIB_COLOR_TONEMAP_OPENDRT_PRESETS_GLSL
#define LIB_COLOR_TONEMAP_OPENDRT_PRESETS_GLSL

#include "/lib/contract/settings.glsl"

// OpenDRT v1.1.0 preset values, by Jed Smith (GPLv3).
// Source: display-transforms/opendrt/OpenDRT.dctl, LOOK PRESETS and
// TONESCALE PRESETS; licenses/THIRD_PARTY_NOTICES.md section 5. No numeric
// player controls.
// DCTL names map to descriptive ODT_* constants in the renderer.

#if TONEMAP_ODT_LOOK == 0 // Standard
const float ODT_LOOK_CONTRAST = 1.66;
const float ODT_LOOK_SHOULDER_CLIP = 0.5;
const float ODT_LOOK_TOE = 0.003;
const float ODT_LOOK_OFFSET = 0.005;
const int ODT_LOOK_HIGH_CONTRAST_ENABLE = 0;
const float ODT_LOOK_HIGH_CONTRAST = 0.0;
const float ODT_LOOK_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_LOOK_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOOK_LOW_CONTRAST_ENABLE = 0;
const float ODT_LOOK_LOW_CONTRAST = 0.0;
const float ODT_LOOK_LOW_CONTRAST_WIDTH = 0.5;
const float ODT_CREATIVE_WHITE_RANGE = 0.25;
const float ODT_RENDER_SATURATION = 0.35;
const float ODT_RENDER_WEIGHT_R = 0.25;
const float ODT_RENDER_WEIGHT_B = 0.55;
const float ODT_PURITY_LOW = 0.25;
const float ODT_PURITY_LOW_R = 0.5;
const float ODT_PURITY_LOW_G = 0.0;
const float ODT_PURITY_LOW_B = 0.1;
const float ODT_PURITY_HIGH = 0.25;
const float ODT_PURITY_HIGH_R = 0.5;
const float ODT_PURITY_HIGH_B = 0.0;
const float ODT_PURITY_SOFTCLIP_C = 0.06;
const float ODT_PURITY_SOFTCLIP_M = 0.08;
const float ODT_PURITY_SOFTCLIP_Y = 0.06;
const float ODT_MID_PURITY_LOW = 0.4;
const float ODT_MID_PURITY_LOW_RANGE = 0.25;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.5;
const float ODT_MID_PURITY_HIGH = -0.8;
const float ODT_MID_PURITY_HIGH_RANGE = 0.35;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.4;
const float ODT_BRILLIANCE = 0.0;
const float ODT_BRILLIANCE_R = -2.5;
const float ODT_BRILLIANCE_G = -1.5;
const float ODT_BRILLIANCE_B = -1.5;
const float ODT_BRILLIANCE_RANGE = 0.5;
const float ODT_BRILLIANCE_STRENGTH = 0.35;
const float ODT_POST_BRILLIANCE = -0.5;
const float ODT_POST_BRILLIANCE_R = -1.25;
const float ODT_POST_BRILLIANCE_G = -1.25;
const float ODT_POST_BRILLIANCE_B = -0.25;
const float ODT_HUE_CONTRAST_R = 1.0;
const float ODT_HUE_CONTRAST_RANGE = 0.3;
const float ODT_HUE_SHIFT_R = 0.6;
const float ODT_HUE_SHIFT_R_RANGE = 0.6;
const float ODT_HUE_SHIFT_G = 0.35;
const float ODT_HUE_SHIFT_G_RANGE = 1.0;
const float ODT_HUE_SHIFT_B = 0.66;
const float ODT_HUE_SHIFT_B_RANGE = 1.0;
const float ODT_HUE_SHIFT_C = 0.25;
const float ODT_HUE_SHIFT_C_RANGE = 1.0;
const float ODT_HUE_SHIFT_M = 0.0;
const float ODT_HUE_SHIFT_M_RANGE = 1.0;
const float ODT_HUE_SHIFT_Y = 0.0;
const float ODT_HUE_SHIFT_Y_RANGE = 1.0;
const mat3 ODT_CREATIVE_WHITE_MATRIX = mat3(
    vec3(1.224940176280561, -0.042056954709688, -0.019637554590334),
    vec3(-0.224940176280560, 1.042056954709688, -0.078636045550632),
    vec3(0.000000000000000, -0.000000000000000, 1.098273600140966));
const float ODT_CREATIVE_WHITE_NORMALIZATION = 1.000000000000;

#elif TONEMAP_ODT_LOOK == 1 // Arriba
const float ODT_LOOK_CONTRAST = 1.05;
const float ODT_LOOK_SHOULDER_CLIP = 0.5;
const float ODT_LOOK_TOE = 0.1;
const float ODT_LOOK_OFFSET = 0.01;
const int ODT_LOOK_HIGH_CONTRAST_ENABLE = 0;
const float ODT_LOOK_HIGH_CONTRAST = 0.0;
const float ODT_LOOK_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_LOOK_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOOK_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOOK_LOW_CONTRAST = 1.5;
const float ODT_LOOK_LOW_CONTRAST_WIDTH = 0.2;
const float ODT_CREATIVE_WHITE_RANGE = 0.25;
const float ODT_RENDER_SATURATION = 0.35;
const float ODT_RENDER_WEIGHT_R = 0.25;
const float ODT_RENDER_WEIGHT_B = 0.55;
const float ODT_PURITY_LOW = 0.25;
const float ODT_PURITY_LOW_R = 0.45;
const float ODT_PURITY_LOW_G = 0.0;
const float ODT_PURITY_LOW_B = 0.1;
const float ODT_PURITY_HIGH = 0.25;
const float ODT_PURITY_HIGH_R = 0.25;
const float ODT_PURITY_HIGH_B = 0.0;
const float ODT_PURITY_SOFTCLIP_C = 0.06;
const float ODT_PURITY_SOFTCLIP_M = 0.08;
const float ODT_PURITY_SOFTCLIP_Y = 0.06;
const float ODT_MID_PURITY_LOW = 1.0;
const float ODT_MID_PURITY_LOW_RANGE = 0.4;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.5;
const float ODT_MID_PURITY_HIGH = -0.8;
const float ODT_MID_PURITY_HIGH_RANGE = 0.66;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.6;
const float ODT_BRILLIANCE = 0.0;
const float ODT_BRILLIANCE_R = -2.5;
const float ODT_BRILLIANCE_G = -1.5;
const float ODT_BRILLIANCE_B = -1.5;
const float ODT_BRILLIANCE_RANGE = 0.5;
const float ODT_BRILLIANCE_STRENGTH = 0.35;
const float ODT_POST_BRILLIANCE = 0.0;
const float ODT_POST_BRILLIANCE_R = -1.7;
const float ODT_POST_BRILLIANCE_G = -2.0;
const float ODT_POST_BRILLIANCE_B = -0.5;
const float ODT_HUE_CONTRAST_R = 1.0;
const float ODT_HUE_CONTRAST_RANGE = 0.3;
const float ODT_HUE_SHIFT_R = 0.6;
const float ODT_HUE_SHIFT_R_RANGE = 0.8;
const float ODT_HUE_SHIFT_G = 0.35;
const float ODT_HUE_SHIFT_G_RANGE = 1.0;
const float ODT_HUE_SHIFT_B = 0.66;
const float ODT_HUE_SHIFT_B_RANGE = 1.0;
const float ODT_HUE_SHIFT_C = 0.15;
const float ODT_HUE_SHIFT_C_RANGE = 1.0;
const float ODT_HUE_SHIFT_M = 0.0;
const float ODT_HUE_SHIFT_M_RANGE = 1.0;
const float ODT_HUE_SHIFT_Y = 0.0;
const float ODT_HUE_SHIFT_Y_RANGE = 1.0;
const mat3 ODT_CREATIVE_WHITE_MATRIX = mat3(
    vec3(1.224940176280561, -0.042056954709688, -0.019637554590334),
    vec3(-0.224940176280560, 1.042056954709688, -0.078636045550632),
    vec3(0.000000000000000, -0.000000000000000, 1.098273600140966));
const float ODT_CREATIVE_WHITE_NORMALIZATION = 1.000000000000;

#elif TONEMAP_ODT_LOOK == 2 // Sylvan
const float ODT_LOOK_CONTRAST = 1.6;
const float ODT_LOOK_SHOULDER_CLIP = 0.5;
const float ODT_LOOK_TOE = 0.01;
const float ODT_LOOK_OFFSET = 0.01;
const int ODT_LOOK_HIGH_CONTRAST_ENABLE = 0;
const float ODT_LOOK_HIGH_CONTRAST = 0.0;
const float ODT_LOOK_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_LOOK_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOOK_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOOK_LOW_CONTRAST = 0.25;
const float ODT_LOOK_LOW_CONTRAST_WIDTH = 0.75;
const float ODT_CREATIVE_WHITE_RANGE = 0.25;
const float ODT_RENDER_SATURATION = 0.25;
const float ODT_RENDER_WEIGHT_R = 0.25;
const float ODT_RENDER_WEIGHT_B = 0.55;
const float ODT_PURITY_LOW = 0.15;
const float ODT_PURITY_LOW_R = 0.5;
const float ODT_PURITY_LOW_G = 0.15;
const float ODT_PURITY_LOW_B = 0.1;
const float ODT_PURITY_HIGH = 0.25;
const float ODT_PURITY_HIGH_R = 0.15;
const float ODT_PURITY_HIGH_B = 0.15;
const float ODT_PURITY_SOFTCLIP_C = 0.05;
const float ODT_PURITY_SOFTCLIP_M = 0.08;
const float ODT_PURITY_SOFTCLIP_Y = 0.05;
const float ODT_MID_PURITY_LOW = 0.5;
const float ODT_MID_PURITY_LOW_RANGE = 0.5;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.5;
const float ODT_MID_PURITY_HIGH = -0.8;
const float ODT_MID_PURITY_HIGH_RANGE = 0.5;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.5;
const float ODT_BRILLIANCE = -1.0;
const float ODT_BRILLIANCE_R = -2.0;
const float ODT_BRILLIANCE_G = -2.0;
const float ODT_BRILLIANCE_B = 0.0;
const float ODT_BRILLIANCE_RANGE = 0.25;
const float ODT_BRILLIANCE_STRENGTH = 0.25;
const float ODT_POST_BRILLIANCE = -1.0;
const float ODT_POST_BRILLIANCE_R = -0.5;
const float ODT_POST_BRILLIANCE_G = -0.25;
const float ODT_POST_BRILLIANCE_B = -0.25;
const float ODT_HUE_CONTRAST_R = 1.0;
const float ODT_HUE_CONTRAST_RANGE = 0.4;
const float ODT_HUE_SHIFT_R = 0.6;
const float ODT_HUE_SHIFT_R_RANGE = 1.15;
const float ODT_HUE_SHIFT_G = 0.8;
const float ODT_HUE_SHIFT_G_RANGE = 1.25;
const float ODT_HUE_SHIFT_B = 0.6;
const float ODT_HUE_SHIFT_B_RANGE = 1.0;
const float ODT_HUE_SHIFT_C = 0.25;
const float ODT_HUE_SHIFT_C_RANGE = 0.25;
const float ODT_HUE_SHIFT_M = 0.25;
const float ODT_HUE_SHIFT_M_RANGE = 0.5;
const float ODT_HUE_SHIFT_Y = 0.35;
const float ODT_HUE_SHIFT_Y_RANGE = 0.5;
const mat3 ODT_CREATIVE_WHITE_MATRIX = mat3(
    vec3(1.224940176280561, -0.042056954709688, -0.019637554590334),
    vec3(-0.224940176280560, 1.042056954709688, -0.078636045550632),
    vec3(0.000000000000000, -0.000000000000000, 1.098273600140966));
const float ODT_CREATIVE_WHITE_NORMALIZATION = 1.000000000000;

#elif TONEMAP_ODT_LOOK == 3 // Colorful
const float ODT_LOOK_CONTRAST = 1.5;
const float ODT_LOOK_SHOULDER_CLIP = 0.5;
const float ODT_LOOK_TOE = 0.003;
const float ODT_LOOK_OFFSET = 0.003;
const int ODT_LOOK_HIGH_CONTRAST_ENABLE = 0;
const float ODT_LOOK_HIGH_CONTRAST = 0.0;
const float ODT_LOOK_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_LOOK_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOOK_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOOK_LOW_CONTRAST = 0.4;
const float ODT_LOOK_LOW_CONTRAST_WIDTH = 0.5;
const float ODT_CREATIVE_WHITE_RANGE = 0.25;
const float ODT_RENDER_SATURATION = 0.35;
const float ODT_RENDER_WEIGHT_R = 0.25;
const float ODT_RENDER_WEIGHT_B = 0.55;
const float ODT_PURITY_LOW = 0.5;
const float ODT_PURITY_LOW_R = 1.0;
const float ODT_PURITY_LOW_G = 0.0;
const float ODT_PURITY_LOW_B = 0.5;
const float ODT_PURITY_HIGH = 0.15;
const float ODT_PURITY_HIGH_R = 0.15;
const float ODT_PURITY_HIGH_B = 0.15;
const float ODT_PURITY_SOFTCLIP_C = 0.05;
const float ODT_PURITY_SOFTCLIP_M = 0.06;
const float ODT_PURITY_SOFTCLIP_Y = 0.05;
const float ODT_MID_PURITY_LOW = 0.8;
const float ODT_MID_PURITY_LOW_RANGE = 0.5;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.4;
const float ODT_MID_PURITY_HIGH = -0.8;
const float ODT_MID_PURITY_HIGH_RANGE = 0.4;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.4;
const float ODT_BRILLIANCE = 0.0;
const float ODT_BRILLIANCE_R = -1.25;
const float ODT_BRILLIANCE_G = -1.25;
const float ODT_BRILLIANCE_B = -0.25;
const float ODT_BRILLIANCE_RANGE = 0.3;
const float ODT_BRILLIANCE_STRENGTH = 0.5;
const float ODT_POST_BRILLIANCE = -0.5;
const float ODT_POST_BRILLIANCE_R = -1.25;
const float ODT_POST_BRILLIANCE_G = -1.25;
const float ODT_POST_BRILLIANCE_B = -0.5;
const float ODT_HUE_CONTRAST_R = 1.0;
const float ODT_HUE_CONTRAST_RANGE = 0.4;
const float ODT_HUE_SHIFT_R = 0.5;
const float ODT_HUE_SHIFT_R_RANGE = 0.8;
const float ODT_HUE_SHIFT_G = 0.35;
const float ODT_HUE_SHIFT_G_RANGE = 1.0;
const float ODT_HUE_SHIFT_B = 0.5;
const float ODT_HUE_SHIFT_B_RANGE = 1.0;
const float ODT_HUE_SHIFT_C = 0.25;
const float ODT_HUE_SHIFT_C_RANGE = 1.0;
const float ODT_HUE_SHIFT_M = 0.0;
const float ODT_HUE_SHIFT_M_RANGE = 1.0;
const float ODT_HUE_SHIFT_Y = 0.25;
const float ODT_HUE_SHIFT_Y_RANGE = 1.0;
const mat3 ODT_CREATIVE_WHITE_MATRIX = mat3(
    vec3(1.224940176280561, -0.042056954709688, -0.019637554590334),
    vec3(-0.224940176280560, 1.042056954709688, -0.078636045550632),
    vec3(0.000000000000000, -0.000000000000000, 1.098273600140966));
const float ODT_CREATIVE_WHITE_NORMALIZATION = 1.000000000000;

#elif TONEMAP_ODT_LOOK == 4 // Aery
const float ODT_LOOK_CONTRAST = 1.15;
const float ODT_LOOK_SHOULDER_CLIP = 0.5;
const float ODT_LOOK_TOE = 0.04;
const float ODT_LOOK_OFFSET = 0.006;
const int ODT_LOOK_HIGH_CONTRAST_ENABLE = 0;
const float ODT_LOOK_HIGH_CONTRAST = 0.0;
const float ODT_LOOK_HIGH_CONTRAST_PIVOT = 0.0;
const float ODT_LOOK_HIGH_CONTRAST_EXTENSION = 0.5;
const int ODT_LOOK_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOOK_LOW_CONTRAST = 0.5;
const float ODT_LOOK_LOW_CONTRAST_WIDTH = 2.0;
const float ODT_CREATIVE_WHITE_RANGE = 0.25;
const float ODT_RENDER_SATURATION = 0.25;
const float ODT_RENDER_WEIGHT_R = 0.2;
const float ODT_RENDER_WEIGHT_B = 0.5;
const float ODT_PURITY_LOW = 0.0;
const float ODT_PURITY_LOW_R = 0.5;
const float ODT_PURITY_LOW_G = 0.15;
const float ODT_PURITY_LOW_B = 0.1;
const float ODT_PURITY_HIGH = 0.0;
const float ODT_PURITY_HIGH_R = 0.1;
const float ODT_PURITY_HIGH_B = 0.0;
const float ODT_PURITY_SOFTCLIP_C = 0.05;
const float ODT_PURITY_SOFTCLIP_M = 0.08;
const float ODT_PURITY_SOFTCLIP_Y = 0.05;
const float ODT_MID_PURITY_LOW = 0.8;
const float ODT_MID_PURITY_LOW_RANGE = 0.35;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.5;
const float ODT_MID_PURITY_HIGH = -0.9;
const float ODT_MID_PURITY_HIGH_RANGE = 0.5;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.3;
const float ODT_BRILLIANCE = -3.0;
const float ODT_BRILLIANCE_R = 0.0;
const float ODT_BRILLIANCE_G = 0.0;
const float ODT_BRILLIANCE_B = 1.0;
const float ODT_BRILLIANCE_RANGE = 0.8;
const float ODT_BRILLIANCE_STRENGTH = 0.15;
const float ODT_POST_BRILLIANCE = -1.0;
const float ODT_POST_BRILLIANCE_R = -1.0;
const float ODT_POST_BRILLIANCE_G = -1.0;
const float ODT_POST_BRILLIANCE_B = 0.0;
const float ODT_HUE_CONTRAST_R = 0.5;
const float ODT_HUE_CONTRAST_RANGE = 0.25;
const float ODT_HUE_SHIFT_R = 0.6;
const float ODT_HUE_SHIFT_R_RANGE = 1.0;
const float ODT_HUE_SHIFT_G = 0.35;
const float ODT_HUE_SHIFT_G_RANGE = 2.0;
const float ODT_HUE_SHIFT_B = 0.5;
const float ODT_HUE_SHIFT_B_RANGE = 1.5;
const float ODT_HUE_SHIFT_C = 0.35;
const float ODT_HUE_SHIFT_C_RANGE = 1.0;
const float ODT_HUE_SHIFT_M = 0.25;
const float ODT_HUE_SHIFT_M_RANGE = 1.0;
const float ODT_HUE_SHIFT_Y = 0.35;
const float ODT_HUE_SHIFT_Y_RANGE = 0.5;
const mat3 ODT_CREATIVE_WHITE_MATRIX = mat3(
    vec3(1.193525461445034, -0.039680596307084, -0.018580469435611),
    vec3(-0.260609410892478, 1.046053118246477, -0.071075289729093),
    vec3(-0.003840536714275, 0.000092750556204, 1.234513679083656));
const float ODT_CREATIVE_WHITE_NORMALIZATION = 0.873470832146;

#elif TONEMAP_ODT_LOOK == 5 // Dystopic
const float ODT_LOOK_CONTRAST = 1.6;
const float ODT_LOOK_SHOULDER_CLIP = 0.5;
const float ODT_LOOK_TOE = 0.01;
const float ODT_LOOK_OFFSET = 0.008;
const int ODT_LOOK_HIGH_CONTRAST_ENABLE = 1;
const float ODT_LOOK_HIGH_CONTRAST = 0.25;
const float ODT_LOOK_HIGH_CONTRAST_PIVOT = 0.0;
const float ODT_LOOK_HIGH_CONTRAST_EXTENSION = 1.0;
const int ODT_LOOK_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOOK_LOW_CONTRAST = 1.0;
const float ODT_LOOK_LOW_CONTRAST_WIDTH = 0.75;
const float ODT_CREATIVE_WHITE_RANGE = 0.25;
const float ODT_RENDER_SATURATION = 0.2;
const float ODT_RENDER_WEIGHT_R = 0.25;
const float ODT_RENDER_WEIGHT_B = 0.55;
const float ODT_PURITY_LOW = 0.15;
const float ODT_PURITY_LOW_R = 0.0;
const float ODT_PURITY_LOW_G = 0.0;
const float ODT_PURITY_LOW_B = 0.0;
const float ODT_PURITY_HIGH = 0.0;
const float ODT_PURITY_HIGH_R = 0.0;
const float ODT_PURITY_HIGH_B = 0.0;
const float ODT_PURITY_SOFTCLIP_C = 0.05;
const float ODT_PURITY_SOFTCLIP_M = 0.08;
const float ODT_PURITY_SOFTCLIP_Y = 0.05;
const float ODT_MID_PURITY_LOW = 0.25;
const float ODT_MID_PURITY_LOW_RANGE = 0.25;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.8;
const float ODT_MID_PURITY_HIGH = -0.8;
const float ODT_MID_PURITY_HIGH_RANGE = 0.6;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.25;
const float ODT_BRILLIANCE = -2.0;
const float ODT_BRILLIANCE_R = -2.0;
const float ODT_BRILLIANCE_G = -2.0;
const float ODT_BRILLIANCE_B = 0.0;
const float ODT_BRILLIANCE_RANGE = 0.35;
const float ODT_BRILLIANCE_STRENGTH = 0.35;
const float ODT_POST_BRILLIANCE = 0.0;
const float ODT_POST_BRILLIANCE_R = -1.0;
const float ODT_POST_BRILLIANCE_G = -1.0;
const float ODT_POST_BRILLIANCE_B = -1.0;
const float ODT_HUE_CONTRAST_R = 1.0;
const float ODT_HUE_CONTRAST_RANGE = 0.25;
const float ODT_HUE_SHIFT_R = 0.7;
const float ODT_HUE_SHIFT_R_RANGE = 1.33;
const float ODT_HUE_SHIFT_G = 1.0;
const float ODT_HUE_SHIFT_G_RANGE = 2.0;
const float ODT_HUE_SHIFT_B = 0.75;
const float ODT_HUE_SHIFT_B_RANGE = 2.0;
const float ODT_HUE_SHIFT_C = 1.0;
const float ODT_HUE_SHIFT_C_RANGE = 0.5;
const float ODT_HUE_SHIFT_M = 1.0;
const float ODT_HUE_SHIFT_M_RANGE = 1.0;
const float ODT_HUE_SHIFT_Y = 1.0;
const float ODT_HUE_SHIFT_Y_RANGE = 0.765;
const mat3 ODT_CREATIVE_WHITE_MATRIX = mat3(
    vec3(1.244833299160800, -0.043603783258765, -0.020273173850288),
    vec3(-0.201025494739933, 1.038532749845534, -0.082986382645415),
    vec3(0.002286245917648, -0.000058224102491, 1.018305466758978));
const float ODT_CREATIVE_WHITE_NORMALIZATION = 0.955936992163;

#elif TONEMAP_ODT_LOOK == 6 // Umbra
const float ODT_LOOK_CONTRAST = 1.8;
const float ODT_LOOK_SHOULDER_CLIP = 0.5;
const float ODT_LOOK_TOE = 0.001;
const float ODT_LOOK_OFFSET = 0.015;
const int ODT_LOOK_HIGH_CONTRAST_ENABLE = 0;
const float ODT_LOOK_HIGH_CONTRAST = 0.0;
const float ODT_LOOK_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_LOOK_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOOK_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOOK_LOW_CONTRAST = 1.0;
const float ODT_LOOK_LOW_CONTRAST_WIDTH = 1.0;
const float ODT_CREATIVE_WHITE_RANGE = 0.25;
const float ODT_RENDER_SATURATION = 0.35;
const float ODT_RENDER_WEIGHT_R = 0.25;
const float ODT_RENDER_WEIGHT_B = 0.55;
const float ODT_PURITY_LOW = 0.0;
const float ODT_PURITY_LOW_R = 0.5;
const float ODT_PURITY_LOW_G = 0.0;
const float ODT_PURITY_LOW_B = 0.15;
const float ODT_PURITY_HIGH = 0.25;
const float ODT_PURITY_HIGH_R = 0.25;
const float ODT_PURITY_HIGH_B = 0.0;
const float ODT_PURITY_SOFTCLIP_C = 0.05;
const float ODT_PURITY_SOFTCLIP_M = 0.06;
const float ODT_PURITY_SOFTCLIP_Y = 0.05;
const float ODT_MID_PURITY_LOW = 0.4;
const float ODT_MID_PURITY_LOW_RANGE = 0.35;
const float ODT_MID_PURITY_LOW_STRENGTH = 0.66;
const float ODT_MID_PURITY_HIGH = -0.6;
const float ODT_MID_PURITY_HIGH_RANGE = 0.45;
const float ODT_MID_PURITY_HIGH_STRENGTH = 0.45;
const float ODT_BRILLIANCE = -2.0;
const float ODT_BRILLIANCE_R = -4.5;
const float ODT_BRILLIANCE_G = -3.0;
const float ODT_BRILLIANCE_B = -4.0;
const float ODT_BRILLIANCE_RANGE = 0.35;
const float ODT_BRILLIANCE_STRENGTH = 0.3;
const float ODT_POST_BRILLIANCE = 0.0;
const float ODT_POST_BRILLIANCE_R = -2.0;
const float ODT_POST_BRILLIANCE_G = -1.0;
const float ODT_POST_BRILLIANCE_B = -0.5;
const float ODT_HUE_CONTRAST_R = 1.0;
const float ODT_HUE_CONTRAST_RANGE = 0.35;
const float ODT_HUE_SHIFT_R = 0.66;
const float ODT_HUE_SHIFT_R_RANGE = 1.0;
const float ODT_HUE_SHIFT_G = 0.5;
const float ODT_HUE_SHIFT_G_RANGE = 2.0;
const float ODT_HUE_SHIFT_B = 0.85;
const float ODT_HUE_SHIFT_B_RANGE = 2.0;
const float ODT_HUE_SHIFT_C = 0.0;
const float ODT_HUE_SHIFT_C_RANGE = 1.0;
const float ODT_HUE_SHIFT_M = 0.25;
const float ODT_HUE_SHIFT_M_RANGE = 1.0;
const float ODT_HUE_SHIFT_Y = 0.66;
const float ODT_HUE_SHIFT_Y_RANGE = 0.66;
const mat3 ODT_CREATIVE_WHITE_MATRIX = mat3(
    vec3(1.298419908134572, -0.047991363984483, -0.021808006962516),
    vec3(-0.129634873000589, 1.023821187536695, -0.092408124137560),
    vec3(0.007679483890571, -0.000212461476086, 0.835995071482233));
const float ODT_CREATIVE_WHITE_NORMALIZATION = 0.850004385027;
#endif

#if TONEMAP_ODT_TONESCALE == 0 // Use the selected look
const float ODT_CONTRAST = ODT_LOOK_CONTRAST;
const float ODT_SHOULDER_CLIP = ODT_LOOK_SHOULDER_CLIP;
const float ODT_TOE = ODT_LOOK_TOE;
const float ODT_OFFSET = ODT_LOOK_OFFSET;
const int ODT_HIGH_CONTRAST_ENABLE = ODT_LOOK_HIGH_CONTRAST_ENABLE;
const float ODT_HIGH_CONTRAST = ODT_LOOK_HIGH_CONTRAST;
const float ODT_HIGH_CONTRAST_PIVOT = ODT_LOOK_HIGH_CONTRAST_PIVOT;
const float ODT_HIGH_CONTRAST_EXTENSION = ODT_LOOK_HIGH_CONTRAST_EXTENSION;
const int ODT_LOW_CONTRAST_ENABLE = ODT_LOOK_LOW_CONTRAST_ENABLE;
const float ODT_LOW_CONTRAST = ODT_LOOK_LOW_CONTRAST;
const float ODT_LOW_CONTRAST_WIDTH = ODT_LOOK_LOW_CONTRAST_WIDTH;

#elif TONEMAP_ODT_TONESCALE == 1 // Low Contrast
const float ODT_CONTRAST = 1.4;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.003;
const float ODT_OFFSET = 0.005;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 0;
const float ODT_LOW_CONTRAST = 0.0;
const float ODT_LOW_CONTRAST_WIDTH = 0.5;

#elif TONEMAP_ODT_TONESCALE == 2 // Medium Contrast
const float ODT_CONTRAST = 1.66;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.003;
const float ODT_OFFSET = 0.005;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 0;
const float ODT_LOW_CONTRAST = 0.0;
const float ODT_LOW_CONTRAST_WIDTH = 0.5;

#elif TONEMAP_ODT_TONESCALE == 3 // High Contrast
const float ODT_CONTRAST = 1.4;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.003;
const float ODT_OFFSET = 0.005;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 1.0;
const float ODT_LOW_CONTRAST_WIDTH = 0.5;

#elif TONEMAP_ODT_TONESCALE == 4 // Arriba Tonescale
const float ODT_CONTRAST = 1.05;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.1;
const float ODT_OFFSET = 0.01;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 1.5;
const float ODT_LOW_CONTRAST_WIDTH = 0.2;

#elif TONEMAP_ODT_TONESCALE == 5 // Sylvan Tonescale
const float ODT_CONTRAST = 1.6;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.01;
const float ODT_OFFSET = 0.01;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 0.25;
const float ODT_LOW_CONTRAST_WIDTH = 0.75;

#elif TONEMAP_ODT_TONESCALE == 6 // Colorful Tonescale
const float ODT_CONTRAST = 1.5;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.003;
const float ODT_OFFSET = 0.003;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 0.4;
const float ODT_LOW_CONTRAST_WIDTH = 0.5;

#elif TONEMAP_ODT_TONESCALE == 7 // Aery Tonescale
const float ODT_CONTRAST = 1.15;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.04;
const float ODT_OFFSET = 0.006;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 0.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 0.5;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 0.5;
const float ODT_LOW_CONTRAST_WIDTH = 2.0;

#elif TONEMAP_ODT_TONESCALE == 8 // Dystopic Tonescale
const float ODT_CONTRAST = 1.6;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.01;
const float ODT_OFFSET = 0.008;
const int ODT_HIGH_CONTRAST_ENABLE = 1;
const float ODT_HIGH_CONTRAST = 0.25;
const float ODT_HIGH_CONTRAST_PIVOT = 0.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 1.0;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 1.0;
const float ODT_LOW_CONTRAST_WIDTH = 0.75;

#elif TONEMAP_ODT_TONESCALE == 9 // Umbra Tonescale
const float ODT_CONTRAST = 1.8;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.001;
const float ODT_OFFSET = 0.015;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 1.0;
const float ODT_LOW_CONTRAST_WIDTH = 1.0;

#elif TONEMAP_ODT_TONESCALE == 10 // ACES-1.x
const float ODT_CONTRAST = 1.0;
const float ODT_SHOULDER_CLIP = 0.35;
const float ODT_TOE = 0.02;
const float ODT_OFFSET = 0.0;
const int ODT_HIGH_CONTRAST_ENABLE = 1;
const float ODT_HIGH_CONTRAST = 0.55;
const float ODT_HIGH_CONTRAST_PIVOT = 0.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 2.0;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 1.13;
const float ODT_LOW_CONTRAST_WIDTH = 1.0;

#elif TONEMAP_ODT_TONESCALE == 11 // ACES-2.0
const float ODT_CONTRAST = 1.15;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.04;
const float ODT_OFFSET = 0.0;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 1.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 1.0;
const int ODT_LOW_CONTRAST_ENABLE = 0;
const float ODT_LOW_CONTRAST = 1.0;
const float ODT_LOW_CONTRAST_WIDTH = 0.6;

#elif TONEMAP_ODT_TONESCALE == 12 // Marvelous Tonescape
const float ODT_CONTRAST = 1.5;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.003;
const float ODT_OFFSET = 0.01;
const int ODT_HIGH_CONTRAST_ENABLE = 1;
const float ODT_HIGH_CONTRAST = 0.25;
const float ODT_HIGH_CONTRAST_PIVOT = 0.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 4.0;
const int ODT_LOW_CONTRAST_ENABLE = 1;
const float ODT_LOW_CONTRAST = 1.0;
const float ODT_LOW_CONTRAST_WIDTH = 1.0;

#elif TONEMAP_ODT_TONESCALE == 13 // DaGrinchi Tonegroan
const float ODT_CONTRAST = 1.2;
const float ODT_SHOULDER_CLIP = 0.5;
const float ODT_TOE = 0.02;
const float ODT_OFFSET = 0.0;
const int ODT_HIGH_CONTRAST_ENABLE = 0;
const float ODT_HIGH_CONTRAST = 0.0;
const float ODT_HIGH_CONTRAST_PIVOT = 1.0;
const float ODT_HIGH_CONTRAST_EXTENSION = 1.0;
const int ODT_LOW_CONTRAST_ENABLE = 0;
const float ODT_LOW_CONTRAST = 0.0;
const float ODT_LOW_CONTRAST_WIDTH = 0.6;
#endif

#endif // LIB_COLOR_TONEMAP_OPENDRT_PRESETS_GLSL
