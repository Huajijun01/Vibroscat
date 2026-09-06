#ifndef LIB_COLOR_PURKINJE_GLSL
#define LIB_COLOR_PURKINJE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/color/color.glsl"

// Approximate the rod-dominated scotopic response: blue-green sensitivity
// increases as scene luminance falls while the result keeps its luminance.
vec3 ApplyPurkinjeEffect(vec3 color) {
    float luminance = max(Luminance(color), 1e-5);
    float low_light = 1.0 - smoothstep(PURKINJE_START_LUMINANCE, PURKINJE_END_LUMINANCE, luminance);
    vec3 scotopic = color * PURKINJE_CHANNEL_RESPONSE;
    scotopic *= luminance / max(Luminance(scotopic), 1e-5);
    return mix(color, scotopic, low_light * PURKINJE_STRENGTH);
}

#endif // LIB_COLOR_PURKINJE_GLSL
