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
//#define TAAU
#define TAAU_RENDER_SCALE 0.75 // [0.50 0.59 0.67 0.75 0.85]
#define TAAU_RECONSTRUCTION 1 // [0 1] 0=Bilinear 1=Cubic
#define TAAU_HISTORY_WEIGHT 0.90 // [0.70 0.75 0.80 0.85 0.90 0.95 0.97]
#define TAAU_CLIP_GAMMA 1.00 // [0.75 1.00 1.25 1.50 1.75 2.00]
#define TAAU_MOTION_REJECTION 0.50 // [0.00 0.25 0.50 0.75 1.00]
#define TAAU_REACTIVE_STRENGTH 0.50 // [0.00 0.25 0.50 0.75 1.00]
#define TAAU_SHARPNESS 0.25 // [0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define TAAU_DEBUG 0 // [0 1 2] 0=Scene 1=SpatialReconstruction 2=HistoryRejection

#ifdef TAAU
#ifdef TAA
#define TAAU_ACTIVE
#endif
#endif
//#define DOF
//#define MOTION_BLUR
#define MB_STRENGTH 0.8 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

// Iris constant: half-life in ticks for the time-smoothed center depth that
// the DOF focus distance reads (centerDepthSmooth). Lives with the other Iris
// constant directives.
const float centerDepthHalflife = 1.0;


// Diffuse indirect source: both SSGI and RSM supply SH for uncovered directions.
#define GI_MODE 0 // [0 1 2] 0=None 1=SSGI 2=ReflectiveShadowMap
// Screen-space GI trace budget (GI_MODE 1), ported from the GT-VBGI
// reference constants in recursive_gi.fragment.
#define SSGI_STEPS 16 // [4 8 12 16 24 32 48 64] Geometric march steps per pixel; higher = smoother distant bounce light, linear cost.
#define SSGI_MARCH_PIXELS 512.0 // [128.0 256.0 384.0 512.0 768.0 1024.0] March width cap in screen pixels (the reference's Raymarching_Width).
#define SSGI_THICKNESS 0.5 // [0.1 0.25 0.5 0.75 1.0 1.5 2.0] Sample geometry thickness in view-depth meters (the reference's Thickness).
#define SSGI_RADIANCE_LIMIT 128.0 // [16.0 32.0 64.0 128.0 256.0 512.0] Firefly clamp bounding the stored GI radiance.
#define RSM_SAMPLES 16 // [8 16 32 64]
#define RSM_RADIUS 8.0 // [2.0 4.0 8.0 12.0 16.0 24.0]
#define RSM_STRENGTH 3.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0]
#define RSM_SKY_OCCLUSION // Darkens SH where the shadow map shows sky occlusion; off compiles the tracking path out.
#define RSM_SKY_OCCLUSION_FLOOR 0.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define RSM_DEBUG 0 // [0 1] 0=Scene 1=Raw



#define BLOOM
#define BLOOM_STRENGTH 0.1 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// Ordered IGN grain that hides R11G11B10F and 8-bit banding in smooth
// gradients. Its pattern is a fixed function of the screen position, so a
// still camera accumulates it instead of averaging it out, and it stays as a
// regular hatch over sky, clouds and fog. Off by default: enable it only when
// banding is worse than the grain.
//#define COLOR_DITHER
#define COLOR_DITHER_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Color dither strength: 0.5=conservative, 1.0=default, 2.0=aggressive

#define AE
#define AE_TARGET_LUMINANCE 0.18 // [0.08 0.10 0.12 0.15 0.18 0.21 0.24 0.28 0.32 0.40] Auto-exposure reference display key; 0.18 is middle gray
#define AE_ADAPTATION_STRENGTH 0.70 // [0.0 0.25 0.40 0.55 0.70 0.85 1.0] Scene-key EV compensation; 0=fixed exposure, 1=full compensation

#define CAS
#define CAS_SHARPNESS 0.75 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

