#ifndef LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL
#define LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/atmosphere/skybox_uv.glsl"
#include "/lib/lighting/lightmap.glsl"
#include "/lib/raytrace/ssr.glsl"

// This pass's registered STBN stream: the pair keeps the GGX lobe sample and
// the trace jitter decorrelated. The clamp keeps the GGX inverse-CDF finite
// at exact 0/1 texel values.
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

// VNDF sampling (Heitz 2018, "Sampling the GGX Distribution of Visible Normals");
// wi_std/wm_std live in the alpha-stretched space, the return maps back to roughness space.
vec3 SampleVisibleGGX(vec3 local_v, float alpha, vec2 u) {
    vec3 wi_std = normalize(vec3(local_v.xy * alpha, local_v.z));
    float phi = TAU * u.x;
    float z = (1.0 - u.y) * (1.0 + wi_std.z) - wi_std.z;
    float sin_theta = sqrt(saturate(1.0 - z * z));
    vec3 cap = vec3(sin_theta * cos(phi), sin_theta * sin(phi), z);
    vec3 wm_std = cap + wi_std;
    return normalize(vec3(wm_std.xy * alpha, wm_std.z));
}

// stbn_random is the OpaqueSSRSTBNPair pair from the pass main, seeding the GGX sample.
vec3 OpaqueReflectionDirection(vec3 normal_world, vec3 view_dir,
        float perceptual_roughness, vec2 stbn_random, out vec3 half_dir) {
    float alpha = max(perceptual_roughness * perceptual_roughness, 0.002);
    mat3 frame = BuildOrthonormalBasis(normal_world);
    vec3 local_v = transpose(frame) * view_dir;
    vec3 local_h = SampleVisibleGGX(local_v, alpha, stbn_random);
    half_dir = frame * local_h;
    vec3 light_dir = reflect(-view_dir, half_dir);
    return dot(normal_world, light_dir) > 1e-5 ? light_dir : vec3(0.0);
}

vec3 SampleOpaqueEnvironment(vec3 direction, float sky_light) {
    if (dot(direction, direction) < 1e-8) return vec3(0.0);
    return SkyLightFromLm(sky_light)
        * texture(usam_sky_radiance, SkyRadianceUV(direction)).rgb;
}

// Projected footprint heuristic, not a GGX convolution (widening the color
// sample is biased). History dimensions are full-display under TAAU; the
// scene render scale must not enter this footprint.
float OpaqueHistoryLod(SSRHit hit, vec3 previous_hit, vec3 trace_origin,
        float roughness) {
#if OPAQUE_SSR_COLOR_MIPS == 2
    if (hit.sky) return 0.0;
    vec3 hit_view = NDCToView(hit.screen * 2.0 - 1.0);
    float ray_length = length(hit_view - trace_origin);
    float previous_depth = -PreviousScreenToView(previous_hit).z;
    vec2 history_size = vec2(textureSize(colortex5, 0));
    vec2 focal_pixels = 0.5 * history_size
        * abs(vec2(gbufferPreviousProjection[0][0], gbufferPreviousProjection[1][1]));
    float diameter = 2.0 * OPAQUE_SSR_COLOR_MIP_SCALE * roughness * roughness * ray_length
        * max(focal_pixels.x, focal_pixels.y) / max(previous_depth, 1e-3);
    float max_lod = min(float(OPAQUE_SSR_COLOR_MIP_MAX),
        floor(log2(max(history_size.x, history_size.y))));
    // Keep the support inside the history rectangle near the viewport edge.
    vec2 edge_pixels = min(previous_hit.xy, 1.0 - previous_hit.xy) * history_size;
    max_lod = min(max_lod, log2(max(min(edge_pixels.x, edge_pixels.y), 1.0)));
    return smoothstep(0.04, 0.12, roughness)
        * clamp(log2(max(diameter, 1.0)), 0.0, max_lod);
#else
    return 0.0;
#endif
}

bool SampleOpaqueHistory(SSRHit hit, vec3 trace_origin, float roughness,
        out vec3 history) {
    history = vec3(0.0);
    if (!hit.valid || frameCounter < 1) return false;
    if (!ScreenUVInside(hit.screen.xy)) return false;

    vec3 previous_hit = ToPrevious(hit.screen);
    if (!ScreenUVInside(previous_hit.xy)) return false;

    float lod = OpaqueHistoryLod(hit, previous_hit, trace_origin, roughness);
    history = textureLod(colortex5, previous_hit.xy, lod).rgb;
    if (!IsFinite(history) || any(lessThan(history, vec3(0.0)))) {
        history = vec3(0.0);
        return false;
    }
    history = max(history, vec3(0.0));
    // History can sample the sun disk or other extreme pixels; bound them so one texel cannot spawn fireflies.
    history = min(history, vec3(OPAQUE_SSR_RADIANCE_LIMIT));
    return true;
}
#endif // LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL
