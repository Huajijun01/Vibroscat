#ifndef LIB_VOLUME_EPIPOLAR_CORE_GLSL
#define LIB_VOLUME_EPIPOLAR_CORE_GLSL
// Epipolar slice/quadrant parametrization follows the Intel Outdoor Light
// Scattering Sample (Intel, Apache-2.0; license in licenses/THIRD_PARTY_NOTICES.md
// section 6 and appendix A). Additional reference: Yusov, "Practical Implementation of
// Light Scattering Effects Using Epipolar Sampling and 1D Min/Max Binary
// Trees", GDC 2013.
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Shared epipolar geometry, projection, and unwarp. Medium-agnostic: water
// and air volume light parametrize the same machinery with their own column
// key and E channel. Functions only (uniforms from the includer /
// contract/uniforms.glsl).
// Packed epipolar term (RGBA16F, shared image, one medium per frame):
//   composite1_a (water integrate) -> RGB = water E (full vec3), A = water column depth key
//   composite2   (air integrate)   -> RGB = air E (full vec3),    A = air depth key
// The air pass overwrites the water term; each unwarp consumer runs in the
// fragment stage right after its own integrate pass.

#include "/lib/core/coordinates.glsl"

#ifdef EPIPOLAR_WATER

// Project the active light into NDC. The pole is the light's projective
// screen position: behind the camera it mirrors (lines stay valid); at
// clip.w ~ 0 it is at infinity (lines become parallel). poleInScreen =
// inside the rect.
vec2 EpipolarLightNDC(out bool pole_in_screen) {
    vec3 view_dir = mat3(gbufferModelView) * normalize(u_world_light_dir);
    vec4 clip = gbufferProjection * vec4(view_dir, 0.0);
    float side = clip.w >= 0.0 ? 1.0 : -1.0;
    pole_in_screen = clip.w > 1e-6 && abs(clip.x) <= clip.w && abs(clip.y) <= clip.w;
    return clip.xy / max(abs(clip.w), 1e-6) * side;
}

// Exit point on the rect for slice i (Intel quadrant parametrization):
// uniform perimeter placement keeps coverage even with a far/infinite pole.
vec2 EpipolarSliceExit(int slice) {
    float f = (float(slice) + 0.5) / float(EPIPOLAR_SLICES);
    int sector = clamp(int(f * 4.0), 0, 3);
    float s = fract(f * 4.0);
    if (sector == 0) return vec2(-1.0, 1.0 - 2.0 * s);
    if (sector == 1) return vec2(-1.0 + 2.0 * s, -1.0);
    if (sector == 2) return vec2(1.0, -1.0 + 2.0 * s);
    return vec2(1.0 - 2.0 * s, 1.0);
}

// Other rect crossing of the line through origin and dir (origin = one
// boundary crossing; the ray enters forward or leaves backward; zero dir
// components → ±inf, tolerated by the slab test).
vec2 EpipolarBoundaryHit(vec2 origin, vec2 dir) {
    vec2 inv = 1.0 / dir;
    vec2 t0 = (-1.0 - origin) * inv;
    vec2 t1 = ( 1.0 - origin) * inv;
    vec2 tmin = min(t0, t1);
    vec2 tmax = max(t0, t1);
    float t_far = min(tmax.x, tmax.y);
    float t_other = t_far > 1e-4 ? t_far : max(tmin.x, tmin.y);
    return origin + dir * t_other;
}