// Tonemap operator (0 = AgX, 1 = ACES 2.0, 2 = Blender AgX, 3 = OpenDRT,
// 4 = AMD LPM, 5 = GT7)
#define TONEMAP_MODE 0 // [0 1 2 3 4 5] Tonemap: 0=AgX 1=ACES 2.0 2=Blender AgX 3=OpenDRT 4=AMD LPM 5=GT7
#define TONEMAP_EXPOSURE 0.0 // [-2.0 -1.5 -1.0 -0.75 -0.5 -0.25 0.0 0.25 0.5 0.75 1.0 1.5 2.0] Manual exposure (EV), applied before auto-exposure
#define TONEMAP_SATURATION 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5] Pre-tonemap saturation
#define TONEMAP_STRENGTH 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0] Blend between linear HDR and tonemapped result

// #define PURKINJE_EFFECT // Requires AE: rod-vision night grading driven by the exposure state.
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

// AgX (TONEMAP_MODE == 0): AgX-HSV from DRT Bench. Look, log-domain contrast
// and the display-domain saturation/gamma are the pack's own adjustments on
// top of the reference operator.
#define TONEMAP_AGX_LOOK 1 // [0 1 2] AgX look: 0=Base 1=Punchy 2=Greyscale
#define TONEMAP_AGX_CONTRAST 0.95 // [0.5 0.6 0.7 0.8 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5] AgX log-domain contrast around the mid-grey pivot
#define TONEMAP_AGX_SATURATION 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0] AgX display-domain saturation
#define TONEMAP_AGX_GAMMA 0.9 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5] AgX display-domain gamma
// The variant's signature control: how much of the original hue survives in
// the brightest highlights (1.0 at black, this value at paper white).
#define TONEMAP_AGX_HIGHLIGHT_HUE 0.5 // [0.0 0.25 0.5 0.75 1.0] AgX highlight hue retention (0 = curve's own hue, 1 = keep the scene hue)

// AgX-HSV curve parameters (DRT Bench `AgxParameters::hsv_default()`).
#define TONEMAP_AGX_TOE_POWER 1.55
#define TONEMAP_AGX_SHOULDER_POWER 5.2
#define TONEMAP_AGX_GAMUT_COMPRESSION 0.05
const float AGX_MIN_LOG2 = -12.473931188332412333;    // log2(0.18) - 10 EV
const float AGX_INVERSE_DYNAMIC_RANGE = 0.060606060606060606; // 1 / 16.5 EV
const float AGX_INPUT_PIVOT = 0.6060606060606061;     // 10 / 16.5 EV
const float AGX_OUTPUT_PIVOT = 0.4613561300;          // sRGB OETF(0.18)
const float AGX_PIVOT_SLOPE = 2.4606366;
const float AGX_TOE_A = 11.2194730786;         // curve_coefficient(0.60606, 0.46136, 2.46064, 1.55)
const float AGX_SHOULDER_A = 2568.7503334098;  // curve_coefficient(0.39394, 0.53864, 2.46064, 5.2)
const vec3 AGX_NEUTRAL_WEIGHTS = vec3(0.2120053547549465, 0.3921825078090138, 0.3958121374360396);

// ACES 2.0 output transform (TONEMAP_MODE == 1): the ACES 2.0 reference
// chain (Hellwig-2022 JMh, MM tonescale, hue-dependent chroma compression).
// Its own anchor is c_d = 10.013 nits = 0.100 display-linear for scene 18%
// grey; the default input scale is solved so that the shared 0.18 anchor
// holds, and 1.0 is the reference's own scale.
#define TONEMAP_ACES2_INPUT_SCALE 1.7133450 // [0.5 0.75 1.0 1.25 1.5 1.7133450 2.0 2.5 3.0] ACES 2.0 input scale (1.7133450 = shared 18% grey anchor, 1.0 = reference scale)

