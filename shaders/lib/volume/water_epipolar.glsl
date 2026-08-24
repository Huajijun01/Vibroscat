#ifndef LIB_VOLUME_WATER_EPIPOLAR_GLSL
#define LIB_VOLUME_WATER_EPIPOLAR_GLSL

// Water-column epipolar helpers: column depth keys and the shadow-weighted
// direct-scattering ratio for the water medium. Depends on the medium-agnostic
// projection/unwarp from epipolar_core.glsl. Functions only; each includer
// declares its own uniforms (Iris injects the shared ones).

#include "/lib/contract/settings.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/volume/epipolar_core.glsl"
#include "/lib/core/coordinates.glsl"

#ifdef EPIPOLAR_WATER

// Linear-viewZ key of the water column for a screen texel (0 = no column).
// Above water the column ends at the opaque receiver (depthtex1); underwater
// it ends at the water surface (depthtex0), which is where the sun path
// enters the water. Linear depth keeps the unwarp tolerance scale-invariant
// (raw depth01 saturates at distance and mis-accepts columns at low
// epipolar resolution).
float EpipolarColumnKey(vec2 uv01, ivec2 texel) {
    if (isEyeInWater == 1) return EpipolarViewZ(uv01, texelFetch(depthtex0, texel, 0).r);
    if (texelFetch(colortex2, texel, 0).a < 0.99) return 0.0;
    return EpipolarViewZ(uv01, texelFetch(depthtex1, texel, 0).r);
}

// Water column segment for a screen texel, in camera-relative scene space.
// Returns false when the pixel has no water column (above water and nearest
// translucent is not water). column_key is the column end in LINEAR viewZ
// (same space as EpipolarColumnKey), 0 = no column.
bool EpipolarWaterSegment(ivec2 texel, vec2 uv01, out vec3 start_scene, out vec3 end_scene, out float column_key) {
    float opaque_depth = texelFetch(depthtex1, texel, 0).r;
    if (isEyeInWater == 1) {
        float surface_depth = texelFetch(depthtex0, texel, 0).r;
        start_scene = EyePositionSceneSpace(); // the eye, not the feet-space origin
        end_scene = EpipolarViewToScene(uv01, surface_depth);
        column_key = EpipolarViewZ(uv01, surface_depth);
        return true;
    }
    if (texelFetch(colortex2, texel, 0).a < 0.99) {
        column_key = 0.0;
        return false;
    }
    float surface_depth = texelFetch(depthtex0, texel, 0).r;
    start_scene = EpipolarViewToScene(uv01, surface_depth);
    end_scene = EpipolarViewToScene(uv01, opaque_depth);
    column_key = EpipolarViewZ(uv01, opaque_depth);
    return true;
}

