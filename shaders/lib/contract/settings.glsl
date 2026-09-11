#ifndef LIB_CONTRACT_SETTINGS_GLSL
#define LIB_CONTRACT_SETTINGS_GLSL

// Consolidated compile-time settings: every config module (post,
// clouds, shadows, water, fog, ao) and the shared lighting
// constants in one file. Edit the values here; consumers include
// only this file.

// ==========================================================================
// POST - Post / tonemap
// ==========================================================================
#define TAA
//#define DOF
//#define MOTION_BLUR
#define MB_STRENGTH 0.8 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]


// Diffuse indirect source: both SSGI and RSM supply SH for uncovered directions.
#define GI_MODE 0 // [0 1 2] 0=None 1=SSGI 2=ReflectiveShadowMap
#define GI_DENOISE
#define GI_HISTORY_FRAMES 24 // [4 8 16 24 31]
#define RSM_SAMPLES 16 // [8 16 32 64]
#define RSM_RADIUS 8.0 // [2.0 4.0 8.0 12.0 16.0 24.0]
#define RSM_STRENGTH 3.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0]
#define RSM_SKY_OCCLUSION // Darkens SH where the shadow map shows sky occlusion; off compiles the tracking path out.
#define RSM_SKY_OCCLUSION_FLOOR 0.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define RSM_DEBUG 0 // [0 1 2 3 4] 0=Scene 1=Raw 2=Temporal 3=Filtered 4=HistoryAge



#define BLOOM
#define BLOOM_STRENGTH 0.1 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define COLOR_DITHER_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Color dither strength: 0.5=conservative, 1.0=default, 2.0=aggressive

#define AE
#define AE_TARGET_LUMINANCE 0.18 // [0.08 0.10 0.12 0.15 0.18 0.21 0.24 0.28 0.32 0.40] Auto-exposure reference display key; 0.18 is middle gray
#define AE_ADAPTATION_STRENGTH 0.70 // [0.0 0.25 0.40 0.55 0.70 0.85 1.0] Scene-key EV compensation; 0=fixed exposure, 1=full compensation

#define CAS
#define CAS_SHARPNESS 0.75 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

// Tonemap operator (0 = AgX, 1 = OKLAB, 2 = ACES, 3 = Reinhard-Gamut,
// 4 = GT7, 5 = Reinhard-AgX)
#define TONEMAP_MODE 4 // [0 1 2 3 4 5] Tonemap: 0=AgX 1=OKLAB 2=ACES 3=Reinhard-Gamut 4=GT7 5=Reinhard-AgX
#define TONEMAP_EXPOSURE 0.0 // [-2.0 -1.5 -1.0 -0.75 -0.5 -0.25 0.0 0.25 0.5 0.75 1.0 1.5 2.0] Manual exposure (EV), applied before auto-exposure
#define TONEMAP_SATURATION 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5] Pre-tonemap saturation
#define TONEMAP_STRENGTH 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0] Blend between linear HDR and tonemapped result

#define PURKINJE_EFFECT // Requires AE: rod-vision night grading driven by the exposure state.
#define PURKINJE_STRENGTH 0.8 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] Night vision strength
// Rod-vision (scotopic) model, gated by the exposure state alone. The
// adaptation key is reconstructed from the persistent exposure EV and ramps
// the rod share log-linearly across the mesopic band: 0.004 anchors near the
// full-moon night key (moon ground irradiance ATM_MOON_IRR * ATM_EXPOSURE ~
// 0.007), 0.04 stays below the daylight key. CONE_LUMINANCE is the
// post-exposure luminance pivot where cone color vision retakes over (0.35 ~
// +1 EV over the 0.18 exposure target); the tint is the unit-luminance rod
// gray.
const float PURKINJE_SCOTOPIC_KEY = 0.004;
const float PURKINJE_PHOTOPIC_KEY = 0.04;
const float PURKINJE_CONE_LUMINANCE = 0.35;
const vec3 PURKINJE_TINT = vec3(0.45, 0.65, 1.0);

