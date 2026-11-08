#ifndef LIB_LIGHTING_OPAQUE_DIRECT_GLSL
#define LIB_LIGHTING_OPAQUE_DIRECT_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/lighting/brdf.glsl"
#include "/lib/lighting/plant_subsurface.glsl"
#include "/lib/material/model.glsl"
#include "/lib/shadow/contact_shadow.glsl"
#include "/lib/shadow/pcss.glsl"
#include "/lib/shadow/plant_distant_shadow.glsl"

vec3 EvaluateOpaqueDirectLight(ivec2 tx, vec3 albedo, PBRMaterial material,
        int material_id, float vertex_ao, float sky_light,
        vec3 normal_world, vec3 geo_normal, vec3 view_pos, vec3 world_pos,
        vec3 view_to_eye, float ndotv, out vec3 caustic_brdf,
        out vec3 diffuse_reflectance, out bool diagnostic_output) {
    caustic_brdf = vec3(0.0);
    diffuse_reflectance = vec3(0.0);
    diagnostic_output = false;
    float ndotl = saturate(dot(normal_world, u_world_light_dir));
#if defined(SHADOW_SSS) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
    float transmission_prior = PlantTransmissionPrior(material_id);
#else
    float transmission_prior = 0.0;
#endif
    // Classification uses the base prior: setting transmission to zero must
    // retain the angular material. Metal tissue can still require GGX shadows.
    bool plant_receiver = transmission_prior > 0.0;
    vec2 plant_angular = vec2(0.0);
    if (plant_receiver) {
        plant_angular = PlantAngularWeights(normal_world, u_world_light_dir,
            view_to_eye, PlantUsesTiltedSheets(material_id));
    }
    bool shadow_needed = plant_receiver
        ? (material.diffuse_weight > 0.0 && plant_angular.x + plant_angular.y > 1.0e-4)
            || (ndotl > 1.0e-3 && ndotv > 1.0e-5 && any(greaterThan(material.f0, vec3(0.0))))
        : ndotl > 1.0e-3;

    float plant_skylight = sky_light;
#ifdef WORLD_END
    plant_skylight = 1.0;
#endif
    float plant_prior = PlantDistantPrior(plant_skylight);
    float map_confidence = 0.0;
    float map_visibility = 1.0;
    float shadow_occlusion = 0.0;
    float stbn_dither = 0.0;
    if (shadow_needed) {
#ifdef TAA
        stbn_dither = SampleSTBN(tx, STBNFrame());
#else
        stbn_dither = SampleSTBN(tx, 0);
#endif
        vec3 shadow_proj;
        vec3 shadow_clip;
        ProjectToShadowPair(world_pos, shadow_proj, shadow_clip);
        float clip_edge = max(abs(shadow_clip.x), abs(shadow_clip.y));
        float xy_coverage = 1.0 - smoothstep(SHADOW_SSS_FADE_START, 1.0, clip_edge);
        float z_coverage = 1.0 - smoothstep(SHADOW_SSS_FADE_START, 1.0, abs(shadow_clip.z));
        float shadow_coverage = xy_coverage * z_coverage;
        map_confidence = plant_receiver ? PlantMapConfidence(shadow_clip, view_pos) : shadow_coverage;
        if (map_confidence > 1.0e-3) {
            vec2 depth_gradient = ShadowReceiverGradient(geo_normal);
#ifdef SHADOW_PCSS
            map_visibility = ShadowFilterPCSS(shadow_proj, shadow_clip, depth_gradient,
                stbn_dither, plant_receiver, ndotl, plant_receiver ? PlantShadowFootprint(material_id) : 0.0);
#else
            map_visibility = ShadowFilterHardwarePCF(shadow_proj, shadow_clip, depth_gradient);
#endif
        }
        shadow_occlusion = mix(plant_receiver ? plant_prior : 1.0, map_visibility, map_confidence);
    }

    float screen_blocking = 0.0;
    bool screen_eligible = false;
#if defined(PLANT_SHADOW_DIAGNOSTICS)
    PlantShadowEstimate screen_diagnostic;
    screen_diagnostic.depth_reads = 0;
    screen_diagnostic.packet_reads = 0;
    screen_diagnostic.coarse_reads = 0;
    screen_diagnostic.validation_reads = 0;
    screen_diagnostic.candidate_count = 0;
    screen_diagnostic.valid_projected_extent = false;
    screen_diagnostic.rejected_candidate = false;
#endif
#if defined(SHADOW_SSS_SCREEN) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
    screen_eligible = plant_receiver && shadow_needed && plant_prior > 0.0 && map_confidence < 1.0;
#if SHADOW_SSS_DEBUG == 3 || SHADOW_SSS_DEBUG == 8 || SHADOW_SSS_DEBUG >= 11
    // Diagnostic queries may expose the ray even under full map coverage.
    screen_eligible = plant_receiver && shadow_needed;
#endif
    if (screen_eligible) {
        vec2 jitter_uv = vec2(0.0);
#ifdef TAA
        jitter_uv = u_taa_offset * 0.5;
#endif
        vec3 geo_view = normalize(mat3(gbufferModelView) * geo_normal);
        PlantShadowEstimate estimate = TracePlantDistantShadow(view_pos, geo_view,
            material_id, u_view_light_dir, jitter_uv, stbn_dither, SHADOW_SSS_SCREEN_DISTANCE);
        screen_blocking = estimate.blocking_confidence;
#if defined(PLANT_SHADOW_DIAGNOSTICS)
        screen_diagnostic = estimate;
#endif
        // Screen misses never release the skylight prior. The map and far
        // estimate blend once, rather than multiplying two shelter estimates.
        shadow_occlusion = mix(plant_prior * (1.0 - screen_blocking), map_visibility, map_confidence);
    }
#endif

#if defined(CONTACT_SHADOW) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
#if CONTACT_SHADOW_DEBUG > 0
    if (!plant_receiver && shadow_needed) {
#else
    if (!plant_receiver && shadow_needed && shadow_occlusion > 0.0) {
#endif
        vec3 geo_view_normal = normalize(mat3(gbufferModelView) * geo_normal);
        float contact_shadow = ContactShadowOcclusion(view_pos, geo_view_normal,
            dot(geo_normal, u_world_light_dir), stbn_dither);
        shadow_occlusion = min(shadow_occlusion, contact_shadow);
#if CONTACT_SHADOW_DEBUG > 0
        diagnostic_output = true;
        return vec3(CONTACT_SHADOW_DEBUG == 1
            ? contact_shadow : saturate((1.0 - contact_shadow) * 4.0));
#endif
    }
#endif

    // Ambient/block-light consumers retain their existing reflectance law.
    diffuse_reflectance = EvaluateDiffuseReflectance(albedo, material.f0, material.diffuse_weight);
    vec3 reflected = vec3(0.0);
    vec3 transmitted = vec3(0.0);
    if (shadow_occlusion > 0.0) {
        if (plant_receiver && material.diffuse_weight > 0.0) {
            vec3 budget = PlantInterfaceBudget(material.f0, material.diffuse_weight,
                dot(normal_world, view_to_eye)) * shadow_occlusion;
            reflected = budget * albedo * plant_angular.x;
            transmitted = budget * PlantTransmission(albedo, transmission_prior) * plant_angular.y;
        }
        // Keep the half vector and RGB optics outside the trace's live state.
        if (ndotl > 0.0) {
            vec3 half_vector = view_to_eye + u_world_light_dir;
            vec3 half_dir = half_vector * inversesqrt(max(dot(half_vector, half_vector), 1e-8));
            float ndoth = saturate(dot(normal_world, half_dir));
            float vdoth = saturate(dot(view_to_eye, half_dir));
            vec3 direct_brdf;
            if (plant_receiver) {
                direct_brdf = EvaluateDirectSpecularBRDF(material.f0, material.perceptual_roughness,
                    ndotv, ndotl, ndoth, vdoth);
            } else {
                vec3 diffuse_brdf;
                direct_brdf = EvaluateDirectBRDF(albedo, material.f0, material.diffuse_weight,
                    material.perceptual_roughness, ndotv, ndotl, ndoth, vdoth, vdoth, diffuse_brdf);
            }
            reflected += direct_brdf * ndotl * shadow_occlusion;
        }
    }
    // Underwater caustics consume reflected light only, including GGX.
    caustic_brdf = reflected;
    vec3 color = (reflected + transmitted) * ground_light.rgb;
#if SHADOW_SSS_DEBUG > 0
    diagnostic_output = true;
    if (!plant_receiver) return vec3(0.0);
#if SHADOW_SSS_DEBUG == 1
    return transmitted * ground_light.rgb;
#elif SHADOW_SSS_DEBUG == 2
    return vec3(1.0 - map_confidence, map_confidence, 0.0);
#elif SHADOW_SSS_DEBUG == 3
    return vec3(1.0 - screen_blocking);
#elif SHADOW_SSS_DEBUG == 4
    return vec3(map_visibility);
#elif SHADOW_SSS_DEBUG == 5
    return albedo;
#elif SHADOW_SSS_DEBUG == 6
    return PlantTransmission(albedo, transmission_prior);
#elif SHADOW_SSS_DEBUG == 7
    return vec3(1.0) - albedo - PlantTransmission(albedo, transmission_prior);
#elif SHADOW_SSS_DEBUG == 8
    return vec3(screen_blocking);
#elif SHADOW_SSS_DEBUG == 9
    return vec3(shadow_occlusion);
#elif SHADOW_SSS_DEBUG == 10
    return vec3(plant_angular, 0.0);
#elif SHADOW_SSS_DEBUG == 11
    return vec3(1.0, float(screen_eligible), float(screen_diagnostic.valid_projected_extent));
#elif SHADOW_SSS_DEBUG == 12
    return vec3(float(screen_diagnostic.depth_reads) / 12.0,
        float(screen_diagnostic.packet_reads) / 8.0, float(screen_diagnostic.coarse_reads) / 10.0);
#elif SHADOW_SSS_DEBUG == 13
    return vec3(float(screen_diagnostic.validation_reads) / 2.0,
        float(screen_diagnostic.candidate_count) / 2.0, float(screen_diagnostic.rejected_candidate));
#endif
#endif
    return color + albedo * material.emission * OPAQUE_PBR_EMISSION_SCALE;
}

#endif // LIB_LIGHTING_OPAQUE_DIRECT_GLSL
