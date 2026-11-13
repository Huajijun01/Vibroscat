#ifndef LIB_COLOR_SPACES_GLSL
#define LIB_COLOR_SPACES_GLSL

#include "/lib/core/math_scalar.glsl"

// sRGB <-> Linear conversion. Each direction replaces the IEC 61966-2-1
// piecewise curve (12.92 linear segment, 2.4 power segment) with one
// branchless fitted expression.
vec3 ToLinear(vec3 srgb) {
    return srgb * (srgb * (srgb * 0.3144148469 + 0.6674410945) + 0.0181440586);
}

vec3 FromLinear(vec3 linear_rgb) {
    return 1.2404334562 * sqrt(linear_rgb + vec3(0.000515237193)) - (0.2125965772 * linear_rgb + vec3(0.0281563966));
}

// Rec.709 linear luminance, shared by lighting, fog and temporal blending.
float Luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Linear sRGB (D65) -> CIE XYZ, shared by colorimetric models (scotopic
// estimation in /lib/color/purkinje.glsl).

const mat3 SRGB_TO_XYZ = mat3(
    vec3(0.4124564, 0.2126729, 0.0193339),
    vec3(0.3575761, 0.7151522, 0.1191920),
    vec3(0.1804375, 0.0721750, 0.9503041));

// --- HSV helpers (used by the AgX hue repair) ---

vec3 RGBToHSV(vec3 color) {
    float maximum = max(color.r, max(color.g, color.b));
    float minimum = min(color.r, min(color.g, color.b));
    float chroma = maximum - minimum;
    float hue = 0.0;
    if (chroma > 1.0e-7) {
        if (maximum == color.r)
            hue = (color.g - color.b) / chroma;
        else if (maximum == color.g)
            hue = (color.b - color.r) / chroma + 2.0;
        else
            hue = (color.r - color.g) / chroma + 4.0;
        hue = fract(hue / 6.0);
    }
    float saturation = maximum > 1.0e-7 ? chroma / maximum : 0.0;
    return vec3(hue, saturation, maximum);
}

vec3 HSVToRGB(vec3 hsv) {
    vec3 primary = saturate(abs(fract(hsv.x + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0);
    return hsv.z * mix(vec3(1.0), primary, hsv.y);
}

#endif // LIB_COLOR_SPACES_GLSL
