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

vec3 EvaluateOpaqueDirectLight(ivec2 tx, vec3 albedo, PBRMaterial material,
        int material_id, float vertex_ao, float sky_light,
        vec3 normal_world, vec3 geo_normal, vec3 view_pos, vec3 world_pos,
        vec3 view_to_eye, float ndotv, out vec3 caustic_brdf,
        out vec3 diffuse_reflectance, out bool diagnostic_output) {
    caustic_brdf = vec3(0.0);
    diffuse_reflectance = vec3(0.0);
    diagnostic_output = false;
    float ndotl = saturate(dot(normal_world, u_world_light_dir));
    // Plant translucency from the materialID stored in colortex1.a.
#if defined(SHADOW_SSS) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
    float sss_amount = SSSAmountForId(material_id);
#else
    // Compile-time off: the literal zero folds every SSS branch below out.
    float sss_amount = 0.0;
#endif
    float sss_skylight = sky_light;
#if defined(WORLD_END)
    // The End has directional light but no vanilla sky-light channel.
    sss_skylight = 1.0;
#endif

    float geo_ndotl = dot(geo_normal, u_world_light_dir);

    // Thin foliage broadens diffuse lighting toward a two-sided response.
    // Reflection and its enhancement share directional visibility, so shelter
    // removes both completely. The bent blade normal affects diffuse only.
    bool plant_receiver = sss_amount > 0.01;
    vec2 plant_response = vec2(0.0);
    float plant_sky_access = 1.0;
    if (plant_receiver) {
        vec3 plant_normal = PlantShadingNormal(normal_world, view_to_eye, material_id);
        plant_response = PlantDiffuseResponse(plant_normal, u_world_light_dir,
            view_to_eye, material_id, sss_amount);
        plant_sky_access = smoothstep(0.02, 0.35, sss_skylight);
    }

    // -- Shadow --
    float shadow_occlusion = 1.0;
    float plant_map_visibility = 1.0;
    float sss_map_coverage = 0.0;
    bool shadow_needed = plant_receiver
        ? (plant_response.x + plant_response.y) * plant_sky_access > 1.0e-4
        : ndotl > 1.0e-3;
    // Lit receivers share one STBN read between map filtering and contact.
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
        // The nominal-radius fade is confidence in the map, not a statement
        // about Iris's geometry culling. Screen attenuation runs on both sides.
        sss_map_coverage = shadow_coverage * (1.0 - smoothstep(
            SHADOW_SSS_FADE_START, 1.0, length(world_pos) / shadowDistance));
        float map_confidence = plant_receiver ? sss_map_coverage : shadow_coverage;
        float shadow_filtered = 1.0;
        if (map_confidence > 1.0e-3) {
            vec2 depth_gradient = ShadowReceiverGradient(geo_normal);
#ifdef SHADOW_PCSS
            shadow_filtered = ShadowFilterPCSS(shadow_proj, shadow_clip, depth_gradient, stbn_dither,
                sss_amount, ndotl, plant_receiver && material_id == 129);
#else
            shadow_filtered = ShadowFilterHardwarePCF(shadow_proj, shadow_clip, depth_gradient);
#endif
        }
        plant_map_visibility = shadow_filtered;
        if (plant_receiver) {
            float distant_visibility = PlantDistantVisibility(sss_skylight, vertex_ao, material_id);
            shadow_occlusion = mix(distant_visibility, shadow_filtered, map_confidence)
                * plant_sky_access;
        } else {
            shadow_occlusion = mix(1.0, shadow_filtered, shadow_coverage);
        }
    } else {
        shadow_occlusion = 0.0;
    }
    float sss_contact_visibility = 1.0;
    // Leaf cubes rely on reliable map shelter nearby; increasing screen weight
    // continuously as map confidence fades avoids double-darkening the canopy.
    // Grass uses full screen attenuation at every distance.
    float plant_contact_weight = material_id == 129 && plant_receiver ? 1.0 - sss_map_coverage : 1.0;
