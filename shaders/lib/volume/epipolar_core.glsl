#ifndef LIB_VOLUME_EPIPOLAR_CORE_GLSL
#define LIB_VOLUME_EPIPOLAR_CORE_GLSL
// Epipolar slice/quadrant parametrization follows the Intel Outdoor Light
// Scattering Sample (Intel, Apache-2.0; license in licenses/THIRD_PARTY_NOTICES.md
// section 5 and appendix A). Additional reference: Yusov, "Practical Implementation of
// Light Scattering Effects Using Epipolar Sampling and 1D Min/Max Binary
// Trees", GDC 2013.
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Shared epipolar geometry and depth-aware unwarp. Air stores normalized E;
// underwater stores additive radiance. Only the active medium owns the images.
// composite1 -> composite2 compute -> composite2 fragment use Iris barriers.

#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/color/spaces.glsl"

#if defined(EPIPOLAR_ACTIVE)

// Underwater occupies a bounded lower-left rectangle of the existing images.
// Every active texel is rewritten each frame; neither medium consumes history.
int SliceCount() {
#if defined(WATER_EPIPOLAR_ACTIVE)
    if (isEyeInWater == 1) return min(EPIPOLAR_SLICES, 512);
#endif
    return EPIPOLAR_SLICES;
}

int SampleCount() {
#if defined(WATER_EPIPOLAR_ACTIVE)
    if (isEyeInWater == 1) return min(EPIPOLAR_SAMPLES, 256);
#endif
    return EPIPOLAR_SAMPLES;
}

// Quantize a screen UV to the texel holding its center, shared by every
// epipolar depth/key fetch: clamping to texel centers keeps truncation inside
// the viewport at both edges.
ivec2 ScreenTexel(vec2 uv01) {
    return ivec2(clamp(uv01 * u_render_res, vec2(0.5), u_render_res - vec2(0.5)));
}

// Shadow visibility on the undistorted segment; apply distortion at each step.
float ShadowVisibility(vec3 shadow_clip_start, vec3 shadow_clip_end, float u) {
    vec3 clip = mix(shadow_clip_start, shadow_clip_end, u);
    vec2 uv = clip.xy / GetDistortFactor(clip.xy) * 0.5 + 0.5;
    float shadow_depth = ProtectShadowDepth(clip.z * 0.5 + 0.5);
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))
        || shadow_depth <= 0.0 || shadow_depth >= 1.0) return 1.0;
    return texture(shadowtex1, vec3(uv, shadow_depth));
}

// Project the active light into NDC. The pole is the light's projective
// screen position: behind the camera it mirrors (lines stay valid); at
// clip.w ~ 0 it is at infinity (lines become parallel). pole_in_screen =
// inside the rect.
vec2 LightNDC(out bool pole_in_screen) {
    vec3 light_dir_view = u_view_light_dir;
#if defined(WATER_EPIPOLAR_ACTIVE)
    if (isEyeInWater == 1) light_dir_view = u_view_sun_dir;
#endif
    vec4 clip = gbufferProjection * vec4(light_dir_view, 0.0);
    float side = clip.w >= 0.0 ? 1.0 : -1.0;
    pole_in_screen = clip.w > 1e-6 && abs(clip.x) <= clip.w && abs(clip.y) <= clip.w;
    return clip.xy / max(abs(clip.w), 1e-6) * side;
}

// Exit point on the rect for slice i (Intel quadrant parametrization):
// uniform perimeter placement keeps coverage even with a far/infinite pole.
vec2 SliceExit(int slice) {
    float f = (float(slice) + 0.5) / float(SliceCount());
    int sector = clamp(int(f * 4.0), 0, 3);
    float s = fract(f * 4.0);
    if (sector == 0) return vec2(-1.0, 1.0 - 2.0 * s);
    if (sector == 1) return vec2(-1.0 + 2.0 * s, -1.0);
    if (sector == 2) return vec2(1.0, -1.0 + 2.0 * s);
    return vec2(1.0 - 2.0 * s, 1.0);
}

// Other rect crossing of the line through origin and dir (origin = one
// boundary crossing; the ray enters forward or leaves backward; zero dir
// components -> +/-inf, tolerated by the slab test).
vec2 BoundaryHit(vec2 origin, vec2 dir) {
    // Avoid 0 * inf when a line starts on an edge and is parallel to it:
    // a NaN here would leak into an endpoint line near horizontal/vertical
    // light directions and invalidate the whole slice.
    vec2 tmin = vec2(-1e30);
    vec2 tmax = vec2( 1e30);
    if (abs(dir.x) > 1e-6) {
        vec2 tx = vec2((-1.0 - origin.x) / dir.x,
                       ( 1.0 - origin.x) / dir.x);
        tmin.x = min(tx.x, tx.y);
        tmax.x = max(tx.x, tx.y);
    }
    if (abs(dir.y) > 1e-6) {
        vec2 ty = vec2((-1.0 - origin.y) / dir.y,
                       ( 1.0 - origin.y) / dir.y);
        tmin.y = min(ty.x, ty.y);
        tmax.y = max(ty.x, ty.y);
    }
    float t_far = min(tmax.x, tmax.y);
    float t_other = t_far > 1e-4 ? t_far : max(tmin.x, tmin.y);
    return origin + dir * t_other;
}

