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
// Samples: base-2 radical inverse (Hammersley) polar disk (sqrt radius x angle
// table), rotated by the shared STBN volume.

// ---- Low-discrepancy disk sampling ----

// Stratified disk point via polar Hammersley (radius from index, angle
// from the radical inverse); caller builds the STBN rotation basis once.
// The angle is the base-2 radical inverse of the low four bits, recovered
// by bit reversal into the top nibble. It is computed per tap instead of a
// const vec2[16] table because the loops index it with a runtime step
// counter, and this driver lowers a dynamically indexed const array into
// thread-local memory - one local-memory access per blocker/PCF tap.
vec2 ShadowDiskPoint(int i, int count) {
    float radius = sqrt((float(i) + 0.5) / float(count));
    float angle = float(bitfieldReverse(uint(i) & 15u) >> 28) * (TAU / 16.0);
    return radius * vec2(cos(angle), sin(angle));
}

// Rotate the stratified disk point by the precomputed basis.
vec2 ShadowRotateDisk(vec2 point, vec2 rot_x, vec2 rot_y) {
    return vec2(dot(rot_x, point), dot(rot_y, point));
}

// Texel -> undistorted clip Jacobian scale. The blocker search and the PCF
// pass need the identical expression for the same clip position, so both
// evaluate it once here and share the value.
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

