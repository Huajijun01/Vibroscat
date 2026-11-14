#ifndef LIB_LIGHTING_GTAO_GLSL
#define LIB_LIGHTING_GTAO_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/core/render_scale.glsl"
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/lighting/sky_visibility.glsl"

// GTAO (Jimenez et al. 2016): azimuthal slices integrate the cosine-weighted
// blocked arc against an open-hemisphere control variate, so open surfaces read 1.


// center_ndc: caller-provided hoisted ViewToNDC(center_view).xy.
vec2 ScreenDir(vec3 tangent_view, vec3 center_view, vec2 center_ndc, out float radius_px) {
    vec3 end_view = center_view + tangent_view * GTAO_RADIUS;
    vec2 end_ndc = ViewToNDC(end_view).xy;
    vec2 delta = (end_ndc - center_ndc) * 0.5 * u_render_res;
    // No screen-fraction cap: the search length is the projected radius.
    radius_px = max(length(delta), 1.0e-5);
    return delta / radius_px;
}

float UpdateHorizon(vec2 sample_uv, float sample_depth, vec3 center_view,
                        float center_depth, vec3 view_axis, float horizon_cos) {
    float result = horizon_cos;
    // Same-surface and sky samples do not update the horizon.
    if (!(sample_depth >= 1.0 || abs(sample_depth - center_depth) < 3.0e-7)) {
        vec3 sample_view = NDCToViewSparse(sample_uv * 2.0 - 1.0, sample_depth * 2.0 - 1.0);
        vec3 offset = sample_view - center_view;
        float offset_len_sq = dot(offset, offset);
        if (!(offset_len_sq < 1.0e-6)) {
            float inv_offset_len = inversesqrt(offset_len_sq);
            float offset_len = offset_len_sq * inv_offset_len;
            // Near-field fade (Jimenez section 4.3): linear band [GTAO_FALLOFF_START*R, R].
            float fade = saturate(
                (offset_len - GTAO_RADIUS * GTAO_FALLOFF_START)
                    / max(GTAO_RADIUS * (1.0 - GTAO_FALLOFF_START), 1.0e-4));
            float sample_cos = dot(view_axis, offset) * inv_offset_len * (1.0 - fade) - fade;
            result = max(horizon_cos, sample_cos);
        }
    }
    return result;
}

// Returns positive/negative cosines in [-1,1]; -1 = fully open.
vec2 SearchHorizons(vec2 center_uv, vec3 center_view, vec2 screen_dir,
                        float radius_px, float center_depth, vec3 view_axis,
                        float step_noise) {
    if (radius_px <= 2.0) {
        return vec2(-1.0);  // sub-2px radius: nothing resolvable
    }
    vec2 screen_dir_px = screen_dir * u_render_pixel_size;
    vec2 horizon_cos = vec2(-1.0);
    bool active_pos = true;
    bool active_neg = true;
    for (int i = 0; i < GTAO_HORIZON_STEPS; ++i) {
        float u = (float(i) + step_noise) / float(GTAO_HORIZON_STEPS);
        float dist_px = 1.0 + u * u * (radius_px - 1.0);
        vec2 sample_offset = screen_dir_px * dist_px;
        vec2 sample_uv_pos = center_uv + sample_offset;
        vec2 sample_uv_neg = center_uv - sample_offset;
        active_pos = active_pos && !any(lessThan(sample_uv_pos, vec2(0.0)))
            && !any(greaterThan(sample_uv_pos, vec2(1.0)));
        active_neg = active_neg && !any(lessThan(sample_uv_neg, vec2(0.0)))
            && !any(greaterThan(sample_uv_neg, vec2(1.0)));
        if (!active_pos && !active_neg) {
            break;
        }
        float sample_depth_pos = 1.0;
        float sample_depth_neg = 1.0;
        if (active_pos) {
#if defined(TAAU_ACTIVE)
            sample_depth_pos = texture(depthtex2, SceneTextureUV(sample_uv_pos)).r;
#else
            sample_depth_pos = texture(depthtex2, sample_uv_pos).r;
#endif
        }
        if (active_neg) {
#if defined(TAAU_ACTIVE)
            sample_depth_neg = texture(depthtex2, SceneTextureUV(sample_uv_neg)).r;
#else
            sample_depth_neg = texture(depthtex2, sample_uv_neg).r;
#endif
        }
        horizon_cos.x = UpdateHorizon(sample_uv_pos, sample_depth_pos,
            center_view, center_depth, view_axis, horizon_cos.x);
        horizon_cos.y = UpdateHorizon(sample_uv_neg, sample_depth_neg,
            center_view, center_depth, view_axis, horizon_cos.y);
    }
    return clamp(horizon_cos, vec2(-1.0), vec2(1.0));
}

