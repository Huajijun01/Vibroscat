#ifndef LIB_LIGHTING_GTAO_GLSL
#define LIB_LIGHTING_GTAO_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/core/render_scale.glsl"
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
#include "/lib/atmosphere/sky_light.glsl"
#include "/lib/lighting/sky_visibility.glsl"
#endif

// ============================================================================
// GTAO - horizon-based ambient occlusion (Jimenez et al. 2016)
// ============================================================================
//
// Math contract. The AO integral
//   A(P) = (1/pi) integral_Omegan V(P,omega) <omega,n> domega
// is decomposed into azimuthal slices phi in [0,pi). On each half-slice,
// theta in [0,pi] measures the angle from the toward-camera axis v.
// The projected normal is a*cos(theta)+b*sin(theta), where a=<n,v>, b=<n,t>;
// retain its magnitude and the spherical Jacobian sin(theta). The primitive is
//   F(theta) = a*sin(theta)^2/2 + b*(theta/2 - sin(2*theta)/4).
// Integrate the blocked arc [h,pi], clipped to the positive normal hemisphere.
// Using the known open-hemisphere integral as a control variate gives
//   A = 1 - sum(blocked_positive + blocked_negative)/GTAO_SLICES.
// Open surfaces remain exactly one even with few slices; for n=v and equal
// horizon angles h on both sides, A=sin(h)^2. Normalizing the projected normal
// or dropping sin(theta) would change the spherical cosine integral.
//
// Horizon search conventions (validated against the height-field case that
// dominates Minecraft): the search inits fully open (cosine -1) and skips sky and
// same-surface samples, so open surfaces read exactly 1.0 for every normal
// tilt, while walls in front clamp the arc and produce contact darkening.
// Samples beyond the radius fade toward the open state (paper section4.3).
//
// Slice rotation is dithered per block and per frame with the STBN
// blue-noise texture (point-sampled); the pack's TAA converges the residual
// noise (STBN dithered, converged by TAA).
// ============================================================================


// Screen-space unit direction along the projected tangent and the pixel
// length of the full search radius (projection of GTAO_RADIUS). center_ndc is
// the caller's hoisted ViewToNDC(center_view).xy, loop-invariant across the
// slices; the expression matches the inlined form exactly.
vec2 ScreenDir(vec3 tangent_view, vec3 center_view, vec2 center_ndc, out float radius_px) {
    vec3 end_view = center_view + tangent_view * GTAO_RADIUS;
    vec2 end_ndc = ViewToNDC(end_view).xy;
    vec2 delta = (end_ndc - center_ndc) * 0.5 * u_render_res;
    // No screen-fraction cap: the search length is the projected radius.
    radius_px = max(length(delta), 1.0e-5);
    return delta / radius_px;
}

// Update one side with the original depth rejection and radius falloff.
float UpdateHorizon(vec2 sample_uv, float sample_depth, vec3 center_view,
                        float center_depth, vec3 view_axis, float horizon_cos) {
    if (sample_depth >= 1.0 || abs(sample_depth - center_depth) < 3.0e-7) {
        // Same surface: the height field below the pixel is its horizon,
        // not an occluder (else far blocky terrain reads grid-like steps).
        return horizon_cos;
    }
    vec3 sample_view = NDCToViewSparse(sample_uv * 2.0 - 1.0, sample_depth * 2.0 - 1.0);
    vec3 offset = sample_view - center_view;
    float offset_len_sq = dot(offset, offset);
    if (offset_len_sq < 1.0e-6) {
        return horizon_cos;
    }
    float inv_offset_len = inversesqrt(offset_len_sq);
    float offset_len = offset_len_sq * inv_offset_len;
    // Near-field fade (Jimenez section4.3): linear band [GTAO_FALLOFF_START*R, R]
    // applied to the sample cosine (no hard cut at the radius).
    float fade = clamp(
        (offset_len - GTAO_RADIUS * GTAO_FALLOFF_START)
            / max(GTAO_RADIUS * (1.0 - GTAO_FALLOFF_START), 1.0e-4),
        0.0, 1.0);
    float sample_cos = dot(view_axis, offset) * inv_offset_len * (1.0 - fade) - fade;
    return max(horizon_cos, sample_cos);
}

