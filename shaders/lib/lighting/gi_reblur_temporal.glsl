#ifndef LIB_LIGHTING_GI_REBLUR_TEMPORAL_GLSL
#define LIB_LIGHTING_GI_REBLUR_TEMPORAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/lighting/gi_history.glsl"
#include "/lib/lighting/gi_reblur.glsl"

#ifdef GI_REBLUR_ACTIVE
vec3 AccumulateGIReblur(vec3 current_irradiance, float hit_distance,
        vec3 receiver_world, vec3 normal_world, out float history_age,
        out vec4 fast_history) {
    current_irradiance = GIReblurFinite(current_irradiance);
    history_age = 1.0;
    fast_history = vec4(current_irradiance, hit_distance);
    GIReprojectedHistory reprojected = ReprojectGIHistory(receiver_world, normal_world);
    if (reprojected.weight < 0.05) return current_irradiance;
    history_age = min(floor(reprojected.age) + 1.0, float(GI_HISTORY_FRAMES));
    vec4 fast_previous = reprojected.fast;
    // Weak bilinear support around disocclusion must not retain a long history.
    history_age = min(history_age, mix(2.0, float(GI_HISTORY_FRAMES),
        clamp(reprojected.weight * 2.0, 0.0, 1.0)));
    float fast_age = min(history_age, float(GI_REBLUR_FAST_FRAMES));
    fast_history = mix(fast_previous, vec4(current_irradiance, hit_distance), 1.0 / fast_age);
    return GIReblurFinite(mix(reprojected.irradiance, current_irradiance, 1.0 / history_age));
}
#endif

#endif // LIB_LIGHTING_GI_REBLUR_TEMPORAL_GLSL