// AgX look and adjustments (only used when TONEMAP_MODE == 0)
#define TONEMAP_AGX_LOOK 1 // [0 1 2] AgX look: 0=Base 1=Punchy 2=Greyscale
#define TONEMAP_AGX_CONTRAST 0.95 // [0.5 0.6 0.7 0.8 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5] AgX log-domain contrast around the mid-grey pivot
#define TONEMAP_AGX_SATURATION 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0] AgX display-domain saturation
#define TONEMAP_AGX_GAMMA 0.9 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5] AgX display-domain gamma

// AgX-S2O3 curve parameters (linlin MIT implementation; pack 0.18 anchor).
#define TONEMAP_AGX_TOE_POWER 3.0
#define TONEMAP_AGX_SHOULDER_POWER 3.25
#define TONEMAP_AGX_GAMUT_COMPRESSION 0.2
const float AGX_INPUT_PIVOT = 0.6060606060606061;   // 10 / 16.5 EV
const float AGX_OUTPUT_PIVOT = 0.48943708957387834; // sRGB OETF(0.18)
const float AGX_PIVOT_SLOPE = 2.0;
const float AGX_TOE_A = 63.74164317180604;      // curve_coefficient(0.60606, 0.48944, 2.0, 3.0)
const float AGX_SHOULDER_A = 63.9174843229821;  // curve_coefficient(0.39394, 0.51056, 2.0, 3.25)
const vec3 AGX_NEUTRAL_WEIGHTS = vec3(0.2120053547549465, 0.3921825078090138, 0.3958121374360396);

// Oklab DRT (TONEMAP_MODE == 1): Ottosson display rendering transform.
// Highlight asymptote E (0.5..2.0); mid-grey 0.18 is preserved for any E.
#define TONEMAP_OKLAB_OVEREXPOSURE 1.0 // [0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5 1.55 1.6 1.65 1.7 1.75 1.8 1.85 1.9 1.95 2.0] Oklab DRT highlight asymptote

// Reinhard-Gamut (TONEMAP_MODE == 3): virtual-gamut Reinhard experiment.
// Input scale maps scene-linear 18% gray back to 18% (default 1/(1-0.18)).
#define TONEMAP_RG_GAMUT_EXPANSION 0.03 // [0.0 0.01 0.02 0.03 0.04 0.05 0.1 0.15 0.2 0.3 0.4 0.5 0.6 0.7 0.8] Reinhard-Gamut virtual-primary expansion (coordinates contract toward neutral)
#define TONEMAP_RG_INPUT_SCALE 1.2195122 // [0.1 0.2 0.3 0.5 0.75 1.0 1.2195122 1.5 2.0 3.0 4.0 6.0 8.0] Reinhard-Gamut input scale (1/(1-0.18) preserves 18% gray)
#define TONEMAP_RG_HIGHLIGHT_REACH_EV 6.5 // [6.0 6.5 7.0 7.5 8.0 9.0 10.0 12.0 15.0 20.0] Reinhard-Gamut scene stops above 18% gray that first reach the display peak
#define TONEMAP_RG_HUE_RETENTION 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] Reinhard-Gamut original-hue retention (shortest hue angle)

// Reinhard-AgX (TONEMAP_MODE == 5): DRT Bench's linear-shadow / AgX-shoulder
// hybrid. It shares the virtual gamut and the HSV hue repair with
// Reinhard-Gamut and adds the log shoulder plus its power. Defaults are the
// DRT tool's.
#define TONEMAP_RA_GAMUT_EXPANSION 0.04 // [0.0 0.01 0.02 0.03 0.04 0.05 0.1 0.15 0.2 0.3 0.4 0.5 0.6 0.7 0.8] Reinhard-AgX virtual-primary expansion (coordinates contract toward neutral)
#define TONEMAP_RA_INPUT_SCALE 1.2195122 // [0.1 0.2 0.3 0.5 0.75 1.0 1.2195122 1.5 2.0 3.0 4.0 6.0 8.0] Reinhard-AgX input scale (1/(1-0.18) preserves 18% gray)
#define TONEMAP_RA_COMPRESSION_START 0.18 // [0.0 0.05 0.1 0.15 0.18 0.25 0.35 0.5 0.7 0.9] Reinhard-AgX scene-linear level where the linear segment hands over to the log shoulder
#define TONEMAP_RA_HIGHLIGHT_REACH_EV 8.0 // [4.0 5.0 6.0 6.5 7.0 7.5 8.0 9.0 10.0 12.0 15.0 20.0] Reinhard-AgX scene stops above 18% gray that first reach the display peak
#define TONEMAP_RA_SHOULDER_POWER 5.0 // [1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0] Reinhard-AgX log-shoulder power (higher holds the linear segment longer and sharpens the knee)
#define TONEMAP_RA_HUE_RETENTION 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] Reinhard-AgX original-hue retention (shortest hue angle)

