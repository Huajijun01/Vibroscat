#ifndef LIB_LIGHTING_GTAO_GLSL
#define LIB_LIGHTING_GTAO_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/core/render_scale.glsl"

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


// Per-block STBN: x = slice rotation, y = horizon-step dither. Point-sampled
// Slice-plane tangent at the block-dithered azimuth around the toward-camera
// axis: built once per pixel in ComputeGTAOFromGeometry (the basis depends
// only on view_axis) and rotated per slice below.

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
            sample_depth_pos = texture(depthtex2, SceneTextureUV(sample_uv_pos)).r;
        }
        if (active_neg) {
            sample_depth_neg = texture(depthtex2, SceneTextureUV(sample_uv_neg)).r;
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

// Screen-space GTAO at one receiver (full-res UV, pre-fetched depth and oct
// normal). stbn_noise is the SampleSTBNPair pair sampled by the pass main.
// Returns AO in [0,1].
float ComputeGTAOFromGeometry(vec2 uv, float center_depth, vec2 normal_oct, vec2 stbn_noise) {
    if (center_depth >= 1.0) {
        return 1.0;  // sky: fully open
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
    // The slice tangents form one fixed-rotation orbit; a recurrence pair
    // replaces the per-slice cos/sin calls. The rotation runs before any
    // slice-level continue so every iteration advances the angle.
    float slice_cos = cos(slice_angle_base);
    float slice_sin = sin(slice_angle_base);
    const float slice_step_c = cos(PI / float(GTAO_SLICES));
    const float slice_step_s = sin(PI / float(GTAO_SLICES));
    float occlusion = 0.0;
    for (int s = 0; s < GTAO_SLICES; ++s) {
        // tangent = slice_t*cos + slice_b*sin is already a unit vector
        // orthogonal to view_axis up to ~1e-7 (slice_t/slice_b are an exact
        // orthonormal pair up to the same residual), and the slice plane only
        // consumes its direction, so the old re-orthonormalization round trip
        // is redundant.
        vec3 tangent = slice_t * slice_cos + slice_b * slice_sin;
        float next_c = slice_cos * slice_step_c - slice_sin * slice_step_s;
        slice_sin = slice_sin * slice_step_c + slice_cos * slice_step_s;
        slice_cos = next_c;

        // Projected-normal angle in the slice plane.
        float ndott = dot(normal_view, tangent);
        if (abs(ndott) + abs(ndotv) < 1.0e-4) {
            continue;  // slice perpendicular to the normal_view: zero contribution
        }
        float theta_n = atan(ndott, ndotv);
        float inv_normal_length = inversesqrt(ndott * ndott + ndotv * ndotv);

        vec2 screen_dir;
        float radius_px;
        screen_dir = ScreenDir(tangent, center_view, center_ndc, radius_px);

        vec2 horizons = SearchHorizons(uv, center_view, screen_dir, radius_px,
            center_depth, view_axis, stbn_noise.y);
        occlusion += BlockedArc(ndotv, ndott, theta_n, inv_normal_length, horizons.x)
            + BlockedArc(ndotv, -ndott, -theta_n, inv_normal_length, horizons.y);
    }
    return clamp(1.0 - occlusion / float(GTAO_SLICES), 0.0, 1.0);
}

// Preserve the existing recursive-GI entry point.
float ComputeGTAO(vec2 uv, vec2 texel, vec2 stbn_noise) {
    ivec2 center_texel = ivec2(texel);
    float center_depth = texelFetch(depthtex2, center_texel, 0).r;
    if (center_depth >= 1.0) return 1.0;
    vec2 normal_oct = texelFetch(colortex4, center_texel, 0).xy;
    return ComputeGTAOFromGeometry(uv, center_depth, normal_oct, stbn_noise);
}

#endif // LIB_LIGHTING_GTAO_GLSL
