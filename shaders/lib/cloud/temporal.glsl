#ifndef LIB_CLOUD_TEMPORAL_GLSL
#define LIB_CLOUD_TEMPORAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/filters.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/core/render_scale.glsl"
#include "/lib/cloud/checkerboard.glsl"
#include "/lib/cloud/signal.glsl"

// Camera-only reprojection: the stationary erosion and scrolling distribution are not a rigid flow.
bool CloudProjectToPrevious(vec3 view_dir_world, float distance_km, out vec2 previous_uv) {
    vec3 world_pos = view_dir_world * (distance_km * 1000.0);
    vec4 previous_view = gbufferPreviousModelView
        * vec4(world_pos + u_camera_delta, 1.0);
    vec4 previous_clip = gbufferPreviousProjection * previous_view;
    if (previous_clip.w <= 0.0) return false;
    vec3 previous_ndc = previous_clip.xyz / previous_clip.w;
    previous_uv = previous_ndc.xy * 0.5 + 0.5;
    return all(greaterThanEqual(previous_uv, vec2(0.0)))
        && all(lessThanEqual(previous_uv, vec2(1.0)));
}

// Active lower-left cloud rectangle in colortex12 alt, matching clouds_render.
ivec2 CloudCurrentImageSize() {
    return max(ivec2(u_render_res * CLOUD_CURRENT_SCALE), ivec2(1));
}

// Low-res texel centers sit at (id + r2_offset) * cell_size in full-res pixels, so lattice coordinates are valid centers.
vec2 CloudCurrentGridPosition(ivec2 full_res_texel) {
    vec2 low_size = vec2(CloudCurrentImageSize());
    vec2 cell_size = u_render_res / low_size;
#if CLOUD_TEMPORAL_UPSCALING == 1
    vec2 r2_offset = vec2(0.5);
#else
    vec2 r2_offset = R2Offset();
#endif
    return (vec2(full_res_texel) + 0.5) / cell_size - r2_offset;
}

// Scattering/transmittance are bilinear-filtered; distance stays the nearest sample so reprojection never invents a depth.
CloudFrame CloudSampleCurrentBilinear(ivec2 full_res_texel) {
    vec2 low_size = vec2(CloudCurrentImageSize());
    vec2 low_texel_size = 1.0 / low_size;
    vec2 grid_position = CloudCurrentGridPosition(full_res_texel);
    vec2 current_uv = (grid_position + 0.5) * low_texel_size;
    current_uv = clamp(current_uv, 0.5 * low_texel_size, vec2(1.0) - 0.5 * low_texel_size);
    current_uv *= low_size / vec2(textureSize(colortex12, 0));
    vec4 value = texture(colortex12, current_uv);

    ivec2 nearest_texel = clamp(
        ivec2(floor(grid_position + 0.5)),
        ivec2(0),
        ivec2(low_size) - ivec2(1)
    );
    CloudFrame frame = DecodeCloudFrame(value);
    frame.distance_km = texelFetch(colortex12, nearest_texel, 0).a;
    return frame;
}

bool CloudHistoryInvalid(CloudFrame history) {
    return any(isnan(history.signal.scattering)) || isnan(history.signal.transmittance)
        || isnan(history.distance_km) || !(history.distance_km > 0.0);
}

// The reprojected center texel gates first: CR taps crossing the sky/geometry boundary would
// blend in the AO-side NaN marker (A = 0 reads as a small positive distance). Caller falls back on a NaN frame.
CloudFrame CloudHistorySample(vec2 previous_uv) {
    vec2 texel = 1.0 / u_render_res;
    vec2 clamped_uv = clamp(previous_uv, 2.0 * texel, 1.0 - 2.0 * texel);

    ivec2 center_texel = ivec2(clamped_uv * u_render_res);
    if (!(texelFetch(colortex8, center_texel, 0).a > 0.0)) {
        return DecodeCloudFrame(vec4(HISTORY_NO_CLOUD_DATA));
    }

#if defined(TAAU_ACTIVE)
    vec4 col = FastCatmullRom5Tap(colortex8, SceneTextureUV(clamped_uv), u_view_pixel_size, 0.5);
#else
    vec4 col = FastCatmullRom5Tap(colortex8, clamped_uv, u_view_pixel_size, 0.5);
#endif
    return DecodeCloudFrame(col);
}

// Distance is a hit location: never EMA-mixed, keeps the current sample.
CloudFrame CloudAccumulate(CloudFrame current, CloudFrame history, int pixel_age
) {
    if (any(isnan(history.signal.scattering)) || isnan(history.signal.transmittance)
        || isnan(history.distance_km)) {
        return current;
    }
    float alpha = 1.0 / float(min(pixel_age + 1, CLOUD_HISTORY_FRAMES));
    CloudFrame result;
    result.signal.scattering = vec2(mix(history.signal.scattering.x, current.signal.scattering.x, alpha),
        mix(history.signal.scattering.y, current.signal.scattering.y, alpha));
    result.signal.transmittance = mix(history.signal.transmittance,
        current.signal.transmittance, alpha);
    result.distance_km = current.distance_km;
    return result;
}