// OpenDRT (TONEMAP_MODE == 3): Jed Smith's Open Display Rendering Transform
// (GPL-3.0), Standard look preset. Grey luminance is the operator's own
// display grey level in nits on a fixed 100-nit SDR peak; the reference
// default is 10.0, the default here is the solved value that anchors scene
// 18% grey on 18% display-linear with the default tone-scale parameters.
#define TONEMAP_ODT_GREY_LUMINANCE 15.1306824 // [5.0 7.5 10.0 12.5 15.1306824 17.5 20.0 22.5 25.0] OpenDRT display grey luminance (nits on a 100-nit peak)
#define TONEMAP_ODT_CONTRAST 1.66 // [1.0 1.15 1.3 1.4 1.5 1.66 1.8 2.0] OpenDRT tone-scale contrast
#define TONEMAP_ODT_SHOULDER_CLIP 0.5 // [0.0 0.15 0.25 0.35 0.5 0.65 0.8 1.0] OpenDRT shoulder clip: scene value 2^(6*value+4) and up reaches paper white
#define TONEMAP_ODT_TOE 0.003 // [0.0 0.003 0.01 0.02 0.04 0.07 0.1] OpenDRT quadratic toe strength (deep-shadow compression)
#define TONEMAP_ODT_OFFSET 0.005 // [0.0 0.002 0.005 0.008 0.012 0.016 0.02] OpenDRT pre-tonescale scene offset (shadow lift)
#define TONEMAP_ODT_RENDER_SATURATION 0.35 // [0.0 0.1 0.2 0.25 0.35 0.45 0.55 0.6] OpenDRT render-space strength (scale of the color volume)
#define TONEMAP_ODT_PURITY_LOW 0.25 // [0.0 0.1 0.15 0.25 0.4 0.6 0.8 1.0] OpenDRT purity limit low (midtone and shadow color retention)
#define TONEMAP_ODT_PURITY_HIGH 0.25 // [0.0 0.1 0.15 0.25 0.5 0.8 1.0] OpenDRT purity limit high (highlight color retention)
#define TONEMAP_ODT_BRILLIANCE 0.0 // [-3.0 -2.0 -1.0 -0.5 0.0 0.5 1.0] OpenDRT brilliance (intensity scale of pure stimuli, stops)

// AMD LPM (TONEMAP_MODE == 4): FidelityFX Luma Preserving Mapper (MIT). Its
// curve is pinned by tone(midIn) = 0.18 and tone(hdrMax) = 1.0, and every
// reference preset uses exposure = log2(hdrMax), so the defaults keep LPM's
// own 18% grey anchor exactly (hdrMax 1024 / exposure 10 are the FidelityFX
// sample's values). Contrast is the one tuned default: 0.15 follows this
// pack's shared 0.18-anchored response; the reference header's 0.25 and the
// sample's 0.0 are both selectable.
#define TONEMAP_LPM_CONTRAST 0.15 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3] LPM tone-curve contrast (reference header 0.25, sample 0.0)
#define TONEMAP_LPM_SATURATION 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0] LPM saturation power on the color ratio (1.0 = the reference's own neutral value)
#define TONEMAP_LPM_HDR_MAX 1024.0 // [16.0 64.0 256.0 1024.0 4096.0] LPM input white level the curve maps to 1.0 (hdrMax)
#define TONEMAP_LPM_EXPOSURE 10.0 // [0.0 2.0 4.0 6.0 8.0 10.0] LPM exposure in stops; log2(hdrMax) keeps 18% grey anchored

// GT7 Tone Mapping (TONEMAP_MODE == 5): Polyphony Digital color-volume
// mapping (SIGGRAPH 2025 course, official MIT sample). The curve parameters
// use the official SDR preset except alpha 0 (shoulder converges exactly to
// paper white; see lib/color/tonemap_gt7.glsl) and are fixed there.
#define TONEMAP_GT7_BLEND 0.6 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] GT7 blend between the per-channel curve and the chroma-fade UCS path (official 0.6)
#define TONEMAP_GT7_CHROMA_FADE_START 0.98 // [0.80 0.85 0.90 0.94 0.96 0.98 1.00 1.02 1.04] GT7 chroma-fade start, UCS luma relative to paper white (official 0.98)
#define TONEMAP_GT7_CHROMA_FADE_END 1.16 // [1.00 1.04 1.08 1.12 1.16 1.20 1.24 1.28] GT7 chroma-fade end where chroma reaches fully faded (official 1.16)

