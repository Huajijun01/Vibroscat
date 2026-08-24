#ifndef LIB_SHADOW_PCSS_GLSL
#define LIB_SHADOW_PCSS_GLSL
#include "/lib/contract/settings.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/coordinates.glsl"

// Percentage-Closer Soft Shadows.
//
// Framework: R. Fernando, "Percentage-closer soft shadows", ACM SIGGRAPH 2005
// Sketches: 1) blocker search (shadowtex0); 2) penumbra estimate from the
// receiver/blocker depth ratio; 3) PCF filtering with that radius
// (shadowtex1, HW PCF).
// Samples: base-2 radical inverse (Hammersley) on a disk (Shirley & Chiu
// concentric square-to-disk), rotated by the shared STBN volume.


// ---- Low-discrepancy disk sampling ----

// Stratified disk point via polar Hammersley (radius from index, angle
// from the radical inverse); caller builds the STBN rotation basis once.
vec2 ShadowDiskPoint(int i, int count) {
    float radius = sqrt((float(i) + 0.5) / float(count));
    float theta = RadicalInverse(i) * TAU;
    return radius * vec2(FastCos(theta), FastSin(theta));
}

// Rotate the stratified disk point by the precomputed basis.
vec2 ShadowRotateDisk(vec2 point, vec2 rot_x, vec2 rot_y) {
    return vec2(dot(rot_x, point), dot(rot_y, point));
}

// STBN spatiotemporal noise: spatial slice by fragment coords, time slice
// by frame.
float ShadowDither(vec2 screen_pos) {
#ifdef TAA
    return SampleSTBN(ivec2(screen_pos), frameCounter);
#else
    return SampleSTBN(ivec2(screen_pos), 0);
#endif
}

// Step 1: blocker search. Averages the depths of shadow-map samples that
// occlude the receiver (depth <= receiver depth). Returns false when no
// blocker is found in the search disk, so the pixel can be treated as lit.
bool ShadowFindBlocker(vec3 sp, vec3 clip_pos, vec2 rot_x, vec2 rot_y, int blocker_steps, out float blocker_depth,
    out float sss_thickness_world
) {
    // Texel -> undistorted clip. The distorted UV map is
    //   uv = clip / (2*factor) + 0.5,  factor = (1-D) + D*|clip|,
    // whose local derivative is d(uv)/d(clip) = (1-D)/(2*factor^2), so the
    // inverse per-axis scale is 2*factor^2/(1-D) texels per clip unit.
    vec2 factor = GetDistortFactor(clip_pos.xy);
    vec2 texel_scale = 2.0 * factor * factor / (1.0 - DISTORT_FACTOR) / real_shadow_map_resolution;
    // Convex corners project small false depth deltas; require a
    // world-space gap before counting a blocker (no corner darkening).
    float blocker_bias = ShadowDepthGapFromWorld(SHADOW_BLOCKER_DEPTH_TOLERANCE_METERS);

    float depth_sum = 0.0;
    float weight_sum = 0.0;
    float depth_gap_sum = 0.0;
    ivec2 shadow_size = textureSize(shadowtex0, 0);
    for (int i = 0; i < blocker_steps; ++i) {
        vec2 offset = SHADOW_BLOCKER_SEARCH_TEXELS * texel_scale * ShadowRotateDisk(ShadowDiskPoint(i, blocker_steps),
            rot_x, rot_y);
        vec2 uv = DistortShadowClip(clip_pos.xy + offset);
        ivec2 sample_texel = clamp(ivec2(uv * vec2(shadow_size)), ivec2(0), shadow_size - 1);
        float depth = texelFetch(shadowtex0, sample_texel, 0).x;
        float gap = max(sp.z - depth, 0.0);
        float w = step(depth, sp.z - blocker_bias);
        depth_sum += w * depth;
        weight_sum += w;
        // Every sample contributes its gap (non-occluders add zero);
        // averaged over the disk = foliage thickness along the light.
        depth_gap_sum += w * gap;
    }

    if (weight_sum < 0.5) {
        blocker_depth = 0.0;
        sss_thickness_world = 0.0;
        return false;
    }
    blocker_depth = depth_sum / weight_sum;
    sss_thickness_world = ShadowDepthGapToWorld(depth_gap_sum / float(blocker_steps));
    return true;
}

// LOW-tier filter (SHADOW_PCSS off): single hardware-bilinear PCF lookup,
// no penumbra estimation, no radius PCF. The blocker search still runs so
// the plant-SSS thickness estimate keeps working without the PCSS cost.
//   sp        - shadow NDC [0,1]^3 with depth bias (projectToShadowWithBias)
//   clipPos   - undistorted shadow clip space [-1,1]^3 (projectToShadowClip)
//   screenPos - fragment coordinates, used as the STBN dither seed
//   sssAmount - plant translucency (0 = none); gates the blocker search
//   sssThicknessWorld - out: foliage thickness along the light in meters
float ShadowFilterHardwarePCF(vec3 sp, vec3 clip_pos, vec2 screen_pos, float sss_amount,
                              out float sss_thickness_world) {
    sss_thickness_world = 0.0;
    if (any(lessThan(sp.xy, vec2(0.0))) || any(greaterThan(sp.xy, vec2(1.0)))) {
        return 1.0;
    }
    // Keep the blocker search only for SSS materials (thickness estimate);
    // opaque surfaces skip it entirely in this tier.
    if (sss_amount > 1e-3) {
        float dither = ShadowDither(screen_pos);
        float angle = dither * TAU;
        vec2 rot_x = vec2(cos(angle), -sin(angle));
        vec2 rot_y = vec2(sin(angle), cos(angle));
        float blocker_depth;
        ShadowFindBlocker(sp, clip_pos, rot_x, rot_y, SHADOW_SSS_STEPS, blocker_depth, sss_thickness_world);
    }
    return texture(shadowtex1, sp);
}

