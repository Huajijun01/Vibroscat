#ifndef LIB_WATER_FOG_GLSL
#define LIB_WATER_FOG_GLSL

#include "/lib/contract/sky_light_data.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/color/color.glsl"
#include "/lib/scattering/phase.glsl"

// Beer-Lambert water column parameters shared by the translucent layer and
// the blend pass (above/underwater consistent).
// Defaults: clear freshwater mapped to RGB (650/550/450 nm):
//   absorption  = pure fresh water (Pope & Fry 1997, Appl. Opt. 36:8710) plus
//                 the Lake Taupo CDOM lower bound a_CDOM(443) = 0.03,
//                 S_CDOM = 0.017 nm^-1 (Belzile et al. 2004, WRR 40, W12512);
//   scattering  = Crater Lake total b(550) = 0.026 m^-1 (molecular 0.0021 +
//                 particle 0.0239; Tyler & Smith 1970, JOSA 62:83), particle
//                 scaled by the clear-lake exponent n = 0.63 (Belzile et al.
//                 2004), molecular per Morel 1974. lambda^-3 is the
//                 backscatter slope, NOT the total-particle slope.
// Runtime values from u_water_absorption/u_water_scattering
// (shaders.properties): swamp -> murky Taupo data, ocean -> open-ocean data,
// all other biomes keep the clear defaults.
const vec3 WATER_ABSORPTION = vec3(0.34, 0.06, 0.04);
const vec3 WATER_SCATTERING = vec3(0.022, 0.026, 0.032);
const vec3 WATER_EXTINCTION = WATER_ABSORPTION + WATER_SCATTERING;
// In-water sunlight path per metre of vertical drop (flat-surface
// refraction, air->water IOR 1.333 inlined - no IOR config needed).
float WaterLightPathPerMetre() {
    vec3 light_dir = normalize(u_world_light_dir);
    vec3 refracted = refract(-light_dir, vec3(0.0, 1.0, 0.0), 1.0 / 1.333);
    return 1.0 / max(-refracted.y, 1.0e-3);
}

// Sunlight path through the column between the surface plane and a point.
float WaterColumnLightPath(vec3 world_pos, float surface_world_y) {
    return max(surface_world_y - world_pos.y, 0.0) * WaterLightPathPerMetre();
}


// Eccentricity of the normalized single-lobe scattering phase used by the
// water fog (the Cornette-Shanks phase function, /lib/scattering/phase.glsl).
// g=0 reduces to the Rayleigh phase; positive g biases scattering toward the
// forward (sun) direction.
const float WATER_PHASE_G = 0.3; // forward-scattering lobe

vec3 WaterAbsorptionTransmittance(float dist) {
    return exp(-u_water_absorption * dist);
}

// Total Beer-Lambert attenuation: scattering removes light from the beam
// (re-emitted as in-scatter elsewhere).
vec3 WaterExtinctionTransmittance(float dist) {
    return exp(-(u_water_absorption + u_water_scattering) * dist);
}

// Analytic single-scattering integral over a segment of length S, sunlight
// path varying linearly lightPath1 -> lightPath2:
//   integral_0^S sigma_s * exp(-sigma_t * (t + L(t))) dt
// (column attenuation inside the closed form, not a post-multiplier).
vec3 WaterScatteringIntegral(float segment_length, float light_path1, float light_path2) {
    vec3 extinction = u_water_absorption + u_water_scattering;
    // Closed form valid for any sign of L2-L1+S; only the exact degenerate
    // case needs the limit (exponentials cancel).
    float delta = light_path2 - light_path1 + segment_length;
    if (abs(delta) < 1.0e-3 * max(segment_length, light_path1 + light_path2 + 1.0)) {
        // t + L(t) constant along the segment: exponent = lightPath1.
        return u_water_scattering * segment_length * exp(-extinction * light_path1);
    }
    vec3 v = exp(-extinction * light_path1) - exp(-extinction * (light_path2 + segment_length));
    return u_water_scattering * segment_length * v / (extinction * delta);
}

// Approximate multiple scattering (uniform-phase geometric-series;
// concept after Hillaire EGSR 2020). Per-order fraction = albedo
// omega = sigmas/(sigmas+sigmaa), so sigmas/sigmaa sums all orders. Medium constant (not
// raylen-dependent) avoids perspective inconsistency. Epipolar visibility
// softened to 0.8R+0.2 (scattering leaks into shadows).

const float WATER_MS_SCALE = 0.3;

vec3 WaterMultipleScattering(vec3 sca, vec3 epipolar_light) {
    vec3 v_ms = u_water_scattering / max(u_water_absorption, vec3(1e-3))
             * PHASE_ISOTROPIC;
    return WATER_MS_SCALE * sca * v_ms * (epipolar_light * 0.8 + 0.2);
}

// Water fog compositing. Caller must provide the Iris uniforms (wetness,
// eyeBrightnessSmooth, isEyeInWater) and the groundLight SSBO before
// including this file, plus the column light paths at the segment ends
// (0 at the surface). phaseSun/phaseSky: normalized phases for the direct
// light and the ambient sky lobe. fogMultiScatter: the SH sky-light
// evaluation (EvalSkyLight) standing in for the multi-scatter/ambient lobe.
void WaterFogRender(inout vec3 col, float raylen, float light_path1, float light_path2, float phase_sun, float phase_sky,
                    vec3 fog_multi_scatter, vec3 epipolar_light, float caustic_factor) {
    vec3 t = WaterExtinctionTransmittance(raylen);
    t = mix(t, vec3(Luminance(t)), wetness * 0.8);
    col *= t;
    vec3 sca = WaterScatteringIntegral(raylen, light_path1, light_path2);
    col += sca * (caustic_factor * ground_light.rgb * phase_sun * eyeBrightnessSmooth.y
            * (1.0 / 240.0) * epipolar_light
        + fog_multi_scatter * phase_sky * (isEyeInWater == 0 ? eyeBrightnessSmooth.y * (1.0 / 240.0) : 1.0));
    col += WaterMultipleScattering(sca, epipolar_light) * ground_light.rgb * eyeBrightnessSmooth.y * (1.0 / 240.0);
}

#endif