// GT7 Tone Mapping (TONEMAP_MODE == 4): Polyphony Digital color-volume
// mapping (SIGGRAPH 2025 course, official MIT sample). The curve parameters
// use the official SDR preset except alpha 0 (shoulder converges exactly to
// paper white; see lib/color/color.glsl) and are fixed there.
#define TONEMAP_GT7_BLEND 0.6 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] GT7 blend between the per-channel curve and the chroma-fade UCS path (official 0.6)
#define TONEMAP_GT7_CHROMA_FADE_START 0.98 // [0.80 0.85 0.90 0.94 0.96 0.98 1.00 1.02 1.04] GT7 chroma-fade start, UCS luma relative to paper white (official 0.98)
#define TONEMAP_GT7_CHROMA_FADE_END 1.16 // [1.00 1.04 1.08 1.12 1.16 1.20 1.24 1.28] GT7 chroma-fade end where chroma reaches fully faded (official 1.16)

// ==========================================================================
// CLOUDS - Cloud layers (volumetric + cirrus)
// ==========================================================================
#define VOLUMETRIC_CLOUDS // Enable volumetric cloud rendering.
#define CIRRUS // Enable the high-altitude cirrus shell; independent of the volumetric layer.
#define CLOUD_VIEW_MIN_STEPS 32 // [24 32 40 48 56 64 96 128] Minimum cloud steps for short view rays; higher values stabilize near silhouettes at higher cost.
#define CLOUD_VIEW_MAX_STEPS 128 // [64 80 96 112 128 160 192 256] Maximum cloud steps for long view rays; controls horizon quality and cost.
#define CLOUD_VIEW_TARGET_STEP_KM 0.4 // [0.2 0.25 0.3 0.4 0.5 0.75 1.0] Adaptive step target distance (km); smaller = denser sampling.
#define CLOUD_LIGHT_STEPS 8 // [3 4 5 6 8] Light-direction steps per cloud sample; affects self-shadow quality and primary lighting cost.
#define CLOUD_BASE_ALTITUDE 1.4 // [0.8 1.0 1.2 1.4 1.6 1.8 2.0] Cloud base altitude above terrain (km).
#define CLOUD_THICKNESS_KM 1.5 // [0.6 0.8 1.0 1.2 1.4 1.5 1.6 1.8 2.0] Cloud layer vertical thickness (km).
#define CLOUD_TOP_ALTITUDE (CLOUD_BASE_ALTITUDE + CLOUD_THICKNESS_KM) // Auto-computed from cloud base altitude and thickness.
#define CLOUD_COVERAGE 0.5 // [0.35 0.4 0.45 0.5 0.55 0.58 0.62 0.66 0.7 0.75] Overall cloud coverage; higher = wider coverage and more connected cloud shapes.
#define CLOUD_DISTRIBUTION_SCALE_KM 280.0 // [48.0 64.0 80.0 96.0 128.0 160.0 192.0 240.0 280.0] 2D Worley fBm distribution map world-space scale for a full wrap (km).
#define CLOUD_WIND_SPEED 0.01 // [0.0 0.005 0.01 0.015 0.02 0.03 0.04 0.06 0.08 0.1] Cloud wind speed (km/s); distribution drifts with wind, higher = faster motion.
#define CLOUD_FINE_WIND_FACTOR 2.0 // [1.0 1.25 1.5 1.75 2.0 2.5 3.0] Fine erosion wind speed multiplier; >1 makes details flow faster through clouds for inner motion.
#define CLOUD_EROSION_SCALE_KM 1.5 // [1.5 2.0 3.0 4.0 5.0 6.0 8.0 10.0 12.0] 3D Perlin-Worley erosion texture world-space scale for a full wrap (km).
#define CLOUD_EROSION_STRENGTH 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.65 0.8] Pure Perlin-Worley low-frequency erosion strength.
#define CLOUD_FINE_EROSION_SCALE_KM 0.4 // [0.4 0.5 0.65 0.8 1.0 1.25 1.5 2.0] Channel A independent detail noise scale for a full wrap (km).
#define CLOUD_FINE_EROSION_STRENGTH 0.1 // [0.0 0.05 0.1 0.15 0.18 0.2 0.25 0.3 0.4] Channel A independent curl distortion detail erosion strength.
#define CLOUD_FINE_EROSION_HEIGHT 0.3 // [0.15 0.25 0.3 0.35 0.45 0.55 0.7 0.85 1.0] Normalized height for fine erosion to grow from base to full strength.
#define CLOUD_DENSITY_MULTIPLIER 1.0 // [0.5 0.7 0.85 1.0 1.15 1.3 1.5] final density multiplier; raises opacity and self-shadow together
#define CLOUD_LIGHT_MAX_DISTANCE_KM 2.0 // [1.0 1.5 2.0 3.0 4.0 6.0 8.0] Maximum light-direction optical depth trace distance (km).
#define CLOUD_PHASE_FORWARD_G 0.9 // [0.65 0.75 0.8 0.85 0.9 0.95] HanPi forward HG eccentricity.
#define CLOUD_PHASE_BACKWARD_G 0.3 // [0.15 0.2 0.25 0.3 0.35 0.4] HanPi backward HG eccentricity.
#define CLOUD_MS_ATTENUATION 0.5 // [0.25 0.35 0.5 0.65 0.75 0.85 1.0] HanPi per-octave optical depth multiplier.
#define CLOUD_MS_CONTRIBUTION 0.5 // [0.0 0.25 0.35 0.5 0.65 0.7 0.75 1.0] HanPi per-octave energy multiplier.
#define CLOUD_MS_ECCENTRICITY 0.5 // [0.0 0.25 0.33 0.4 0.5 0.6 0.75 1.0] HanPi per-octave phase eccentricity multiplier.
#define CLOUD_MS_DEPTH_POWER 1.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.75 1.0 1.25 1.5 2.0] HP bottom-confidence depth exponent.
#define CLOUD_MS_DEPTH_BIAS -0.07 // [-0.3 -0.15 -0.07 0.0 0.15 0.3 0.5] HP bottom-confidence normalized-height bias.
#define CLOUD_MS_BOUNDARY_CONFIDENCE 1.0 // [0.0 0.25 0.5 0.75 1.0] HP wrap boundary backlight confidence.
#define CLOUD_PHI_INTENSITY 0.2 // [0.0 0.2 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Vibroscat phi_fwd initial intensity.
#define CLOUD_PHI_COMPRESSION 0.5 // [0.0 0.1 0.25 0.5 1.0 2.0] Vibroscat phi_fwd soft compression.
#define CLOUD_SKY_LIGHT_STRENGTH 8.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0 6.0 8.0] Sky environment scattering total strength; higher = brighter cloud shadow regions.

