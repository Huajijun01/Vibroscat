#ifndef LIB_CORE_FILTERS_GLSL
#define LIB_CORE_FILTERS_GLSL

// Fast 5-tap Catmull-Rom bicubic (sharpness=0.5 typical). Uses texture() and
// explicit weight-sum normalization. UV clipping is caller responsibility.
vec4 FastCatmullRom5Tap(sampler2D tex, vec2 uv, vec2 texel_size, float sharpness) {
    vec2 res = vec2(textureSize(tex, 0));
    vec2 position = uv * res;
    vec2 center = floor(position - 0.5) + 0.5;
    vec2 f = position - center;
    vec2 f2 = f * f;
    vec2 f3 = f * f2;

    vec2 w0 = -sharpness * f3 + 2.0 * sharpness * f2 - sharpness * f;
    vec2 w1 = (2.0 - sharpness) * f3 - (3.0 - sharpness) * f2 + 1.0;
    vec2 w2 = (-2.0 + sharpness) * f3 + (3.0 - 2.0 * sharpness) * f2 + sharpness * f;
    vec2 w3 = sharpness * f3 - sharpness * f2;

    vec2 h0 = w1 + w2;
    vec2 p0 = (center + w2 / h0) * texel_size;
    vec2 p1 = (center - 1.0) * texel_size;
    vec2 p2 = (center + 2.0) * texel_size;

    vec4 col = vec4(0.0);
    float weight;
    weight = h0.x * w0.y;
    float weight_sum = weight;
    col += texture(tex, vec2(p0.x, p1.y)) * weight;
    weight = w0.x * h0.y;
    weight_sum += weight;
    col += texture(tex, vec2(p1.x, p0.y)) * weight;
    weight = h0.x * h0.y;
    weight_sum += weight;
    col += texture(tex, p0) * weight;
    weight = w3.x * h0.y;
    weight_sum += weight;
    col += texture(tex, vec2(p2.x, p0.y)) * weight;
    weight = h0.x * w3.y;
    weight_sum += weight;
    col += texture(tex, vec2(p0.x, p2.y)) * weight;
    return col / weight_sum;
}

// Separable cubic B-spline over a sampler2DShadow (Sigg-style 4 taps/axis);
// each tap uses hardware PCF, so the 16-tap result is smoother than a single
// lookup.
float Shadow2DFastBspline(sampler2DShadow tex0, vec3 sp, float res, float texel) {
    vec2 uv = sp.xy;

    uv *= res;
    uv -= 0.5;
    vec2 pm = floor(uv);

    vec2 pf = fract(uv);
    vec2 pf2 = pf * pf;
    vec2 pf3 = pf2 * pf;

    vec2 w0 = (1.0 / 6.0) * (pf * (pf * (-pf + 3.0) - 3.0) + 1.0);
    vec2 w1 = (1.0 / 6.0) * (pf2 * (3.0 * pf - 6.0) + 4.0);
    vec2 w2 = (1.0 / 6.0) * (pf * (pf * (-3.0 * pf + 3.0) + 3.0) + 1.0);
    vec2 w3 = (1.0 / 6.0) * pf3;

    vec2 g0 = w0 + w1;
    vec2 g1 = w2 + w3;
    vec2 h0 = -1.0 + w1 / g0;
    vec2 h1 = 1.0 + w3 / g1;

    vec4 p = (pm.xyxy + vec4(h0, h1) + 0.5) * texel;

    return g0.y * (g0.x * texture(tex0, vec3(p.xy, sp.z))  + g1.x * texture(tex0, vec3(p.zy, sp.z))) +
           g1.y * (g0.x * texture(tex0, vec3(p.xw, sp.z))  + g1.x * texture(tex0, vec3(p.zw, sp.z)));
}

#endif
