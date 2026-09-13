#ifndef LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL
#define LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL

#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/atmosphere/sky_lut.glsl"
#include "/lib/lighting/ambient_light.glsl"
#include "/lib/raytrace/ssr.glsl"

// The opaque-reflection STBN stream registration: the second scalar shifts
// the spatial texel by (47, 83) and the time slice by 29 so the GGX lobe
// sample and the trace jitter stay decorrelated. The clamp keeps the GGX
// inverse-CDF finite at exact 0/1 texel values.
vec2 OpaqueSSRSTBNPair(ivec2 tx) {
    return clamp(SampleSTBNPair(tx, frameCounter, 29, ivec2(47, 83)),
        vec2(1e-6), vec2(1.0 - 1e-6));
}

mat3 BuildOrthonormalBasis(vec3 normal_world) {
    vec3 up = abs(normal_world.z) < 0.999
        ? vec3(0.0, 0.0, 1.0)
        : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal_world));
    return mat3(tangent, cross(normal_world, tangent), normal_world);
}

// VNDF sampling (Heitz 2018, "Sampling the GGX Distribution of Visible
// Normals"). wi_std/wm_std live in the standard (alpha-stretched) space;
// the return maps the sampled normal back to roughness space.
vec3 SampleVisibleGGX(vec3 local_v, float alpha, vec2 u) {
    vec3 wi_std = normalize(vec3(local_v.xy * alpha, local_v.z));
    float phi = TAU * u.x;
    float z = (1.0 - u.y) * (1.0 + wi_std.z) - wi_std.z;
    float sin_theta = sqrt(clamp(1.0 - z * z, 0.0, 1.0));
    vec3 cap = vec3(sin_theta * cos(phi), sin_theta * sin(phi), z);
    vec3 wm_std = cap + wi_std;
    return normalize(vec3(wm_std.xy * alpha, wm_std.z));
}

// stbn_random is the OpaqueSSRSTBNPair pair sampled by the pass main; it
// seeds the visible-normal GGX sample.
vec3 OpaqueReflectionDirection(vec3 normal_world, vec3 view_direction,
        float perceptual_roughness, vec2 stbn_random, out vec3 half_direction) {
    float alpha = max(perceptual_roughness * perceptual_roughness, 0.002);
    mat3 frame = BuildOrthonormalBasis(normal_world);
    vec3 local_v = transpose(frame) * view_direction;
    vec3 local_h = SampleVisibleGGX(local_v, alpha, stbn_random);
    half_direction = normalize(frame * local_h);
    vec3 light_direction = normalize(reflect(-view_direction, half_direction));
    return dot(normal_world, light_direction) > 1e-5 ? light_direction : vec3(0.0);
}

vec3 SampleOpaqueEnvironment(vec3 direction, float sky_light) {
    if (dot(direction, direction) < 1e-8) return vec3(0.0);
    return SkyLightFromLm(sky_light)
        * texture(usam_sky_radiance, SkyRadianceUV(direction)).rgb;
}

bool SampleOpaqueHistory(SSRHit hit, out vec3 history) {
    history = vec3(0.0);
    if (!hit.valid || frameCounter < 1) return false;
    if (!SSRScreenInside(hit.screen.xy)) return false;

    vec3 previous_hit = ToPrevious(hit.screen);
    if (!SSRScreenInside(previous_hit.xy)) return false;

    history = texture(colortex5, previous_hit.xy).rgb;
    if (!IsFinite(history) || any(lessThan(history, vec3(0.0)))) {
        history = vec3(0.0);
        return false;
    }
    history = max(history, vec3(0.0));
    return true;
}
#endif // LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL
