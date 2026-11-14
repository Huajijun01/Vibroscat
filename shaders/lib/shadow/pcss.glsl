#ifndef LIB_SHADOW_PCSS_GLSL
#define LIB_SHADOW_PCSS_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"

// Percentage-Closer Soft Shadows: R. Fernando, "Percentage-closer soft
// shadows", SIGGRAPH 2005. Blocker search (shadowtex0), PCF on shadowtex1.

// Golden-angle rotation; const-initializer trig folds at compile time.
const mat2 SHADOW_DISK_STEP = mat2(cos(2.39996323), sin(2.39996323),
    -sin(2.39996323), cos(2.39996323));

// Advances the Vogel disk: radius_sq walks (i+0.5)/count in squared units for
// equal annulus area.
vec2 ShadowDiskOffset(inout vec2 dir, inout float radius_sq, float inv_count) {
    vec2 offset = (radius_sq * inversesqrt(radius_sq)) * dir;
    dir = SHADOW_DISK_STEP * dir;
    radius_sq += inv_count;
    return offset;
}

// Local texel -> undistorted clip scale, for PCF sample budgeting only;
// physical radii stay in world meters.
vec2 ShadowFilterTexelScale(vec3 clip_pos) {
    // uv = clip / (2*factor) + 0.5, factor = (1-D) + D*|clip|; the local
    // derivative inverts to 2*factor^2/(1-D) clip units per UV unit.
    vec2 factor = GetDistortFactor(clip_pos.xy);
    return 2.0 * factor * factor / (1.0 - DISTORT_FACTOR) / real_shadow_map_resolution;
}

// Depth gradient per undistorted clip XY, from the shadow-view plane
// n.x*dx + n.y*dy + n.z*dz = 0; sign preserved for two-sided foliage.
vec2 ShadowReceiverGradient(vec3 normal_world) {
    vec3 normal_shadow = mat3(shadowModelView) * normal_world;
    float normal_z = normal_shadow.z < 0.0
        ? min(normal_shadow.z, -0.05) : max(normal_shadow.z, 0.05);
    return (-0.5 * SHADOW_DEPTH_SCALE * shadowProjection[2].z) * normal_shadow.xy
        / (normal_z * u_shadow_projection_xy);
}

// Max depth decrease across the texel footprint: inverting the distortion map
// gives the exact outward span for r texels; pass the disk's largest |clip|.
float ShadowReceiverBias(vec2 clip_extent, vec2 depth_gradient, float texel_radius) {
    vec2 factor = GetDistortFactor(clip_extent);
    vec2 clip_span = 2.0 * texel_radius * factor * factor
        / ((1.0 - DISTORT_FACTOR) * real_shadow_map_resolution
        - 2.0 * texel_radius * DISTORT_FACTOR * factor);
    // 1 cm covers reconstruction/rasterization mismatch; 2*24-bit depth steps
    // cover storage/comparison rounding. Not a triangle-interpolation bound.
    const float RESIDUAL_BIAS_M = 0.01;
    const float DEPTH_ROUNDING_BIAS = 2.0 / 16777216.0;
    return dot(abs(depth_gradient), clip_span)
        + ShadowDepthGapFromWorld(RESIDUAL_BIAS_M) + DEPTH_ROUNDING_BIAS;
}

// dir is the tap-0 disk direction; the walk is local to this call.
bool ShadowFindBlocker(vec3 sp, vec3 clip_pos, vec2 projection_scale, vec2 depth_gradient,
    vec2 dir, int blocker_steps, out float blocker_depth) {
    // Convex corners project small false depth deltas; require a world-space
    // gap before counting a blocker (no corner darkening).
    float blocker_bias = ShadowDepthGapFromWorld(SHADOW_BLOCKER_DEPTH_TOLERANCE_M);
    vec2 blocker_offset_scale = SHADOW_BLOCKER_SEARCH_RADIUS * projection_scale;
    // Nearest depth fetches leave at most half a texel unresolved per axis.
    blocker_bias += ShadowReceiverBias(abs(clip_pos.xy) + blocker_offset_scale, depth_gradient, 0.5);

    // The gap is divided by the tap count, not the occluder count: one stray
    // occluder cannot widen the penumbra to its full depth gap alone.
    float delta_sum = 0.0;
    float weight_sum = 0.0;
    ivec2 shadow_size = ivec2(shadowMapResolution);
    vec2 shadow_size_f = vec2(shadow_size);
    float inv_steps = 1.0 / float(blocker_steps);
    float radius_sq = 0.5 * inv_steps;
    for (int i = 0; i < blocker_steps; ++i) {
        vec2 offset = blocker_offset_scale * ShadowDiskOffset(dir, radius_sq, inv_steps);
        vec2 uv = DistortShadowClip(clip_pos.xy + offset);
        ivec2 sample_texel = clamp(ivec2(uv * shadow_size_f), ivec2(0), shadow_size - 1);
        float shadow_depth = texelFetch(shadowtex0, sample_texel, 0).x;
        // Transport each blocker to the receiver plane first; slopes must not
        // become penumbrae.
        shadow_depth -= dot(depth_gradient, offset);
        float w = step(shadow_depth, sp.z - blocker_bias);
        delta_sum += w * (sp.z - shadow_depth);
        weight_sum += w;
    }

    if (weight_sum < 0.5) {
        blocker_depth = 0.0;
        return false;
    }
    blocker_depth = sp.z - delta_sum * inv_steps;
    return true;
}

