#ifndef LIB_LIGHTING_OPAQUE_DIRECT_GLSL
#define LIB_LIGHTING_OPAQUE_DIRECT_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/cloud/shadow.glsl"
#include "/lib/lighting/brdf.glsl"
#include "/lib/lighting/plant_subsurface.glsl"
#include "/lib/material/model.glsl"
#include "/lib/scattering/phase.glsl"
#include "/lib/shadow/contact_shadow.glsl"
#include "/lib/shadow/pcss.glsl"
#include "/lib/shadow/plant_distant_shadow.glsl"

#if defined(SHADOW_PCSS)

vec3 EvaluateOpaqueDirectLight(ivec2 tx, vec3 albedo, PBRMaterial material,
        int material_id, float vertex_ao, float sky_light,
        vec3 normal_world, vec3 geo_normal, vec3 view_pos, vec3 world_pos,
        vec3 view_to_eye, float ndotv, out vec3 caustic_brdf,
        out vec3 diffuse_reflectance) {
    caustic_brdf = vec3(0.0);
    diffuse_reflectance = vec3(0.0);
    float ndotl = saturate(dot(normal_world, u_world_light_dir));
    float amount = 0.0;
#if defined(WORLD_OVERWORLD) || defined(WORLD_END)
    amount = PlantTransmissionPrior(material_id);
#endif
    bool plant_receiver = amount > 0.0;
    float plant_skylight = sky_light;
#ifdef WORLD_END
    plant_skylight = 1.0;
#endif
    bool scatter_active = false;
#ifdef SHADOW_SSS
    scatter_active = plant_receiver && material.diffuse_weight > 0.0
        && SHADOW_SSS_TRANSMISSION > 0.0 && plant_skylight >= 0.1;
#endif
    bool shadow_needed = ndotl > 1.0e-3 || scatter_active;
    float plant_prior = PlantDistantPrior(plant_skylight);
    float map_confidence = 0.0;
    float map_visibility = 1.0;
    float map_depth = 0.0;
    float shadow_visibility = 0.0;
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
        if (plant_receiver) {
            map_confidence = abs(shadow_clip.z) < 1.0
                ? PlantMapConfidence(shadow_clip, view_pos) : 0.0;
        } else {
            float clip_edge = max(abs(shadow_clip.x), abs(shadow_clip.y));
            float xy_coverage = 1.0 - smoothstep(SHADOW_SSS_FADE_START, 1.0, clip_edge);
            float z_coverage = 1.0 - smoothstep(SHADOW_SSS_FADE_START, 1.0, abs(shadow_clip.z));
            map_confidence = xy_coverage * z_coverage;
        }
        if (map_confidence > 0.0) {
            vec2 gradient = ShadowReceiverGradient(geo_normal);
            map_visibility = ShadowFilterPCSS(shadow_proj, shadow_clip, gradient,
                stbn_dither, plant_receiver, ndotl,
                plant_receiver ? PlantShadowFootprint(material_id) : 0.0, map_depth);
        }
        shadow_visibility = mix(plant_receiver ? plant_prior : 1.0, map_visibility, map_confidence);
    }

    float screen_visibility = 1.0;
    float screen_depth = 0.0;
    bool screen_eligible = false;
#if defined(SHADOW_SSS_SCREEN) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
    screen_eligible = plant_receiver && shadow_needed && plant_prior > 0.0 && map_confidence < 1.0;
    if (screen_eligible) {
        vec2 jitter_uv = vec2(0.0);
#ifdef TAA
        jitter_uv = u_taa_offset * 0.5;
#endif
        PlantShadowEstimate estimate = TracePlantDistantShadow(view_pos,
            u_view_light_dir, jitter_uv, stbn_dither, SHADOW_SSS_SCREEN_DISTANCE);
        screen_visibility = estimate.visibility;
        screen_depth = estimate.sss_depth;
        shadow_visibility = mix(plant_prior * screen_visibility, map_visibility, map_confidence);
    }
#endif

#if defined(CONTACT_SHADOW) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
    if (!plant_receiver && shadow_needed && shadow_visibility > 0.0) {
        vec3 geo_view_normal = normalize(mat3(gbufferModelView) * geo_normal);
        float contact_shadow = ContactShadowOcclusion(view_pos, geo_view_normal,
            dot(geo_normal, u_world_light_dir), stbn_dither);
        shadow_visibility = min(shadow_visibility, contact_shadow);
    }