#define CLOUD_TEMPORAL_UPSCALING 3   // [1 2 3 4] low-res render divisor (1 = full resolution)
//#define CLOUD_HISTORY_GUIDED_MARCH_END // Guide the view march end from reprojected cloud history.
#define CLOUD_HISTORY_GUIDED_END_SCALE 1.2 // [1.0 1.05 1.10 1.15 1.20 1.25] centroid-distance safety scale
#define CLOUD_AGE_LIMIT 24 // [8 12 16 24 32 48] accepted-frame/history-weight cap
#define CLOUD_NO_CLOUD_DISTANCE 1e4  // no-cloud distance sentinel (km, half-float safe)
#define CLOUD_HISTORY_NO_DATA uintBitsToFloat(0x7fc00000u)  // NaN marker: history slot has no data

// ==========================================================================
// SHADOWS - Shadows / PCSS / SSS
// ==========================================================================
const int shadowMapResolution = 2048; // [1024 1536 2048 3072 4096 6144 8192]
const bool shadowHardwareFiltering = true;
const float sunPathRotation = -15.0;
const float shadowIntervalSize = 2.0;
const float real_shadow_map_resolution = float(shadowMapResolution);
const float shadowDistance = 128.0;

// Shadow depth protection: the shadow map depth is
// remapped from [0,1] into [0.5-0.5*SCALE, 0.5+0.5*SCALE] so depth never
// approaches the near/far planes, preserving precision and leaving headroom
// for bias. Every producer/consumer of shadow depth must use the same map.
const float SHADOW_DEPTH_SCALE = 1.0 / 6.0;

// PCSS shadows (Fernando 2005 framework, custom implementation). The LOW
// profile disables the penumbra estimation + radius PCF and falls back to
// hardware bilinear shadow filtering; the blocker search stays on (while
// SHADOW_SSS is on) so the plant-SSS thickness estimate keeps working.
#define SHADOW_PCSS
#define SHADOW_BLOCKER_SAMPLES 4 // [2 3 4 5 6 8 10 12]
#define SHADOW_BLOCKER_SEARCH_TEXELS 12.0 // [4.0 6.0 8.0 10.0 12.0 16.0 20.0 24.0]
#define SHADOW_SUN_ANGULAR_RADIUS 0.05 // [0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.10 0.12 0.15]
#define SHADOW_PCF_MIN_SAMPLES 4 // [2 3 4 5 6 8]
#define SHADOW_PCF_MAX_SAMPLES 16 // [6 8 10 12 16 20 24]
#define SHADOW_PCF_GAIN 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5]
#define SHADOW_SUN_HEIGHT_BOOST 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define SHADOW_DISTANCE_BOOST 1.5 // [1.0 1.25 1.5 1.75 2.0 2.5 3.0]
#define SHADOW_CONTACT_SHARPEN_TEXELS 4.0 // [1.0 2.0 3.0 4.0 6.0 8.0]
#define SHADOW_BLOCKER_DEPTH_TOLERANCE_METERS 0.0 // [0.0 0.05 0.1 0.15 0.2 0.3 0.5]

// Plant subsurface scattering settings.
#define SHADOW_SSS // Plant translucency transmission; off compiles the SSS lighting and thickness estimate out.
#define SHADOW_SSS_STEPS 8 // [4 6 8 10 12 16]
#define SHADOW_SSS_DENSITY 3.0 // [1.0 2.0 3.0 4.0 6.0 8.0]
#define SHADOW_SSS_SCALE 1.0 // [0.5 1.0 1.5 2.0 2.5 3.0 4.0]
#define SHADOW_SSS_PENUMBRA_BOOST 7.0 // [0.0 1.0 2.0 3.0 5.0 7.0 10.0]
#define SHADOW_SSS_PHASE_G 0.4 // [0.0 0.3 0.4 0.5 0.6 0.7 0.8 0.9]
#define SHADOW_SSS_FADE_START 0.75 // [0.0 0.5 0.6 0.7 0.75 0.8 0.9 0.95]
#define SHADOW_SSS_ENERGY 0.85 // [0.1 0.2 0.3 0.35 0.4 0.5 0.6 0.8 0.85 1.0]
#define SHADOW_SSS_DEBUG 0 // [0 1] Isolate plant transmission in deferred shading.

// Screen-space contact shadows (short-range, alongside the shadow map):
// deferred4 marches a screen-projected ray toward the active directional
// light against depthtex1 per receiver pixel and applies the result as an
// upper bound (min) on the shadow-map result, so it fills PCF contact seams
// and keeps directional occlusion past the shadow map boundary. Overworld and
// End only (the Nether has no directional light).
#define CONTACT_SHADOWS 1 // [0 1] Screen-space contact shadows; 0 = off.
#define CONTACT_SHADOW_STEPS 12 // [4 6 8 12 16 24] depth samples per receiver pixel.
#define CONTACT_SHADOW_MAX_DISTANCE 24.0 // [4.0 6.0 8.0 12.0 16.0 24.0] world-space march reach cap (m); the reach scales with view distance.
#define CONTACT_SHADOW_THICKNESS 0.02 // [0.02 0.05 0.1 0.25 0.5 1.0] near-field occluder thickness slab (m); it also widens with view distance.
#define CONTACT_SHADOW_DEBUG 0 // [0 1 2] debug view: 0 = scene, 1 = raw mask, 2 = boosted darkness.
const float CONTACT_SHADOW_GAP_MIN_METERS = 0.005; // receiver self-occlusion guard (m)