// ==========================================================================
// CLOUDS - Cloud layers (volumetric + cirrus)
// ==========================================================================
#define VOLUMETRIC_CLOUDS // Enable volumetric cloud rendering.
#define CIRRUS // Enable the high-altitude cirrus shell; independent of the volumetric layer.
#define CLOUD_SINGLE_LIGHT // Trace the cloud layer toward one folded sun/moon direction instead of marching both lights.
#define CLOUD_VIEW_MIN_STEPS 20 // [20 24 32 40 48 56 64 96 128] Minimum cloud steps for short view rays; higher values stabilize near silhouettes at higher cost.
#define CLOUD_VIEW_MAX_STEPS 40 // [40 64 80 96 112 128 160 192 256] Maximum cloud steps for long view rays; controls horizon quality and cost.
#define CLOUD_VIEW_TARGET_STEP_KM 0.4 // [0.2 0.25 0.3 0.4 0.5 0.75 1.0] Adaptive step target distance (km); smaller = denser sampling.
#define CLOUD_LIGHT_STEPS 6 // [3 4 5 6 8] Light-direction steps per cloud sample; affects self-shadow quality and primary lighting cost.
#define CLOUD_LIGHT_START_OFFSET_KM 0.2 // [0.0 0.025 0.05 0.075 0.1 0.15 0.2 0.3 0.4 0.5] Distance skipped toward the light before cloud self-shadow integration (km).
#define CLOUD_BASE_ALTITUDE 1.4 // [0.8 1.0 1.2 1.4 1.6 1.8 2.0] Cloud base altitude above terrain (km).
#define CLOUD_THICKNESS_KM 1.3 // [0.6 0.8 1.0 1.2 1.3 1.4 1.5 1.6 1.8 2.0] Cloud layer vertical thickness (km).
#define CLOUD_TOP_ALTITUDE (CLOUD_BASE_ALTITUDE + CLOUD_THICKNESS_KM) // Auto-computed from cloud base altitude and thickness.
#define CLOUD_COVERAGE 0.5 // [0.4 0.5 0.55 0.6 0.65 0.7 0.8] Weather-map coverage bar; higher = a wider cloud footprint. Rain still pushes coverage to full overcast.
#define CLOUD_DISTRIBUTION_SCALE_KM 70.0 // [48.0 64.0 80.0 96.0 128.0 160.0 192.0 240.0 280.0] 2D Worley fBm distribution map world-space scale for a full wrap (km).
#define CLOUD_DISTRIBUTION_UV_SCALE 4.5 // [2.0 2.5 3.0 3.5 4.0 4.5 5.0 6.0] Extra sampling frequency on the distribution atlas; higher = smaller, more frequent weather cells.
#define CLOUD_WIND_SPEED 0.01 // [0.0 0.005 0.01 0.015 0.02 0.03 0.04 0.06 0.08 0.1] Cloud wind speed (km/s); distribution drifts with wind, higher = faster motion.
#define CLOUD_FINE_WIND_FACTOR 2.0 // [1.0 1.25 1.5 1.75 2.0 2.5 3.0] Fine erosion wind speed multiplier; >1 makes details flow faster through clouds for inner motion.
#define CLOUD_FINE_EROSION_SCALE 1.5 // [1.0 1.5 2.0 3.0 4.0 5.0 6.0 8.0] Voronoise coordinate scale per kilometer; higher = smaller, denser erosion cells.
#define CLOUD_FINE_EROSION_STRENGTH 0.7 // [0.25 0.5 0.7 1.0 1.5] Light-trace erosion strength; scales the voronoise mean the same way the view path scales its per-point read.
#define CLOUD_ALPHA_EXTINCTION_SRGB_GRAY 50.0 // [25.0 35.0 50.0 65.0 80.0 100.0] Extinction of a fully dense sample (km^-1); higher = denser, more opaque clouds.
#define CLOUD_LIGHT_MAX_DISTANCE_KM 2.0 // [1.0 1.5 2.0 3.0 4.0 6.0 8.0] Maximum light-direction optical depth trace distance (km).
#define CLOUD_PHASE_FORWARD_G 0.9 // [0.65 0.75 0.8 0.85 0.9 0.95] Forward HG eccentricity of the cloud phase.
#define CLOUD_PHASE_BACKWARD_G 0.3 // [0.15 0.2 0.25 0.3 0.35 0.4] Backward HG eccentricity of the cloud phase.
#define CLOUD_MS_ATTENUATION 0.3 // [0.25 0.35 0.5 0.65 0.75 0.85 1.0] Per-octave optical depth multiplier.
#define CLOUD_MS_CONTRIBUTION 0.5 // [0.0 0.25 0.35 0.5 0.65 0.7 0.75 1.0] Per-octave energy multiplier.
#define CLOUD_MS_ECCENTRICITY 0.5 // [0.0 0.25 0.33 0.4 0.5 0.6 0.75 1.0] Per-octave phase eccentricity multiplier.
#define CLOUD_MS_SAT_ALBEDO 0.99 // [0.9 0.95 0.97 0.98 0.99 0.995 0.999 1.0] Saturation albedo omega of the fms series; the added orders converge to omega / (1 - omega), so values near 1.0 brighten dense interiors steeply.
#define CLOUD_MS_ISOTROPIC 0.2 // [0.0 0.1 0.25 0.3 0.5 0.75 1.0 1.25 1.5 2.0] Isotropic geometric-series strength; higher = brighter, milkier cloud interiors.
#define CLOUD_SKY_LIGHT_STRENGTH 8.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0 6.0 8.0] Sky environment strength for both cloud layers; higher = brighter cloud shadow regions.
#define CIRRUS_MS_ISOTROPIC 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Cirrus multiple-scattering order strength on the direct lights; higher = brighter, more filled cirrus bodies.
#define CLOUD_MILKYWAY_TRANSMISSION 0.1 // [0.0 0.1 0.2 0.3 0.5 0.75 1.0] Share of the Milky Way background the volumetric layer scatters into a glow; 1.0 is the isotropic single-scatter total.
#define CIRRUS_MILKYWAY_TRANSMISSION 0.6 // [0.0 0.1 0.2 0.3 0.5 0.75 1.0] Share of the Milky Way background the cirrus shell scatters into a glow; 1.0 is the isotropic single-scatter total.