// Camera-relative world point from UV+depth; do NOT add cameraPosition
// (shadowModelView maps this space).
vec3 WorldPosFromScreenUV(vec2 uv01, float depth01) {
    vec3 view_pos = NDCToView(vec3(uv01 * 2.0 - 1.0, depth01 * 2.0 - 1.0));
    return ViewToWorldSpace(view_pos);
}

// Gather order: lower/upper sample on slice0, then on slice1. Iris uses
// linear filtering and clamp-to-edge for these noninteger custom images.
vec4 GatherKeys(int slice0, int row) {
    vec2 uv = vec2(float(slice0 + 1) / float(EPIPOLAR_SLICES),
        float(row + 1) / float(EPIPOLAR_SAMPLES));
    if (slice0 < SliceCount() - 1) return textureGather(usam_epipolar_term, uv, 3).wxzy;
    vec4 left = textureGather(usam_epipolar_term, vec2((float(slice0) + 0.5)
        / float(EPIPOLAR_SLICES), uv.y), 3);
    vec4 right = textureGather(usam_epipolar_term, vec2(0.5 / float(EPIPOLAR_SLICES), uv.y), 3);
    return vec4(left.w, left.x, right.w, right.x);
}

// Compare relative errors by cross multiplication, without four reciprocals
// per search footprint. Settings expose power-of-two slice counts.
void SelectKey(vec4 keys, float pixel_key, int slice0, int row,
        inout float closest_distance, inout float closest_scale, inout ivec2 closest_texel) {
    vec4 distance_z = abs(vec4(pixel_key) - keys);
    vec4 scale_z = max(vec4(pixel_key), max(keys, vec4(1.0)));
    distance_z = mix(vec4(1e30), distance_z, greaterThan(keys, vec4(0.0)));
    int corner = 0;
    float candidate_distance = distance_z.x;
    float candidate_scale = scale_z.x;
    if (distance_z.y * candidate_scale < candidate_distance * scale_z.y) {
        corner = 1;
        candidate_distance = distance_z.y;
        candidate_scale = scale_z.y;
    }
    if (distance_z.z * candidate_scale < candidate_distance * scale_z.z) {
        corner = 2;
        candidate_distance = distance_z.z;
        candidate_scale = scale_z.z;
    }
    if (distance_z.w * candidate_scale < candidate_distance * scale_z.w) {
        corner = 3;
        candidate_distance = distance_z.w;
        candidate_scale = scale_z.w;
    }
    if (candidate_distance * closest_scale < closest_distance * candidate_scale) {
        closest_distance = candidate_distance;
        closest_scale = candidate_scale;
        closest_texel = ivec2((slice0 + (corner >> 1)) & (SliceCount() - 1), row + (corner & 1));
    }
}