// Full PCSS filter.
//   sp        - shadow NDC [0,1]^3 with depth bias (projectToShadowWithBias)
//   clipPos   - undistorted shadow clip space [-1,1]^3 (projectToShadowClip)
//   screenPos - fragment coordinates, used as the STBN dither seed
//   view_pos  - eye-space receiver position (for the distance response)
//   sssAmount - plant translucency (0 = none); widens the blocker search so
//               the thickness estimate is stable across sparse foliage
//   NdotL       - surface dot(light); back faces return early with thickness
//   sssThicknessWorld - out: foliage thickness along the light in meters
float ShadowFilterPCSS(vec3 sp, vec3 clip_pos, vec2 screen_pos, vec3 view_pos,
                       float sss_amount, float ndotl, out float sss_thickness_world) {
    sss_thickness_world = 0.0;
    if (any(lessThan(sp.xy, vec2(0.0))) || any(greaterThan(sp.xy, vec2(1.0)))) {
        return 1.0;
    }

    // One STBN read + rotation basis serves both passes (coherent dither).
    float dither = ShadowDither(screen_pos);
    float angle = dither * TAU;
    vec2 rot_x = vec2(cos(angle), -sin(angle));
    vec2 rot_y = vec2(sin(angle), cos(angle));

    float blocker_depth;
    int blocker_steps = sss_amount > 1e-3 ? SHADOW_SSS_STEPS : SHADOW_BLOCKER_SAMPLES;
    if (!ShadowFindBlocker(sp, clip_pos, rot_x, rot_y, blocker_steps, blocker_depth, sss_thickness_world
    )) {
        return 1.0;
    }

    // Back faces have no direct light: skip PCF (thickness already computed).
    if (ndotl < 1.0e-3) {
        return 0.0;
    }

    // Step 2: penumbra. width = gap · tan(angular radius); gap from the NDC
    // delta + ortho z scale → texels (blur tracks shadow length, not the
    // absolute blocker depth).
    float depth_delta = max(sp.z - blocker_depth, 0.0);
    float ortho_width_scale = abs(shadowProjection[0].x);
    float world_depth_gap = ShadowDepthGapToWorld(depth_delta);
    float texel_world_size = 2.0 / (max(ortho_width_scale, 1e-6) * real_shadow_map_resolution);
    float penumbra_texels = world_depth_gap * SHADOW_SUN_ANGULAR_RADIUS / texel_world_size;
    // SSS foliage scatters through a wider penumbra.
    penumbra_texels *= 1.0 + SHADOW_SSS_PENUMBRA_BOOST * sss_amount;

    // Distance softening masks shadow-map resolution loss; view_pos is
    // eye space, so length() is the true eye distance.
    float distance_factor = 1.0 + (SHADOW_DISTANCE_BOOST - 1.0)
        * smoothstep(10.0, 120.0, length(view_pos));
    penumbra_texels *= distance_factor;

    // Filter capped inside the blocker search disk (grows at low sun).
    float max_penumbra_texels = SHADOW_BLOCKER_SEARCH_TEXELS
        * (1.0 + SHADOW_SUN_HEIGHT_BOOST);
    penumbra_texels = min(penumbra_texels, max_penumbra_texels);

    // Step 3: PCF with the penumbra radius; sample count grows with size,
    // capped by quality.
    int step_count = clamp(int(SHADOW_PCF_MIN_SAMPLES + SHADOW_PCF_GAIN * penumbra_texels), SHADOW_PCF_MIN_SAMPLES,
        SHADOW_PCF_MAX_SAMPLES);
    vec2 factor = GetDistortFactor(clip_pos.xy);
    vec2 filter_texel_scale = 2.0 * factor * factor / (1.0 - DISTORT_FACTOR) / real_shadow_map_resolution;

    float shadow = 0.0;
    int early_samples = min(4, step_count);
    for (int i = 0; i < early_samples; ++i) {
        vec2 offset = max(penumbra_texels, 1.0) * filter_texel_scale
            * ShadowRotateDisk(
            ShadowDiskPoint(i, step_count), rot_x, rot_y);
        vec2 uv = clamp(DistortShadowClip(clip_pos.xy + offset), vec2(0.0), vec2(1.0));
        shadow += texture(shadowtex1, vec3(uv, sp.z));
    }
    // First 4 taps classify lit/shadowed early-exit (saves samples on large
    // penumbras).
    if (step_count > 4) {
        if (shadow < 0.5) {
            return 0.0;
        }
        if (shadow > 3.5) {
            return 1.0;
        }
        for (int i = 4; i < step_count; ++i) {
            vec2 offset = max(penumbra_texels, 1.0) * filter_texel_scale
                * ShadowRotateDisk(
                ShadowDiskPoint(i, step_count), rot_x, rot_y);
            vec2 uv = clamp(DistortShadowClip(clip_pos.xy + offset), vec2(0.0), vec2(1.0));
            shadow += texture(shadowtex1, vec3(uv, sp.z));
        }
    }
    shadow *= 1.0 / float(step_count);
    return shadow;
}

#endif
