#ifndef LIB_SHADOW_REFLECTIVE_SHADOW_MAP_GLSL
#define LIB_SHADOW_REFLECTIVE_SHADOW_MAP_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/color/spaces.glsl"
#include "/lib/shadow/rsm_data.glsl"

// Reconstruct the sampled texel center, undoing both axial distortion and
// protected depth. All distances used in the VPL integral are in meters.
vec3 RSMShadowViewPosition(vec2 shadow_uv, float protected_depth) {
    vec2 distorted_clip = shadow_uv * 2.0 - 1.0;
    vec2 clip_xy = distorted_clip * (1.0 - DISTORT_FACTOR)
        / max(vec2(1.0) - DISTORT_FACTOR * abs(distorted_clip), vec2(1.0e-5));
    float clip_z = (protected_depth * 2.0 - 1.0) / SHADOW_DEPTH_SCALE;
    return (vec3(clip_xy, clip_z) - shadowProjection[3].xyz)
        / vec3(u_shadow_projection_xy, u_shadow_projection_z);
}

// Dachsbacher & Stamminger, "Reflective Shadow Maps", I3D 2005.
// A directional-light texel reflects Phi = rho * E_light * A_projected.
// NdotL cancels between incident irradiance and projected emitter area.
// Integrate in UNDISTORTED light-plane meters: p_A = 1/(2*pi*R*r).
// Thus neither a shadow-resolution gain nor a distorted-UV area bias is needed.
// stbn_noise is the two-sample STBN pair sampled by the deferred3 main
// (radial jitter in y, golden-angle rotation seed in x).
// Output includes the uncovered sky fallback, before the receiver BRDF.
vec3 GatherRSM(vec3 receiver_world, vec3 receiver_view, vec3 normal_world,
        vec2 stbn_noise, vec3 sky_fallback, vec3 ambient_ao, out float sample_sigma) {
    sample_sigma = 0.0;
    float availability = 1.0 - smoothstep(max(shadowDistance - RSM_RADIUS, 0.0),
        shadowDistance, length(receiver_view));
    if (availability <= 0.0) {
        // Outside the shadow map the fallback is all there is: with
        // directional sky it already carries its own occlusion and floor.
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
        return sky_fallback;
#else
        return sky_fallback * ambient_ao;
#endif
    }

    vec3 receiver_shadow = (shadowModelView * vec4(receiver_world + normal_world * 0.03, 1.0)).xyz;
    vec3 normal_shadow = normalize(mat3(shadowModelView) * normal_world);
    ivec2 shadow_size = ivec2(shadowMapResolution);
    vec2 shadow_size_f = vec2(shadow_size);
    float rsm_sample_count = float(RSM_SAMPLES);
    // The texel-extent denominator is loop-invariant; carry its reciprocal
    // so each sample trades the division for a multiply.
    vec2 texel_extent_inv_denom = 1.0
        / ((1.0 - DISTORT_FACTOR) * abs(u_shadow_projection_xy) * vec2(shadow_size));
    vec3 sum_irradiance = vec3(0.0);
    float sum_coverage = 0.0;
    vec3 transport_moments = vec3(0.0);
    // The azimuth sequence TAU * fract(seed + k * GOLDEN_RATIO_CONJUGATE) is the orbit of
    // one fixed rotation (TAU-periodic), so one sin/cos pair per pixel seeds a
    // rotation recurrence and the per-sample angle never needs fract, a float
    // convert, a multiply or a sin/cos pair. Same recurrence the SSAO, DOF and
    // GTAO samplers already use.
    float cos_step = cos(TAU * GOLDEN_RATIO_CONJUGATE);
    float sin_step = sin(TAU * GOLDEN_RATIO_CONJUGATE);
    float sample_azimuth_c = cos(TAU * stbn_noise.x);
    float sample_azimuth_s = sin(TAU * stbn_noise.x);
    float rsm_inv_sample_count = 1.0 / rsm_sample_count;

    for (int sample_index = 0; sample_index < RSM_SAMPLES; ++sample_index) {
        float radial_distance = RSM_RADIUS * (float(sample_index) + stbn_noise.y)
            * rsm_inv_sample_count;
        // Inverse disk-area PDF, with its common constant cancelled.
        vec2 sample_shadow_xy = receiver_shadow.xy
            + radial_distance * vec2(sample_azimuth_c, sample_azimuth_s);
        // Advance the azimuth by one golden angle; every later sample reads the
        // rotated pair, so the cos/sin pair below stays per-pixel.
        float next_azimuth_c = sample_azimuth_c * cos_step - sample_azimuth_s * sin_step;
        sample_azimuth_s = sample_azimuth_s * cos_step + sample_azimuth_c * sin_step;
        sample_azimuth_c = next_azimuth_c;
        vec2 sample_clip = u_shadow_projection_xy * sample_shadow_xy + shadowProjection[3].xy;
        if (any(greaterThanEqual(abs(sample_clip), vec2(1.0)))) continue;
        vec2 distort_factor = GetDistortFactor(sample_clip);
        vec2 sample_uv = sample_clip / distort_factor * 0.5 + 0.5;
        ivec2 sample_texel = ivec2(sample_uv * shadow_size_f);
        if (any(lessThan(sample_texel, ivec2(0))) || any(greaterThanEqual(sample_texel, shadow_size))) continue;
        // The payload read shares the depth read's texel and neither address
        // depends on the other's value, so both issue back-to-back and the
        // validity checks below consume them from registers; a rejected tap
        // discards the payload read it no longer uses.
        float sample_depth = texelFetch(shadowtex0, sample_texel, 0).r;
        vec4 source_data = texelFetch(shadowcolor0, sample_texel, 0);
        if (sample_depth <= 0.0 || sample_depth >= 1.0) continue;
        vec2 texel_uv = (vec2(sample_texel) + 0.5) / shadow_size_f;
        vec3 emitter_shadow = RSMShadowViewPosition(texel_uv, sample_depth);
        vec3 delta_shadow = emitter_shadow - receiver_shadow;
        // All-zero is the reserved absent/translucent payload: no emitter here.
        if (all(equal(source_data, vec4(0.0)))) continue;
        vec3 reflectance = DecodeRSMSource(source_data);

        vec2 texel_extent_m = 2.0 * distort_factor * distort_factor
            * texel_extent_inv_denom;
        // dot(d,d) needs no root of its own; the angles below derive the plain
        // length from it. Writing length(d) first and squaring it back added
        // one sqrt and one multiply per tap for the same value (a round trip
        // through sqrt loses rounding on denormal-sized deltas).
        float distance_squared = dot(delta_shadow, delta_shadow);
        float delta_length_m = sqrt(distance_squared);
        if (distance_squared < 0.0025) continue;
        vec3 emitter_normal = DecodeOctahedralNormal(source_data.ba);
        float receiver_cosine_distance = max(dot(normal_shadow, delta_shadow), 0.0);
        // The angular margin suppresses false coplanar coverage from oct8
        // normal quantization. This gather only integrates one-sided bounce.
        float emitter_facing_distance = -dot(emitter_normal, delta_shadow);
        float angular_margin = 0.01 * delta_length_m;
        float emitter_cosine_distance = max(emitter_facing_distance - angular_margin, 0.0);
        if (receiver_cosine_distance * emitter_cosine_distance <= 0.0) continue;

        float projected_cosine = max(abs(emitter_normal.z), 0.05);
        float emitter_area = texel_extent_m.x * texel_extent_m.y / projected_cosine;
        float softened_distance_squared = max(distance_squared, max(0.04, emitter_area / PI));
        // TAU / PI is exactly 2 and folded here, so the transport weight
        // below needs no division.
        float inverse_pdf = 2.0 * RSM_RADIUS * radial_distance;
        float geometry_term = receiver_cosine_distance * emitter_cosine_distance
            / (distance_squared * softened_distance_squared);
        float transport_weight = geometry_term * inverse_pdf;
        vec3 sample_irradiance = reflectance * transport_weight * ground_light.rgb * RSM_STRENGTH;
        // Convert projected area to surface area for cosine-weighted solid
        // angle coverage. Unlike flux, this has no incident-cosine factor.
        float sample_coverage = transport_weight / projected_cosine;
        sum_irradiance += sample_irradiance;
        sum_coverage += sample_coverage;
        float sample_luminance = Luminance(sample_irradiance);
        transport_moments += vec3(sample_luminance * sample_luminance,
            sample_coverage * sample_coverage, sample_luminance * sample_coverage);
    }

    vec3 irradiance = sum_irradiance / rsm_sample_count;
    float mean_coverage = sum_coverage / rsm_sample_count;
    // AO belongs to the uncovered environment, not transported RSM bounce.
    // Apply it before the moments so their fallback matches what is returned.
    // The directional-sky fallback above already includes its occlusion and
    // floor, so it enters uncovered coverage without a second AO product.
#if defined(RSM_DIRECTIONAL_SKY_ACTIVE)
    vec3 uncovered_sky = sky_fallback;
#else
    vec3 uncovered_sky = sky_fallback * ambient_ao;
#endif
    // A first-surface RSM only approximates receiver visibility; overlapping
    // solid angles and stochastic overshoot cannot remove more than all SH.
    float coverage = saturate(mean_coverage) * availability;
    // The SH term depends on the same coverage samples as bounce radiance.
    // Include their covariance rather than treating them as independent noise.
    vec3 moments = transport_moments * rsm_inv_sample_count;
    float sky_luminance = Luminance(uncovered_sky);
    float mean_transport = Luminance(irradiance) - sky_luminance * mean_coverage;
    float transport_variance = max(moments.x + sky_luminance * sky_luminance * moments.y
        - 2.0 * sky_luminance * moments.z - mean_transport * mean_transport, 0.0);
    sample_sigma = sqrt(transport_variance * rsm_inv_sample_count);
    sample_sigma *= availability;
    return max(irradiance, vec3(0.0)) * availability + uncovered_sky * (1.0 - coverage);
}

#endif // LIB_SHADOW_REFLECTIVE_SHADOW_MAP_GLSL
