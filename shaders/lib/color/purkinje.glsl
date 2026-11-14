#ifndef LIB_COLOR_PURKINJE_GLSL
#define LIB_COLOR_PURKINJE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/color/spaces.glsl"

vec3 ApplyPurkinjeEffect(vec3 color, float adaptation_luma) {
    float key = max(adaptation_luma, 1.0e-6);
    float rod_weight = saturate(
        (log2(PURKINJE_PHOTOPIC_KEY) - log2(key))
            / (log2(PURKINJE_PHOTOPIC_KEY) - log2(PURKINJE_SCOTOPIC_KEY)));
    rod_weight *= PURKINJE_STRENGTH;
    if (rod_weight <= 0.0) {
        return color;
    }

    vec3 xyz = SRGB_TO_XYZ * max(color, vec3(0.0));
    float scotopic_factor = 1.33
        * (1.0 + (xyz.y + xyz.z) / max(xyz.x, 1.0e-6)) - 1.68;
    float scotopic_luminance = xyz.y * max(scotopic_factor, 0.0);
    vec3 rod_color = scotopic_luminance
        * (PURKINJE_TINT / Luminance(PURKINJE_TINT));

    float cone_takeover = exp2(-Luminance(color) / PURKINJE_CONE_LUMINANCE);
    return mix(color, rod_color, rod_weight * cone_takeover);
}

#endif // LIB_COLOR_PURKINJE_GLSL