#if defined(CONTACT_SHADOW) && (defined(WORLD_OVERWORLD) || defined(WORLD_END))
#if CONTACT_SHADOW_DEBUG > 0 || SHADOW_SSS_DEBUG == 3
    if (shadow_needed) {
#else
    // No direct light survives a fully sheltered receiver: skip its screen ray.
    if (shadow_needed && shadow_occlusion > 0.0 && plant_contact_weight > 0.0) {
#endif
        vec3 geo_view_normal = plant_receiver ? vec3(0.0) : normalize(mat3(gbufferModelView) * geo_normal);
        float contact_shadow = ContactShadowOcclusion(view_pos, geo_view_normal, geo_ndotl,
            stbn_dither, sss_amount);
        // Plant hits represent partial occupancy; compound it with map shelter.
        // Opaque receivers retain the existing first-hit/min visibility rule.
        shadow_occlusion = plant_receiver
            ? shadow_occlusion * mix(1.0, contact_shadow, plant_contact_weight)
            : min(shadow_occlusion, contact_shadow);
        sss_contact_visibility = contact_shadow;
#if CONTACT_SHADOW_DEBUG > 0
        diagnostic_output = true;
        return vec3(CONTACT_SHADOW_DEBUG == 1
            ? contact_shadow : saturate((1.0 - contact_shadow) * 4.0));
#endif
    }
#endif

    // Reuse diffuse reflectance for direct plants, ambient and block light.
    diffuse_reflectance = EvaluateDiffuseReflectance(
        albedo, material.f0, material.diffuse_weight);
    vec3 direct_visibility = vec3(0.0);
    vec3 sss_lighting = vec3(0.0);
    if (shadow_occlusion > 0.0) {
        if (plant_receiver) {
            vec2 visible_response = plant_response * shadow_occlusion;
            direct_visibility = diffuse_reflectance * visible_response.x;
            sss_lighting = diffuse_reflectance * visible_response.y;
        }
        // Half-vector work belongs after visibility, outside the screen ray's
        // live state. Plants retain GGX at every roughness on the real surface
        // normal; their two-sided response replaces only the diffuse lobe.
        if (ndotl > 0.0) {
            vec3 half_vector = view_to_eye + u_world_light_dir;
            vec3 half_dir = half_vector * inversesqrt(max(dot(half_vector, half_vector), 1e-8));
            // Unit N,V,L and guarded unit H bound both cosines. V.H == L.H.
            float ndoth = saturate(dot(normal_world, half_dir));
            float vdoth = saturate(dot(view_to_eye, half_dir));
            vec3 diffuse_brdf;
            vec3 direct_brdf = EvaluateDirectBRDF(
                albedo, material.f0, material.diffuse_weight,
                material.perceptual_roughness,
                ndotv, ndotl, ndoth, vdoth, vdoth, diffuse_brdf);
            // Plant diffuse and transmission were already evaluated above.
            if (plant_receiver) direct_brdf = max(direct_brdf - diffuse_brdf, vec3(0.0));
            direct_visibility += direct_brdf * ndotl * shadow_occlusion;
        }
    }
    // colortex5 feeds underwater caustics; exclude transmitted diffuse light.
    caustic_brdf = direct_visibility;
    vec3 color = (direct_visibility + sss_lighting) * ground_light.rgb;
#if SHADOW_SSS_DEBUG == 1
    diagnostic_output = true;
    return sss_lighting * ground_light.rgb;
#elif SHADOW_SSS_DEBUG == 2
    diagnostic_output = true;
    return plant_receiver ? vec3(1.0 - sss_map_coverage, sss_map_coverage, 0.0) : vec3(0.0);
#elif SHADOW_SSS_DEBUG == 3
    diagnostic_output = true;
    return plant_receiver ? vec3(sss_contact_visibility) : vec3(0.0);
#elif SHADOW_SSS_DEBUG == 4
    diagnostic_output = true;
    return plant_receiver ? vec3(plant_map_visibility) : vec3(0.0);
#endif

    return color + albedo * material.emission * OPAQUE_PBR_EMISSION_SCALE;
}

#endif // LIB_LIGHTING_OPAQUE_DIRECT_GLSL
