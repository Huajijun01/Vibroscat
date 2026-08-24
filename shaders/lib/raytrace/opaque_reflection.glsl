#ifndef LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL
#define LIB_RAYTRACE_OPAQUE_REFLECTION_GLSL

#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"

struct OpaqueTraceHit {
    vec3 screen;
    float path_length;
    float thickness_error;
    bool valid;
};

OpaqueTraceHit OpaqueTraceMiss() {
    OpaqueTraceHit hit;
    hit.screen = vec3(0.0);
    hit.path_length = 0.0;
    hit.thickness_error = 0.0;
    hit.valid = false;
    return hit;
}

bool OpaqueFinite(vec2 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

bool OpaqueFinite(vec3 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

float OpaqueDepthAt(vec2 uv) {
    ivec2 size = textureSize(depthtex1, 0);
    ivec2 tx = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    return texelFetch(depthtex1, tx, 0).r;
}

vec3 OpaqueGeometricViewNormalAt(vec2 uv) {
    ivec2 size = textureSize(colortex4, 0);
    ivec2 tx = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    return DecodeOctahedralNormal(texelFetch(colortex4, tx, 0).xy);
}

float OpaqueTraceThickness(float path_length) {
    return OPAQUE_SSR_THICKNESS * (1.0 + 0.02 * path_length);
}

vec3 OpaquePerspectivePoint(vec3 Q0, vec3 Q1, float k0, float k1,
        float interpolation) {
    float k = mix(k0, k1, interpolation);
    return mix(Q0, Q1, interpolation) / max(k, 1e-8);
}

vec2 OpaqueSSRRandom2(ivec2 tx) {
    ivec3 size = textureSize(utex_stbn_scalar, 0);
    ivec2 p0 = ivec2(
        (tx.x % size.x + size.x) % size.x,
        (tx.y % size.y + size.y) % size.y);
    int z = (frameCounter % size.z + size.z) % size.z;
    ivec2 p1 = (p0 + ivec2(47, 83)) % size.xy;
    float u0 = texelFetch(utex_stbn_scalar, ivec3(p0, z), 0).r;
    float u1 = texelFetch(
        utex_stbn_scalar, ivec3(p1, (z + 29) % size.z), 0).r;
    return clamp(vec2(u0, u1), vec2(1e-6), vec2(1.0 - 1e-6));
}

mat3 BuildOrthonormalBasis(vec3 N) {
    vec3 up = abs(N.z) < 0.999
        ? vec3(0.0, 0.0, 1.0)
        : vec3(1.0, 0.0, 0.0);
    vec3 T = normalize(cross(up, N));
    return mat3(T, cross(N, T), N);
}

vec3 SampleVisibleGGX(vec3 local_v, float alpha, vec2 u) {
    vec3 wi_std = normalize(vec3(local_v.xy * alpha, local_v.z));
    float phi = 2.0 * PI * u.x;
    float z = (1.0 - u.y) * (1.0 + wi_std.z) - wi_std.z;
    float sin_theta = sqrt(clamp(1.0 - z * z, 0.0, 1.0));
    vec3 cap = vec3(sin_theta * cos(phi), sin_theta * sin(phi), z);
    vec3 wm_std = cap + wi_std;
    return normalize(vec3(wm_std.xy * alpha, wm_std.z));
}

vec3 OpaqueReflectionDirection(vec3 N, vec3 V,
        float perceptual_roughness, ivec2 tx, out vec3 H) {
    float alpha = max(perceptual_roughness * perceptual_roughness, 0.002);
    mat3 frame = BuildOrthonormalBasis(N);
    vec3 local_v = transpose(frame) * V;
    vec3 local_h = SampleVisibleGGX(
        local_v, alpha, OpaqueSSRRandom2(tx));
    H = normalize(frame * local_h);
    vec3 L = normalize(reflect(-V, H));
    return dot(N, L) > 1e-5 ? L : vec3(0.0);
}

OpaqueTraceHit TraceOpaqueReflection(vec3 view_origin,
        vec3 view_direction, float jitter) {
    OpaqueTraceHit miss = OpaqueTraceMiss();
    if (!OpaqueFinite(view_origin) || !OpaqueFinite(view_direction)
            || view_origin.z >= -near || length(view_direction) < 0.999) {
        return miss;
    }

    float ray_length = OPAQUE_SSR_MAX_DISTANCE;
    if (view_direction.z > 1e-6) {
        ray_length = min(ray_length,
            (-near * 1.01 - view_origin.z) / view_direction.z);
    } else if (view_direction.z < -1e-6) {
        ray_length = min(ray_length,
            (-far * 0.999 - view_origin.z) / view_direction.z);
    }
    if (ray_length <= 0.05) return miss;

    vec3 view_end = view_origin + view_direction * ray_length;
    vec4 clip0 = gbufferProjection * vec4(view_origin, 1.0);
    vec4 clip1 = gbufferProjection * vec4(view_end, 1.0);
    if (clip0.w <= 1e-6 || clip1.w <= 1e-6) return miss;

    float k0 = 1.0 / clip0.w;
    float k1 = 1.0 / clip1.w;
    vec3 Q0 = view_origin * k0;
    vec3 Q1 = view_end * k1;
    vec2 resolution = vec2(viewWidth, viewHeight);
    vec2 P0 = (clip0.xy * k0 * 0.5 + 0.5) * resolution;
    vec2 P1 = (clip1.xy * k1 * 0.5 + 0.5) * resolution;
#ifdef TAA
    vec2 jitter_pixels = u_taa_offset * 0.5 * resolution;
    P0 += jitter_pixels;
    P1 += jitter_pixels;
#endif

    vec2 screen_min = vec2(0.5);
    vec2 screen_max = resolution - 0.5;
    if (any(lessThan(P0, screen_min)) || any(greaterThan(P0, screen_max))) {
        return miss;
    }

    vec2 projected_delta = P1 - P0;
    float clip_fraction = 1.0;
    if (projected_delta.x > 0.0) {
        clip_fraction = min(clip_fraction,
            (screen_max.x - P0.x) / projected_delta.x);
    } else if (projected_delta.x < 0.0) {
        clip_fraction = min(clip_fraction,
            (screen_min.x - P0.x) / projected_delta.x);
    }
    if (projected_delta.y > 0.0) {
        clip_fraction = min(clip_fraction,
            (screen_max.y - P0.y) / projected_delta.y);
    } else if (projected_delta.y < 0.0) {
        clip_fraction = min(clip_fraction,
            (screen_min.y - P0.y) / projected_delta.y);
    }
    clip_fraction = clamp(clip_fraction, 0.0, 1.0);
    P1 = mix(P0, P1, clip_fraction);
    Q1 = mix(Q0, Q1, clip_fraction);
    k1 = mix(k0, k1, clip_fraction);

    projected_delta = P1 - P0;
    float major_length = max(abs(projected_delta.x), abs(projected_delta.y));
    if (major_length < 0.25) return miss;
    int step_count = min(
        max(int(ceil(major_length)), 2), OPAQUE_SSR_STEPS);
    float step_denominator = float(max(step_count - 1, 1));
    float first_step = 0.5 + 0.5 * clamp(jitter, 0.0, 1.0);
    float previous_t = 0.0;
    float previous_gap = -OpaqueTraceThickness(0.0);

    for (int i = 0; i < OPAQUE_SSR_STEPS; ++i) {
        if (i >= step_count) break;
        float sample_t = min(
            (float(i) + first_step) / step_denominator, 1.0);
        vec2 sample_uv = mix(P0, P1, sample_t) / resolution;
        float surface_depth = OpaqueDepthAt(sample_uv);
        vec3 ray_view = OpaquePerspectivePoint(Q0, Q1, k0, k1, sample_t);
        float ray_depth = -ray_view.z;

        if (surface_depth < 1.0) {
            float surface_linear = LinearDepthFromScreenDepth(surface_depth);
            float gap = ray_depth - surface_linear;
            if (gap >= 0.0 && previous_gap < 0.0) {
                float lo = previous_t;
                float hi = sample_t;
                for (int j = 0; j < OPAQUE_SSR_REFINE_STEPS; ++j) {
                    float mid = 0.5 * (lo + hi);
                    vec2 mid_uv = mix(P0, P1, mid) / resolution;
                    float mid_surface_depth = OpaqueDepthAt(mid_uv);
                    vec3 mid_view = OpaquePerspectivePoint(
                        Q0, Q1, k0, k1, mid);
                    float mid_gap = mid_surface_depth >= 1.0
                        ? -OPAQUE_SSR_THICKNESS
                        : -mid_view.z
                            - LinearDepthFromScreenDepth(mid_surface_depth);
                    if (mid_gap >= 0.0) hi = mid;
                    else lo = mid;
                }

                float hit_t = 0.5 * (lo + hi);
                vec2 hit_uv = mix(P0, P1, hit_t) / resolution;
                float hit_depth = OpaqueDepthAt(hit_uv);
                vec3 hit_view = OpaquePerspectivePoint(
                    Q0, Q1, k0, k1, hit_t);
                float path_length = length(hit_view - view_origin);
                float thickness_error = hit_depth >= 1.0
                    ? 1e20
                    : abs(-hit_view.z
                        - LinearDepthFromScreenDepth(hit_depth));
                vec3 hit_normal = OpaqueGeometricViewNormalAt(hit_uv);
                bool front_facing = dot(hit_normal, -view_direction) > 1e-4;
                bool accepted = path_length > 0.05
                    && path_length <= OPAQUE_SSR_MAX_DISTANCE
                    && thickness_error <= OpaqueTraceThickness(path_length)
                    && front_facing;
                if (accepted) {
                    OpaqueTraceHit hit;
                    hit.screen = vec3(hit_uv, hit_depth);
                    hit.path_length = path_length;
                    hit.thickness_error = thickness_error;
                    hit.valid = true;
                    return hit;
                }
            }
            previous_gap = gap;
        } else {
            previous_gap = -OpaqueTraceThickness(ray_depth);
        }
        previous_t = sample_t;
    }
    return miss;
}

float OpaqueHistoryMip(float path_length, float perceptual_roughness,
        float origin_view_depth, out float cone_pixels) {
    cone_pixels = max(1.0,
        path_length * perceptual_roughness * perceptual_roughness
            * viewHeight / max(origin_view_depth, 1.0));
    int mip_count = textureQueryLevels(colortex5);
    return clamp(log2(cone_pixels), 0.0, float(max(mip_count - 1, 0)));
}

float OpaqueScreenEdgeWeight(vec2 uv) {
    vec2 edge_distance = min(uv, vec2(1.0) - uv);
    return smoothstep(0.005, 0.04, min(edge_distance.x, edge_distance.y));
}

float OpaqueHistoryConfidence(OpaqueTraceHit hit, vec3 previous_hit,
        vec3 hit_geo_normal, vec3 ray_direction) {
    if (!hit.valid || frameCounter < 2 || !OpaqueFinite(previous_hit)) {
        return 0.0;
    }
    if (any(lessThanEqual(previous_hit, vec3(0.0)))
            || any(greaterThanEqual(previous_hit, vec3(1.0)))) {
        return 0.0;
    }

    float thickness_ratio = hit.thickness_error
        / max(OpaqueTraceThickness(hit.path_length), 1e-5);
    float thickness_weight = 1.0 - smoothstep(0.25, 1.0, thickness_ratio);
    float distance_weight = 1.0 - smoothstep(
        OPAQUE_SSR_MAX_DISTANCE * 0.65,
        OPAQUE_SSR_MAX_DISTANCE, hit.path_length);
    float facing_weight = smoothstep(
        0.02, 0.25, dot(hit_geo_normal, -ray_direction));
    float edge_weight = OpaqueScreenEdgeWeight(hit.screen.xy)
        * OpaqueScreenEdgeWeight(previous_hit.xy);

    vec3 camera_delta = cameraPosition - previousCameraPosition;
    float translation_weight = 1.0 - smoothstep(
        0.25, 1.0, length(camera_delta));
    vec3 current_forward = normalize(vec3(
        gbufferModelView[0][2],
        gbufferModelView[1][2],
        gbufferModelView[2][2]));
    vec3 previous_forward = normalize(vec3(
        gbufferPreviousModelView[0][2],
        gbufferPreviousModelView[1][2],
        gbufferPreviousModelView[2][2]));
    float rotation_weight = smoothstep(
        0.5, 0.95, dot(current_forward, previous_forward));

    return clamp(thickness_weight * distance_weight * facing_weight
        * edge_weight * translation_weight * rotation_weight, 0.0, 1.0);
}

vec3 SampleOpaqueHistory(OpaqueTraceHit hit, vec3 hit_geo_normal,
        vec3 ray_direction, float perceptual_roughness,
        float origin_view_depth, out float confidence, out float selected_mip) {
    confidence = 0.0;
    selected_mip = 0.0;
    if (!hit.valid) return vec3(0.0);

    vec3 previous_hit = ToPrevious(hit.screen);
    confidence = OpaqueHistoryConfidence(
        hit, previous_hit, hit_geo_normal, ray_direction);
    if (confidence <= 0.0) return vec3(0.0);

    float cone_pixels;
    selected_mip = OpaqueHistoryMip(
        hit.path_length, perceptual_roughness,
        origin_view_depth, cone_pixels);
    vec3 history = textureLod(
        colortex5, previous_hit.xy, selected_mip).rgb;
    if (!OpaqueFinite(history) || any(lessThan(history, vec3(0.0)))) {
        confidence = 0.0;
        return vec3(0.0);
    }
    return max(history, vec3(0.0));
}

#endif