#endif

    diffuse_reflectance = EvaluateDiffuseReflectance(albedo, material.f0, material.diffuse_weight);
    vec3 reflected = vec3(0.0);
    if (shadow_visibility > 0.0 && ndotl > 0.0) {
        vec3 half_vector = view_to_eye + u_world_light_dir;
        vec3 half_dir = half_vector * inversesqrt(max(dot(half_vector, half_vector), 1e-8));
        float ndoth = saturate(dot(normal_world, half_dir));
        float vdoth = saturate(dot(view_to_eye, half_dir));
        vec3 diffuse_brdf;
        vec3 direct_brdf = EvaluateDirectBRDF(albedo, material.f0, material.diffuse_weight,
            material.perceptual_roughness, ndotv, ndotl, ndoth, vdoth, vdoth, diffuse_brdf);
        reflected = direct_brdf * ndotl * shadow_visibility;
    }
    vec3 scatter = vec3(0.0);
    vec3 sigma_a = vec3(0.0);
    vec3 sigma_s = vec3(0.0);
    float phase = 0.0;
    if (scatter_active) {
        PlantScatteringCoefficients(albedo, amount, sigma_a, sigma_s);
        float light_view = dot(u_world_light_dir, view_to_eye);
        phase = PHASE_ISOTROPIC;
        vec3 sigma_t = sigma_a + sigma_s;
        vec3 attenuation;
        if (map_confidence >= 1.0) {
            attenuation = exp(-sigma_t * map_depth);
        } else if (map_confidence <= 0.0) {
            attenuation = screen_depth < 0.0 ? vec3(0.0) : exp(-sigma_t * screen_depth);
        } else {
            vec3 far_attenuation = screen_depth < 0.0 ? vec3(0.0) : exp(-sigma_t * screen_depth);
            attenuation = mix(far_attenuation, exp(-sigma_t * map_depth), map_confidence);
        }
        // Art-directed constants. Only the sheen uses shadow visibility; tissue
        // SSS keeps its depth attenuation independent of PCSS visibility.
        vec3 tissue_scatter = 2.0 * sigma_s * phase * attenuation;
        float sun_alignment = saturate(-light_view);
        float backlight_sheen = 0.35 * amount * Pow4(sun_alignment * sun_alignment)
            * shadow_visibility;
        vec3 sheen_tint = mix(vec3(1.0),
            albedo / max(max(albedo.r, albedo.g), albedo.b), 0.75);
        scatter = SHADOW_SSS_TRANSMISSION * material.diffuse_weight
            * (tissue_scatter + backlight_sheen * sheen_tint);
    }
    float cloud_shadow = CloudShadowTransmittance(world_pos);
    caustic_brdf = reflected * cloud_shadow;
    vec3 color = (reflected + scatter) * ground_light.rgb * cloud_shadow;
    return color + albedo * material.emission * OPAQUE_PBR_EMISSION_SCALE;
}

#else

vec3 EvaluateOpaqueDirectLight(ivec2 tx, vec3 albedo, PBRMaterial material,
        int material_id, float vertex_ao, float sky_light,
        vec3 normal_world, vec3 geo_normal, vec3 view_pos, vec3 world_pos,
        vec3 view_to_eye, float ndotv, out vec3 caustic_brdf,
        out vec3 diffuse_reflectance) {
    caustic_brdf = vec3(0.0);
    diffuse_reflectance = vec3(0.0);
    float ndotl = saturate(dot(normal_world, u_world_light_dir));
#if defined(SHADOW_SSS) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
    float transmission_prior = PlantTransmissionPrior(material_id);
#else
    float transmission_prior = 0.0;
#endif
    // Classification uses the base prior so SHADOW_SSS=0 keeps the angular
    // material; metal tissue still needs GGX shadows.
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
#if defined(SHADOW_SSS_SCREEN) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
    screen_eligible = plant_receiver && shadow_needed && plant_prior > 0.0 && map_confidence < 1.0;
    if (screen_eligible) {
        vec2 jitter_uv = vec2(0.0);
#ifdef TAA
        jitter_uv = u_taa_offset * 0.5;
#endif
        vec3 geo_view = normalize(mat3(gbufferModelView) * geo_normal);
        PlantShadowEstimate estimate = TracePlantDistantShadow(view_pos, geo_view,
            u_view_light_dir, jitter_uv, stbn_dither, SHADOW_SSS_SCREEN_DISTANCE);
        screen_blocking = estimate.blocking_confidence;
        // Blend map and screen estimates once instead of multiplying two
        // shelter factors; a screen miss never releases the skylight prior.
        shadow_occlusion = mix(plant_prior * (1.0 - screen_blocking), map_visibility, map_confidence);
    }
#endif

#if defined(CONTACT_SHADOW) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
    if (!plant_receiver && shadow_needed && shadow_occlusion > 0.0) {
        vec3 geo_view_normal = normalize(mat3(gbufferModelView) * geo_normal);
        float contact_shadow = ContactShadowOcclusion(view_pos, geo_view_normal,
            dot(geo_normal, u_world_light_dir), stbn_dither);
        shadow_occlusion = min(shadow_occlusion, contact_shadow);
    }
#endif

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
    float cloud_shadow = CloudShadowTransmittance(world_pos);
    caustic_brdf = reflected * cloud_shadow;
    vec3 color = (reflected + transmitted) * ground_light.rgb * cloud_shadow;
    return color + albedo * material.emission * OPAQUE_PBR_EMISSION_SCALE;
}

#endif

#endif // LIB_LIGHTING_OPAQUE_DIRECT_GLSL