#define CLOUD_TEMPORAL_UPSCALING 3   // [1 2 3 4] low-res render divisor (1 = full resolution)
// Active cloud rectangle in the existing colortex12 alt workspace. Compute
// and temporal upsampling both truncate u_render_res * CLOUD_CURRENT_SCALE;
// the backing texture stays display-sized, including under TAAU.
#if CLOUD_TEMPORAL_UPSCALING == 1
const vec2 CLOUD_CURRENT_SCALE = vec2(1.0);
#elif CLOUD_TEMPORAL_UPSCALING == 2
const vec2 CLOUD_CURRENT_SCALE = vec2(0.5);
#elif CLOUD_TEMPORAL_UPSCALING == 3
const vec2 CLOUD_CURRENT_SCALE = vec2(0.333333);
#else
const vec2 CLOUD_CURRENT_SCALE = vec2(0.25);
#endif
//#define CLOUD_HISTORY_GUIDED_MARCH_END // Guide the view march end from reprojected cloud history.
#define CLOUD_HISTORY_GUIDED_END_SCALE 1.2 // [1.0 1.05 1.1 1.15 1.2 1.25] centroid-distance safety scale
#define CLOUD_HISTORY_FRAMES 24 // [8 12 16 24 32 48] accepted-frame/history-weight cap
#define CLOUD_NO_CLOUD_DISTANCE 1e4  // no-cloud distance sentinel (km, half-float safe)
#define HISTORY_NO_CLOUD_DATA uintBitsToFloat(0x7fc00000u)  // NaN marker: history slot has no data