// Integral of max(a*cos(t)+b*sin(t),0)*sin(t) over [acos(c),pi]; a,b keep the
// projected normal's magnitude. Back-facing branch covers interval wrap past pi.
float BlockedArc(float a, float b, float normal_angle, float inv_normal_length, float c) {
    if (a >= 0.0) {
        if (c <= -b * inv_normal_length) return 0.0;
        float h = acos(c);
        float s = sqrt(saturate(1.0 - c * c));
        return max(0.5 * (a * c * c
            + b * (normal_angle + PI * 0.5 - h + s * c)), 0.0);
    }
    float h = acos(c);
    if (normal_angle < -PI * 0.5) normal_angle += TAU;
    float lo = max(h, max(normal_angle - PI * 0.5, 0.0));
    float hi = min(normal_angle + PI * 0.5, PI);
    if (hi <= lo) return 0.0;
    float sin_lo = sin(lo);
    float sin_hi = sin(hi);
    return max(0.5 * a * (sin_hi * sin_hi - sin_lo * sin_lo)
        + b * (0.5 * (hi - lo) - 0.25 * (sin(2.0 * hi) - sin(2.0 * lo))), 0.0);
}

#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
// RGB outputs carry no lightmap/strength/floor composition; ambient_light.glsl
// owns that.
struct GTAOSkyResult {
    float ao;
    vec3 open_sky;
    vec3 visible_sky;
};
#endif

