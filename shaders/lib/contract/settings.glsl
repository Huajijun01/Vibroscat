#ifndef LIB_CONTRACT_SETTINGS_GLSL
#define LIB_CONTRACT_SETTINGS_GLSL

// Consolidated compile-time settings: every config module (post,
// clouds, shadows, water, fog, ao) and the shared lighting
// constants in one file. Edit the values here; consumers include
// only this file.

// ==========================================================================
// POST — Post / tonemap
// ==========================================================================
#define TAA
//#define DOF
//#define MOTION_BLUR
#define MB_STRENGTH 0.8 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

#define BLOOM
#define BLOOM_STRENGTH 0.1 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define COLOR_DITHER_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Color dither strength: 0.5=conservative, 1.0=default, 2.0=aggressive

//#define AE

#define CAS
#define CAS_SHARPNESS 0.75 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

// Tonemap operator (0 = AgX, 1 = OKLAB, 2 = ACES, 3 = Reinhard-Gamut)
#define TONEMAP_MODE 3 // [0 1 2 3] Tonemap: 0=AgX 1=OKLAB 2=ACES 3=Reinhard-Gamut
#define TONEMAP_EXPOSURE 0.0 // [-2.0 -1.5 -1.0 -0.75 -0.5 -0.25 0.0 0.25 0.5 0.75 1.0 1.5 2.0] Manual exposure (EV), applied before auto-exposure
#define TONEMAP_SATURATION 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5] Pre-tonemap saturation
#define TONEMAP_STRENGTH 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0] Blend between linear HDR and tonemapped result

// AgX look and adjustments (only used when TONEMAP_MODE == 0)
#define TONEMAP_AGX_LOOK 1 // [0 1 2] AgX look: 0=Base 1=Punchy 2=Greyscale
#define TONEMAP_AGX_CONTRAST 0.95 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5] AgX log-domain contrast around the mid-grey pivot
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

// ==========================================================================
// CLOUDS — Volumetric clouds
// ==========================================================================
#define VOLUMETRIC_CLOUDS // Enable volumetric cloud rendering.
#define CLOUD_VIEW_MIN_STEPS 32 // [24 32 40 48 56 64 96 128] Minimum cloud steps for short view rays; higher values stabilize near silhouettes at higher cost.
#define CLOUD_VIEW_MAX_STEPS 128 // [64 80 96 112 128 160 192 256] Maximum cloud steps for long view rays; controls horizon quality and cost.
#define CLOUD_VIEW_TARGET_STEP_KM 0.4 // [0.2 0.25 0.3 0.4 0.5 0.75 1.0] Adaptive step target distance (km); smaller = denser sampling.
#define CLOUD_LIGHT_STEPS 8 // [3 4 5 6 8] Light-direction steps per cloud sample; affects self-shadow quality and primary lighting cost.
#define CLOUD_BASE_ALTITUDE 1.4 // [0.8 1.0 1.2 1.4 1.6 1.8 2.0] Cloud base altitude above terrain (km).
#define CLOUD_THICKNESS_KM 1.5 // [0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0] Cloud layer vertical thickness (km).
#define CLOUD_TOP_ALTITUDE (CLOUD_BASE_ALTITUDE + CLOUD_THICKNESS_KM) // Auto-computed from cloud base altitude and thickness.
#define CLOUD_COVERAGE 0.5 // [0.35 0.4 0.45 0.5 0.55 0.58 0.62 0.66 0.7 0.75] Overall cloud coverage; higher = wider coverage and more connected cloud shapes.
#define CLOUD_DISTRIBUTION_SCALE_KM 64.0 // [48.0 64.0 80.0 96.0 128.0 160.0 192.0] 2D Worley fBm distribution map world-space scale for a full wrap (km).
#define CLOUD_WIND_SPEED 0.01 // [0.0 0.005 0.01 0.015 0.02 0.03 0.04 0.06 0.08 0.1] Cloud wind speed (km/s); distribution drifts with wind, higher = faster motion.
#define CLOUD_FINE_WIND_FACTOR 2.0 // [1.0 1.25 1.5 1.75 2.0 2.5 3.0] Fine erosion wind speed multiplier; >1 makes details flow faster through clouds for inner motion.
#define CLOUD_EROSION_SCALE_KM 1.5 // [2.0 3.0 4.0 5.0 6.0 8.0 10.0 12.0] 3D Worley fBm erosion texture world-space scale for a full wrap (km).
#define CLOUD_EROSION_STRENGTH 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.65 0.8] Composite low-frequency erosion channel total strength.
#define CLOUD_FINE_EROSION_SCALE_KM 0.4 // [0.4 0.5 0.65 0.8 1.0 1.25 1.5 2.0] Channel A independent detail noise scale for a full wrap (km).
#define CLOUD_FINE_EROSION_STRENGTH 0.1 // [0.0 0.05 0.1 0.15 0.18 0.2 0.25 0.3 0.4] Channel A independent curl distortion detail erosion strength.
#define CLOUD_FINE_EROSION_HEIGHT 0.3 // [0.15 0.25 0.35 0.45 0.55 0.7 0.85 1.0] Normalized height for fine erosion to grow from base to full strength.
#define CLOUD_DENSITY_MULTIPLIER 1.0 // [0.5 0.7 0.85 1.0 1.15 1.3 1.5] final density multiplier; raises opacity and self-shadow together
#define CLOUD_LIGHT_MAX_DISTANCE_KM 2.0 // [1.0 1.5 2.0 3.0 4.0 6.0 8.0] Maximum light-direction optical depth trace distance (km).
#define CLOUD_PHASE_FORWARD_G 0.9 // [0.65 0.75 0.8 0.85 0.9 0.95] HanPi forward HG eccentricity.
#define CLOUD_PHASE_BACKWARD_G 0.3 // [0.15 0.2 0.25 0.3 0.35 0.4] HanPi backward HG eccentricity.
#define CLOUD_MS_ATTENUATION 0.5 // [0.25 0.35 0.5 0.65 0.75 0.85 1.0] HanPi per-octave optical depth multiplier.
#define CLOUD_MS_CONTRIBUTION 0.5 // [0.0 0.25 0.35 0.5 0.65 0.7 0.75 1.0] HanPi per-octave energy multiplier.
#define CLOUD_MS_ECCENTRICITY 0.5 // [0.0 0.25 0.33 0.4 0.5 0.6 0.75 1.0] HanPi per-octave phase eccentricity multiplier.
#define CLOUD_PHI_INTENSITY 0.1 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Vibroscat phi_fwd initial intensity.
#define CLOUD_PHI_COMPRESSION 0.0 // [0.0 0.1 0.25 0.5 1.0 2.0] Vibroscat phi_fwd soft compression.
#define CLOUD_SKY_LIGHT_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Sky environment scattering total strength; higher = brighter cloud shadow regions.