// ==========================================================================
// SHADOWS - Shadows / PCSS / SSS
// ==========================================================================
const int shadowMapResolution = 2048; // [1024 1536 2048 3072 4096 6144 8192]
const bool shadowHardwareFiltering = true;
const float sunPathRotation = -15.0;
const float shadowIntervalSize = 2.0;
const float real_shadow_map_resolution = float(shadowMapResolution);
const float shadowDistance = 128.0;
// Iris ShadowMatrices.NEAR/FAR defaults, i.e. the host values while these
// const directives stay undeclared; pinning them keeps the custom-light
// projection (lib/core/coordinates.glsl) on the host's exact depth slab.
const float shadowNearPlane = -100.05;
const float shadowFarPlane = 156.0;

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
#define SHADOW_PENUMBRA_CAP_BOOST 1.0 // [0.0 0.5 1.0 1.5 2.0] Multiplier on the penumbra-radius cap; no sun-height dependence.
#define SHADOW_BLOCKER_DEPTH_TOLERANCE_M 0.0 // [0.0 0.05 0.1 0.15 0.2 0.3 0.5]

// Plant subsurface scattering settings.
#define SHADOW_SSS // Plant translucency transmission; off compiles the SSS lighting and thickness estimate out.
#define SHADOW_SSS_STEPS 8 // [4 6 8 10 12 16]
#define SHADOW_SSS_DENSITY 3.0 // [1.0 2.0 3.0 4.0 6.0 8.0]
#define SHADOW_SSS_SCALE 1.0 // [0.5 1.0 1.5 2.0 2.5 3.0 4.0]
#define SHADOW_SSS_PENUMBRA_BOOST 7.0 // [0.0 1.0 2.0 3.0 5.0 7.0 10.0]
#define SHADOW_SSS_PHASE_G 0.4 // [0.0 0.3 0.4 0.5 0.6 0.7 0.8 0.9]
// Shadow-map coverage fade start (fraction of the XY/depth extent). One
// curve drives the direct-shadow fade-out and the plant-SSS presence gate.
#define SHADOW_SSS_FADE_START 0.75 // [0.0 0.5 0.6 0.7 0.75 0.8 0.9 0.95]
#define SHADOW_SSS_ENERGY 0.85 // [0.1 0.2 0.3 0.35 0.4 0.5 0.6 0.8 0.85 1.0]
#define SHADOW_SSS_DEBUG 0 // [0 1] Isolate plant transmission in deferred shading.

// Screen-space contact shadows (short-range, alongside the shadow map):
// deferred4 marches a screen-projected ray toward the active directional
// light against depthtex1 per receiver pixel and applies the result as an
// upper bound (min) on the shadow-map result, so it fills PCF contact seams
// and keeps directional occlusion past the shadow map boundary. Overworld and
// End only (the Nether has no directional light).
#define CONTACT_SHADOW 1 // [0 1] Screen-space contact shadows; 0 = off.
#define CONTACT_SHADOW_STEPS 12 // [4 6 8 12 16 24] depth samples per receiver pixel.
#define CONTACT_SHADOW_MAX_DISTANCE 24.0 // [4.0 6.0 8.0 10.0 12.0 16.0 24.0] world-space march reach cap (m); the reach scales with view distance.
#define CONTACT_SHADOW_THICKNESS 0.02 // [0.02 0.05 0.1 0.25 0.5 1.0] near-field occluder thickness slab (m); it also widens with view distance.
#define CONTACT_SHADOW_DEBUG 0 // [0 1 2] debug view: 0 = scene, 1 = raw mask, 2 = boosted darkness.
const float CONTACT_SHADOW_GAP_MIN_METERS = 0.005; // receiver self-occlusion guard (m)

// ==========================================================================
// WATER - Water surface
// ==========================================================================

// Rain uses the existing opaque material/normal payload and reflection path.
#define RAIN_WETNESS
#define RAIN_PUDDLES
#define RAIN_RIPPLES
#define RAIN_PUDDLE_COVERAGE 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8] puddle coverage threshold on the cloud distribution atlas
#define RAIN_PUDDLE_SCALE_M 64 // [16 32 64 128 256] world-space wrap of the puddle pattern (m)
#define RAIN_RIPPLE_STRENGTH 4.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0 3.5 4.0] slope strength on wet ground and water

