#ifndef LIB_SHADOW_PCSS_GLSL
#define LIB_SHADOW_PCSS_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"

// Percentage-Closer Soft Shadows.
//
// Framework: R. Fernando, "Percentage-closer soft shadows", ACM SIGGRAPH 2005
// Sketches: 1) blocker search (shadowtex0); 2) penumbra estimate from the
// receiver/blocker depth ratio; 3) PCF filtering with that radius
// (shadowtex1, HW PCF).
// Samples: golden-angle (Vogel) disk - equal-area stratified radii whose
// direction advances by one constant rotation per tap, started from the
// shared STBN rotation.

// ---- Golden-angle disk sampling ----

// Golden-angle rotation between consecutive taps. Literal-argument trig in
// a const initializer folds at compile time, so each tap costs one 2x2
// multiply instead of a sincos pair.
const mat2 SHADOW_DISK_STEP = mat2(cos(2.39996323), sin(2.39996323),
    -sin(2.39996323), cos(2.39996323));

// Offset of the current tap, then advance to the next. dir starts as the
// STBN-rotated first direction; radius_sq walks (i + 0.5) / count in
// squared-radius units, which gives every tap equal annulus area.
vec2 ShadowDiskOffset(inout vec2 dir, inout float radius_sq, float inv_count) {
    vec2 offset = (radius_sq * inversesqrt(radius_sq)) * dir;
    dir = SHADOW_DISK_STEP * dir;
    radius_sq += inv_count;
    return offset;
}

// Local texel -> undistorted clip scale, used only to budget PCF samples.
// Physical search and filter radii are projected directly from world meters.
vec2 ShadowFilterTexelScale(vec3 clip_pos) {
    // The distorted UV map is
    //   uv = clip / (2*factor) + 0.5,  factor = (1-D) + D*|clip|,
    // whose local derivative is d(uv)/d(clip) = (1-D)/(2*factor^2), so the
    // inverse per-axis scale is 2*factor^2/(1-D) clip units per UV unit.
    vec2 factor = GetDistortFactor(clip_pos.xy);
    return 2.0 * factor * factor / (1.0 - DISTORT_FACTOR) / real_shadow_map_resolution;
}

// Protected depth gradient per undistorted clip XY. The geometric plane is
// n.x*dx + n.y*dy + n.z*dz = 0 in shadow-view space. Preserve its sign for
// two-sided foliage; near edge-on planes need a bounded extrapolation.
vec2 ShadowReceiverGradient(vec3 normal_world) {
    vec3 normal_shadow = mat3(shadowModelView) * normal_world;
    float normal_z = normal_shadow.z < 0.0
        ? min(normal_shadow.z, -0.05) : max(normal_shadow.z, 0.05);
    return (-0.5 * SHADOW_DEPTH_SCALE * shadowProjection[2].z) * normal_shadow.xy
        / (normal_z * u_shadow_projection_xy);
}

// Maximum depth decrease across the unresolved texel footprint. Inverting
// u = 0.5 + c/(2*f), f = 1-D+D*abs(c), gives the exact outward span
// dx = 2*r*f^2 / ((1-D)*N - 2*r*D*f), where r is measured in texels.
// Use the largest |clip| reached by the disk to bound every tap once.
float ShadowReceiverBias(vec2 clip_extent, vec2 depth_gradient, float texel_radius) {
    vec2 factor = GetDistortFactor(clip_extent);
    vec2 clip_span = 2.0 * texel_radius * factor * factor
        / ((1.0 - DISTORT_FACTOR) * real_shadow_map_resolution
        - 2.0 * texel_radius * DISTORT_FACTOR * factor);
    // One centimeter covers small reconstruction/rasterization mismatches;
    // two 24-bit depth steps cover storage/comparison rounding independently
    // of the XY warp. This residual is not a triangle-interpolation bound.
    const float RESIDUAL_BIAS_M = 0.01;
    const float DEPTH_ROUNDING_BIAS = 2.0 / 16777216.0;
    return dot(abs(depth_gradient), clip_span)
        + ShadowDepthGapFromWorld(RESIDUAL_BIAS_M) + DEPTH_ROUNDING_BIAS;
}

