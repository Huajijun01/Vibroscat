#ifndef LIB_VOLUME_WATER_EPIPOLAR_GLSL
#define LIB_VOLUME_WATER_EPIPOLAR_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/sky_light_data.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/scattering/phase.glsl"
#include "/lib/volume/epipolar_core.glsl"
#include "/lib/water/caustic_coordinates.glsl"
#include "/lib/water/fog.glsl"

#if defined(WATER_EPIPOLAR_ACTIVE)
// Authored additive radiance, separate from the analytic water medium. No
// second attenuation is applied to scene color. The source is constant along
// the unrefracted world sun direction, including its projection to the pole.
vec3 EpipolarWaterRadiance(vec3 start_scene, vec3 direction_world, float distance_m, float ray_jitter) {
    float sun_height = u_water_sun_height;
    float sky_access = u_water_skylight;
    if (sun_height <= 0.0 || sky_access <= 0.0) return vec3(0.0);

    float length_m = min(distance_m, WATER_GODRAYS_DISTANCE_M);
    vec3 ray_delta = direction_world * length_m;
    vec3 start_world = start_scene + cameraPosition;
    // No refraction. This projection has zero derivative along worldSunDir.
    vec2 sun_slope = u_sun_slope;
    vec2 entry_xz = start_world.xz + sun_slope * (CAUSTIC_PLANE_Y - start_world.y);
    vec2 source_uv = CAUSTIC_WORLD_TO_UV * (entry_xz - u_caustic_advection);
    vec2 source_delta = CAUSTIC_WORLD_TO_UV * (ray_delta.xz - sun_slope * ray_delta.y);
    float source_time = u_caustic_source_time;

    vec3 shadow_start = ProjectToShadowClip(start_scene);
    vec3 shadow_end = ProjectToShadowClip(start_scene + ray_delta);
    float inv_steps = 1.0 / float(WATER_GODRAYS_STEPS);
    vec3 transmittance = vec3(1.0);
    vec3 integral = vec3(0.0);
    for (int k = 0; k < WATER_GODRAYS_STEPS; ++k) {
        // Stratified, equal-length bins matching the air march; exact
        // exponential weights retain the constant-source integral. A shared
        // STBN offset moves the origin within every bin, breaking coherent
        // integration bands. TAA consumes the changing sequence; with TAA
        // off STBNFrame fixes it to a spatial blue-noise pattern.
        float a = float(k) * inv_steps;
        float b = float(k + 1) * inv_steps;
        float u = mix(a, b, ray_jitter);
        vec3 next_transmittance = exp(-FAST_WATERFOG_EXTINCTION * (length_m * b));
        vec3 weight = transmittance - next_transmittance;
        float irradiance = textureLod(utex_godray_caustics,
            vec3(source_uv + source_delta * u, source_time), 0.0).r;
        // Positive caustic excess forms shafts without another uniform fog.
        float source = max(irradiance - 0.9, 0.0) * 4.0;
        float visibility = EpipolarShadowVisibility(shadow_start, shadow_end, u);
        integral += weight * (source * visibility);
        transmittance = next_transmittance;
    }
    vec3 incident = ground_light.rgb * u_water_ambient_transmittance;
    float phase = PhaseCornetteShanks(dot(direction_world, u_world_sun_dir), 0.35);
    return integral * (FAST_WATERFOG_SCATTERING / FAST_WATERFOG_EXTINCTION) * incident
        * (phase * sky_access * sky_access * sun_height * u_water_wetness_gain * WATER_GODRAYS_STRENGTH);
}
#endif // WATER_EPIPOLAR_ACTIVE

#endif // LIB_VOLUME_WATER_EPIPOLAR_GLSL