// ==========================================================================
// WATER - Water / epipolar
// ==========================================================================

// Opaque recursive screen-space indirect specular. This budget is separate
// from the forward water/glass SSR path below.
#define OPAQUE_REFLECTION 1 // [0 1] opaque screen-space reflection toggle; 0 = sky SH only
#define OPAQUE_SSR_QUALITY 2 // [0 1 2 3]
#define OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD 0.5 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0] roughness at which opaque reflections become SH-only and dielectric reflection fades out
#define OPAQUE_REFLECTION_ROUGHNESS_TRANSITION 0.1 // [0.01 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5] roughness span used to blend SSR into SH
#define OPAQUE_SSR_DEBUG 0 // [0 1 2 3 4 5 6 7 8]
#if OPAQUE_REFLECTION && OPAQUE_SSR_QUALITY > 0
#define OPAQUE_SSR
#endif
#if OPAQUE_SSR_QUALITY == 1
#define OPAQUE_SSR_STEPS 24
#elif OPAQUE_SSR_QUALITY == 2
#define OPAQUE_SSR_STEPS 40
#elif OPAQUE_SSR_QUALITY == 3
#define OPAQUE_SSR_STEPS 64
#endif
#define OPAQUE_SSR_MAX_DISTANCE 96.0
#define OPAQUE_SSR_RECURSION_DECAY 0.92
#define OPAQUE_PBR_EMISSION_SCALE 10.0

#define WATER_SSR
#ifdef WATER_SSR
#define WATER_SSR_ENABLED
#endif

// Screen-space reflections march budget: samples along the full reflection
// path (McGuire & Mara 2014). Quality/perf knob for the water forward pass.
#define SSR_STEPS 16 // [8 10 12 16 20 24 32] water SSR march samples

// Water fog caustic modulation: the screen-space Jacobian of the water
// surface normal approximates sunlight focusing/defocusing by the waves.
#define WATER_FOG_CAUSTICS
#define WATER_FOG_CAUSTIC_STRENGTH 2.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 8.0 15.0 30.0]

// Water parallax occlusion mapping (ocean.glsl): normal evaluated at the
// parallax-corrected position. LOW profile disables it (normal at the plane
// position) to save cost.
#define WATER_POM

// Water parallax search budget: coarse fixed-step height-chase samples and
// bisection refinement iterations (mode selected by POM_BISECTION_ENABLED in
// ocean.glsl). LOW profile disables POM entirely, so these stay at defaults.
#define VALUE_NOISE_POM_COARSE_STEPS 4 // [2 3 4 5 6 8] coarse POM height-chase steps
#define VALUE_NOISE_POM_BISECT_STEPS 2 // [0 1 2 3 4] POM bisection refinement iterations

// Epipolar water volume light: E(x) = active-light shadow visibility along
// the water column, multiplied onto the analytic water fog direct term.
// March-distance cap for the water epipolar shadow ratio (metres): beyond
// this the column transmittance is optically negligible, and truncating
// rescales the light path so the ratio stays consistent. LOW tier uses 8 m
// to cut noise.
#define WATER_EPIPOLAR_MAX_DISTANCE 32.0 // [6.0 8.0 12.0 16.0 24.0 32.0 48.0 64.0 96.0 128.0]
#define EPIPOLAR_WATER
#define EPIPOLAR_SLICES 1024 // [256 512 1024 2048]
#define EPIPOLAR_SAMPLES 512 // [128 256 512 1024]
#define EPIPOLAR_SHADOW_STEPS 64 // [16 24 32 48 64 96 128 192 256]
#define EPIPOLAR_DEPTH_TOLERANCE 0.03 // [0.01 0.02 0.03 0.04 0.06 0.08] Relative viewZ column-match tolerance (3%).
#define EPIPOLAR_EDGE_SHARPEN 0.25 // [0.1 0.2 0.25 0.3 0.4]
#define EPIPOLAR_EDGE_EXTEND 16 // [0 4 8 16 32 64]

// ==========================================================================
// FOG - Air fog
// ==========================================================================
const float eyeBrightnessHalflife = 3.0;

// Analytic air fog (composite2, after blend).
#define AIR_FOG
#define AIR_FOG_INTENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0 3.0 4.0]
#define AIR_FOG_DENSITY 10.0 // [0.5 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0]
#define AIR_FOG_SKY_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
#define AIR_FOG_SHADOWS

// Boundary fog: fade near-boundary geometry into the clouded skybox so the
// loaded-area edge is masked instead of cutting off. Applied in the air fog
// composite (composite2) before the epipolar air fog; Overworld only, with air
// fog.
#define BOUNDARY_FOG
#define BOUNDARY_FOG_START 0.5 // [0.25 0.4 0.5 0.6 0.7 0.8 0.9] render-distance fraction where the fade begins
#define BOUNDARY_FOG_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define BOUNDARY_FOG_HEIGHT_FADE 0.8 // [0.0 0.25 0.5 0.75 0.8 1.0] sky-facing dampening

// ==========================================================================
// ATMOSPHERE - Sky atmosphere
// ==========================================================================

#define ATM_HORIZON_DIP 1 // [0 1] Horizon below-dip; 0 = off
#define ATM_HORIZON_DIP_SCALE 8.0 // [0.0 2.0 4.0 6.0 8.0 12.0 16.0 24.0 32.0 48.0 64.0] below-surface dip depth (km)

// ==========================================================================
// AO - Ambient occlusion
// ==========================================================================
const float ambientOcclusionLevel = 1.0;

// AO_MODE selects the algorithm (settings slider, 0/1/2): GTAO is the
// horizon-based method (Jimenez et al. 2016), SSAO the Monte-Carlo
// hemisphere estimator (Crytek 2007). Both share the deferred1_a half-res
// generator, deferred1 full-res temporal accumulation and deferred2 apply.
#define AO_MODE 1 // [0 1 2] 0=off 1=GTAO 2=SSAO
#if AO_MODE == 1 && GI_MODE != 1
#define GTAO // pass toggle: enables program.worldX/deferred1_a and the deferred2 application
#endif
#if AO_MODE == 2 && GI_MODE != 1
#define SSAO // Monte-Carlo hemisphere AO (heavier; temporal accumulation replaces spatial filtering)
#endif
#define GTAO_SLICES 2 // [2 3 4 6 8 10 12] horizon slices per pixel
#define GTAO_RADIUS 3.0 // [0.5 1.0 1.5 2.0 3.0 4.0] view-space search radius (m)
#define GTAO_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0] AO contrast (exponent)
#define GTAO_HORIZON_STEPS 3 // [2 3 4 6 8] depth samples per horizon side
#define GTAO_FALLOFF_START 0.75 // [0.0 0.25 0.5 0.6 0.7 0.75 0.8 0.9 1.0] radius fraction where the falloff begins
#define GTAO_MULTIBOUNCE true // [false true] albedo-dependent energy recovery (paper Eq. 12)
#define SSAO_SAMPLES 16 // [8 12 16 24 32 48 64] hemisphere samples per pixel
#define SSAO_RADIUS 1.0 // [0.5 1.0 1.5 2.0 3.0 4.0] view-space search radius (m)
#define SSAO_STRENGTH 8.0 // [1.0 1.5 2.0 2.5 3.0 4.0 6.0 8.0] AO contrast (exponent; SSAO looks lighter, so steeper than GTAO)