#ifdef RAIN_WETNESS
#if defined(WORLD_OVERWORLD) && (defined(PROGRAM_GBUFFERS_TERRAIN) || defined(PROGRAM_GBUFFERS_TERRAIN_SOLID) || defined(PROGRAM_GBUFFERS_TERRAIN_CUTOUT) || defined(PROGRAM_GBUFFERS_BLOCK))
#define RAIN_WETNESS_ACTIVE
#endif
#endif

// Opaque recursive screen-space indirect specular. This budget is separate
// from the forward water/glass SSR path below.
#define OPAQUE_REFLECTION 1 // [0 1] opaque screen-space reflection toggle; 0 = sky SH only
#define OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD 0.5 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0] roughness at which opaque reflections become SH-only and dielectric reflection fades out
#define OPAQUE_REFLECTION_ROUGHNESS_TRANSITION 0.1 // [0.01 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5] roughness span used to blend SSR into SH
#define OPAQUE_SSR_DEBUG 0 // hidden debug: opaque SSR stage select; no UI surface
#if OPAQUE_REFLECTION
#define OPAQUE_SSR
#endif

// Opaque SSR march budget: samples along the full reflection path
// (McGuire & Mara 2014). The default keeps the whole trace at 9 depth
// samples: 8 march steps plus 1 interpolation read. Raising the march count
// extends how far reflections reach, not how accurately they hit.
#define OPAQUE_SSR_STEPS 8 // [8 12 16 20 24 32 40 48 64] opaque SSR march samples
#define OPAQUE_SSR_RECURSION_DECAY 0.92
#define OPAQUE_PBR_EMISSION_SCALE 10.0

#define WATER_SSR

#define SSR_QUARTER_DEPTH // trace both SSR paths with width/4, height/4 R16F depth
#ifdef SSR_QUARTER_DEPTH
#if defined(WATER_SSR) || defined(OPAQUE_SSR)
#define SSR_QUARTER_DEPTH_ACTIVE
#endif
#endif

// Shared SSR first-crossing refinement: interpolate the hit inside the
// accepted march step in the affine ray-depth domain, then correct once
// against the interpolated position's surface depth. Off reports the raw
// march sample at the crossing.
#define SSR_INTERPOLATION

// Water SSR march budget: samples along the full reflection path
// (McGuire & Mara 2014). The default keeps the whole trace at 9 depth
// samples: 8 march steps plus 1 interpolation read. Raising the march count
// extends how far reflections reach, not how accurately they hit.
#define WATER_SSR_STEPS 8 // [8 10 12 16 20 24 32] water SSR march samples

// Water parallax occlusion mapping (ocean.glsl): normal evaluated at the
// parallax-corrected position. LOW profile disables it (normal at the plane
// position) to save cost.
#define WATER_POM


// River texture height gain: scales all four layer amplitudes.
// 1.0 (default) matches the master band energies (sigma ~4.4 cm).
#define WATER_RIVER_GAIN 1.5 // [0.5 1.0 1.5 2.0 2.5 3.0 3.69 5.0]

// Water parallax search budget: coarse fixed-step height-chase samples and
// bisection refinement iterations (mode selected by POM_BISECTION_ENABLED in
// ocean.glsl). LOW profile disables POM entirely, so these stay at defaults.
#define WATER_POM_COARSE_STEPS 4 // [2 3 4 5 6 8] coarse POM height-chase steps
#define WATER_POM_BISECT_STEPS 2 // [0 1 2 3 4] POM bisection refinement iterations

// ==========================================================================
// FOG - Boundary fog
// ==========================================================================
const float eyeBrightnessHalflife = 3.0;
// Minecraft lightmap units: eyeBrightnessSmooth components range 0..240.
const float EYE_BRIGHTNESS_SCALE = 240.0;

