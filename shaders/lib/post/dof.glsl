#ifndef LIB_POST_DOF_GLSL
#define LIB_POST_DOF_GLSL

#include "/lib/contract/dof_data.glsl"
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

// Signed thin-lens-inspired radius, in display pixels. The 80 px*m scale
// and 8 px cap are specified at 1080p; axial depth gives a planar focus.
// Sources are ordered by an uncapped affine inverse-depth coordinate,
// independent of the blur cap and support spread.
const float DOF_LENS_SCALE = 80.0;
const float DOF_RADIUS_LIMIT = 8.0;
const float DOF_FOCUS_HALFLIFE_SECONDS = 0.15;
// Largest finite half: distinct from the scene's uncapped CoC at supported
// settings/resolutions, exactly preserved by the RGBA16F workspace.
const float DOF_HAND_COC = 65504.0;
const vec2 DOF_GOLDEN_ROTATION = vec2(-0.737368878, -0.675490294);

// Area-stratum midpoints sqrt((i + 0.5) / N). Frame-varying STBN rotation
// remains; constant radii remove per-pixel square roots and a second noise read.
#if DOF_QUALITY == 0
const int DOF_SEARCH_SAMPLES = 6;
const int DOF_GATHER_SAMPLES = 8;
const float DOF_SEARCH_RADII[6] = float[](0.288675135, 0.500000000, 0.645497224, 0.763762616, 0.866025404, 0.957427108);
const float DOF_GATHER_RADII[8] = float[](0.250000000, 0.433012702, 0.559016994, 0.661437828, 0.750000000, 0.829156198, 0.901387819, 0.968245837);
#elif DOF_QUALITY == 1
const int DOF_SEARCH_SAMPLES = 10;
const int DOF_GATHER_SAMPLES = 12;
const float DOF_SEARCH_RADII[10] = float[](0.223606798, 0.387298335, 0.500000000, 0.591607978, 0.670820393, 0.741619849, 0.806225775, 0.866025404, 0.921954446, 0.974679434);
const float DOF_GATHER_RADII[12] = float[](0.204124145, 0.353553391, 0.456435465, 0.540061725, 0.612372436, 0.677003200, 0.735980072, 0.790569415, 0.841625412, 0.889756521, 0.935414347, 0.978945010);
#else
const int DOF_SEARCH_SAMPLES = 12;
const int DOF_GATHER_SAMPLES = 24;
const float DOF_SEARCH_RADII[12] = float[](0.204124145, 0.353553391, 0.456435465, 0.540061725, 0.612372436, 0.677003200, 0.735980072, 0.790569415, 0.841625412, 0.889756521, 0.935414347, 0.978945010);
const float DOF_GATHER_RADII[24] = float[](0.144337567, 0.250000000, 0.322748612, 0.381881308, 0.433012702, 0.478713554, 0.520416500, 0.559016994, 0.595119036, 0.629152870, 0.661437828, 0.692218655, 0.721687836, 0.750000000, 0.777281588, 0.803637563, 0.829156198, 0.853912564, 0.877971146, 0.901387819, 0.924211376, 0.946484724, 0.968245837, 0.989528507);
#endif

float DofInverseDepth(float screen_depth) {
    // Native sky has no finite object distance. Hand is tagged separately
    // before this conversion, so its compressed projection is never decoded.
    return screen_depth == 1.0 ? 0.0
        : (2.0 * screen_depth - 1.0) * gbufferProjectionInverse[2][3]
            + gbufferProjectionInverse[3][3];
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
