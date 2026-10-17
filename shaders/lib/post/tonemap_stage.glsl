#ifndef LIB_POST_TONEMAP_STAGE_GLSL
#define LIB_POST_TONEMAP_STAGE_GLSL

#include "/lib/contract/exposure_data.glsl"
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/color/spaces.glsl"
#include "/lib/color/tonemap.glsl"
#include "/lib/color/dither.glsl"
#include "/lib/color/purkinje.glsl"
#include "/lib/post/bloom.glsl"

// One owner for the display-referred conversion. composite21 stores the
// result in the colortex12 workspace for CAS to sharpen; with CAS off the
// same pass is scheduled away and final calls this directly on scene colour,
// which removes one full-screen RGBA16F write and its matching read.
const float TONEMAP_JITTER_SEED = 97.0;

// Sample mip 2 at a continuous local coordinate (integers are texel centres).
// Clamping keeps the atlas's neighbouring mip tiles out of the reconstruction.
vec3 SampleBloomMip2(vec2 local, vec2 origin, vec2 size, vec2 inv_size) {
    vec2 texel = clamp(local, vec2(0.0), size - 1.0);
    return textureLod(colortex12, (origin + texel + 0.5) * inv_size, 0.0).rgb;
}

// Tonemapped colour for one display pixel, dithered for RGBA16F storage.
vec3 TonemapStage(vec2 frag_coord) {
    vec2 uv = frag_coord * u_view_pixel_size;

    vec3 hdr = texture(colortex0, uv).rgb;

#ifdef BLOOM
    // The prefilter's scene origin is 0.5, so screen pixel i reads (i-0.5)/4.
    // gl_FragCoord is i + 0.5, so gl_FragCoord * 0.25 - 0.25 is the local
    // mip 2 coordinate with integers on texel centres. Clamp to the actual
    // tile, including floor rounding at odd render resolutions.
    ivec2 bloom_full_size = textureSize(colortex12, 0);
    vec2 bloom_origin = vec2(GetBloomMipOrigin(bloom_full_size, 2));
    vec2 bloom_size = vec2(GetBloomMipSize(bloom_full_size, 2));
    vec2 bloom_inv_size = 1.0 / vec2(bloom_full_size);
    vec2 bloom_local = clamp(frag_coord * 0.25 - 0.25, vec2(0.0), bloom_size - 1.0);
    vec2 bloom_base = floor(bloom_local);
    vec2 bloom_f = bloom_local - bloom_base;
    vec2 bloom_f2 = bloom_f * bloom_f;
    vec2 bloom_f3 = bloom_f2 * bloom_f;

    // One cubic B-spline reconstruction. The basis is separable and sums to
    // one, so it adds no energy. Folding each adjacent pair into one bilinear
    // fetch needs only the pair sums and pair ratios; the four individual
    // weights are never materialised:
    //   ax0 = w0 + w1 = (5 - 3f - 3f^2 + 2f^3) / 6,  ax1 = 1 - ax0
    //   w1 = (3f^3 - 6f^2 + 4) / 6,  w3 = f^3 / 6
    vec2 bloom_w1 = (3.0 * bloom_f3 - 6.0 * bloom_f2 + 4.0) * (1.0 / 6.0);
    vec2 bloom_w3 = bloom_f3 * (1.0 / 6.0);
    vec2 bloom_ax0 = (5.0 - 3.0 * bloom_f - 3.0 * bloom_f2 + 2.0 * bloom_f3) * (1.0 / 6.0);
    vec2 bloom_ax1 = 1.0 - bloom_ax0;
    vec2 bloom_px = vec2(bloom_base.x - 1.0 + bloom_w1.x / bloom_ax0.x,
                         bloom_base.x + 1.0 + bloom_w3.x / bloom_ax1.x);
    vec2 bloom_py = vec2(bloom_base.y - 1.0 + bloom_w1.y / bloom_ax0.y,
                         bloom_base.y + 1.0 + bloom_w3.y / bloom_ax1.y);

    vec3 bloom_00 = SampleBloomMip2(vec2(bloom_px.x, bloom_py.x), bloom_origin, bloom_size, bloom_inv_size);
    vec3 bloom_01 = SampleBloomMip2(vec2(bloom_px.x, bloom_py.y), bloom_origin, bloom_size, bloom_inv_size);
    vec3 bloom_10 = SampleBloomMip2(vec2(bloom_px.y, bloom_py.x), bloom_origin, bloom_size, bloom_inv_size);
    vec3 bloom_11 = SampleBloomMip2(vec2(bloom_px.y, bloom_py.y), bloom_origin, bloom_size, bloom_inv_size);
    vec3 bloom = bloom_00 * (bloom_ax0.x * bloom_ax0.y) + bloom_01 * (bloom_ax0.x * bloom_ax1.y)
               + bloom_10 * (bloom_ax1.x * bloom_ax0.y) + bloom_11 * (bloom_ax1.x * bloom_ax1.y);
    // The weights already sum to one, so the scale normalisation stays 1/7.
    bloom *= BLOOM_STRENGTH * (1.0 / 7.0);
    hdr += bloom;
#endif
    hdr *= exp2(TONEMAP_EXPOSURE);
#ifdef AE
    hdr *= exposure;
#endif
// The scotopic shift models adapted rod vision, so it requires AE. Keep the
// feature gates as #ifdef directives so Iris discovers PURKINJE_EFFECT as a
// configurable boolean option.
#ifdef PURKINJE_EFFECT
#ifdef AE
    float adapted_key_lum = AE_TARGET_LUMINANCE * exp2(-adapted_exposure_ev);
    hdr = ApplyPurkinjeEffect(hdr, adapted_key_lum);
#endif
#endif
    return JitterRGBA16F(Tonemap(hdr), frag_coord, TONEMAP_JITTER_SEED);
}

// Reproduce the RGBA16F storage rounding that composite21 applies implicitly,
// so the folded path hands final the identical value.
vec3 QuantizeToHalf(vec3 color) {
    vec2 rg = unpackHalf2x16(packHalf2x16(color.rg));
    float b = unpackHalf2x16(packHalf2x16(vec2(color.b, 0.0))).x;
    return vec3(rg, b);
}

#endif // LIB_POST_TONEMAP_STAGE_GLSL
