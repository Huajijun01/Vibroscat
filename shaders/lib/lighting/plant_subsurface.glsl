#ifndef LIB_LIGHTING_PLANT_SUBSURFACE_GLSL
#define LIB_LIGHTING_PLANT_SUBSURFACE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/scattering/phase.glsl"

// Thin foliage shares one directional-light visibility for reflection and
// transmission. Neither term can light a fully occluded receiver. Provenance
// and license terms: licenses/THIRD_PARTY_NOTICES.md section 29.
const float PLANT_BLADE_REFERENCE_AMOUNT = 0.55;
const float PLANT_FORWARD_PEAK_LIMIT = 2.5;

// Crossed blades represent many small tilted leaves. Bend their diffuse normal
// upward, while leaf blocks retain their face orientation and canopy shape.
// Orient two-sided foliage toward the eye before broadening diffuse lighting.
vec3 PlantShadingNormal(vec3 normal_world, vec3 view_to_eye, int material_id) {
    vec3 facing_normal = dot(normal_world, view_to_eye) < 0.0 ? -normal_world : normal_world;
    bool blade = material_id == 128 || material_id == 130 || material_id == 131;
    return blade ? normalize(facing_normal + vec3(0.0, 0.6, 0.0)) : facing_normal;
}

// Return ordinary diffuse / thin-foliage enhancement before reflectance and
// visibility. Crossed grass quads represent a cluster of differently oriented
// blades: a one-sided cosine cannot represent its exposed tips. Lift their
// angular response toward a broad two-sided target, without subtracting light
// from the directly lit side. Map/screen visibility still removes both terms.
// This is an artistic micro-leaf approximation, not a measured leaf BSSRDF.
vec2 PlantDiffuseResponse(vec3 normal_world, vec3 light_dir, vec3 view_to_eye,
    int material_id, float sss_amount) {
    float ndotl = dot(normal_world, light_dir);
    bool blade = material_id == 128 || material_id == 130 || material_id == 131;
    float amount_scale = blade ? 1.0 / PLANT_BLADE_REFERENCE_AMOUNT : 1.0;
    float strength = saturate(sss_amount * amount_scale * SHADOW_SSS_SCALE)
        * saturate(SHADOW_SSS_ENERGY);
    // Unit normal and light directions keep ndotl in [-1, 1]: exact for this
    // saturate, and it caps the blade's 0.9 + 0.1 * |ndotl| target at 1.
    float reflection = saturate(ndotl);
    // Leaf cubes keep their geometric normals, so their angular compensation
    // must be stronger than grass (whose normal already bends toward the sky).
    // Canopy shape comes from map shelter, not artificially dim leaf backfaces.
    float broad_target = blade ? 0.9 + 0.1 * abs(ndotl) : 1.0;
    float transmission = saturate(broad_target - reflection);
    if (transmission > 0.0 && strength > 0.0) {
        // The directional lobe adds a restrained highlight. Leaf targets
        // already reach the cap, so they skip the phase evaluation.
        if (broad_target < 1.0) {
            float directional = PI * PhaseHenyeyGreensteinSurfaceNormalized(
                -dot(light_dir, view_to_eye), SHADOW_SSS_PHASE_G);
            broad_target *= 1.0 + 0.15 * max(min(directional, PLANT_FORWARD_PEAK_LIMIT) - 1.0, 0.0);
        }
        transmission = saturate(saturate(broad_target) - reflection) * strength;
    } else {
        transmission = 0.0;
    }
    return vec2(reflection, transmission) * (1.0 / PI);
}

// Only a missing-map estimate. The map keeps full authority wherever reliable;
// sky access is not a replacement for actual directional occlusion there.
float PlantDistantVisibility(float skylight, float vertex_ao, int material_id) {
    float sky2 = saturate(skylight) * saturate(skylight);
    float sky4 = sky2 * sky2;
    float sky_visibility = material_id == 129 ? sky4 * sky2 : sky4;
    return sky_visibility * mix(0.6, 1.0, saturate(vertex_ao));
}

#endif // LIB_LIGHTING_PLANT_SUBSURFACE_GLSL