// Step 1: blocker search. Averages the depths of shadow-map samples that
// occlude the receiver (depth <= receiver depth). Returns false when no
// blocker is found in the search disk, so the pixel can be treated as lit.
bool ShadowFindBlocker(vec3 sp, vec3 clip_pos, vec2 texel_scale, vec2 depth_gradient, vec2 rot_x, vec2 rot_y,
    int blocker_steps, out float blocker_depth) {
    // Convex corners project small false depth deltas; require a
    // world-space gap before counting a blocker (no corner darkening).
    float blocker_bias = ShadowDepthGapFromWorld(SHADOW_BLOCKER_DEPTH_TOLERANCE_M);
    vec2 blocker_offset_scale = SHADOW_BLOCKER_SEARCH_TEXELS * texel_scale;
    // Nearest depth fetches leave at most half a texel unresolved per axis.
    blocker_bias += ShadowReceiverBias(abs(clip_pos.xy) + blocker_offset_scale, depth_gradient, 0.5);

    float depth_sum = 0.0;
    float weight_sum = 0.0;
    ivec2 shadow_size = ivec2(shadowMapResolution);
    // The texel-to-UV scale is loop-invariant; carry it as a float vector so
    // each tap trades an int->float conversion of the resolution for a mul.
    vec2 shadow_size_f = vec2(shadow_size);
    for (int i = 0; i < blocker_steps; ++i) {
        vec2 offset = blocker_offset_scale * ShadowRotateDisk(ShadowDiskPoint(i, blocker_steps),
            rot_x, rot_y);
        vec2 uv = DistortShadowClip(clip_pos.xy + offset);
        ivec2 sample_texel = clamp(ivec2(uv * shadow_size_f), ivec2(0), shadow_size - 1);
        float shadow_depth = texelFetch(shadowtex0, sample_texel, 0).x;
        // Transport each blocker to the center receiver plane before both
        // classification and gap averaging; slopes must not become penumbrae.
        shadow_depth -= dot(depth_gradient, offset);
        float w = step(shadow_depth, sp.z - blocker_bias);
        depth_sum += w * shadow_depth;
        weight_sum += w;
    }

    if (weight_sum < 0.5) {
        blocker_depth = 0.0;
        return false;
    }
    blocker_depth = depth_sum / weight_sum;
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
//   leaf_receiver - leaf cubes need a world-space diffusion footprint
float ShadowFilterPCSS(vec3 sp, vec3 clip_pos, vec2 depth_gradient, float stbn_dither,
    float sss_amount, float ndotl, bool leaf_receiver) {
    // The caller (deferred_shading) gates sp into [0,1]^3 before calling.
    // One dither value + rotation basis serves both passes (coherent dither);
    // one texel scale serves the blocker search and the PCF pass below.
    float angle = stbn_dither * TAU;
    vec2 rot_x = vec2(cos(angle), -sin(angle));
    vec2 rot_y = vec2(sin(angle), cos(angle));
    vec2 texel_scale = ShadowFilterTexelScale(clip_pos);

    float blocker_depth;
    bool blocker_found = ShadowFindBlocker(sp, clip_pos, texel_scale, depth_gradient, rot_x, rot_y,
        SHADOW_BLOCKER_SAMPLES, blocker_depth);
    if (!blocker_found && !leaf_receiver) {
        return 1.0;
    }

    // Thin foliage can transmit from the back side and needs real visibility.
    if (ndotl < 1.0e-3 && sss_amount <= 0.01) {
        return 0.0;
    }

    // Step 2: penumbra. width = gap * tan(angular radius); gap from the NDC
    // delta + ortho z scale -> texels (blur tracks shadow length, not the
    // absolute blocker depth).
    float depth_delta = blocker_found ? saturate(sp.z - blocker_depth) : 0.0;
    float ortho_width_scale = abs(u_shadow_projection_xy.x);
    float world_depth_gap = ShadowDepthGapToWorld(depth_delta);
    float texel_world_size = 2.0 / (max(ortho_width_scale, 1e-6) * real_shadow_map_resolution);
    float penumbra_texels = world_depth_gap * SHADOW_SUN_ANGULAR_RADIUS / texel_world_size;
    // SSS foliage scatters through a wider penumbra.
    penumbra_texels *= 1.0 + SHADOW_SSS_PENUMBRA_BOOST * sss_amount;
    // A small material diffusion radius preserves a soft foliage terminator
    // even at a local blocker. It does not create visibility in a shadow core.
    float plant_radius_m = 0.06 * sss_amount * (1.0 + 0.1 * SHADOW_SSS_PENUMBRA_BOOST);
    penumbra_texels = max(penumbra_texels, plant_radius_m / texel_world_size);

    // Cap the variable texel footprint independently of sun height. Leaf
    // diffusion has its own world-space minimum below, even without blockers.
    float max_penumbra_texels = SHADOW_BLOCKER_SEARCH_TEXELS
        * (1.0 + SHADOW_PENUMBRA_CAP_BOOST);
    penumbra_texels = min(penumbra_texels, max_penumbra_texels);

    // Step 3: PCF with the penumbra radius; sample count grows with size,
    // capped by quality.
    // Ordered bounds: the two sliders may be set either way round, and GLSL
    // clamp is undefined for minVal > maxVal.
    int step_count = clamp(int(SHADOW_PCF_MIN_SAMPLES + SHADOW_PCF_GAIN * penumbra_texels),
        min(SHADOW_PCF_MIN_SAMPLES, SHADOW_PCF_MAX_SAMPLES),
        max(SHADOW_PCF_MIN_SAMPLES, SHADOW_PCF_MAX_SAMPLES));
    if (sss_amount > 0.01) step_count = SHADOW_SSS_STEPS;
    float filter_radius = max(penumbra_texels, 1.0);
    vec2 filter_offset_scale = filter_radius * texel_scale;
    if (leaf_receiver) {
        // Independently tuned to span several 1/16 m cutout cells while
        // retaining canopy shadow cores. Convert meters directly to clip XY:
        // the texel Jacobian would shrink this footprint near the map center.
        // The minimum also applies after an empty blocker search, otherwise
        // sparse cutouts turn the soft transition back into all-or-nothing.
        const float LEAF_DIFFUSION_RADIUS_M = 0.08;
        float leaf_radius_m = LEAF_DIFFUSION_RADIUS_M * sss_amount
            * (1.0 + 0.1 * SHADOW_SSS_PENUMBRA_BOOST);
        vec2 leaf_radius_clip = leaf_radius_m * abs(u_shadow_projection_xy);
        filter_offset_scale = max(filter_offset_scale, leaf_radius_clip);
    }

    // Hardware bilinear PCF may compare a texel center almost one full texel
    // away. The disk itself is handled by the signed plane correction below,
    // so increasing penumbra radius does not require a radius-sized bias.
    float receiver_depth = sp.z
        - ShadowReceiverBias(abs(clip_pos.xy) + filter_offset_scale, depth_gradient, 1.0);
    float shadow = 0.0;
    int early_samples = min(4, step_count);
    for (int i = 0; i < early_samples; ++i) {
        vec2 offset = filter_offset_scale
            * ShadowRotateDisk(
            ShadowDiskPoint(i, step_count), rot_x, rot_y);
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
            vec2 offset = filter_offset_scale
                * ShadowRotateDisk(
                ShadowDiskPoint(i, step_count), rot_x, rot_y);
            vec2 uv = saturate(DistortShadowClip(clip_pos.xy + offset));
            shadow += texture(shadowtex1, vec3(uv, receiver_depth + dot(depth_gradient, offset)));
        }
    }
    shadow *= 1.0 / float(step_count);
    return shadow;
}

#endif // LIB_SHADOW_PCSS_GLSL