// Fade near-boundary geometry into the cloud-free sky in composite2.
// Overworld only; independent of the always-on analytic water fog.
#define BOUNDARY_FOG
#define BOUNDARY_FOG_START 0.7 // [0.25 0.4 0.5 0.6 0.7 0.8 0.9] render-distance fraction where the fade begins
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
//#define GTAO_MULTIBOUNCE // albedo-dependent energy recovery (paper Eq. 12); default off.
#define SSAO_SAMPLES 16 // [8 12 16 24 32 48 64] hemisphere samples per pixel
#define SSAO_RADIUS 1.0 // [0.5 1.0 1.5 2.0 3.0 4.0] view-space search radius (m)
#define SSAO_STRENGTH 8.0 // [1.0 1.5 2.0 2.5 3.0 4.0 6.0 8.0] AO contrast (exponent; SSAO looks lighter, so steeper than GTAO)

// Temporal accumulation (deferred1 fragment): full-resolution history in the
// merged colortex8 buffer with reprojection, soft depth rejection and a
// capped running average (the cloud scheme, CloudAccumulate).
#define AO_TEMPORAL // temporal toggle: enables the history accumulation
#ifdef AO_TEMPORAL
#define AO_TEMPORAL_ENABLED
#endif
// AO generation is plain half resolution: every half-res texel is evaluated
// every frame at its full-res block origin and upsampled bilinearly - one
// sample per pixel per frame at full convergence speed.
#define AO_HISTORY_FRAMES 48 // [2 4 6 8 10 16 24 32 48] accumulated-average length cap (frames); fresh weight settles at 1/N
// Rejection lifts the fresh-sample weight toward 1, so an untrusted history
// is replaced quickly instead of lingering (vanished objects' AO does not
// fade out slowly).
// History rejection: the reprojected history is
// trusted only when the world-space displacement from the previous-frame
// depth stays under the distance limit and the normal at the reprojected
// position agrees with the current pixel beyond the dot floor; both weights
// ramp smoothly to zero (AOHistoryWeight in lib/lighting/temporal_ao.glsl).
#define AO_HISTORY_DISTANCE_LIMIT 0.2 // [0.1 0.2 0.25 0.5 1.0 2.0] history rejection: max world displacement (m)
#define AO_HISTORY_NORMAL_DOT_FLOOR 0.866 // [0.5 0.71 0.82 0.866 0.91 0.94] history rejection: min normal dot (cos 30 deg)

// ==========================================================================
// LIGHTING - Lighting constants
// ==========================================================================

// Warm artificial-light palette, shared by deferred2 and the forward
// translucent passes. TORCH_BRIGHTNESS scales the light intensity only;
// the warm tint stays fixed.
#define TORCH_BRIGHTNESS 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5 2.0] torch light intensity multiplier
const vec3 TORCH_LIGHT_COLOR = vec3(1.00, 0.70, 0.35) * 12.0 * TORCH_BRIGHTNESS;

// Sky ambient (SH) strength: scales the SH sky irradiance that
// lib/lighting/ambient_light.glsl feeds into every surface's ambient term, so
// the no-GI ambient of the deferred shading pass and the SH fallback both GI
// sources leave in their uncovered directions share one control. Direct
// sunlight, the AMBIENT_FLOOR floor below and the SH environment reflection are
// outside this scale.
#define SKY_AMBIENT_STRENGTH 0.9 // [0.0 0.25 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.25 1.5 2.0] sky SH ambient light intensity multiplier

// Minimum ambient light floor added to every surface's sky ambient, so caves
// and deep shadows never render fully black (see AmbientLight in
// lib/lighting/ambient_light.glsl).
#define AMBIENT_FLOOR 0.005 // [0.0 0.03 0.06 0.1 0.15 0.2] minimum ambient light floor
// Night star map gain: linear multiplier applied after the LogLuv32
// decode (celestial.glsl).
#define STAR_MAP_INTENSITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] night star brightness
// Night star map artistic grade, applied to the decoded map color before the
// transmittance and night fades (celestial.glsl).
#define STAR_MAP_CONTRAST 2.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5] star map contrast exponent
#define STAR_MAP_BRIGHT_BOOST 4.0 // [0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0] luminance-keyed bright star gain

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

#endif // LIB_CONTRACT_SETTINGS_GLSL
