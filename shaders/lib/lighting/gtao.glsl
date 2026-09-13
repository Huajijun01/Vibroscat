#ifndef LIB_LIGHTING_GTAO_GLSL
#define LIB_LIGHTING_GTAO_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/core/packing.glsl"

// ============================================================================
// GTAO - horizon-based ambient occlusion (Jimenez et al. 2016)
// ============================================================================
//
// Math contract. The AO integral
//   A(P) = (1/pi) integral_Omegan V(P,omega) <omega,n> domega
// is decomposed per azimuthal slice (Fubini). In the slice plane, directions
// are parametrized by the angle theta from the toward-camera axis v, the normal
// projects to thetan = atan2(<n,t>, <n,v>), and the visible arc is bounded by
// the horizon angles h1,h2 found by marching the projected radius through
// the depth buffer. Clamping to the cosine-positive hemisphere of n and
// integrating exactly gives, per slice,
//   I(phi) = sin(thetahi - thetan) - sin(thetalo - thetan),
//   thetalo = max(h1, thetan - pi/2),   thetahi = min(h2, thetan + pi/2),
// and A(P) = (1/2S) Sigma_s I(phi_s) (open space: I = 2, A = 1; fully occluded:
// thetahi <= thetalo, I = 0).
//
// Horizon search conventions (validated against the height-field case that
// dominates Minecraft): the search inits fully open at +/-pi and skips sky and
// same-surface samples, so open surfaces read exactly 1.0 for every normal
// tilt, while walls in front clamp the arc and produce contact darkening.
// Samples beyond the radius fade toward the open state (paper section4.3).
//
// Slice rotation is dithered per block and per frame with the STBN
// blue-noise texture (point-sampled); the pack's TAA converges the residual
// noise (STBN dithered, converged by TAA).
// ============================================================================