vec3 SampleEpipolarTerm(vec2 ndc, float pixel_key, vec3 fallback) {
    bool pole_in_screen;
    vec2 pole;
#ifdef EPIPOLAR_POLE_VARYING
    pole_in_screen = v_epipolar_pole_in_screen != 0;
    pole = v_epipolar_pole;
#else
    pole = LightNDC(pole_in_screen);
    if (pole_in_screen) pole = unpackHalf2x16(packHalf2x16(pole));
#endif
    vec2 delta = ndc - pole;
    vec2 magnitude = max(abs(delta), vec2(1e-10));
    bvec2 negative = lessThan(delta, vec2(0.0));
    vec2 forward_bounds = mix(vec2(1.0) - ndc, ndc + vec2(1.0), negative);
    bool exit_x = forward_bounds.x * magnitude.y < forward_bounds.y * magnitude.x;
    float exit_bound = exit_x ? forward_bounds.x : forward_bounds.y;
    float exit_magnitude = exit_x ? magnitude.x : magnitude.y;
    float to_exit = exit_bound / exit_magnitude;
    vec2 exit_point = ndc + delta * to_exit;
    float perimeter;
    if (exit_x) {
        perimeter = negative.x ? (1.0 - exit_point.y) * 0.5 : 2.0 + (exit_point.y + 1.0) * 0.5;
    } else {
        perimeter = negative.y ? 1.0 + (exit_point.x + 1.0) * 0.5 : 3.0 + (1.0 - exit_point.x) * 0.5;
    }
    float slice_f = fract(perimeter * 0.25 - 0.5 / float(SliceCount())) * float(SliceCount());
    int slice0 = int(slice_f);
    int slice1 = (slice0 + 1) & (SliceCount() - 1);
    // Progress on the continuous pole->pixel line. Inside one exit sector
    // this inverts the producer grid exactly for an in-screen pole. Outside
    // the screen it follows the continuous entry/exit ray; interpolation of
    // neighbouring stored lines remains a finite-grid approximation.
    float t;
    if (pole_in_screen) {
        float pole_bound = exit_x ? (negative.x ? 1.0 + pole.x : 1.0 - pole.x)
            : (negative.y ? 1.0 + pole.y : 1.0 - pole.y);
        t = exit_magnitude / max(pole_bound, 1e-6);
    } else {
        vec2 backward_bounds = vec2(2.0) - forward_bounds;
        bool entry_x = backward_bounds.x * magnitude.y < backward_bounds.y * magnitude.x;
        float entry_bound = entry_x ? backward_bounds.x : backward_bounds.y;
        float entry_magnitude = entry_x ? magnitude.x : magnitude.y;
        float entry_weight = entry_bound * exit_magnitude;
        t = entry_weight / max(entry_weight + exit_bound * entry_magnitude, 1e-20);
    }
    float sample_f = saturate(t) * float(SampleCount() - 1);
    int row = min(int(sample_f), SampleCount() - 2);
    vec2 blend = vec2(fract(slice_f), sample_f - float(row));
    vec4 keys = GatherKeys(slice0, row);
    vec4 distance_z = abs(vec4(pixel_key) - keys);
    vec4 tolerance_z = EPIPOLAR_DEPTH_TOLERANCE * max(vec4(pixel_key), max(keys, vec4(1.0)));
    vec2 uv = vec2((slice_f + 0.5) / float(EPIPOLAR_SLICES),
        (sample_f + 0.5) / float(EPIPOLAR_SAMPLES));
    if (slice0 < SliceCount() - 1 && all(greaterThan(keys, vec4(0.0)))
            && all(lessThanEqual(distance_z, tolerance_z))) {
        return textureLod(usam_epipolar_term, uv, 0.0).rgb;
    }
    vec4 spatial = vec4((1.0 - blend.x) * (1.0 - blend.y), (1.0 - blend.x) * blend.y,
        blend.x * (1.0 - blend.y), blend.x * blend.y);
    vec4 weight = tolerance_z / max(distance_z, tolerance_z);
    weight *= weight;
    weight *= weight;
    weight = mix(vec4(0.0), weight * spatial, greaterThan(keys, vec4(0.0)));
    float total = dot(weight, vec4(1.0));
    if (total >= 1e-4) {
        if (slice0 < SliceCount() - 1) {
            vec2 footprint_uv = vec2(float(slice0 + 1) / float(EPIPOLAR_SLICES),
                float(row + 1) / float(EPIPOLAR_SAMPLES));
            vec4 red = textureGather(usam_epipolar_term, footprint_uv, 0).wxzy;
            vec4 green = textureGather(usam_epipolar_term, footprint_uv, 1).wxzy;
            vec4 blue = textureGather(usam_epipolar_term, footprint_uv, 2).wxzy;
            return vec3(dot(red, weight), dot(green, weight), dot(blue, weight)) / total;
        }
        vec4 a = texelFetch(usam_epipolar_term, ivec2(slice0, row), 0);
        vec4 b = texelFetch(usam_epipolar_term, ivec2(slice0, row + 1), 0);
        vec4 c = texelFetch(usam_epipolar_term, ivec2(slice1, row), 0);
        vec4 d = texelFetch(usam_epipolar_term, ivec2(slice1, row + 1), 0);
        return (a.rgb * weight.x + b.rgb * weight.y + c.rgb * weight.z + d.rgb * weight.w) / total;
    }
    if (pixel_key <= 0.0) return fallback;
    float closest_distance = 1e30;
    float closest_scale = 1.0;
    ivec2 closest_texel = ivec2(slice0, row);
    SelectKey(keys, pixel_key, slice0, row, closest_distance, closest_scale, closest_texel);
    for (int k = 1; k <= EPIPOLAR_EDGE_EXTEND; k += 2) {
        int below = max(row - k - 1, 0);
        int above = min(row + 1 + k, SampleCount() - 2);
        SelectKey(GatherKeys(slice0, below), pixel_key, slice0, below,
            closest_distance, closest_scale, closest_texel);
        SelectKey(GatherKeys(slice0, above), pixel_key, slice0, above,
            closest_distance, closest_scale, closest_texel);
        if (closest_distance <= EPIPOLAR_DEPTH_TOLERANCE * closest_scale) break;
    }
    return closest_distance < 1e30 ? texelFetch(usam_epipolar_term, closest_texel, 0).rgb : fallback;
}

#endif // EPIPOLAR_ACTIVE
#endif // LIB_VOLUME_EPIPOLAR_CORE_GLSL
