#ifndef LIB_LIGHTING_REFLECTIVE_SHADOW_MAP_GLSL
#define LIB_LIGHTING_REFLECTIVE_SHADOW_MAP_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/color/color.glsl"
#include "/lib/lighting/rsm_data.glsl"

vec3 RSMOccludedSky(vec3 sky_fallback, float shadow_occlusion) {
    float sky_factor = mix(1.0, RSM_SKY_OCCLUSION_FLOOR, clamp(shadow_occlusion, 0.0, 1.0));
    return (sky_fallback - vec3(AMBIENT_BASE)) * sky_factor + vec3(AMBIENT_BASE);
}

// In shadow view, larger z is nearer the light. Reject the receiver's own
// plane (including tilted planes) without depending on a VPL's facing or flux.
float RSMShadowSampleOcclusion(vec3 delta_shadow, vec3 normal_shadow, float texel_footprint) {
    float depth_bias = 0.05 + texel_footprint * 0.5;
    float plane_bias = depth_bias + 0.02 * length(delta_shadow);
    return float(delta_shadow.z > depth_bias && abs(dot(normal_shadow, delta_shadow)) > plane_bias);
}

// Reconstruct the sampled texel center, undoing both axial distortion and
// protected depth. All distances used in the VPL integral are in meters.
vec3 RSMShadowViewPosition(vec2 shadow_uv, float protected_depth) {
    vec2 distorted_clip = shadow_uv * 2.0 - 1.0;
    vec2 clip_xy = distorted_clip * (1.0 - DISTORT_FACTOR)
        / max(vec2(1.0) - DISTORT_FACTOR * abs(distorted_clip), vec2(1.0e-5));
    float clip_z = (protected_depth * 2.0 - 1.0) / SHADOW_DEPTH_SCALE;
    return (vec3(clip_xy, clip_z) - shadowProjection[3].xyz)
        / vec3(shadowProjection[0].x, shadowProjection[1].y, shadowProjection[2].z);
}

// RSMs contain the light's first surface, not complete secondary visibility.
// Reject intervening surfaces represented by the camera depth buffer. Offscreen
// connections retain the conventional RSM visibility approximation.
float RSMConnectionVisibility(vec3 receiver_view, vec3 delta_view, float random_offset) {
    const int VISIBILITY_STEPS = 6;
    float thickness_m = min(0.75, 0.10 + length(delta_view) * 0.04);
    for (int step_index = 0; step_index < VISIBILITY_STEPS; ++step_index) {
        float fraction = (float(step_index) + 0.5 + 0.5 * random_offset) / float(VISIBILITY_STEPS + 1);
        vec3 point_view = receiver_view + delta_view * fraction;
        if (point_view.z >= -near) continue;
        vec4 projected = gbufferProjection * vec4(point_view, 1.0);
        vec2 sample_uv = projected.xy / projected.w * 0.5 + 0.5;
#ifdef TAA
        sample_uv += u_taa_offset * 0.5;
#endif
        if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThanEqual(sample_uv, vec2(1.0)))) continue;
        float scene_depth = textureLod(depthtex2, sample_uv, 0.0).r;
        if (scene_depth >= 1.0) continue;
        float scene_view_depth = LinearDepthFromScreenDepth(scene_depth);
        float depth_gap = -point_view.z - scene_view_depth;
        if (depth_gap > 0.05 && depth_gap < thickness_m) return 0.0;
    }
    return 1.0;
}