// Step 1: blocker search. Accumulates the receiver depth gap of shadow-map
// samples that occlude the receiver (depth <= receiver depth). Returns false
// when no blocker is found in the search disk, so the pixel can be treated
// as lit. dir is the tap-0 disk direction; the walk is local to this call.
bool ShadowFindBlocker(vec3 sp, vec3 clip_pos, vec2 projection_scale, vec2 depth_gradient,
    vec2 dir, int blocker_steps, out float blocker_depth) {
    // Convex corners project small false depth deltas; require a
    // world-space gap before counting a blocker (no corner darkening).
    float blocker_bias = ShadowDepthGapFromWorld(SHADOW_BLOCKER_DEPTH_TOLERANCE_M);
    vec2 blocker_offset_scale = SHADOW_BLOCKER_SEARCH_RADIUS * projection_scale;
    // Nearest depth fetches leave at most half a texel unresolved per axis.
    blocker_bias += ShadowReceiverBias(abs(clip_pos.xy) + blocker_offset_scale, depth_gradient, 0.5);

    // The gap is summed over every tap but divided by the tap count, not the
    // occluder count, so one stray occluder cannot widen the penumbra to its
    // full depth gap alone.
    float delta_sum = 0.0;
    float weight_sum = 0.0;
    ivec2 shadow_size = ivec2(shadowMapResolution);
    // The texel-to-UV scale is loop-invariant; carry it as a float vector so
    // each tap trades an int->float conversion of the resolution for a mul.
    vec2 shadow_size_f = vec2(shadow_size);
    float inv_steps = 1.0 / float(blocker_steps);
    float radius_sq = 0.5 * inv_steps;
    for (int i = 0; i < blocker_steps; ++i) {
        vec2 offset = blocker_offset_scale * ShadowDiskOffset(dir, radius_sq, inv_steps);
        vec2 uv = DistortShadowClip(clip_pos.xy + offset);
        ivec2 sample_texel = clamp(ivec2(uv * shadow_size_f), ivec2(0), shadow_size - 1);
        float shadow_depth = texelFetch(shadowtex0, sample_texel, 0).x;
        // Transport each blocker to the center receiver plane before both
        // classification and gap averaging; slopes must not become penumbrae.
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

// LOW-tier filter (SHADOW_PCSS off): single hardware-bilinear PCF lookup,
// no penumbra estimation or blocker search. Plant transmission shares this
// visibility and retains its depth-only screen attenuation.
// sp is unbiased protected shadow UV/depth in [0,1]^3.
float ShadowFilterHardwarePCF(vec3 sp, vec3 clip_pos, vec2 depth_gradient) {
    // The caller (deferred_shading) gates sp into [0,1]^3 before calling.
    sp.z -= ShadowReceiverBias(abs(clip_pos.xy), depth_gradient, 1.0);
    return texture(shadowtex1, sp);
}

// Full PCSS filter.
//   sp        - unbiased protected shadow UV/depth [0,1]^3
//   clip_pos  - undistorted shadow clip space [-1,1]^3
//   stbn_dither - STBN dither sampled by the pass main (serves the blocker
//               search and the PCF pass with one coherent rotation)
//   sss_amount  - receiver translucency; controls plant softness/sample budget
//   ndotl       - clamped surface dot(light); only opaque backfaces exit early
//   leaf_receiver - leaf cubes need a world-space diffusion footprint, kept
//               after an empty blocker search
float ShadowFilterPCSS(vec3 sp, vec3 clip_pos, vec2 depth_gradient, float stbn_dither,
    float sss_amount, float ndotl, bool leaf_receiver) {
    // The caller (deferred_shading) gates sp into [0,1]^3 before calling.
    // One dither value + first direction serves both passes. The orthographic
    // XY scale projects their world-space disks before each sample is warped.
    float angle = stbn_dither * TAU;
    vec2 dir = vec2(cos(angle), sin(angle));
    vec2 projection_scale = abs(u_shadow_projection_xy);

    float blocker_depth;
    bool blocker_found = ShadowFindBlocker(sp, clip_pos, projection_scale, depth_gradient,
        dir, SHADOW_BLOCKER_SAMPLES, blocker_depth);
    if (!blocker_found && !(leaf_receiver && sss_amount > 0.01)) {
        return 1.0;
    }

    // Thin foliage can transmit from the back side and needs real visibility.
    if (ndotl < 1.0e-3 && sss_amount <= 0.01) {
        return 0.0;
    }

    // Step 2: world-space penumbra, using the small-angle approximation
    // radius = gap * angular radius. XY distortion must not change its size.
    float depth_delta = blocker_found ? saturate(sp.z - blocker_depth) : 0.0;
    float world_depth_gap = ShadowDepthGapToWorld(depth_delta);
    float penumbra_radius_m = world_depth_gap * SHADOW_SUN_ANGULAR_RADIUS;
    // SSS foliage scatters through a wider penumbra.
    penumbra_radius_m *= 1.0 + SHADOW_SSS_PENUMBRA_BOOST * sss_amount;
    // A small material diffusion radius preserves a soft foliage terminator
    // even at a local blocker. Leaf cubes also need it after an empty search.
    float diffusion_radius_m = 0.06 * sss_amount * (1.0 + 0.1 * SHADOW_SSS_PENUMBRA_BOOST);
    if (leaf_receiver) {
        // Span several 1/16 m cutout cells while retaining canopy shadow cores.
        const float LEAF_DIFFUSION_RADIUS_M = 0.08;
        diffusion_radius_m = LEAF_DIFFUSION_RADIUS_M * sss_amount
            * (1.0 + 0.1 * SHADOW_SSS_PENUMBRA_BOOST);
    }

    // A world-space cap keeps the same maximum at every map position and
    // resolution. The material diffusion minimum wins if the controls overlap.
    float max_penumbra_radius_m = SHADOW_BLOCKER_SEARCH_RADIUS
        * (1.0 + SHADOW_PENUMBRA_CAP_BOOST);
    max_penumbra_radius_m = max(max_penumbra_radius_m, diffusion_radius_m);
    penumbra_radius_m = clamp(penumbra_radius_m, diffusion_radius_m, max_penumbra_radius_m);
    vec2 filter_offset_scale = penumbra_radius_m * projection_scale;

    // Step 3: budget samples from the local texel footprint without changing
    // the physical disk. Hardware bilinear PCF supplies subtexel filtering.
    vec2 filter_radius_texels = filter_offset_scale / ShadowFilterTexelScale(clip_pos);
    float penumbra_texels = max(filter_radius_texels.x, filter_radius_texels.y);
    // Ordered bounds: the two sliders may be set either way round, and GLSL
    // clamp is undefined for minVal > maxVal.
    int step_count = clamp(int(SHADOW_PCF_MIN_SAMPLES + SHADOW_PCF_GAIN * penumbra_texels),
        min(SHADOW_PCF_MIN_SAMPLES, SHADOW_PCF_MAX_SAMPLES),
        max(SHADOW_PCF_MIN_SAMPLES, SHADOW_PCF_MAX_SAMPLES));
    if (sss_amount > 0.01) step_count = SHADOW_SSS_STEPS;

    // Hardware bilinear PCF may compare a texel center almost one full texel
    // away. The disk itself is handled by the signed plane correction below,
    // so increasing penumbra radius does not require a radius-sized bias.
    float receiver_depth = sp.z
        - ShadowReceiverBias(abs(clip_pos.xy) + filter_offset_scale, depth_gradient, 1.0);
    float shadow = 0.0;
    int early_samples = min(4, step_count);
    // The PCF disk restarts the radius walk under its own budget.
    float inv_pcf = 1.0 / float(step_count);
    float radius_sq = 0.5 * inv_pcf;
    for (int i = 0; i < early_samples; ++i) {
        vec2 offset = filter_offset_scale * ShadowDiskOffset(dir, radius_sq, inv_pcf);
        vec2 uv = clamp(DistortShadowClip(clip_pos.xy + offset), vec2(0.0), vec2(1.0));
        shadow += texture(shadowtex1, vec3(uv, receiver_depth + dot(depth_gradient, offset)));
    }
    // Opaque receivers retain the first-four classification. Plants complete
    // their smaller budget so partial visibility is not rounded to black/white.
    if (step_count > 4) {
        if (sss_amount <= 0.01 && shadow < 0.5) {
            return 0.0;
        }
        if (sss_amount <= 0.01 && shadow > 3.5) {
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