#define CLOUD_TEMPORAL_UPSCALING 3   // [1 2 3 4] low-res render divisor (1 = full resolution)
#define CLOUD_CHECKERBOARD_AREA (CLOUD_TEMPORAL_UPSCALING * CLOUD_TEMPORAL_UPSCALING)
//#define CLOUD_HISTORY_GUIDED_MARCH_END // Guide the view march end from reprojected cloud history.
#define CLOUD_HISTORY_GUIDED_END_SCALE 1.1 // [1.0 1.05 1.10 1.15 1.25] centroid-distance safety scale
#define CLOUD_ACCUMULATION_BOX_SAMPLES 9 // box-average the first 9 samples (seed + 8 blends = one checkerboard cycle)
#define CLOUD_ACCUMULATION_ALPHA 0.2 // steady-state EMA weight after the box phase
#define CLOUD_AGE_LIMIT 240 // cloud age cap in frames; must exceed BOX_SAMPLES * CLOUD_CHECKERBOARD_AREA
#define CLOUD_NO_CLOUD_DISTANCE 1e4  // no-cloud distance sentinel (km, half-float safe)
#define CLOUD_HISTORY_NO_DATA uintBitsToFloat(0x7fc00000u)  // NaN marker: history slot has no data

// ==========================================================================
// SHADOWS — Shadows / PCSS / SSS
// ==========================================================================
const int shadowMapResolution = 2048; // [1024 1536 2048 3072 4096 6144 8192]
const bool shadowHardwareFiltering = true;
const float sunPathRotation = -35.0;
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
// hardware bilinear shadow filtering; the blocker search stays on so the
// plant-SSS thickness estimate keeps working.
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
#define SHADOW_SSS_STEPS 8 // [4 6 8 10 12 16]
#define SHADOW_SSS_DENSITY 3.0 // [1.0 2.0 3.0 4.0 6.0 8.0]
#define SHADOW_SSS_SCALE 4.0 // [0.5 1.0 1.5 2.0 2.5 3.0]
#define SHADOW_SSS_PENUMBRA_BOOST 7.0 // [0.0 1.0 2.0 3.0 5.0 7.0 10.0]
#define SHADOW_SSS_PHASE_G 0.4 // [0.0 0.3 0.5 0.6 0.7 0.8 0.9]
#define SHADOW_SSS_FADE_START 0.75 // [0.0 0.5 0.6 0.7 0.75 0.8 0.9 0.95]

// ==========================================================================
// WATER — Water / epipolar
// ==========================================================================