// Dachsbacher & Stamminger, "Reflective Shadow Maps", I3D 2005.
// A directional-light texel reflects Phi = rho * E_light * A_projected.
// NdotL cancels between incident irradiance and projected emitter area.
// Integrate in UNDISTORTED light-plane meters: p_A = 1/(2*pi*R*r).
// Thus neither a shadow-resolution gain nor a distorted-UV area bias is needed.
// Output includes the uncovered sky fallback, before the receiver BRDF.
vec3 GatherRSM(vec3 receiver_world, vec3 normal_world, ivec2 texel,
        vec3 sky_fallback, out float sample_sigma) {
    sample_sigma = 0.0;
    vec3 receiver_view = SceneToViewSpace(receiver_world);
    float availability = 1.0 - smoothstep(max(shadowDistance - RSM_RADIUS, 0.0),
        shadowDistance, length(receiver_view));
    if (availability <= 0.0) return sky_fallback;

    vec3 receiver_shadow = (shadowModelView * vec4(receiver_world + normal_world * 0.03, 1.0)).xyz;
    vec3 normal_shadow = normalize(mat3(shadowModelView) * normal_world);
    mat3 shadow_to_view = mat3(gbufferModelView) * transpose(mat3(shadowModelView));
    vec2 noise = vec2(SampleSTBN(texel, frameCounter), SampleSTBN(texel, frameCounter + 23));
    ivec2 shadow_size = textureSize(shadowtex0, 0);
    vec2 projection_xy = vec2(shadowProjection[0].x, shadowProjection[1].y);
    vec3 sum_irradiance = vec3(0.0);
    float sum_coverage = 0.0;
    vec3 sum_transport_moments = vec3(0.0);
    float sum_shadow_occlusion = 0.0;
    float sum_shadow_weight = 0.0;
    float sum_squared_shadow_weight = 0.0;

    for (int sample_index = 0; sample_index < RSM_SAMPLES; ++sample_index) {
        float radial_distance = RSM_RADIUS * (float(sample_index) + noise.y) / float(RSM_SAMPLES);
        // Inverse disk-area PDF, with its common constant cancelled. Invalid
        // shadow-map samples retain their weight and count as unoccluded.
        float shadow_weight = radial_distance / RSM_RADIUS;
        sum_shadow_weight += shadow_weight;
        sum_squared_shadow_weight += shadow_weight * shadow_weight;
        float angle = TAU * fract(noise.x + float(sample_index) * 0.61803398875);
        vec2 sample_shadow_xy = receiver_shadow.xy + radial_distance * vec2(cos(angle), sin(angle));
        vec2 sample_clip = projection_xy * sample_shadow_xy + shadowProjection[3].xy;
        if (any(greaterThanEqual(abs(sample_clip), vec2(1.0)))) continue;
        vec2 sample_uv = DistortShadowClip(sample_clip);
        ivec2 sample_texel = ivec2(sample_uv * vec2(shadow_size));
        if (any(lessThan(sample_texel, ivec2(0))) || any(greaterThanEqual(sample_texel, shadow_size))) continue;
        vec2 texel_uv = (vec2(sample_texel) + 0.5) / vec2(shadow_size);
        vec2 distort_factor = GetDistortFactor(sample_clip);
        vec2 texel_extent_m = 2.0 * distort_factor * distort_factor
            / ((1.0 - DISTORT_FACTOR) * abs(projection_xy) * vec2(shadow_size));
        float sample_depth = texelFetch(shadowtex0, sample_texel, 0).r;
        if (sample_depth <= 0.0 || sample_depth >= 1.0) continue;
        vec3 emitter_shadow = RSMShadowViewPosition(texel_uv, sample_depth);
        vec3 delta_shadow = emitter_shadow - receiver_shadow;
        // Integrate opaque shadow visibility separately from bounce transport.
        // Roof backfaces, black surfaces and rejected VPL connections still
        // participate; water's first depth layer must not act as an opaque roof.
        if (RSM_SKY_OCCLUSION_FLOOR < 1.0) {
            float depth_bias = 0.05 + 0.5 * length(texel_extent_m);
            float reference_depth = ProtectShadowDepth(
                (shadowProjection[2].z * receiver_shadow.z + shadowProjection[3].z) * 0.5 + 0.5)
                - ShadowDepthGapFromWorld(depth_bias);
            float opaque_shadow = 1.0 - texture(shadowtex1, vec3(texel_uv, reference_depth));
            sum_shadow_occlusion += shadow_weight * opaque_shadow
                * RSMShadowSampleOcclusion(delta_shadow, normal_shadow, length(texel_extent_m));
        }
        vec4 source_data = texelFetch(shadowcolor0, sample_texel, 0);
        // Only the reserved translucent payload is absent. Black emitters
        // still occupy directions and must attenuate the sky fallback.
        if (all(equal(source_data, vec4(0.0)))) continue;
        vec3 reflectance = DecodeRSMReflectance(source_data);

        float distance_squared = dot(delta_shadow, delta_shadow);
        if (distance_squared < 0.0025) continue;
        vec3 emitter_normal = DecodeOctahedralNormal(source_data.ba);
        float receiver_cosine_distance = max(dot(normal_shadow, delta_shadow), 0.0);
        // The angular margin suppresses false coplanar coverage from oct8
        // normal quantization. This gather only integrates one-sided bounce.
        float emitter_facing_distance = -dot(emitter_normal, delta_shadow);
        float angular_margin = 0.01 * sqrt(distance_squared);
        float emitter_cosine_distance = max(emitter_facing_distance - angular_margin, 0.0);
        if (receiver_cosine_distance * emitter_cosine_distance <= 0.0) continue;

        float projected_cosine = max(abs(emitter_normal.z), 0.05);
        float emitter_area = texel_extent_m.x * texel_extent_m.y / projected_cosine;
        float softened_distance_squared = max(distance_squared, max(0.04, emitter_area / PI));
        float inverse_pdf = TAU * RSM_RADIUS * radial_distance;
        float geometry_term = receiver_cosine_distance * emitter_cosine_distance
            / (distance_squared * softened_distance_squared);
        vec3 delta_view = shadow_to_view * delta_shadow;
        float visibility = RSMConnectionVisibility(receiver_view, delta_view, noise.y);
        float transport_weight = geometry_term * inverse_pdf * visibility / PI;
        vec3 sample_irradiance = reflectance * transport_weight * ground_light.rgb * RSM_STRENGTH;
        // Convert projected area to surface area for cosine-weighted solid
        // angle coverage. Unlike flux, this has no incident-cosine factor.
        float sample_coverage = transport_weight / projected_cosine;
        sum_irradiance += sample_irradiance;
        sum_coverage += sample_coverage;
        float bounce_luminance = Luminance(sample_irradiance);
        sum_transport_moments += vec3(bounce_luminance * bounce_luminance,
            sample_coverage * sample_coverage, bounce_luminance * sample_coverage);
    }

    vec3 irradiance = sum_irradiance / float(RSM_SAMPLES);
    float mean_coverage = sum_coverage / float(RSM_SAMPLES);
    float mean_shadow_occlusion = clamp(sum_shadow_occlusion / sum_shadow_weight, 0.0, 1.0);
    float shadow_occlusion = mean_shadow_occlusion * availability;
    vec3 occluded_sky = RSMOccludedSky(sky_fallback, shadow_occlusion);
    // A first-surface RSM only approximates receiver visibility; overlapping
    // solid angles and stochastic overshoot cannot remove more than all SH.
    float coverage = clamp(mean_coverage, 0.0, 1.0) * availability;
    // Evaluate the bounce/coverage covariance with the final sky factor. Add
    // the shadow estimator's standard error conservatively for shared samples.
    vec3 moments = sum_transport_moments / float(RSM_SAMPLES);
    float sky_luminance = Luminance(occluded_sky);
    float mean_luminance = Luminance(irradiance) - sky_luminance * mean_coverage;
    float transport_variance = max(moments.x + sky_luminance * sky_luminance * moments.y
        - 2.0 * sky_luminance * moments.z - mean_luminance * mean_luminance, 0.0);
    float shadow_variance = mean_shadow_occlusion * (1.0 - mean_shadow_occlusion)
        * sum_squared_shadow_weight / (sum_shadow_weight * sum_shadow_weight);
    float shadow_scale = (1.0 - RSM_SKY_OCCLUSION_FLOOR)
        * Luminance(sky_fallback - vec3(AMBIENT_BASE)) * (1.0 - coverage);
    sample_sigma = (sqrt(transport_variance / float(RSM_SAMPLES))
        + shadow_scale * sqrt(shadow_variance)) * availability;
    return max(irradiance, vec3(0.0)) * availability + occluded_sky * (1.0 - coverage);
}

#endif // LIB_LIGHTING_REFLECTIVE_SHADOW_MAP_GLSL
