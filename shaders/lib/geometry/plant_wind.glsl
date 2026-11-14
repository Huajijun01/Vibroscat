#ifndef LIB_GEOMETRY_PLANT_WIND_GLSL
#define LIB_GEOMETRY_PLANT_WIND_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"

// block.properties: low byte keeps the material, upper byte is the geometry class
// (1 rooted, 2 tall lower, 3 tall upper, 4 continuous canopy). Both terrain and shadow call
// this in feet-player space before projection, gated on PLANT_WIND and the *_ACTIVE defines.
vec3 PlantWindOffset(vec3 world_pos, vec3 to_block_center, int block_id) {
    int plant_class = block_id >> 8;
    if (plant_class < 1 || plant_class > 4) return vec3(0.0);

    bool canopy = plant_class == 4;
    float height_m = max(0.5 - to_block_center.y, 0.0);
    if (plant_class == 3) height_m += 1.0;
    if (!canopy && height_m < 0.001) return vec3(0.0);

    // Rooted plants share the root's wind, both halves of tall plants alike; full leaf cubes
    // sample a continuous vertex field so a shared corner gets the same offset from any face.
    vec3 sample_pos = canopy ? world_pos : world_pos + to_block_center;
    if (!canopy) sample_pos.y -= plant_class == 3 ? 1.5 : 0.5;
    vec3 periodic_camera = vec3(cameraPositionInt & ivec3(255)) + cameraPositionFract;
    vec3 absolute_pos = sample_pos + periodic_camera;
    vec2 field_m = absolute_pos.xz + absolute_pos.y * vec2(0.25, 0.125);
    // Field and mechanical responses solved offline; exactly one LOD-0 fetch per moving vertex.
    // 3600 s clock wrap is seamless: U*3600/32 = (360, 270) whole periods.
    vec2 wind_uv = (field_m - u_plant_wind_time) / 32.0;
    vec4 response = textureLod(utex_plant_wind, wind_uv, 0.0);
    float weather_gain = 1.0;
#if defined(WORLD_OVERWORLD)
    weather_gain = u_plant_weather_gain;
#endif
    float strength = PLANT_WIND_STRENGTH * weather_gain;
    if (canopy) {
        vec2 bend = response.ba * (0.055 * PLANT_WIND_LEAVES * strength);
        // Limit keeps bends small enough for the unchanged block-face normal approximation.
        bend /= 1.0 + length(bend) / 0.2;
        return vec3(bend.x, 0.0, bend.y);
    }

    float length_m = plant_class == 1 ? 1.0 : 2.0;
    float h = saturate(height_m / length_m);
    // Euler-Bernoulli cantilever under uniform drag, normalized at the tip; zero root displacement and slope.
    float shape = h * h * (6.0 - 4.0 * h + h * h) / 3.0;
    int material_id = block_id & 255;
    float compliance = material_id == 133 ? 0.45 : (material_id == 134 ? 0.3 : 1.0);
    vec2 bend = response.rg * (0.13 * length_m * PLANT_WIND_GRASS * strength * compliance);
    // 30%-of-stalk lateral bound is the small-deflection model's validity limit, even in rain.
    bend /= 1.0 + length(bend) / (0.3 * length_m);
    bend *= shape;
    // Second-order shortening of an inextensible bent stem. Shared tall-plant seams share
    // height, shape and wind, so their XYZ offsets stay identical.
    float drop_m = -0.5 * dot(bend, bend) / max(height_m, 0.01);
    return vec3(bend.x, drop_m, bend.y);
}

#endif // LIB_GEOMETRY_PLANT_WIND_GLSL