// March both sides at the same distance in one loop. Each side keeps its
// original screen-edge termination; leaving one edge never stops the other.
// Issue the independent depth reads together before consuming either result.
// Returns positive-side / negative-side cosines in [-1,1] (-1 = fully open).
vec2 SearchHorizons(vec2 center_uv, vec3 center_view, vec2 screen_dir,
                        float radius_px, float center_depth, vec3 view_axis,
                        float step_noise) {
    if (radius_px <= 2.0) {
        return vec2(-1.0);  // sub-2px radius: nothing resolvable
    }
    // The per-step uv delta is screen_dir scaled by a loop-invariant pixel
    // size; premultiply once and keep the loop on one vector multiply.
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

// Integral of max(a*cos(theta)+b*sin(theta),0)*sin(theta) on [acos(c),pi].
// a,b keep the projected normal's magnitude. The back-facing branch handles
// two-sided geometry whose positive normal interval wraps past pi.
float BlockedArc(float a, float b, float normal_angle, float inv_normal_length, float c) {
    if (a >= 0.0) {
        if (c <= -b * inv_normal_length) return 0.0;
        float h = acos(c);
        float s = sqrt(max(1.0 - c * c, 0.0));
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
// Combined GTAO and directional sky visibility at one receiver. ao is the raw
// geometric GTAO before strength and multibounce. open_sky is the full
// analytic EvalSkyLight at the shading normal; visible_sky is that irradiance
// with the L0/L1 sky field integrated over the same GTAO blocked arcs plus
// the blocked fraction applied to the L2 band of the same estimate, clamped
// to [0, open_sky] at the receiver only. Neither RGB output carries
// lightmap, SKY_AMBIENT_STRENGTH, material response or the ambient floor;
// ambient_light.glsl owns that composition.
struct GTAOSkyResult {
    float ao;
    vec3 open_sky;
    vec3 visible_sky;
};
#endif

// Screen-space GTAO at one receiver (full-res UV, pre-fetched depth and oct
// normal). stbn_noise is the SampleSTBNPair pair sampled by the pass main.
// Returns AO in [0,1]. With RSM_DIRECTIONAL_SKY_ACTIVE the same horizon
// search also integrates the raw L1 sky field over the blocked arcs: one
// SearchHorizons call per slice feeds both results, and the function returns
// the combined GTAOSkyResult.
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
        // sky: fully open
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
        return result;
#else
        return 1.0;
#endif
    }
    vec3 center_view = NDCToViewSparse(uv * 2.0 - 1.0, center_depth * 2.0 - 1.0);
    vec3 view_axis = normalize(-center_view);  // toward camera
    // colortex4 carries the world-space geometric normal; the slices are built
    // around the view axis, so the transform is paid once per pixel here. The
    // octahedral decode returns a unit vector and the camera rotation
    // preserves its length.
    vec3 normal_view = mat3(gbufferModelView)
        * DecodeOctahedralNormal(normal_oct);

    // The slice basis depends only on the toward-camera axis: slice_t/slice_b
    // are built once here and each slice rotates them (identical operations,
    // evaluated once).
    vec3 slice_up = abs(view_axis.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 slice_t = normalize(cross(slice_up, view_axis));
    vec3 slice_b = cross(view_axis, slice_t);
    float slice_angle_base = stbn_noise.x * PI;
    float ndotv = dot(normal_view, view_axis);
    // The center projection is identical for every slice; hoist the identical
    // expression out of the slice loop.
    vec2 center_ndc = ViewToNDC(center_view).xy;
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
    // Sky arcs evaluate the world-axis L1 field. The slice orbit rotates to
    // world once here; each slice assembles its polynomial and normal
    // projection from the orbit cos/sin without re-rotating its tangent.
    mat3 view_to_world = mat3(gbufferModelViewInverse);
    vec3 view_axis_world = view_to_world * view_axis;
    vec3 world_slice_t = view_to_world * slice_t;
    vec3 world_slice_b = view_to_world * slice_b;
    SkyLinearField sky_field = BuildSkyLinearField(view_axis_world,
        world_slice_t, world_slice_b);
    float sky_ndotv = dot(sky_normal_world, view_axis_world);
    float sky_ndott_t = dot(sky_normal_world, world_slice_t);
    float sky_ndott_b = dot(sky_normal_world, world_slice_b);
    // Hoisted before the slice loop: the same evaluation in the function
    // epilogue compiled into a far slower register allocation on this pass
    // (paired A/B: ~106 us vs ~9 us at GTAO_SLICES=2).
    vec3 sky_l2_blocked = EvalSkyLightL2(sky_normal_world);
    vec3 blocked_sky = vec3(0.0);
#endif
    // The slice tangents form one fixed-rotation orbit; a recurrence pair
    // replaces the per-slice cos/sin calls. The rotation runs before any
    // slice-level continue so every iteration advances the angle.
    float slice_cos = cos(slice_angle_base);
    float slice_sin = sin(slice_angle_base);
    const float slice_step_c = cos(PI / float(GTAO_SLICES));
    const float slice_step_s = sin(PI / float(GTAO_SLICES));
    float occlusion = 0.0;
    for (int s = 0; s < GTAO_SLICES; ++s) {
        // tangent = slice_t*cos + slice_b*sin stays unit and orthogonal to
        // view_axis up to ~1e-7 (slice_t/slice_b are an exact orthonormal
        // pair up to the same residual), and the slice plane consumes only
        // its direction.
        vec3 tangent = slice_t * slice_cos + slice_b * slice_sin;
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
        // The recurrence below advances (slice_cos, slice_sin) to the next
        // slice, so the sky terms must be assembled from this slice's angle:
        // the horizon search runs along `tangent`, built from the same
        // pre-advance values.
        float sky_ndott = slice_cos * sky_ndott_t + slice_sin * sky_ndott_b;
        vec3 sky_sin_term = slice_cos * sky_field.sin_term_t
            + slice_sin * sky_field.sin_term_b;
#endif
        float next_c = slice_cos * slice_step_c - slice_sin * slice_step_s;
        slice_sin = slice_sin * slice_step_c + slice_cos * slice_step_s;
        slice_cos = next_c;

        // Projected-normal angle in the slice plane.
        float ndott = dot(normal_view, tangent);
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
        // Skip the search only when the projection degenerates for both
        // normals: a normal-mapped sky normal can still carry sky energy in a
        // slice whose geometric projection is zero.
        bool geometric_arc_open = abs(ndott) + abs(ndotv) >= 1.0e-4;
        if (!geometric_arc_open && abs(sky_ndott) + abs(sky_ndotv) < 1.0e-4) {
            continue;
        }
#else
        if (abs(ndott) + abs(ndotv) < 1.0e-4) {
            continue;  // slice perpendicular to the normal_view: zero contribution
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
        // Open horizons (cosine -1) make both arcs empty; the pair shares
        // one atan and the RGB products across the two sides.
        if (horizons.x > -1.0 || horizons.y > -1.0) {
            SkyArcPolynomial sky_arc;
            sky_arc.constant_term = sky_field.constant_term;
            sky_arc.cos_term = sky_field.cos_term;
            sky_arc.sin_term = sky_sin_term;
            blocked_sky += IntegrateSkyBlockedArcPair(sky_arc, sky_ndotv,
                sky_ndott, horizons);
        }
#else
        occlusion += BlockedArc(ndotv, ndott, theta_n, inv_normal_length, horizons.x)
            + BlockedArc(ndotv, -ndott, -theta_n, inv_normal_length, horizons.y);
#endif
    }
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
    float blocked_fraction = occlusion / float(GTAO_SLICES);
    result.ao = clamp(1.0 - blocked_fraction, 0.0, 1.0);
    // Phi is uniform over [0, pi) across GTAO_SLICES slices, so the arc sum
    // becomes irradiance with the full PI/GTAO_SLICES measure (the scalar AO
    // normalization already folds AO's 1/pi into its own definition). The
    // clamp runs only here: arcs stay linear so raw SH negative lobes cancel
    // across slices instead of biasing each arc positive. The arcs carry the
    // L0/L1 field only; the blocked L2 share is the same cosine-weighted
    // blocked fraction the AO accumulates, applied to the L2 band of the
    // hemisphere estimate instead of a larger arc polynomial.
    result.visible_sky = clamp(result.open_sky
        - blocked_sky * (PI / float(GTAO_SLICES))
        - blocked_fraction * sky_l2_blocked,
        vec3(0.0), result.open_sky);
    return result;
#else
    return clamp(1.0 - occlusion / float(GTAO_SLICES), 0.0, 1.0);
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
