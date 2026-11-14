#ifndef LIB_CORE_FILTERS_GLSL
#define LIB_CORE_FILTERS_GLSL

vec4 CatmullRomTap(sampler2D tex, vec2 uv, bool base_level) {
    return base_level ? textureLod(tex, uv, 0.0) : texture(tex, uv);
}

// Fast 5-tap Catmull-Rom bicubic; sharpness 0.5 is typical. The optional bounds clamp
// lets cropped scene inputs reuse the filter.
vec4 FastCatmullRom5Tap(sampler2D tex, vec2 uv, vec2 texel_size, float sharpness,
        vec2 uv_min, vec2 uv_max, bool base_level) {
    vec2 res = 1.0 / texel_size;
    vec2 texel = uv * res;
    vec2 center = floor(texel - 0.5) + 0.5;
    vec2 f = texel - center;
    vec2 f2 = f * f;
    vec2 f3 = f * f2;

    vec2 w0 = -sharpness * f3 + 2.0 * sharpness * f2 - sharpness * f;
    vec2 w2 = (-2.0 + sharpness) * f3 + (3.0 - 2.0 * sharpness) * f2 + sharpness * f;
    vec2 w3 = sharpness * f3 - sharpness * f2;

    // h0 merges w1+w2; their cubic terms cancel exactly, so altering it breaks the weights.
    vec2 h0 = 1.0 + sharpness * f * (1.0 - f);
    vec2 p0 = (center + w2 / h0) * texel_size;
    vec2 p1 = (center - 1.0) * texel_size;
    vec2 p2 = (center + 2.0) * texel_size;

    vec4 col = vec4(0.0);
    float weight;
    weight = h0.x * w0.y;
    float weight_sum = weight;
    col += CatmullRomTap(tex, clamp(vec2(p0.x, p1.y), uv_min, uv_max), base_level) * weight;
    weight = w0.x * h0.y;
    weight_sum += weight;
    col += CatmullRomTap(tex, clamp(vec2(p1.x, p0.y), uv_min, uv_max), base_level) * weight;
    weight = h0.x * h0.y;
    weight_sum += weight;
    col += CatmullRomTap(tex, clamp(p0, uv_min, uv_max), base_level) * weight;
    weight = w3.x * h0.y;
    weight_sum += weight;
    col += CatmullRomTap(tex, clamp(vec2(p2.x, p0.y), uv_min, uv_max), base_level) * weight;
    weight = h0.x * w3.y;
    weight_sum += weight;
    col += CatmullRomTap(tex, clamp(vec2(p0.x, p2.y), uv_min, uv_max), base_level) * weight;
    return col / weight_sum;
}

vec4 FastCatmullRom5Tap(sampler2D tex, vec2 uv, vec2 texel_size, float sharpness,
        vec2 uv_min, vec2 uv_max) {
    return FastCatmullRom5Tap(tex, uv, texel_size, sharpness, uv_min, uv_max, false);
}

// History mip levels can be stale after another pass writes mip 0.
vec4 FastCatmullRom5TapLod0(sampler2D tex, vec2 uv, vec2 texel_size, float sharpness) {
    return FastCatmullRom5Tap(tex, uv, texel_size, sharpness,
        vec2(-1.0e30), vec2(1.0e30), true);
}

// No uv bounds: taps outside the texture follow the sampler's wrap mode.
vec4 FastCatmullRom5Tap(sampler2D tex, vec2 uv, vec2 texel_size, float sharpness) {
    return FastCatmullRom5Tap(tex, uv, texel_size, sharpness, vec2(-1.0e30), vec2(1.0e30));
}

// f is a fractional texel offset in [0, 1]; shared by the shadow-map PCF filter and the caustics sampler.
void BsplineWeights(vec2 f, out vec2 w0, out vec2 w1, out vec2 w2, out vec2 w3) {
    vec2 f2 = f * f;
    vec2 f3 = f2 * f;
    w0 = (1.0 / 6.0) * (f * (f * (-f + 3.0) - 3.0) + 1.0);
    w1 = (1.0 / 6.0) * (f2 * (3.0 * f - 6.0) + 4.0);
    w2 = (1.0 / 6.0) * (f * (f * (-3.0 * f + 3.0) + 3.0) + 1.0);
    w3 = (1.0 / 6.0) * f3;
}

#endif // LIB_CORE_FILTERS_GLSL