// Temporal accumulation (deferred1 fragment): full-resolution history in the
// merged colortex8 buffer with reprojection, soft depth rejection and an
// age-capped exponential blend.
#define GTAO_TEMPORAL // temporal toggle: enables the history accumulation
#ifdef GTAO_TEMPORAL
#define GTAO_TEMPORAL_ENABLED
#endif
// AO generation is plain half resolution: every half-res texel is evaluated
// every frame at its full-res block origin and upsampled bilinearly - one
// sample per pixel per frame at full convergence speed.
#define GTAO_AGE_LIMIT 48 // [2 4 6 8 10 16 24 32 48] history age cap (frames) before full trust
// AO accumulation matches the cloud temporal scheme: box-average the first
// AO_ACCUMULATION_BOX_SAMPLES phase samples (one 2x2 checkerboard cycle),
// then a steady-state EMA with AO_ACCUMULATION_ALPHA. Rejection lifts the
// fresh-sample weight toward 1, so an untrusted history is replaced quickly
// instead of lingering (vanished objects' AO does not fade out slowly).
const int AO_ACCUMULATION_BOX_SAMPLES = 4;   // box-average the first 4 phase samples (one checkerboard cycle)
const float AO_ACCUMULATION_ALPHA = 0.2;     // steady-state EMA weight after the box phase
// Darkening slowdown: while the fresh sample is darker than the history
// (AO darkening in progress) the fresh weight is scaled by
// AO_DARKEN_SLOWDOWN so black AO fades in slowly - the eye is sensitive to
// darkening, and a sudden dark jump reads as noise. The condition is the
// darkening state itself, not the per-frame rejection: the slow rate is
// carried by the age (base alpha keeps dropping toward the steady state),
// so the fade-in continues even after the rejection clears. The
// brightening path (vanished objects) stays fast.
#define AO_DARKEN_SLOWDOWN 0.35 // [0.1 0.2 0.35 0.5 0.75 1.0] darkening: fresh-weight scale (1.0 = no slowdown)
// History rejection: the reprojected history is
// trusted only when the world-space displacement from the previous-frame
// depth stays under the distance limit and the normal at the reprojected
// position agrees with the current pixel beyond the dot floor; both weights
// ramp smoothly to zero (GTAOHistoryWeight in lib/lighting/temporal_ao.glsl).
#define GTAO_HISTORY_DISTANCE_LIMIT 0.2 // [0.1 0.2 0.25 0.5 1.0 2.0] history rejection: max world displacement (m)
#define GTAO_HISTORY_NORMAL_DOT_MIN 0.866 // [0.94 0.91 0.866 0.82 0.71 0.5] history rejection: min normal dot (cos 30 deg)

// ==========================================================================
// LIGHTING - Lighting constants
// ==========================================================================

// Warm artificial-light palette, shared by deferred2 and the forward
// translucent passes. TORCH_BRIGHTNESS scales the light intensity only;
// the warm tint stays fixed.
#define TORCH_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0] torch light intensity multiplier
const vec3 TORCH_LIGHT_COLOR = vec3(1.00, 0.70, 0.35) * 12.0 * TORCH_BRIGHTNESS;

// Minimum ambient light floor added to every surface's sky ambient, so caves
// and deep shadows never render fully black (see AmbientLight in
// lib/lighting/ambient_light.glsl).
#define AMBIENT_BASE 0.03 // [0.0 0.03 0.06 0.1 0.15 0.2] minimum ambient light floor
// Night star map gain: linear multiplier applied after the LogLuv32
// decode (celestial.glsl).
#define STAR_MAP_INTENSITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] night star brightness

// Angular radii of the rendered sun/moon discs, in radians. Shared by the
// sky disc renderer (celestial.glsl) and the water/translucent GGX area
// light so the specular glint uses the same disc size as the visible sky.
const float SUN_DISC_RADIUS  = 0.005;   // ~0.267 deg
const float SUN_GLOW_RADIUS  = 0.03;    // ~1.0 deg soft falloff
const float MOON_DISC_RADIUS = 0.00436; // ~0.25 deg
const float MOON_GLOW_RADIUS = 0.012;

// ==========================================================================
// UI-ONLY - display-only pseudo options, never read by shader code
// ==========================================================================

// Iris renders each single-value option as an inert settings button; the
// visible text comes from the lang files (option.<NAME> / value.<NAME>.0).
// Keep every name listed in the shaders.properties screen lists and present
// in both lang files.
#define ABOUT 0 //[0]
#define INFO_LICENSE 0 //[0]
#define INFO_PROFILE 0 //[0]
#define INFO_TOOLTIPS 0 //[0]

#endif