// Opaque recursive screen-space indirect specular. This budget is separate
// from the forward water/glass SSR path below.
#define OPAQUE_REFLECTION 1 // [0 1] opaque screen-space reflection toggle; 0 = sky SH only
#define OPAQUE_SSR_QUALITY 2 // [0 1 2 3]
#define OPAQUE_SSR_DEBUG 0 // [0 1 2 3 4 5 6 7 8]
#if OPAQUE_REFLECTION && OPAQUE_SSR_QUALITY > 0
#define OPAQUE_SSR
#endif
#if OPAQUE_SSR_QUALITY == 1
#define OPAQUE_SSR_STEPS 24
#define OPAQUE_SSR_FILTER_RADIUS 4.0
#elif OPAQUE_SSR_QUALITY == 2
#define OPAQUE_SSR_STEPS 40
#define OPAQUE_SSR_FILTER_RADIUS 6.0
#elif OPAQUE_SSR_QUALITY == 3
#define OPAQUE_SSR_STEPS 64
#define OPAQUE_SSR_FILTER_RADIUS 8.0
#endif
#define OPAQUE_SSR_MAX_DISTANCE 96.0
#define OPAQUE_SSR_RECURSION_DECAY 0.92
#define OPAQUE_PBR_EMISSION_SCALE 1.0

#define WATER_SSR

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
#define EPIPOLAR_DEPTH_TOLERANCE 0.03 // [0.01 0.02 0.03 0.04 0.06 0.08] Relative viewZ column-match tolerance (3% = Alpha Piscium refinement threshold).
#define EPIPOLAR_EDGE_SHARPEN 0.25 // [0.1 0.2 0.25 0.3 0.4]
#define EPIPOLAR_EDGE_EXTEND 16 // [0 4 8 16 32 64]

// ==========================================================================
// FOG — Air fog
// ==========================================================================
const float eyeBrightnessHalflife = 3.0;

// Analytic air fog (composite2, after blend).
#define AIR_FOG
#define AIR_FOG_INTENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0 3.0 4.0]
#define AIR_FOG_DENSITY 10.0 // [0.5 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0]
#define AIR_FOG_SKY_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
#define AIR_FOG_SHADOWS

// ==========================================================================
// AO — Ambient occlusion
// ==========================================================================
const float ambientOcclusionLevel = 1.0;

// AO_MODE selects the algorithm (settings slider, 0/1/2): GTAO is the
// horizon-based method (Jimenez et al. 2016), SSAO the Monte-Carlo
// hemisphere estimator (Crytek 2007). Both share the deferred1_a half-res
// generator, deferred1 full-res temporal accumulation and deferred2 apply.
#define AO_MODE 1 // [0 1 2] 0=off 1=GTAO 2=SSAO
#if AO_MODE == 1
#define GTAO // pass toggle: enables program.worldX/deferred1_a and the deferred2 application
#endif
#if AO_MODE == 2
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
// AO generation is plain half resolution: every half-res texel is evaluated
// every frame at its full-res block origin and upsampled bilinearly — one
// sample per pixel per frame at full convergence speed.
#define GTAO_AGE_LIMIT 24 // [2 4 6 8 10 16 24 32] history age cap (frames) before full trust
// AO accumulation matches the cloud temporal scheme: box-average the first
// AO_ACCUMULATION_BOX_SAMPLES phase samples (one 2x2 checkerboard cycle),
// then a steady-state EMA with AO_ACCUMULATION_ALPHA. Rejection lifts the
// fresh-sample weight toward 1, so an untrusted history is replaced quickly
// instead of lingering (vanished objects' AO does not fade out slowly).
const int AO_ACCUMULATION_BOX_SAMPLES = 4;   // box-average the first 4 phase samples (one checkerboard cycle)
const float AO_ACCUMULATION_ALPHA = 0.2;     // steady-state EMA weight after the box phase
// Darkening slowdown: while the fresh sample is darker than the history
// (AO darkening in progress) the fresh weight is scaled by
// AO_DARKEN_SLOWDOWN so black AO fades in slowly — the eye is sensitive to
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
#define GTAO_HISTORY_DISTANCE_LIMIT 0.2 // [0.1 0.25 0.5 1.0 2.0] history rejection: max world displacement (m)
#define GTAO_HISTORY_NORMAL_DOT_MIN 0.866 // [0.94 0.91 0.87 0.82 0.71 0.5] history rejection: min normal dot (cos 30 deg)

// ==========================================================================
// LIGHTING — Lighting constants
// ==========================================================================

// Warm artificial-light palette, shared by deferred2 and the forward
// translucent passes. TORCH_BRIGHTNESS scales the light intensity only;
// the warm tint stays fixed.
#define TORCH_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0] torch light intensity multiplier
const vec3 TORCH_LIGHT_COLOR = vec3(1.00, 0.70, 0.35) * 12.0 * TORCH_BRIGHTNESS;

// Minimum ambient light floor added to every surface's sky ambient, so caves
// and deep shadows never render fully black (see AmbientLight in
// lib/lighting/ambient_light.glsl).
#define AMBIENT_BASE 0.06 // [0.0 0.03 0.06 0.1 0.15 0.2] minimum ambient light floor
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

#endif
