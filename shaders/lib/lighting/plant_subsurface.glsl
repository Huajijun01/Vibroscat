#ifndef LIB_LIGHTING_PLANT_SUBSURFACE_GLSL
#define LIB_LIGHTING_PLANT_SUBSURFACE_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/core/math_scalar.glsl"

#if defined(SHADOW_PCSS)

// Reference distance in empirical transport-depth units.
const float PLANT_TRANSPORT_DISTANCE = 0.25;

// color must be linear; it sets scattering, its complement the absorption.
void PlantScatteringCoefficients(vec3 color, float amount,
        out vec3 sigma_a, out vec3 sigma_s) {
    sigma_a = (vec3(1.0) - color) / PLANT_TRANSPORT_DISTANCE;
    sigma_s = color * (amount / PLANT_TRANSPORT_DISTANCE);
}

#else

// Thin-layer model anchored to linear biome-tinted color; R + T <= 1 per channel.
vec3 PlantTransmission(vec3 color, float transmission_prior) {
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float dark_gate = luminance / (luminance + 0.04);
    float prior = min(transmission_prior * SHADOW_SSS_TRANSMISSION, 1.0);
    return prior * (vec3(1.0) - color) * sqrt(color) * dark_gate;
}

float PlantFresnelComplement(float cosine) {
    return 1.0 - Pow5(1.0 - cosine);
}

// Tilted micro-sheet model for vertical cards, collapsing onto the real normal
// at the horizontal poles; GGX keeps using the original surface normal.
vec2 PlantAngularWeights(vec3 normal_world, vec3 light_world,
        vec3 view_to_eye, bool tilted_sheets) {
    float normal_view = dot(normal_world, view_to_eye);
    float normal_light = dot(normal_world, light_world);
    vec2 signed_light;
    vec2 view_projection;
    if (tilted_sheets) {
        float tilt_cosine = sqrt(0.5 + 0.5 * normal_world.y * normal_world.y);
        float up_view = view_to_eye.y - normal_world.y * normal_view;
        float up_light = light_world.y - normal_world.y * normal_light;
        view_projection = tilt_cosine * vec2(normal_view)
            + vec2(0.7071067811865476, -0.7071067811865476) * up_view;
        signed_light = tilt_cosine * vec2(normal_light)
            + vec2(0.7071067811865476, -0.7071067811865476) * up_light;
    } else {
        view_projection = vec2(normal_view, 0.0);
        signed_light = vec2(normal_light, 0.0);
    }
    if (view_projection.x < 0.0) signed_light.x = -signed_light.x;
    if (view_projection.y < 0.0) signed_light.y = -signed_light.y;
    vec2 projection = abs(view_projection);
    float projection_sum = projection.x + projection.y;
    float plus_weight = tilted_sheets
        ? (projection_sum > 0.0 ? projection.x / projection_sum : 0.5) : 1.0;
    vec2 weights = vec2(plus_weight, 1.0 - plus_weight);
    vec2 light_budget = vec2(PlantFresnelComplement(abs(signed_light.x)),
        PlantFresnelComplement(abs(signed_light.y)));
    return vec2(dot(weights * light_budget, max(signed_light, vec2(0.0))),
        dot(weights * light_budget, max(-signed_light, vec2(0.0))));
}

vec3 PlantInterfaceBudget(vec3 f0, float diffuse_weight, float normal_view) {
    vec3 complement = vec3(1.0) - f0;
    return complement * complement
        * (diffuse_weight * PlantFresnelComplement(abs(normal_view)) / PI);
}

#endif

#endif // LIB_LIGHTING_PLANT_SUBSURFACE_GLSL