// Slice coordinate of a screen point: exit sector of the pole→pixel ray,
// same parametrization as EpipolarSliceExit; ∈ [0, EPIPOLAR_SLICES).
float EpipolarSliceOf(vec2 ndc, vec2 pole) {
    vec2 dir = ndc - pole;
    float len = length(dir);
    if (len < 1e-6) return 0.0;
    vec2 ray_dir = dir / len;
    float x = ndc.x;
    float y = ndc.y;
    float rx = ray_dir.x;
    float ry = ray_dir.y;
    // Exit edge by quadrant + one cross-multiplied time comparison (only the
    // chosen edge needs a division).
    float s;
    if (rx > 1e-6) {
        if (ry > 1e-6) {
            if ((1.0 - x) * ry < (1.0 - y) * rx) {
                float t = (1.0 - x) / rx;
                s = 2.0 + (y + ry * t + 1.0) * 0.5;
            } else {
                float t = (1.0 - y) / ry;
                s = 3.0 + (1.0 - (x + rx * t)) * 0.5;
            }
        } else if (ry < -1e-6) {
            if ((1.0 - x) * (-ry) < (y + 1.0) * rx) {
                float t = (1.0 - x) / rx;
                s = 2.0 + (y + ry * t + 1.0) * 0.5;
            } else {
                float t = (-1.0 - y) / ry;
                s = 1.0 + (x + rx * t + 1.0) * 0.5;
            }
        } else {
            float t = (1.0 - x) / rx;
            s = 2.0 + (y + 1.0) * 0.5;
        }
    } else if (rx < -1e-6) {
        if (ry > 1e-6) {
            if ((x + 1.0) * ry < (1.0 - y) * (-rx)) {
                float t = (x + 1.0) / (-rx);
                s = 0.0 + (1.0 - (y + ry * t)) * 0.5;
            } else {
                float t = (1.0 - y) / ry;
                s = 3.0 + (1.0 - (x + rx * t)) * 0.5;
            }
        } else if (ry < -1e-6) {
            if ((x + 1.0) * (-ry) < (y + 1.0) * (-rx)) {
                float t = (x + 1.0) / (-rx);
                s = 0.0 + (1.0 - (y + ry * t)) * 0.5;
            } else {
                float t = (-1.0 - y) / ry;
                s = 1.0 + (x + rx * t + 1.0) * 0.5;
            }
        } else {
            float t = (x + 1.0) / (-rx);
            s = 0.0 + (1.0 - y) * 0.5;
        }
    } else if (ry > 1e-6) {
        float t = (1.0 - y) / ry;
        s = 3.0 + (1.0 - x) * 0.5;
    } else {
        float t = (-1.0 - y) / ry;
        s = 1.0 + (x + 1.0) * 0.5;
    }
    return s * 0.25 * float(EPIPOLAR_SLICES);
}

// Camera-relative scene point from UV+depth; do NOT add cameraPosition
// (shadowModelView maps this space).
vec3 EpipolarViewToScene(vec2 uv01, float depth01) {
    vec3 view_pos = NDCToView(vec3(uv01 * 2.0 - 1.0, depth01 * 2.0 - 1.0));
    return ViewToSceneSpace(view_pos);
}

// Linear |view z| (meters) for a screen texel. The epipolar column keys are
// stored in this linear space instead of raw depth01: the non-linear depth
// encoding saturates at distance and makes any absolute tolerance either too
// tight up close or meaningless far away. Relative comparison against these
// keys is scale-invariant (see EpipolarEdgeWeight).
float EpipolarViewZ(vec2 uv01, float depth01) {
    return -NDCToView(vec3(uv01 * 2.0 - 1.0, depth01 * 2.0 - 1.0)).z;
}

// Depth-aware unwarp weight: columns differing from the pixel's are
// down-weighted (no silhouette/shadow-edge smearing). The keys are linear
// viewZ and the tolerance is RELATIVE (fraction of the deeper key), so the
// acceptance band is scale-invariant: full weight inside the band, steep
// 4th-power falloff outside (pattern from Alpha Piscium's refinement
// weight). A relative test with linear depth fixes the hard blocks at low
// epipolar resolution, where raw depth01 saturates and an absolute
// tolerance mis-accepts distant columns.
float EpipolarEdgeWeight(float pixel_key, float sample_key) {
    if (pixel_key <= 0.0 || sample_key <= 0.0) return 0.0;
    float max_z = max(pixel_key, max(sample_key, 1.0));
    float rel = abs(pixel_key - sample_key) / max_z;
    float w = EPIPOLAR_DEPTH_TOLERANCE / max(rel, EPIPOLAR_DEPTH_TOLERANCE);
    w = clamp(w, 0.0, 1.0);
    float w2 = w * w;
    return w2 * w2;
}

// Value-aware sharpening: strong candidate difference = real shadow edge →
// strengthen the contrast of the blend weight continuously (no hard snap:
// step() at low resolution turns sparse samples into blocky edges).
float EpipolarSharpen(float w, float a, float b) {
    float edge = smoothstep(0.05, EPIPOLAR_EDGE_SHARPEN, abs(a - b));
    float sharp = w * w * (3.0 - 2.0 * w); // smooth S-curve, same endpoints
    return mix(w, sharp, edge);
}

