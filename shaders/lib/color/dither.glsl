#ifndef LIB_COLOR_DITHER_GLSL
#define LIB_COLOR_DITHER_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/noise.glsl"

#ifndef COLOR_DITHER_STRENGTH
#define COLOR_DITHER_STRENGTH 1.0
#endif

float ColorDitherNoise(vec2 pixel, float seed) {
    vec2 seed_offset = vec2(seed * 17.0, seed * 47.0);
    return InterleavedGradientNoise(pixel + seed_offset) - 0.5;
}

vec3 JitterR11G11B10F(vec3 color, vec2 pixel, float seed
) {
    float noise = ColorDitherNoise(pixel, seed);
    vec3 step_size = max(abs(color), vec3(1e-4))
        * vec3(1.0 / 64.0, 1.0 / 64.0, 1.0 / 32.0)
        * COLOR_DITHER_STRENGTH;
    return max(color + noise * step_size, vec3(0.0));
}

vec3 JitterRGBA16F(vec3 color, vec2 pixel, float seed
) {
    float noise = ColorDitherNoise(pixel, seed);
    vec3 step_size = max(abs(color), vec3(1e-4))
        * (1.0 / 1024.0) * COLOR_DITHER_STRENGTH;
    return max(color + noise * step_size, vec3(0.0));
}

vec3 JitterSRGB8(vec3 color, vec2 pixel, float seed) {
    float noise = ColorDitherNoise(pixel, seed);
    return clamp(color + noise * (1.0 / 255.0) * COLOR_DITHER_STRENGTH, 0.0, 1.0);
}

#endif
