#ifndef LIB_SHADOW_FILTER_GLSL
#define LIB_SHADOW_FILTER_GLSL

#include "/lib/core/filters.glsl"

// Separable cubic B-spline over a sampler2DShadow (Sigg-style 4 taps/axis);
// each tap uses hardware PCF, so the 16-tap result is smoother than a single
// lookup. Direct-shadow filtering, so it lives with the shadow domain next to
// the PCSS/PCF family rather than in the domain-neutral core library.
float Shadow2DFastBspline(sampler2DShadow tex0, vec3 sp, float res, float texel) {
    vec2 uv = sp.xy;

    uv *= res;
    uv -= 0.5;
    vec2 pm = floor(uv);

    vec2 pf = fract(uv);

    vec2 w0;
    vec2 w1;
    vec2 w2;
    vec2 w3;
    BsplineWeights(pf, w0, w1, w2, w3);

    vec2 g0 = w0 + w1;
    vec2 g1 = w2 + w3;
    vec2 h0 = -1.0 + w1 / g0;
    vec2 h1 = 1.0 + w3 / g1;

    vec4 p = (pm.xyxy + vec4(h0, h1) + 0.5) * texel;

    return g0.y * (g0.x * texture(tex0, vec3(p.xy, sp.z))  + g1.x * texture(tex0, vec3(p.zy, sp.z))) +
           g1.y * (g0.x * texture(tex0, vec3(p.xw, sp.z))  + g1.x * texture(tex0, vec3(p.zw, sp.z)));
}

#endif // LIB_SHADOW_FILTER_GLSL
