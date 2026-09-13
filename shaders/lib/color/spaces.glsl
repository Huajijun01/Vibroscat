#ifndef LIB_COLOR_SPACES_GLSL
#define LIB_COLOR_SPACES_GLSL

// sRGB <-> Linear conversion (BT.709 OETF)
vec3 ToLinear(vec3 srgb) {
    bvec3 cutoff = lessThan(srgb, vec3(0.04045));
    vec3 higher = pow((srgb + vec3(0.055)) / vec3(1.055), vec3(2.4));
    vec3 lower = srgb / vec3(12.92);
    return mix(higher, lower, cutoff);
}

vec3 FromLinear(vec3 linear_rgb) {
    bvec3 cutoff = lessThan(linear_rgb, vec3(0.0031308));
    vec3 higher = vec3(1.055) * pow(linear_rgb, vec3(1.0 / 2.4)) - vec3(0.055);
    vec3 lower = linear_rgb * vec3(12.92);
    return mix(higher, lower, cutoff);
}

// Rec.709 linear luminance, shared by lighting, fog and temporal blending.
float Luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Linear sRGB (D65) -> CIE XYZ, shared by colorimetric models (scotopic

const mat3 SRGB_TO_XYZ = mat3(
    vec3(0.4124564, 0.2126729, 0.0193339),
    vec3(0.3575761, 0.7151522, 0.1191920),
    vec3(0.1804375, 0.0721750, 0.9503041));

// OKLAB
// l/m/s are the LMS cone responses, l_/m_/s_ their cube roots (Ottosson's
// reference notation).
vec3 RGBToOKLAB(vec3 c) {
    float l = 0.4121656120 * c.r + 0.5362752080 * c.g + 0.0514575653 * c.b;
    float m = 0.2118591070 * c.r + 0.6807189584 * c.g + 0.1074065790 * c.b;
    float s = 0.0883097947 * c.r + 0.2818474174 * c.g + 0.6302613616 * c.b;

    float l_ = pow(l, 1.0 / 3.0);
    float m_ = pow(m, 1.0 / 3.0);
    float s_ = pow(s, 1.0 / 3.0);

    vec3 lab;
    lab.x = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    lab.y = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    lab.z = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
    return lab;
}

vec3 OKLABToRGB(vec3 c) {
    float l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;

    float l = l_ * l_ * l_;
    float m = m_ * m_ * m_;
    float s = s_ * s_ * s_;

    vec3 rgb;
    rgb.r =  4.0767245293 * l - 3.3072168827 * m + 0.2307590544 * s;
    rgb.g = -1.2681437731 * l + 2.6093323231 * m - 0.3411344290 * s;
    rgb.b = -0.0041119885 * l - 0.7034763098 * m + 1.7068625689 * s;
    return rgb;
}

// AgX display rendering transform.
// Concept: [SOB22] Sobotka, Troy. AgX. 2022. https://github.com/sobotka/AgX

// --- HSV helpers (shared by the Reinhard-Gamut hue protection) ---

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
    vec3 primary = clamp(abs(fract(hsv.x + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return hsv.z * mix(vec3(1.0), primary, hsv.y);
}

#endif // LIB_COLOR_SPACES_GLSL