// AO in [0,1]; each slice's SearchHorizons call feeds both AO and sky visibility.
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
GTAOSkyResult ComputeGTAOSkyFromGeometry(vec2 uv, float center_depth,
        vec2 normal_oct, vec2 stbn_noise, vec3 sky_normal_world) {
    GTAOSkyResult result;
    result.ao = 1.0;
    result.open_sky = EvalSkyLight(sky_normal_world);
    result.visible_sky = result.open_sky;
#else
float ComputeGTAOFromGeometry(vec2 uv, float center_depth,
        vec2 normal_oct, vec2 stbn_noise) {
#endif
    if (center_depth >= 1.0) {
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
        return result;
#else
        return 1.0;
#endif
    }
    vec3 center_view = NDCToViewSparse(uv * 2.0 - 1.0, center_depth * 2.0 - 1.0);
    vec3 view_axis = normalize(-center_view);
    // colortex4 carries the world-space geometric normal; the decode returns a
    // unit vector and the camera rotation preserves its length.
    vec3 normal_view = mat3(gbufferModelView)
        * DecodeOctahedralNormal(normal_oct);

    vec3 slice_up = abs(view_axis.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 slice_t = normalize(cross(slice_up, view_axis));
    vec3 slice_b = cross(view_axis, slice_t);
    float slice_angle_base = stbn_noise.x * PI;
    float ndotv = dot(normal_view, view_axis);
    vec2 center_ndc = ViewToNDC(center_view).xy;
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
    // n dot (R*u) = (transpose(R)*n) dot u.
    vec3 sky_normal_view = transpose(mat3(gbufferModelViewInverse)) * sky_normal_world;
    float sky_ndotv = dot(sky_normal_view, view_axis);
    float sky_ndott_t = dot(sky_normal_view, slice_t);
    float sky_ndott_b = dot(sky_normal_view, slice_b);
    // Hoisted: this evaluation in the epilogue compiles to a far slower
    // register allocation on this pass.
    vec3 sky_l2_blocked = EvalSkyLightL2(sky_normal_world);
    vec4 blocked_moments = vec4(0.0);
#endif
    // The rotation must advance before any slice-level continue so every
    // iteration keeps its own angle.
    float slice_cos = cos(slice_angle_base);
    float slice_sin = sin(slice_angle_base);
    const float slice_step_c = cos(PI / float(GTAO_SLICES));
    const float slice_step_s = sin(PI / float(GTAO_SLICES));
    float occlusion = 0.0;
    for (int s = 0; s < GTAO_SLICES; ++s) {
        // tangent stays unit and orthogonal to view_axis up to ~1e-7; no
        // renormalization needed.
        vec3 tangent = slice_t * slice_cos + slice_b * slice_sin;
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
        // Snapshot before the recurrence advances; the moment accumulation
        // uses this slice's angle.
        vec2 sky_slice_orbit = vec2(slice_cos, slice_sin);
        float sky_ndott = dot(sky_slice_orbit, vec2(sky_ndott_t, sky_ndott_b));
#endif
        float next_c = slice_cos * slice_step_c - slice_sin * slice_step_s;
        slice_sin = slice_sin * slice_step_c + slice_cos * slice_step_s;
        slice_cos = next_c;

        float ndott = dot(normal_view, tangent);
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
        // Skip only when both projections degenerate: a normal-mapped sky
        // normal can still carry energy in a geometrically degenerate slice.
        bool geometric_arc_open = abs(ndott) + abs(ndotv) >= 1.0e-4;
        if (!geometric_arc_open && abs(sky_ndott) + abs(sky_ndotv) < 1.0e-4) {
            continue;
        }
#else
        if (abs(ndott) + abs(ndotv) < 1.0e-4) {
            continue;
        }
        float theta_n = atan(ndott, ndotv);
        float inv_normal_length = inversesqrt(ndott * ndott + ndotv * ndotv);
#endif

        vec2 screen_dir;
        float radius_px;
        screen_dir = ScreenDir(tangent, center_view, center_ndc, radius_px);

        vec2 horizons = SearchHorizons(uv, center_view, screen_dir, radius_px,
            center_depth, view_axis, stbn_noise.y);
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
        if (geometric_arc_open) {
            float theta_n = atan(ndott, ndotv);
            float inv_normal_length = inversesqrt(ndott * ndott + ndotv * ndotv);
            occlusion += BlockedArc(ndotv, ndott, theta_n, inv_normal_length, horizons.x)
                + BlockedArc(ndotv, -ndott, -theta_n, inv_normal_length, horizons.y);
        }
        if (horizons.x > -1.0 || horizons.y > -1.0) {
            vec3 arc_moments = IntegrateSkyBlockedArcPairMoments(sky_ndotv, sky_ndott, horizons);
            blocked_moments.xy += arc_moments.xy;
            blocked_moments.zw += arc_moments.z * sky_slice_orbit;
        }
#else
        occlusion += BlockedArc(ndotv, ndott, theta_n, inv_normal_length, horizons.x)
            + BlockedArc(ndotv, -ndott, -theta_n, inv_normal_length, horizons.y);
#endif
    }
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
    vec3 blocked_direction_view = view_axis * blocked_moments.y
        + slice_t * blocked_moments.z + slice_b * blocked_moments.w;
    vec3 blocked_sky = EvalSkyBlockedMoments(blocked_moments.x,
        mat3(gbufferModelViewInverse) * blocked_direction_view);
    float blocked_fraction = occlusion / float(GTAO_SLICES);
    result.ao = saturate(1.0 - blocked_fraction);
    // Clamp only here: arcs stay linear so raw SH negative lobes cancel across
    // slices instead of biasing each arc positive.
    result.visible_sky = clamp(result.open_sky
        - blocked_sky * (PI / float(GTAO_SLICES))
        - blocked_fraction * sky_l2_blocked,
        vec3(0.0), result.open_sky);
    return result;
#else
    return saturate(1.0 - occlusion / float(GTAO_SLICES));
#endif
}

#if !defined(RSM_DIRECTIONAL_SKY_ACTIVE)
// Entry point used by the recursive-GI pass.
float ComputeGTAO(vec2 uv, vec2 texel, vec2 stbn_noise) {
    ivec2 center_texel = ivec2(texel);
    float center_depth = texelFetch(depthtex2, center_texel, 0).r;
    if (center_depth >= 1.0) return 1.0;
    vec2 normal_oct = texelFetch(colortex4, center_texel, 0).xy;
    return ComputeGTAOFromGeometry(uv, center_depth, normal_oct, stbn_noise);
}
#endif

#endif // LIB_LIGHTING_GTAO_GLSL
