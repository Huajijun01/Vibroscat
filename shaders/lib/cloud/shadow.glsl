#ifndef LIB_CLOUD_SHADOW_GLSL
#define LIB_CLOUD_SHADOW_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/cloud/density.glsl"

// Sines of 5 and 18 degrees; the flat column fades out before its projected footprint becomes unbounded.
const float CLOUD_SHADOW_FADE_LOW = 0.08715574;
const float CLOUD_SHADOW_FADE_HIGH = 0.30901699;
const float CLOUD_SHADOW_COLUMN_HEIGHT = 0.3;

// Camera-relative world position in meters.
float CloudShadowTransmittance(vec3 world_pos) {
#if defined(WORLD_OVERWORLD) && defined(VOLUMETRIC_CLOUDS) && defined(CLOUD_SHADOWS)
    float sun_elevation = u_world_sun_dir.y;
    float altitude_km = u_cam_altitude + world_pos.y * 0.001;
    if (sun_elevation <= CLOUD_SHADOW_FADE_LOW || altitude_km >= CLOUD_TOP_ALTITUDE) return 1.0;

    float column_base_km = max(altitude_km, CLOUD_BASE_ALTITUDE);
    float sample_altitude_km = mix(column_base_km, CLOUD_TOP_ALTITUDE, CLOUD_SHADOW_COLUMN_HEIGHT);
    float light_distance_km = (sample_altitude_km - altitude_km) / sun_elevation;
    vec2 sample_xz_km = world_pos.xz * 0.001 + u_world_sun_dir.xz * light_distance_km;
    CloudDensityFrame frame = CloudDensityFrameForRay();
    // Explicit LOD 0: implicit derivatives are undefined behind the receiver-height early return.
    float distribution = textureLod(utex_cloud_distribution_tex,
        CloudDistributionUV(sample_xz_km, frame), 0.0).r;
    float distribution_density = clamp((distribution - frame.distribution_floor) * frame.inv_coverage, 0.0, 1.0);
    float height_fraction = clamp((altitude_km - CLOUD_BASE_ALTITUDE) / CLOUD_THICKNESS_KM, 0.0, 1.0);
    float optical_depth = CloudVerticalOpticalDepth(distribution_density, height_fraction) / sun_elevation;
    float shadow_weight = smoothstep(CLOUD_SHADOW_FADE_LOW, CLOUD_SHADOW_FADE_HIGH, sun_elevation);
    return mix(1.0, exp(-optical_depth), shadow_weight);
#else
    return 1.0;
#endif
}

#endif // LIB_CLOUD_SHADOW_GLSL