// Shadow-weighted direct-scattering ratio: estimates the transmittance-
// weighted average shadow visibility along the column. The NUMERATOR is a
// Riemann sum of the render-pass integrand (exp(-extinction·(t+L(t)))) with
// per-step shadow; the DENOMINATOR is the analytic full-column integral in
// the SAME closed form the fragment fog uses (WaterScatteringIntegral,
// σs omitted — it cancels). Beyond the march cap the column is taken
// unshadowed analytically, so a shadowed near field darkens only the near
// part instead of zeroing the whole analytic fog (which integrates over the
// full ray length).
vec3 EpipolarShadowRatio(vec3 start_scene, vec3 end_scene, float light_path1, float light_path2,
                         vec3 extinction, ivec2 rand_coord) {
    // Interpolate in undistorted shadow clip space (the distortion is
    // nonlinear — mixing warped UVs would curve the march); re-apply
    // distortion + protected depth per step.
    vec3 s = ProjectToShadowClip(start_scene);
    vec3 e = ProjectToShadowClip(end_scene);
    vec3 diff = end_scene - start_scene;
    float S_full = length(diff);
    if (S_full < 1e-4) return vec3(1.0);
    float lp2_full = light_path2; // full-column end (the fragment fog uses this)
    // March-distance cap: clamp the marched interval to
    // WATER_EPIPOLAR_MAX_DISTANCE; endpoint and marched light path rescale
    // with it (light path is linear in t).
    float S = min(S_full, WATER_EPIPOLAR_MAX_DISTANCE);
    float scale = S / S_full;
    if (scale < 1.0) {
        e = ProjectToShadowClip(start_scene + diff * scale);
        light_path2 = light_path1 + (light_path2 - light_path1) * scale;
    }
    float d_l = light_path2 - light_path1;
    // Importance sampling: steps placed so the max-channel transmittance
    // decays arithmetically (inverse-CDF of the exponential attenuation),
    // concentrating samples where the scattering weight is large.
    float seg_optical = S + d_l; // per-channel optical depth = extinction * segOptical
    vec3 t_end_vec = exp(-extinction * seg_optical);
    float t_end = max(max(t_end_vec.r, t_end_vec.g), t_end_vec.b);
    float tau = -log(max(t_end, 1e-6));
    bool uniform_steps = abs(seg_optical) < 1e-3 || abs(tau) < 1e-3;
    // Without TAA, only spatial blue noise dithers the slice, so it would
    // shimmer (no temporal accumulation to hide it).
#ifdef TAA
    float jitter = SampleSTBN(rand_coord, frameCounter);
#else
    float jitter = SampleSTBN(rand_coord, 0);
#endif
    vec3 num = vec3(0.0);
    float inv_steps = 1.0 / float(EPIPOLAR_SHADOW_STEPS);
    for (int k = 0; k < EPIPOLAR_SHADOW_STEPS; ++k) {
        float p = (float(k) + jitter) * inv_steps;
        float t_sample = 1.0 + p * (t_end - 1.0); // arithmetic transmittance decay
        float u;
        float du;
        if (uniform_steps) {
            u = p;
            du = inv_steps;
        } else {
            u = -log(max(t_sample, 1e-6)) / tau;
            u = clamp(u, 0.0, 1.0);
            // Jacobian of the inverse CDF: du/dp = (1-t_end)/(tau·t_sample),
            // so the Riemann cell width in t is S·du.
            du = (1.0 - t_end) / (tau * max(t_sample, 1e-6)) * inv_steps;
        }
        vec3 clip = mix(s, e, u);
        vec2 uv = clip.xy / GetDistortFactor(clip.xy) * 0.5 + 0.5;
        float depth = ProtectShadowDepth(clip.z * 0.5 + 0.5);
        float shadow = texture(shadowtex1, vec3(uv, depth));
        float light_path = light_path1 + d_l * u;
        vec3 weight = exp(-extinction * (u * S + light_path));
        num += weight * shadow * (S * du);
    }

    // Analytic full-column denominator, same closed form as
    // WaterScatteringIntegral with σs omitted: integral of
    // exp(-ext·(t + L(t))) over [0, S_full], L linear light_path1 → lp2_full.
    float delta_full = lp2_full - light_path1 + S_full;
    vec3 den;
    if (abs(delta_full) < 1.0e-3 * max(S_full, light_path1 + lp2_full + 1.0)) {
        den = S_full * exp(-extinction * light_path1);
    } else {
        den = S_full * (exp(-extinction * light_path1) - exp(-extinction * (lp2_full + S_full)))
            / max(extinction * delta_full, vec3(1e-6));
    }

    // Unshadowed analytic tail beyond the cap: integral over [S, S_full]
    // with V = 1, same closed form (L(S) = light_path1 + d_l_full·scale).
    float lp_at_cap = light_path1 + (lp2_full - light_path1) * scale;
    float tail_len = S_full - S;
    float delta_tail = lp2_full - lp_at_cap + tail_len;
    vec3 tail;
    if (tail_len < 1e-6 || abs(delta_tail) < 1.0e-3 * max(tail_len, lp_at_cap + lp2_full + 1.0)) {
        tail = tail_len * exp(-extinction * (lp_at_cap + S));
    } else {
        tail = tail_len * (exp(-extinction * (lp_at_cap + S)) - exp(-extinction * (lp2_full + S_full)))
            / max(extinction * delta_tail, vec3(1e-6));
    }

    return Saturate((num + tail) / max(den, vec3(1e-6)));
}

#endif // EPIPOLAR_WATER
#endif // LIB_VOLUME_WATER_EPIPOLAR_GLSL
