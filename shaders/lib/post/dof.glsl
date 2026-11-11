#ifndef LIB_POST_DOF_GLSL
#define LIB_POST_DOF_GLSL

#include "/lib/contract/dof_data.glsl"
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Signed thin-lens-inspired radius, in display pixels. The 80 px*m scale
// and 8 px cap are specified at 1080p; axial depth gives a planar focus.
// Sundial-Lite motivated the separate support search and foreground gather;
// this implementation retains actual inverse depth for ordering. See notices.
const float DOF_LENS_SCALE = 80.0;
const float DOF_RADIUS_LIMIT = 8.0;
const float DOF_FOCUS_HALFLIFE_SECONDS = 0.15;
const vec2 DOF_GOLDEN_ROTATION = vec2(-0.737368878, -0.675490294);

#if DOF_QUALITY == 0
const int DOF_SEARCH_SAMPLES = 6;
const int DOF_GATHER_SAMPLES = 8;
#elif DOF_QUALITY == 1
const int DOF_SEARCH_SAMPLES = 10;
const int DOF_GATHER_SAMPLES = 12;
#else
const int DOF_SEARCH_SAMPLES = 12;
const int DOF_GATHER_SAMPLES = 24;
#endif

float DofInverseDepth(float screen_depth) {
    // Native sky has no finite object distance. Hand is tagged separately
    // before this conversion, so its compressed projection is never decoded.
    return screen_depth == 1.0 ? 0.0
        : (2.0 * screen_depth - 1.0) * gbufferProjectionInverse[2][3]
            + gbufferProjectionInverse[3][3];
}

float DofRadius(float inverse_depth_m, float lens_scale_px_m, float radius_limit_px) {
    return clamp((dof_focus_inverse_m - inverse_depth_m) * lens_scale_px_m,
        -radius_limit_px, radius_limit_px);
}

// Point-fetch depth and material together. Negative inverse depth is the
// sharp-hand tag; zero is sky; positive values are physical axial 1/meters.
float DofSceneInverseDepth(ivec2 texel) {
    float screen_depth = texelFetch(depthtex0, texel, 0).r;
    bool hand = screen_depth < 1.0
        && int(texelFetch(colortex1, texel, 0).a * 255.0 + 0.5) == 64;
    return hand ? -1.0 : DofInverseDepth(screen_depth);
}

#endif // LIB_POST_DOF_GLSL