#if CLOUD_RECONSTRUCTION_MODE == 1 && CLOUD_TEMPORAL_UPSCALING > 1

// Provisional spatial fill; phase_offset is uniform per frame and already evaluated by the caller.
CloudFrame CloudCheckerboardCurrent(ivec2 full_res_texel, ivec2 phase_offset, float shell_distance) {
    vec2 grid = (vec2(full_res_texel) - vec2(phase_offset))
        / float(CLOUD_TEMPORAL_UPSCALING);
    ivec2 base = ivec2(floor(grid));
    vec2 fraction = grid - vec2(base);
    ivec2 grid_max = CloudCheckerboardSize() - 1;
    vec3 scattering_transmittance_sum = vec3(0.0);
    float weight_sum = 0.0;
    float nearest_squared = 1.0e30;
    CloudFrame result;
    result.signal = CloudSignal(vec2(0.0), 1.0);
    result.distance_km = shell_distance;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            float weight = (x == 0 ? 1.0 - fraction.x : fraction.x)
                * (y == 0 ? 1.0 - fraction.y : fraction.y);
            if (weight <= 0.0) continue;
            ivec2 texel = clamp(base + ivec2(x, y), ivec2(0), grid_max);
            vec4 sample_value = texelFetch(colortex12, texel, 0);
            if (!(sample_value.a > 0.0)) continue;
            scattering_transmittance_sum += sample_value.rgb * weight;
            weight_sum += weight;
            vec2 delta = vec2(texel) - grid;
            float delta_squared = dot(delta, delta);
            if (delta_squared < nearest_squared) {
                nearest_squared = delta_squared;
                result.distance_km = sample_value.a;
            }
        }
    }
    if (weight_sum > 0.0) {
        result.signal = CloudSignal(scattering_transmittance_sum.xy / weight_sum,
            scattering_transmittance_sum.z / weight_sum);
    }
    return result;
}

// Distance uses the reprojected center sample, not the cubic weights; filter taps clamp to the scene rectangle.
CloudFrame CloudCheckerboardHistory(vec2 previous_uv) {
    ivec2 center = clamp(ivec2(previous_uv * u_render_res), ivec2(0), ivec2(u_render_res) - 1);
    vec4 center_value = texelFetch(colortex8, center, 0);
    CloudFrame result = DecodeCloudFrame(center_value);
    if (CloudHistoryInvalid(result)) return result;
    vec4 filtered = FastCatmullRom5Tap(colortex8, previous_uv * u_render_scale,
        u_view_pixel_size, 0.5, 0.5 * u_view_pixel_size,
        (u_render_res - 0.5) * u_view_pixel_size, true);
    if (any(isnan(filtered))) {
        result.distance_km = HISTORY_NO_CLOUD_DATA;
        return result;
    }
    result.signal = CloudSignal(max(filtered.xy, vec2(0.0)), clamp(filtered.z, 1.0e-4, 1.0));
    return result;
}

// Age counts consecutive accepted screen frames, not transported observations; the first full cycle replaces provisional fills.
CloudFrame CloudCheckerboardAccumulate(CloudFrame current, CloudFrame history, int pixel_age) {
    if (pixel_age < CLOUD_CHECKERBOARD_AREA) return current;
    float dense_alpha = 1.0 / float(min(pixel_age + 1, CLOUD_HISTORY_FRAMES));
    // Exact multiplies instead of pow: avoids the exp2/log2 chain and its negative-base hazard.
    float retained = 1.0 - dense_alpha;
#if CLOUD_TEMPORAL_UPSCALING == 2
    float retained2 = retained * retained;
    float decayed = retained2 * retained2;
#elif CLOUD_TEMPORAL_UPSCALING == 3
    float retained2 = retained * retained;
    float retained4 = retained2 * retained2;
    float decayed = retained4 * retained4 * retained;
#else
    float retained2 = retained * retained;
    float retained4 = retained2 * retained2;
    float retained8 = retained4 * retained4;
    float decayed = retained8 * retained8;
#endif
    float alpha = 1.0 - decayed;
    CloudFrame result;
    // Transmittance must average arithmetically with the same observation weights as scattering;
    // a geometric mean darkens silhouettes without a matching scattering change.
    result.signal.scattering = mix(history.signal.scattering, current.signal.scattering, alpha);
    result.signal.transmittance = mix(history.signal.transmittance,
        current.signal.transmittance, alpha);
    result.distance_km = current.distance_km;
    return result;
}

#endif

#endif // LIB_CLOUD_TEMPORAL_GLSL