// Per-block STBN: x = slice rotation, y = horizon-step dither. Point-sampled
// Slice-plane tangent at azimuth `angle` around the toward-camera axis.
vec3 GTAOSliceTangent(vec3 view_axis, float angle) {
    vec3 up = abs(view_axis.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 t = normalize(cross(up, view_axis));
    vec3 b = cross(view_axis, t);
    return t * cos(angle) + b * sin(angle);
}

// Screen-space unit direction along the projected tangent and the pixel
// length of the full search radius (projection of GTAO_RADIUS).
vec2 GTAOScreenDir(vec3 tangent_view, vec3 center_view, out float radius_px) {
    vec3 end_view = center_view + tangent_view * GTAO_RADIUS;
    vec2 end_ndc = ViewToNDC(end_view).xy;
    vec2 center_ndc = ViewToNDC(center_view).xy;
    vec2 delta = (end_ndc - center_ndc) * 0.5 * vec2(viewWidth, viewHeight);
    radius_px = max(length(delta), 1.0e-5);
    return delta / radius_px;
}

// March one horizon direction; returns the horizon angle in [0, pi] (acos of
// the max sample cosine; init pi = fully open). Steps dense near the pixel,
// quadratic spread, per-pixel dither.
float GTAOSearchHorizon(vec2 center_uv, vec3 center_view, vec2 screen_dir,
                        float radius_px, float center_depth, vec3 view_axis,
                        float step_noise) {
    if (radius_px <= 2.0) {
        return PI;  // sub-2px radius: nothing resolvable
    }
    float horizon_cos = -1.0;
    for (int i = 0; i < GTAO_HORIZON_STEPS; ++i) {
        float u = (float(i) + step_noise) / float(GTAO_HORIZON_STEPS);
        float dist_px = 1.0 + u * u * (radius_px - 1.0);
        vec2 sample_uv = center_uv + screen_dir * (dist_px * u_view_pixel_size);
        if (any(lessThan(sample_uv, vec2(0.0)))
                || any(greaterThan(sample_uv, vec2(1.0)))) {
            break;
        }
        // Clamp the 1.0 edge (the integer texel would be out of bounds).
        ivec2 sample_texel = ivec2(clamp(sample_uv, vec2(0.0), vec2(1.0) - 1.0e-5)
            * vec2(viewWidth, viewHeight));
        float sample_depth = texelFetch(depthtex2, sample_texel, 0).r;
        if (sample_depth >= 1.0) {
            continue;  // sky: not an occluder
        }
        if (abs(sample_depth - center_depth) < 3.0e-7) {
            // Same surface: the height field below the pixel is its horizon,
            // not an occluder (else far blocky terrain reads grid-like steps).
            continue;
        }
        vec3 sample_view = NDCToView(vec3(sample_uv * 2.0 - 1.0, sample_depth * 2.0 - 1.0));
        vec3 offset = sample_view - center_view;
        float offset_len = length(offset);
        if (offset_len < 1.0e-3) {
            continue;
        }
        // Near-field fade (Jimenez section4.3): linear band [FALLOFF_START*R, R]
        // applied to the sample cosine (no hard cut at the radius).
        float fade = clamp(
            (offset_len - GTAO_RADIUS * GTAO_FALLOFF_START)
                / max(GTAO_RADIUS * (1.0 - GTAO_FALLOFF_START), 1.0e-4),
            0.0, 1.0);
        float sample_cos = dot(view_axis, offset / offset_len) * (1.0 - fade) - fade;
        horizon_cos = max(horizon_cos, sample_cos);
    }
    return acos(clamp(horizon_cos, -1.0, 1.0));
}

// Screen-space GTAO at one pixel (full-res UV and texel). stbn_noise is the
// SampleSTBNPair pair sampled by the pass main. Returns AO in [0,1].
float ComputeGTAO(vec2 uv, vec2 texel, vec2 stbn_noise) {
    ivec2 center_texel = ivec2(texel);
    float center_depth = texelFetch(depthtex2, center_texel, 0).r;
    if (center_depth >= 1.0) {
        return 1.0;  // sky: fully open
    }
    vec3 center_view = NDCToView(vec3(uv * 2.0 - 1.0, center_depth * 2.0 - 1.0));
    vec3 view_axis = normalize(-center_view);  // toward camera
    vec4 geometry_data = texelFetch(colortex4, center_texel, 0);
    // colortex4 carries the world-space geometric normal; the slices are built
    // around the view axis, so the transform is paid once per pixel here.
    vec3 normal_view = normalize(mat3(gbufferModelView)
        * DecodeOctahedralNormal(geometry_data.xy));

    float slice_angle_base = stbn_noise.x * PI;
    float ndotv = dot(normal_view, view_axis);
    float visibility = 0.0;
    for (int s = 0; s < GTAO_SLICES; ++s) {
        float slice_angle = slice_angle_base
            + PI * float(s) / float(GTAO_SLICES);
        vec3 tangent = GTAOSliceTangent(view_axis, slice_angle);
        vec3 binormal = normalize(cross(view_axis, tangent));
        tangent = normalize(cross(binormal, view_axis));

        // Projected-normal angle in the slice plane.
        float ndott = dot(normal_view, tangent);
        if (abs(ndott) + abs(ndotv) < 1.0e-4) {
            continue;  // slice perpendicular to the normal_view: zero contribution
        }
        float theta_n = atan(ndott, ndotv);

        vec2 screen_dir;
        float radius_px;
        screen_dir = GTAOScreenDir(tangent, center_view, radius_px);

        float h_pos = GTAOSearchHorizon(uv, center_view, screen_dir, radius_px,
            center_depth, view_axis, stbn_noise.y);
        float h_neg = -GTAOSearchHorizon(uv, center_view, -screen_dir, radius_px,
            center_depth, view_axis, stbn_noise.y);

        // Clamp the visible arc to the cosine-positive hemisphere of n and
        // integrate exactly.
        float theta_lo = max(h_neg, theta_n - PI * 0.5);
        float theta_hi = min(h_pos, theta_n + PI * 0.5);
        if (theta_hi > theta_lo) {
            visibility += sin(theta_hi - theta_n) - sin(theta_lo - theta_n);
        }
    }
    return clamp(visibility / (2.0 * float(GTAO_SLICES)), 0.0, 1.0);
}

#endif // LIB_LIGHTING_GTAO_GLSL
