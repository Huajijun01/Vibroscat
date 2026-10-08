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

vec3 RSMOccludedSky(vec3 sky_fallback, float shadow_occlusion) {
    float sky_factor = mix(1.0, RSM_SKY_OCCLUSION_FLOOR, clamp(shadow_occlusion, 0.0, 1.0));
    return (sky_fallback - vec3(AMBIENT_FLOOR)) * sky_factor + vec3(AMBIENT_FLOOR);
}

// In shadow view, larger z is nearer the light. Reject the receiver's own
// plane (including tilted planes) without depending on a VPL's facing or flux.
float RSMShadowSampleOcclusion(vec3 delta_shadow, vec3 normal_shadow,
        float texel_footprint, float delta_length_m) {
    float depth_bias = 0.05 + texel_footprint * 0.5;
    float plane_bias = depth_bias + 0.02 * delta_length_m;
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

// Dachsbacher & Stamminger, "Reflective Shadow Maps", I3D 2005.
// A directional-light texel reflects Phi = rho * E_light * A_projected.
// NdotL cancels between incident irradiance and projected emitter area.
// Integrate in UNDISTORTED light-plane meters: p_A = 1/(2*pi*R*r).
// Thus neither a shadow-resolution gain nor a distorted-UV area bias is needed.
// stbn_noise is the two-sample STBN pair sampled by the deferred3 main
// (radial jitter in y, golden-angle rotation seed in x).
// Output includes the uncovered sky fallback, before the receiver BRDF.
vec3 GatherRSM(vec3 receiver_world, vec3 receiver_view, vec3 normal_world,
        vec2 stbn_noise, vec3 sky_fallback) {
    float availability = 1.0 - smoothstep(max(shadowDistance - RSM_RADIUS, 0.0),
        shadowDistance, length(receiver_view));
    if (availability <= 0.0) return sky_fallback;

    vec3 receiver_shadow = (shadowModelView * vec4(receiver_world + normal_world * 0.03, 1.0)).xyz;
    vec3 normal_shadow = normalize(mat3(shadowModelView) * normal_world);
    ivec2 shadow_size = ivec2(shadowMapResolution);
    vec2 shadow_size_f = vec2(shadow_size);
    float rsm_sample_count = float(RSM_SAMPLES);
    vec2 projection_xy = vec2(shadowProjection[0].x, shadowProjection[1].y);
    // The texel-extent denominator is loop-invariant; carry its reciprocal
    // so each sample trades the division for a multiply.
    vec2 texel_extent_inv_denom = 1.0
        / ((1.0 - DISTORT_FACTOR) * abs(projection_xy) * vec2(shadow_size));
    vec3 sum_irradiance = vec3(0.0);
    float sum_coverage = 0.0;
#ifdef RSM_SKY_OCCLUSION
    float sum_shadow_occlusion = 0.0;
    float sum_shadow_weight = 0.0;
#endif
    // Loop-invariant SSBO payload: the gather never writes sky_light_data,
    // so hoist the ground light out of the sample loop. The strength stays at
    // the use site to keep the original multiplication order bit-identical.
    vec3 ground_light_payload = ground_light.rgb;

    for (int sample_index = 0; sample_index < RSM_SAMPLES; ++sample_index) {
        float radial_distance = RSM_RADIUS * (float(sample_index) + stbn_noise.y) / float(RSM_SAMPLES);
        // Inverse disk-area PDF, with its common constant cancelled. Invalid
        // shadow-map samples retain their weight and count as unoccluded.
#ifdef RSM_SKY_OCCLUSION
        float shadow_weight = radial_distance / RSM_RADIUS;
        sum_shadow_weight += shadow_weight;
#endif
        float angle = TAU * fract(stbn_noise.x + float(sample_index) * GOLDEN_RATIO);
        vec2 sample_shadow_xy = receiver_shadow.xy + radial_distance * vec2(cos(angle), sin(angle));
        vec2 sample_clip = projection_xy * sample_shadow_xy + shadowProjection[3].xy;
        if (any(greaterThanEqual(abs(sample_clip), vec2(1.0)))) continue;
        vec2 distort_factor = GetDistortFactor(sample_clip);
        vec2 sample_uv = sample_clip / distort_factor * 0.5 + 0.5;
        ivec2 sample_texel = ivec2(sample_uv * shadow_size_f);
        if (any(lessThan(sample_texel, ivec2(0))) || any(greaterThanEqual(sample_texel, shadow_size))) continue;
        float sample_depth = texelFetch(shadowtex0, sample_texel, 0).r;
        if (sample_depth <= 0.0 || sample_depth >= 1.0) continue;
        vec2 texel_uv = (vec2(sample_texel) + 0.5) / shadow_size_f;
        vec3 emitter_shadow = RSMShadowViewPosition(texel_uv, sample_depth);
        vec3 delta_shadow = emitter_shadow - receiver_shadow;
        vec2 texel_extent_m;
        // Reuse the sampled first-surface depth for sky occlusion: a
        // directional test against the receiver plane; transparent depth
        // is valid here.
#ifdef RSM_SKY_OCCLUSION
        texel_extent_m = 2.0 * distort_factor * distort_factor
            * texel_extent_inv_denom;
        float texel_footprint = length(texel_extent_m);
        // dot(d,d) needs no root of its own; the plain length is derived from
        // it below. Writing length(d) first and squaring it back added one
        // sqrt and one multiply per tap for the same value (a round trip
        // through sqrt loses rounding on denormal-sized deltas).
        float distance_squared = dot(delta_shadow, delta_shadow);
        float delta_length_m = sqrt(distance_squared);
        sum_shadow_occlusion += shadow_weight
            * RSMShadowSampleOcclusion(delta_shadow, normal_shadow, texel_footprint, delta_length_m);
#endif
        vec4 source_data = texelFetch(shadowcolor0, sample_texel, 0);
        // Only the reserved translucent payload is absent. Black emitters
        // still occupy directions and must attenuate the sky fallback.
        if (all(equal(source_data, vec4(0.0)))) continue;
        vec3 reflectance = DecodeRSMSource(source_data);

#ifndef RSM_SKY_OCCLUSION
        texel_extent_m = 2.0 * distort_factor * distort_factor
            * texel_extent_inv_denom;
        float distance_squared = dot(delta_shadow, delta_shadow);
        float delta_length_m = sqrt(distance_squared);
#endif
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
        vec3 sample_irradiance = reflectance * transport_weight * ground_light_payload * RSM_STRENGTH;
        // Convert projected area to surface area for cosine-weighted solid
        // angle coverage. Unlike flux, this has no incident-cosine factor.
        float sample_coverage = transport_weight / projected_cosine;
        sum_irradiance += sample_irradiance;
        sum_coverage += sample_coverage;
    }

    vec3 irradiance = sum_irradiance / rsm_sample_count;
    float mean_coverage = sum_coverage / rsm_sample_count;
#ifdef RSM_SKY_OCCLUSION
    float mean_shadow_occlusion = clamp(sum_shadow_occlusion / sum_shadow_weight, 0.0, 1.0);
    float shadow_occlusion = mean_shadow_occlusion * availability;
    vec3 occluded_sky = RSMOccludedSky(sky_fallback, shadow_occlusion);
#else
    vec3 occluded_sky = sky_fallback;
#endif
    // A first-surface RSM only approximates receiver visibility; overlapping
    // solid angles and stochastic overshoot cannot remove more than all SH.
    float coverage = clamp(mean_coverage, 0.0, 1.0) * availability;
    return max(irradiance, vec3(0.0)) * availability + occluded_sky * (1.0 - coverage);
}

#endif // LIB_SHADOW_REFLECTIVE_SHADOW_MAP_GLSL