// LOW-tier filter (SHADOW_PCSS off): single hardware-bilinear PCF lookup, no
// blocker search. sp is unbiased protected shadow UV/depth in [0,1]^3.
float ShadowFilterHardwarePCF(vec3 sp, vec3 clip_pos, vec2 depth_gradient) {
    // The caller (deferred_shading) gates sp into [0,1]^3 before calling.
    sp.z -= ShadowReceiverBias(abs(clip_pos.xy), depth_gradient, 1.0);
    return texture(shadowtex1, sp);
}

// Plants keep their full sample budget and a small class-based cutout footprint.
float ShadowFilterPCSS(vec3 sp, vec3 clip_pos, vec2 depth_gradient, float stbn_dither,
    bool plant_receiver, float ndotl, float footprint_radius_m, out float sss_depth) {
    float angle = stbn_dither * TAU;
    vec2 dir = vec2(cos(angle), sin(angle));
    vec2 projection_scale = abs(u_shadow_projection_xy);

    float blocker_depth;
    bool blocker_found = ShadowFindBlocker(sp, clip_pos, projection_scale, depth_gradient,
        dir, SHADOW_BLOCKER_SAMPLES, blocker_depth);
    float depth_delta = blocker_found ? saturate(sp.z - blocker_depth) : 0.0;
    float world_depth_gap = ShadowDepthGapToWorld(depth_delta);
    // Half the coverage-weighted world separation, in the tissue model's
    // transport units.
    sss_depth = 0.5 * world_depth_gap;
    if (!blocker_found && !plant_receiver) {
        return 1.0;
    }

    // Thin foliage can transmit from the back side and needs real visibility.
    if (ndotl < 1.0e-3 && !plant_receiver) {
        return 0.0;
    }

    // World-space penumbra: small-angle radius = gap * angular radius; XY
    // distortion must not change its size.
    float penumbra_radius_m = world_depth_gap * SHADOW_SUN_ANGULAR_RADIUS;
    // World-space cap keeps one maximum across positions/resolutions; the
    // footprint minimum wins if the controls overlap.
    float max_penumbra_radius_m = SHADOW_BLOCKER_SEARCH_RADIUS
        * (1.0 + SHADOW_PENUMBRA_CAP_BOOST);
    max_penumbra_radius_m = max(max_penumbra_radius_m, footprint_radius_m);
    penumbra_radius_m = clamp(penumbra_radius_m, footprint_radius_m, max_penumbra_radius_m);
    vec2 filter_offset_scale = penumbra_radius_m * projection_scale;

    // Sample budget from the local texel footprint; the physical disk is
    // unchanged and hardware bilinear PCF filters subtexel.
    vec2 filter_radius_texels = filter_offset_scale / ShadowFilterTexelScale(clip_pos);
    float penumbra_texels = max(filter_radius_texels.x, filter_radius_texels.y);
    // Ordered bounds: the sliders may be set either way round and clamp() is
    // undefined for minVal > maxVal.
    int step_count = clamp(int(SHADOW_PCF_MIN_SAMPLES + SHADOW_PCF_GAIN * penumbra_texels),
        min(SHADOW_PCF_MIN_SAMPLES, SHADOW_PCF_MAX_SAMPLES),
        max(SHADOW_PCF_MIN_SAMPLES, SHADOW_PCF_MAX_SAMPLES));
    if (plant_receiver) step_count = SHADOW_SSS_STEPS;

    // HW PCF may compare a texel center almost one texel away; the disk itself
    // is handled by the signed plane correction below, so no radius-sized bias.
    float receiver_depth = sp.z
        - ShadowReceiverBias(abs(clip_pos.xy) + filter_offset_scale, depth_gradient, 1.0);
    float shadow = 0.0;
    int early_samples = min(4, step_count);
    float inv_pcf = 1.0 / float(step_count);
    float radius_sq = 0.5 * inv_pcf;
    for (int i = 0; i < early_samples; ++i) {
        vec2 offset = filter_offset_scale * ShadowDiskOffset(dir, radius_sq, inv_pcf);
        vec2 uv = clamp(DistortShadowClip(clip_pos.xy + offset), vec2(0.0), vec2(1.0));
        shadow += texture(shadowtex1, vec3(uv, receiver_depth + dot(depth_gradient, offset)));
    }
    // Plants complete their smaller budget so partial visibility is not
    // rounded to black/white.
    if (step_count > 4) {
        if (!plant_receiver && shadow < 0.5) {
            return 0.0;
        }
        if (!plant_receiver && shadow > 3.5) {
            return 1.0;
        }
        for (int i = 4; i < step_count; ++i) {
            vec2 offset = filter_offset_scale * ShadowDiskOffset(dir, radius_sq, inv_pcf);
            vec2 uv = saturate(DistortShadowClip(clip_pos.xy + offset));
            shadow += texture(shadowtex1, vec3(uv, receiver_depth + dot(depth_gradient, offset)));
        }
    }
    shadow *= 1.0 / float(step_count);
    return shadow;
}

#endif // LIB_SHADOW_PCSS_GLSL
