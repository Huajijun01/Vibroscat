#ifndef LIB_CLOUD_DENSITY_GLSL
#define LIB_CLOUD_DENSITY_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"

struct CloudDensityFrame {
    float coverage;
    float distribution_floor;
    float inv_coverage;
    vec2 camera_xz_km;
    vec2 distribution_uv_offset;
};

struct CloudHeightProfile {
    float height_fraction;
    float bottom_ramp;
    float fine_exposure;
};

// Mean of the baked R8 erosion volume, decoded to [0, 1].
const float CLOUD_VORONOISE_MEAN = 0.484805118;

float CloudRemapErosion(float density, float threshold) {
    threshold = saturate(threshold);
    return saturate((density - threshold) / max(1.0 - threshold, 1.0e-5));
}

// Local planet-space XZ is camera-relative. The frame offset already
// contains camera XZ / scale and wind advection, so translation is applied once.
vec2 CloudDistributionUV(vec2 local_xz_km, CloudDensityFrame frame) {
    return local_xz_km * (1.0 / CLOUD_DISTRIBUTION_SCALE_KM) + frame.distribution_uv_offset;
}

// Coverage and absolute/wind offsets are constant across view and light samples.
CloudDensityFrame CloudDensityFrameForRay() {
    CloudDensityFrame frame;
    frame.coverage = CLOUD_COVERAGE * (1.0 - rainStrength) + rainStrength;
    frame.distribution_floor = 1.0 - frame.coverage;
    frame.inv_coverage = 1.0 / max(frame.coverage, 1.0e-5);
    frame.camera_xz_km = u_cloud_absolute_km_offset;
    frame.distribution_uv_offset = frame.camera_xz_km * (1.0 / CLOUD_DISTRIBUTION_SCALE_KM)
        + vec2(frameTimeCounter * (CLOUD_WIND_SPEED / CLOUD_DISTRIBUTION_SCALE_KM), 0.0);
    return frame;
}

// Normalized height and density-independent ramps, evaluated once per sample.
CloudHeightProfile CloudHeightProfileFor(float altitude_km) {
    CloudHeightProfile profile;
    profile.height_fraction = saturate((altitude_km - CLOUD_BASE_ALTITUDE)
        / max(CLOUD_TOP_ALTITUDE - CLOUD_BASE_ALTITUDE, 1.0e-5));
    profile.bottom_ramp = smoothstep(0.0, 0.2, profile.height_fraction);
    profile.fine_exposure = smoothstep(0.0, 0.5, profile.height_fraction) * 0.6 + 0.4;
    return profile;
}

// Shared base field for view and light samples. With coverage in [0, 1],
// the upper edge exceeds the lower edge by 0.5 + 0.1 * distribution_density.
float CloudBaseDensity(float distribution_density, CloudHeightProfile profile) {
    float top_fade = 1.0 - smoothstep(distribution_density * 0.4,
        distribution_density * 0.5 + 0.5, profile.height_fraction);
    return distribution_density * profile.bottom_ramp * top_fade;
}

// Eroded density in [0, 1] at one point in the cloud layer. The caller owns
// the altitude band test (it needs the raw altitude for CloudHeightProfileFor
// anyway) and the distribution read: the view march issues that 2D fetch one
// sample ahead, so this decode consumes it from a register and only the
// fine-detail volume read happens here, behind the density gates.
float DecodeCloudDensity(vec3 atmosphere_position, CloudDensityFrame frame, CloudHeightProfile profile,
    float distribution_fetch
) {
    vec2 density_absolute_km = atmosphere_position.xz + frame.camera_xz_km;
    float distribution_density = saturate((distribution_fetch
        - frame.distribution_floor) * frame.inv_coverage);
    if (distribution_density < 0.001) {
        return 0.0;
    }
    float lq_density = CloudBaseDensity(distribution_density, profile);
    if (lq_density < 0.001) {
        return 0.0;
    }
    float detailed_noise = texture(utex_cloud_voronoise_tex,
        vec3(density_absolute_km, length(atmosphere_position) - ATM_PLANET_R) * CLOUD_FINE_EROSION_SCALE).r;
    float hq_density = CloudRemapErosion(lq_density,
        detailed_noise * CLOUD_FINE_EROSION_STRENGTH * profile.fine_exposure);
    return hq_density;
}

// Mean-erosion density shared by directional and upward sky transport.
float CloudDensityLowQuality(float distribution_density, CloudHeightProfile profile) {
    return CloudRemapErosion(CloudBaseDensity(distribution_density, profile),
        CLOUD_VORONOISE_MEAN * CLOUD_FINE_EROSION_STRENGTH * profile.fine_exposure);
}

// Directional transport reads the distribution at each light sample. The
// erosion threshold uses the texture mean, saving one 3D read per light step.
float SampleCloudDensityLowQuality(vec3 atmosphere_position, CloudDensityFrame frame, CloudHeightProfile profile
) {
    float distribution_density = saturate((
        texture(utex_cloud_distribution_tex,
            CloudDistributionUV(atmosphere_position.xz, frame)).r
        - frame.distribution_floor) * frame.inv_coverage);
    if (distribution_density < 0.001) {
        return 0.0;
    }
    return CloudDensityLowQuality(distribution_density, profile);
}

#endif // LIB_CLOUD_DENSITY_GLSL