// Interpolate E between the two nearest stored samples, gated by column
// depth. The shared term image holds exactly the medium whose integrate
// pass ran last, so E is read directly from RGB and the key from A.
vec3 EpipolarSampleOnSlice(int slice, vec2 ndc, float pixel_key,
                           out float sample_key) {
    vec4 line = texelFetch(usam_epipolar_endpoints, ivec2(slice, 0), 0);
    if (all(equal(line, vec4(0.0)))) {
        sample_key = 0.0;
        return vec3(1.0);
    }
    vec2 d = line.zw - line.xy;
    float len2 = dot(d, d);
    float t = dot(ndc - line.xy, d) / max(len2, 1e-8);
    float sample_f = clamp(t, 0.0, 1.0) * float(EPIPOLAR_SAMPLES - 1);
    int s = int(sample_f);
    float f = fract(sample_f);
    vec4 a = texelFetch(usam_epipolar_term, ivec2(slice, s), 0);
    vec4 b = texelFetch(usam_epipolar_term, ivec2(slice, min(s + 1, EPIPOLAR_SAMPLES - 1)), 0);

    float ka = a.a;
    float kb = b.a;
    vec3 va = a.rgb;
    vec3 vb = b.rgb;

    float wa = EpipolarEdgeWeight(pixel_key, ka);
    float wb = EpipolarEdgeWeight(pixel_key, kb);
    f = EpipolarSharpen(f, dot(va, vec3(0.2126, 0.7152, 0.0722)),
                        dot(vb, vec3(0.2126, 0.7152, 0.0722)));
    float wsum = (1.0 - f) * wa + f * wb;
    if (wsum < 1e-4) {
        // No matching column on the two nearest samples. Do NOT fall back to
        // E=1 here -- on a shadowed silhouette that paints a bright
        // unshadowed ring. Instead weight-average the valid columns within
        // EPIPOLAR_EDGE_EXTEND by the relative-depth weight (closest column
        // dominates, tiny far-column bleed keeps the value continuous);
        // E=1 stays only for a slice with no valid column at all (sky /
        // no medium), where it is the correct neutral value.
        if (pixel_key > 0.0) {
            float nsum = 0.0;
            vec3 nval = vec3(0.0);
            float nkey_w = 0.0;
            float nkey_sum = 0.0;
            for (int k = 1; k <= EPIPOLAR_EDGE_EXTEND; ++k) {
                int lo = max(s - k, 0);
                int hi = min(s + 1 + k, EPIPOLAR_SAMPLES - 1);
                vec4 c = texelFetch(usam_epipolar_term, ivec2(slice, lo), 0);
                float ck = c.a;
                if (ck > 0.0) {
                    float w = EpipolarEdgeWeight(pixel_key, ck);
                    nsum += w;
                    nval += w * c.rgb;
                    nkey_sum += w * ck;
                    nkey_w += w;
                }
                c = texelFetch(usam_epipolar_term, ivec2(slice, hi), 0);
                ck = c.a;
                if (ck > 0.0) {
                    float w = EpipolarEdgeWeight(pixel_key, ck);
                    nsum += w;
                    nval += w * c.rgb;
                    nkey_sum += w * ck;
                    nkey_w += w;
                }
            }
            if (nsum > 1e-4) {
                sample_key = nkey_sum / max(nkey_w, 1e-6);
                return nval / nsum;
            }
        }
        sample_key = 0.0;
        return vec3(1.0);
    }
    sample_key = ((1.0 - f) * ka * wa + f * kb * wb) / wsum;
    return ((1.0 - f) * va * wa + f * vb * wb) / wsum;
}

// Full unwarp: pixel's slice by angle, bilinear across neighbouring slices
// and stored samples, gated by column depth. Returns E (1.0 when invalid).
// The term image holds the medium whose integrate pass ran last; call this
// only in the fragment stage that follows that pass.
vec3 EpipolarSampleE(vec2 ndc, float pixel_key) {
    bool pole_in_screen;
    vec2 pole = EpipolarLightNDC(pole_in_screen);
    float slice_f = EpipolarSliceOf(ndc, pole);
    int s0 = int(slice_f) % EPIPOLAR_SLICES;
    float w = fract(slice_f);
    float key0;
    float key1;
    vec3 e0 = EpipolarSampleOnSlice(s0, ndc, pixel_key, key0);
    vec3 e1 = EpipolarSampleOnSlice((s0 + 1) % EPIPOLAR_SLICES, ndc, pixel_key,
                                    key1);
    w = EpipolarSharpen(w, dot(e0, vec3(0.2126, 0.7152, 0.0722)),
                        dot(e1, vec3(0.2126, 0.7152, 0.0722)));
    float w0 = EpipolarEdgeWeight(pixel_key, key0);
    float w1 = EpipolarEdgeWeight(pixel_key, key1);
    float wsum = (1.0 - w) * w0 + w * w1;
    if (wsum < 1e-4) {
        // Neither neighbouring slice has a matching column: fall back to the
        // depth-weighted blend of the two slice results (continuous value)
        // instead of E=1, which would paint a bright unshadowed ring. E=1 is
        // returned only when the pixel has no valid column at all (sky / no
        // medium), where it is the correct neutral value.
        float ssum = w0 + w1;
        if (ssum > 1e-6) return (e0 * w0 + e1 * w1) / ssum;
        if (key0 > 0.0) return e0;
        if (key1 > 0.0) return e1;
        return vec3(1.0);
    }
    return (e0 * ((1.0 - w) * w0) + e1 * (w * w1)) / wsum;
}

#endif // EPIPOLAR_WATER
#endif // LIB_VOLUME_EPIPOLAR_CORE_GLSL
