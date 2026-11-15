#ifndef LIB_CONTRACT_SETTINGS_GLSL
#define LIB_CONTRACT_SETTINGS_GLSL

// Toggles are bare defines, sliders carry `// [values] description`; Iris
// recognizes toggles through the registration block at the end of this file.

// 1. SKY - atmosphere and celestial

#define ATM_HORIZON_DIP // Horizon below-dip; off keeps the ellipsoid ground line.
#define ATM_HORIZON_DIP_SCALE 8.0 // [0.0 2.0 4.0 6.0 8.0 12.0 16.0 24.0 32.0 48.0 64.0] below-surface dip depth (km)

// Linear gain after the LogLuv32 decode (celestial.glsl).
#define STAR_MAP_INTENSITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] night star brightness
// Artistic grade applied before the transmittance and night fades (celestial.glsl).
#define STAR_MAP_CONTRAST 2.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 2.0] star map contrast exponent
#define STAR_MAP_BRIGHT_BOOST 4.0 // [0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0] luminance-keyed bright star gain

// Disc radii (radians), shared by the sky renderer and the GGX area light so
// the specular glint matches the visible sky.
const float SUN_DISC_RADIUS  = 0.005;   // ~0.267 deg
const float SUN_GLOW_RADIUS  = 0.03;    // ~1.0 deg soft falloff
const float MOON_DISC_RADIUS = 0.00436; // ~0.25 deg
const float MOON_GLOW_RADIUS = 0.012;

// 2. CLOUDS - Cloud layers (volumetric + cirrus)

#define VOLUMETRIC_CLOUDS
//#define CLOUD_SHADOWS // Single-lookup cloud shadows on direct sunlight and its RSM bounce.
#define CIRRUS // Independent of the volumetric layer.
#define CIRRUS_WIND_SPEED 0.01 // [0.0 0.005 0.01 0.015 0.02 0.03 0.04 0.06 0.08 0.1] Cirrus drift speed (km/s); moves the body and strands together.
#define CLOUD_VIEW_MIN_STEPS 20 // [20 24 32 40 48 56 64 96 128] Minimum cloud steps for short view rays; higher values stabilize near silhouettes at higher cost.
#define CLOUD_VIEW_MAX_STEPS 40 // [40 64 80 96 112 128 160 192 256] Maximum cloud steps for long view rays; controls horizon quality and cost.
#define CLOUD_VIEW_TARGET_STEP_KM 0.4 // [0.2 0.25 0.3 0.4 0.5 0.75 1.0] Adaptive step target distance (km); smaller = denser sampling.
#define CLOUD_LIGHT_STEPS 6 // [3 4 5 6 8] Light-direction steps per cloud sample; affects self-shadow quality and primary lighting cost.
#define CLOUD_LIGHT_START_OFFSET_KM 0.0 // [0.0 0.025 0.05 0.075 0.1 0.15 0.2 0.3 0.4 0.5] Distance skipped toward the light before cloud self-shadow integration (km).
#define CLOUD_BASE_ALTITUDE 1.4 // [0.8 1.0 1.2 1.4 1.6 1.8 2.0] Cloud base altitude above terrain (km).
#define CLOUD_THICKNESS_KM 1.0 // [0.6 0.8 1.0 1.2 1.3 1.4 1.5 1.6 1.8 2.0] Cloud layer vertical thickness (km).
#define CLOUD_TOP_ALTITUDE (CLOUD_BASE_ALTITUDE + CLOUD_THICKNESS_KM)
#define CLOUD_COVERAGE 0.5 // [0.4 0.5 0.55 0.6 0.65 0.7 0.8] Weather-map coverage bar; higher = a wider cloud footprint. Rain still pushes coverage to full overcast.
#define CLOUD_DISTRIBUTION_SCALE_KM 70.0 // [48.0 64.0 70.0 80.0 96.0 128.0 160.0 192.0 240.0 280.0] 2D Worley fBm distribution map world-space scale for a full wrap (km).
#define CLOUD_WIND_SPEED 0.01 // [0.0 0.005 0.01 0.015 0.02 0.03 0.04 0.06 0.08 0.1] Cloud wind speed (km/s); distribution drifts with wind, higher = faster motion.
#define CLOUD_FINE_EROSION_SCALE 1.5 // [1.0 1.5 2.0 3.0 4.0 5.0 6.0 8.0] Voronoise coordinate scale per kilometer; higher = smaller, denser erosion cells.
#define CLOUD_FINE_EROSION_STRENGTH 0.6 // [0.25 0.5 0.6 0.7 1.0 1.5] Light-trace erosion strength; scales the voronoise mean the same way the view path scales its per-point read.
#define CLOUD_ALPHA_EXTINCTION_SRGB_GRAY 80.0 // [25.0 35.0 50.0 65.0 80.0 100.0] Extinction of a fully dense sample (km^-1); higher = denser, more opaque clouds.
#define CLOUD_LIGHT_MAX_DISTANCE_KM 4.0 // [1.0 1.5 2.0 3.0 4.0 6.0 8.0] Maximum light-direction optical depth trace distance (km).
#define CLOUD_PHASE_FORWARD_G 0.95 // [0.65 0.75 0.8 0.85 0.9 0.95] Forward HG eccentricity of the cloud phase.
#define CLOUD_PHASE_BACKWARD_G 0.3 // [0.15 0.2 0.25 0.3 0.35 0.4] Backward HG eccentricity of the cloud phase.
#define CLOUD_MS_ATTENUATION 0.4 // [0.25 0.3 0.35 0.4 0.5 0.65 0.75 0.85 1.0] Per-octave optical depth multiplier.
#define CLOUD_MS_CONTRIBUTION 0.7 // [0.0 0.25 0.35 0.5 0.65 0.7 0.75 1.0] Per-octave energy multiplier.
#define CLOUD_MS_ECCENTRICITY 0.4 // [0.0 0.25 0.33 0.35 0.4 0.5 0.6 0.75 1.0] Per-octave phase eccentricity multiplier.
#define CLOUD_MS_SAT_ALBEDO 0.99 // [0.9 0.95 0.97 0.98 0.99 0.995 0.999] Saturation albedo of the geometric series; values below one bound its scattering weights in half-float history.
#define CLOUD_MS_ISOTROPIC 0.6 // [0.0 0.1 0.2 0.25 0.3 0.5 0.6 0.75 1.0 1.25 1.5 2.0] Isotropic geometric-series strength; higher = brighter, milkier cloud interiors.
#define CLOUD_AMBIENT_STRENGTH 0.75 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Volumetric cloud SH ambient strength; higher = brighter shadowed regions.
#define CLOUD_SKY_LIGHT_STRENGTH 8.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0 6.0 8.0 12.0 16.0] Cirrus sky fill strength; higher = brighter shadowed regions.
#define CIRRUS_MS_ISOTROPIC 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Cirrus multiple-scattering order strength on the direct lights; higher = brighter, more filled cirrus bodies.
#define CLOUD_MILKYWAY_GLOW // Milky Way glow scattered inside the volumetric layer; the transmission slider below owns its share.
#define CIRRUS_MILKYWAY_GLOW // Artistic Milky Way glow inside the cirrus sheet; independent of the background transmission.
#define CLOUD_MILKYWAY_TRANSMISSION 0.1 // [0.1 0.2 0.3 0.5 0.75 1.0] Share of the Milky Way background the volumetric layer scatters into a glow; 1.0 is the isotropic single-scatter total.
#define CIRRUS_MILKYWAY_TRANSMISSION 0.3 // [0.1 0.2 0.3 0.5 0.6 0.75 1.0] Share of the Milky Way background the cirrus sheet scatters into a glow; 1.0 is the isotropic single-scatter total.

#define CLOUD_RECONSTRUCTION_MODE 1 // [0 1] 0 = continuous reconstruction, 1 = checkerboard reconstruction
#define CLOUD_TEMPORAL_UPSCALING 3   // [1 2 3 4] low-res render divisor (1 = full resolution)
// Both modes use colortex12 alt inside its display-sized allocation, including TAAU.
#if CLOUD_TEMPORAL_UPSCALING == 1
const vec2 CLOUD_CURRENT_SCALE = vec2(1.0);
#elif CLOUD_TEMPORAL_UPSCALING == 2
const vec2 CLOUD_CURRENT_SCALE = vec2(0.5);
#elif CLOUD_TEMPORAL_UPSCALING == 3
const vec2 CLOUD_CURRENT_SCALE = vec2(0.333333);
#else
const vec2 CLOUD_CURRENT_SCALE = vec2(0.25);
#endif
#define CLOUD_HISTORY_FRAMES 24 // [8 12 16 24 32 48] continuous history cap or checkerboard decay horizon
#define CLOUD_NO_CLOUD_DISTANCE 1e4  // no-cloud distance sentinel (km, half-float safe)
#define HISTORY_NO_CLOUD_DATA uintBitsToFloat(0x7fc00000u)  // NaN marker: history slot has no data

// 3. FOG - Air and boundary fog

const float eyeBrightnessHalflife = 3.0;

#define AIR_FOG
#define AIR_FOG_INTENSITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 5.0]
#define AIR_FOG_DENSITY_DAY 20.0 // [0.0 1.0 2.0 5.0 10.0 15.0 20.0 30.0 40.0 60.0]
#define AIR_FOG_DENSITY_DUSK 160.0 // [0.0 1.0 2.0 5.0 10.0 15.0 20.0 30.0 40.0 60.0 80.0 100.0 120.0 160.0 200.0 240.0 300.0]
#define AIR_FOG_DENSITY_NIGHT 80.0 // [0.0 1.0 2.0 5.0 10.0 15.0 20.0 30.0 40.0 60.0 80.0]
#define AIR_FOG_DENSITY_RAIN 160.0 // [0.0 5.0 10.0 20.0 30.0 40.0 60.0 80.0 100.0 120.0 160.0 200.0 256.0]
#define AIR_FOG_REFERENCE_HEIGHT_M 64.0 // [0.0 32.0 64.0 96.0 128.0]
#define AIR_FOG_SCALE_HEIGHT_M 8.0 // [8.0 12.0 32.0 48.0 64.0 96.0 128.0 192.0 256.0]
#define AIR_FOG_SKY_STRENGTH 0.5 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
#define AIR_FOG_SHADOWS
#define EPIPOLAR_VOLUMETRICS
#define EPIPOLAR_SLICES 1024 // [256 512 1024 2048]
#define EPIPOLAR_SAMPLES 512 // [128 256 512 1024]
#define AIR_EPIPOLAR_SHADOW_STEPS 12 // [8 12 16 24 32 48 64]
#define EPIPOLAR_DEPTH_TOLERANCE 0.03 // [0.01 0.02 0.03 0.04 0.06 0.08]
#define EPIPOLAR_EDGE_EXTEND 16 // [0 4 8 16 32 64]

#define WATER_GODRAYS
#define WATER_GODRAYS_STRENGTH 3.0 // [0.0 0.5 1.0 1.5 2.0 3.0 4.0 6.0 8.0]
#define WATER_GODRAYS_STEPS 32 // [8 12 16 24 32]
#define WATER_GODRAYS_DISTANCE_M 16.0 // [2.0 4.0 6.0 8.0 12.0 16.0 24.0 32.0]

// Overworld only; independent of the analytic water fog.
#define BOUNDARY_FOG
#define BOUNDARY_FOG_START 0.7 // [0.25 0.4 0.5 0.6 0.7 0.8 0.9] render-distance fraction where the fade begins
#define BOUNDARY_FOG_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define BOUNDARY_FOG_HEIGHT_FADE 0.8 // [0.0 0.25 0.5 0.75 0.8 1.0] sky-facing dampening

// 4. SHADOWS - Shadows / PCSS / SSS

const int shadowMapResolution = 1536; // [1024 1536 2048 3072 4096 6144 8192]
const bool shadowHardwareFiltering = true;
const float sunPathRotation = -15.0; // [-60.0 -45.0 -30.0 -15.0 0.0 15.0 30.0 45.0 60.0]
const float shadowIntervalSize = 2.0;
const float real_shadow_map_resolution = float(shadowMapResolution);
const float shadowDistance = 128.0; // [64.0 96.0 128.0 192.0 256.0 384.0 512.0]
// Positive: cull shadow terrain at shadowDistance * mul; host default -1 leaves it unculled.
const float shadowDistanceRenderMul = 1.0;

// Shadow depth remapped into [0.5-0.5*SCALE, 0.5+0.5*SCALE]; every producer/consumer
// of shadow depth must use the same map.
const float SHADOW_DEPTH_SCALE = 1.0 / 6.0;

// Fernando 2005 blocker search + penumbra PCF; LOW falls back to one hardware-PCF lookup.
#define SHADOW_PCSS
#define SHADOW_BLOCKER_SAMPLES 4 // [2 3 4 5 6 8 10 12]
#define SHADOW_BLOCKER_SEARCH_RADIUS 0.15 // [0.05 0.075 0.1 0.125 0.15 0.2 0.25 0.3] World-space search radius (m).
#define SHADOW_SUN_ANGULAR_RADIUS 0.02 // [0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.10 0.12 0.15]
#define SHADOW_PCF_MIN_SAMPLES 4 // [2 3 4 5 6 8]
#define SHADOW_PCF_MAX_SAMPLES 16 // [6 8 10 12 16 20 24]
#define SHADOW_PCF_GAIN 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5]
#define SHADOW_PENUMBRA_CAP_BOOST 1.0 // [0.0 0.5 1.0 1.5 2.0] Multiplier on the penumbra-radius cap; no sun-height dependence.
#define SHADOW_BLOCKER_DEPTH_TOLERANCE_M 0.0 // [0.0 0.05 0.1 0.15 0.2 0.3 0.5]

// Colored reference-layer transport; no AO/GI or external layer absorption.
#define SHADOW_SSS
#define SHADOW_SSS_TRANSMISSION 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] PCSS scattering gain; LOW thin-layer transmission.
#define SHADOW_SSS_STEPS 8 // [4 6 8 10 12 16] Near PCSS filter only.
#define SHADOW_SSS_SCREEN
#define SHADOW_SSS_SCREEN_DISTANCE 48.0 // [16.0 32.0 48.0 64.0 96.0] Meters; at most 12 depth-only reads.
#define SHADOW_SSS_FADE_START 0.75 // [0.5 0.6 0.7 0.75 0.8 0.9 0.95]

// Screen-projected ray toward the light; applied as a min() upper bound on the
// shadow-map result (Overworld only).
#define CONTACT_SHADOW // Screen-space contact shadows alongside the shadow map.
#define CONTACT_SHADOW_STEPS 12 // [4 6 8 12 16 24] depth samples per receiver pixel.
#define CONTACT_SHADOW_MAX_DISTANCE 24.0 // [4.0 6.0 8.0 10.0 12.0 16.0 24.0] world-space march reach cap (m); the reach scales with view distance.
#define CONTACT_SHADOW_THICKNESS 0.02 // [0.02 0.05 0.1 0.25 0.5 1.0] near-field occluder thickness slab (m); it also widens with view distance.
const float CONTACT_SHADOW_GAP_MIN_METERS = 0.005; // receiver self-occlusion guard (m)

// 5. GLOBAL ILLUMINATION - Diffuse indirect (SSGI / RSM)

// Both SSGI and RSM supply SH for uncovered directions.
#define GI_MODE 0 // [0 1 2] 0=None 1=SSGI 2=ReflectiveShadowMap
// Trace implementation (GI_MODE 1): recursive_gi.fragment.
#define SSGI_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0] Bounce gain after the bounce-only radiance limit; does not scale sky ambient.
#define SSGI_STEPS 16 // [4 8 12 16 24 32 48 64] Geometric march steps per pixel; higher = smoother distant bounce light, linear cost.
#define SSGI_MARCH_PIXELS 512.0 // [128.0 256.0 384.0 512.0 768.0 1024.0] March width cap in screen pixels.
#define SSGI_THICKNESS 0.5 // [0.1 0.25 0.5 0.75 1.0 1.5 2.0] Sample geometry thickness in view-depth meters.
#define SSGI_RADIANCE_LIMIT 128.0 // [16.0 32.0 64.0 128.0 256.0 512.0] Bounds the unscaled SSGI bounce before strength and sky are added.
#define RSM_SAMPLES 8 // [8 16 32 64]
#define RSM_RADIUS 8.0 // [2.0 4.0 8.0 12.0 16.0 24.0]
#define RSM_STRENGTH 1.5 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0]
#define RSM_DIRECTIONAL_SKY // Directional sky visibility for RSM with GTAO; extra shading cost.
#define SSGI_DIRECTIONAL_SKY // Directional sky visibility for SSGI; extra GPU cost.

// 6. AO - Ambient occlusion

const float ambientOcclusionLevel = 1.0;

#define AO_MODE 0 // [0 1] 0=vanilla AO 1=GTAO
#define GTAO_SLICES 2 // [2 3 4 6 8 10 12] horizon slices per pixel
#define GTAO_RADIUS 1.5 // [0.5 1.0 1.5 2.0 3.0 4.0] view-space search radius (m)
#define GTAO_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0] AO contrast (exponent)
#define GTAO_HORIZON_STEPS 3 // [2 3 4 6 8] depth samples per horizon side
#define GTAO_FALLOFF_START 0.75 // [0.0 0.25 0.5 0.6 0.7 0.75 0.8 0.9 1.0] radius fraction where the falloff begins
#define GTAO_MULTIBOUNCE // albedo-dependent energy recovery (paper Eq. 12).
// Temporal accumulation details: lib/lighting/temporal_ao.glsl and ao.compute.
#define AO_TEMPORAL // temporal toggle: enables the history accumulation
#define AO_HISTORY_FRAMES 12 // [2 4 6 8 10 12 16 24 32 48] accumulated-average length cap (frames); fresh weight settles at 1/N
#define AO_HISTORY_DISTANCE_LIMIT 0.2 // [0.1 0.2 0.25 0.5 1.0 2.0] history rejection: max receiver-plane distance (m)
#define AO_HISTORY_NORMAL_DOT_FLOOR 0.866 // [0.5 0.71 0.82 0.866 0.91 0.94] history rejection: min normal dot (cos 30 deg)

// 7. LIGHTING - Lighting constants

// User-picked because MC_TEXTURE_FORMAT_LAB_PBR only exists when the resource
// pack declares format=lab-pbr; host mipmapping still follows the pack.
// 0 = LabPBR: specular B=aux, A=emission, G>=230 metal; normal XY+Z, B=AO.
// 1 = oldPBR: specular G=metalness, B=emission; RGB tangent normals.
#define MATERIAL_FORMAT 0 // [0 1] 0=LabPBR 1=oldPBR

// Shared by deferred5 and the forward translucent passes; brightness scales intensity only.
#define TORCH_BRIGHTNESS 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5 2.0] torch light intensity multiplier
const vec3 TORCH_LIGHT_COLOR = vec3(1.00, 0.70, 0.35) * 12.0 * TORCH_BRIGHTNESS;

// Scales the SH sky ambient; direct sun, AMBIENT_FLOOR and SH reflections are outside it.
#define SKY_AMBIENT_STRENGTH 0.75 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5 1.55 1.6 1.65 1.7 1.75 1.8 1.85 1.9 1.95 2.0] sky SH ambient light intensity multiplier

// Ambient floor so caves never render fully black (lib/lighting/ambient_light.glsl).
#define AMBIENT_FLOOR 0.005 // [0.0 0.005 0.03 0.06 0.1 0.15 0.2] minimum ambient light floor

// Forward-lit opaque particles; some Iris builds ignore particles.ordering and keep the order.
//#define PARTICLE_FORWARD

// 8. WATER - Water surface

#define RAIN_WETNESS
#define RAIN_PUDDLES
#define RAIN_RIPPLES
#define RAIN_PUDDLE_COVERAGE 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8] puddle coverage threshold on the cloud distribution atlas
#define RAIN_PUDDLE_SCALE_M 64 // [16 32 64 128 256] world-space wrap of the puddle pattern (m)
#define RAIN_RIPPLE_STRENGTH 4.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0 3.5 4.0] slope strength on wet ground and water

// #define OPAQUE_REFLECTION // opaque screen-space reflection toggle; off = sky SH only
#define OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD 0.5 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0] roughness at which opaque reflections become SH-only and dielectric reflection fades out
#define OPAQUE_REFLECTION_ROUGHNESS_TRANSITION 0.1 // [0.01 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5] roughness span used to blend SSR into SH
// 0 = unfiltered, 1 = temporal denoising.
#define OPAQUE_SSR_FILTER 1 // [0 1]
#define OPAQUE_SSR_DEMODULATION

// History-color filtering: 0 = base, 1 = generate only, 2 = roughness/distance
// footprint; a biased filter on the VNDF sample, not a second GGX convolution.
#define OPAQUE_SSR_COLOR_MIPS 2 // [0 1 2]
#define OPAQUE_SSR_COLOR_MIP_SCALE 1.0 // [0.125 0.25 0.5 1.0]
#define OPAQUE_SSR_COLOR_MIP_MAX 5 // [2 3 4 5]
// Firefly clamp: the sun disk would otherwise flicker as bright sparkles through the filter.
#define OPAQUE_SSR_RADIANCE_LIMIT 12.0 // [2.0 4.0 8.0 12.0 16.0 24.0 32.0 64.0 128.0] cap on radiance sampled from the reflected scene

// Opaque SSR march budget (McGuire & Mara 2014); more steps extend reach, not hit accuracy.
#define OPAQUE_SSR_STEPS 12 // [8 12 16 20 24 32 40 48 64] opaque SSR march samples
// Each iteration halves the march bracket; 4 keeps the hit within step/16 of the flip.
#define OPAQUE_SSR_BISECT_STEPS 4
#define OPAQUE_SSR_RECURSION_DECAY 1.0
#define OPAQUE_PBR_EMISSION_SCALE 1.0

#define WATER_SSR

#define SSR_QUARTER_DEPTH // trace both SSR paths with width/4, height/4 R16F depth

// Bisect inside the accepted march bracket, then correct once against the surface depth.
#define SSR_INTERPOLATION

// Water SSR march budget (McGuire & Mara 2014).
#define WATER_SSR_STEPS 10 // [8 10 12 16 20 24 32] water SSR march samples
// Same step/16 bound as the opaque path.
#define WATER_SSR_BISECT_STEPS 4

// LOW profile disables POM (normal evaluated at the plane position).
#define WATER_POM

// 0 = small waves, 1 = medium-large (more normal / POM layers).
#define WATER_SURFACE_QUALITY 0 // [0 1]

// Small-wave height and slope gain.
#define WATER_RIVER_GAIN 1.0 // [0.5 1.0 1.5 2.0 2.5 3.0 3.69 5.0]

// Large-wave height and slope gain; 1.0 uses the baked amplitude.
#define WATER_LARGE_POM_HEIGHT 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0]

// LOW profile disables POM entirely, so these stay at defaults.
#define WATER_POM_COARSE_STEPS 4 // [2 3 4 5 6 8] coarse POM height-chase steps
#define WATER_POM_BISECT_STEPS 2 // [0 1 2 3 4] POM bisection refinement iterations

// 9. POST - Exposure, tonemapping, and screen effects

#define AE
#define AE_TARGET_LUMINANCE 0.18 // [0.08 0.10 0.12 0.15 0.18 0.21 0.24 0.28 0.32 0.40] Auto-exposure reference display key; 0.18 is middle gray
#define AE_ADAPTATION_STRENGTH 0.70 // [0.0 0.25 0.40 0.55 0.70 0.85 1.0] Scene-key EV compensation; 0=fixed exposure, 1=full compensation

#define TONEMAP_MODE 5 // [0 3 5 6 7 8 10] Tonemap: 0=AgX-HSV 3=OpenDRT 5=GT7 6=ACES-Fitted 7=Hable 8=ACESFilmic 10=Hejl2015
#define TONEMAP_EXPOSURE 0.0 // [-2.0 -1.5 -1.0 -0.75 -0.5 -0.25 0.0 0.25 0.5 0.75 1.0 1.5 2.0] Manual exposure (EV), applied before auto-exposure

// #define PURKINJE_EFFECT // Requires AE: rod-vision night grading driven by the exposure state.
#define PURKINJE_STRENGTH 0.8 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] Night vision strength
// Exposure-derived keys: full rod adaptation at 16x exposure, within AE's 32x limit.
const float PURKINJE_SCOTOPIC_KEY = AE_TARGET_LUMINANCE / 16.0;
const float PURKINJE_PHOTOPIC_KEY = AE_TARGET_LUMINANCE / 2.0;
const float PURKINJE_CONE_LUMINANCE = 0.35;
const vec3 PURKINJE_TINT = vec3(0.45, 0.65, 1.0);

#define BLOOM
#define BLOOM_STRENGTH 0.1 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// IGN grain hides R11G11B10F/8-bit banding; screen-fixed, so a still camera accumulates it.
#define COLOR_DITHER
#define COLOR_DITHER_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Color dither strength: 0.5=conservative, 1.0=default, 2.0=aggressive

#define CAS
#define CAS_SHARPNESS 0.75 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

//#define DOF
#define DOF_STRENGTH 1.0 // [0.5 1.0 1.5 2.0 3.0 4.0] Lens scale; radius capped at 8 pixels at 1080p
#define DOF_QUALITY 1 // [0 1 2] Support/color taps: 6/8, 10/12, 12/24
//#define MOTION_BLUR
#define MB_STRENGTH 0.8 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

#define TAA
//#define TAAU
#define TAAU_RENDER_SCALE 0.75 // [0.50 0.59 0.67 0.75 0.85]
#define TAA_RECONSTRUCTION 0 // [0 1] 0=Bilinear 1=Cubic
#define TAA_JITTER 0 // [0 1] 0=Halton8 1=R2
#define TAA_HISTORY_WEIGHT 0.90 // [0.70 0.75 0.80 0.85 0.90 0.95 0.97]
#define TAA_MOTION_REJECTION 0.50 // [0.00 0.25 0.50 0.75 1.00]
#define TAA_REACTIVE_STRENGTH 0.50 // [0.00 0.25 0.50 0.75 1.00]

// 10. UI-ONLY - display-only pseudo options, never read by shader code

// Inert settings buttons; text comes from the lang files. Keep every name in
// the shaders.properties screen lists and both lang files.
#define ABOUT 0 //[0]
#define INFO_LICENSE 0 //[0]
#define INFO_PROFILE 0 //[0]
#define INFO_TOOLTIPS 0 //[0]

// Plant wind - precomputed turbulent drag and damped elastic response.
#define PLANT_WIND
#define PLANT_WIND_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Wind load multiplier.
#define PLANT_WIND_GRASS 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Rooted-plant compliance.
#define PLANT_WIND_LEAVES 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0] Canopy compliance.

// Rebuild the terrain TBN from derivatives; off keeps the flat per-face basis.
#define TERRAIN_DERIVATIVE_TBN

// 11. DERIVED STATE - internal pass toggles computed from the options above

// Internal toggles; a plain `#ifdef NAME` outside the registration block below
// would register one as a hidden user option (default on).

#if defined(PLANT_WIND) && (defined(PROGRAM_GBUFFERS_TERRAIN) || defined(PROGRAM_GBUFFERS_TERRAIN_SOLID) || defined(PROGRAM_GBUFFERS_TERRAIN_CUTOUT))
#define PLANT_WIND_TERRAIN_ACTIVE
#endif
#if defined(PLANT_WIND) && !defined(PROGRAM_SHADOW_ENTITIES) && !defined(PROGRAM_SHADOW_BLOCK) && !defined(PROGRAM_SHADOW_WATER)
#define PLANT_WIND_SHADOW_ACTIVE
#endif

// Opaque programs whose vertex stage carries a real per-primitive material id.
#if defined(PROGRAM_GBUFFERS_TERRAIN) || defined(PROGRAM_GBUFFERS_TERRAIN_SOLID) || defined(PROGRAM_GBUFFERS_TERRAIN_CUTOUT)
#define GBUFFER_TERRAIN_ACTIVE
#endif

#if defined(GBUFFER_TERRAIN_ACTIVE) || defined(PROGRAM_GBUFFERS_BLOCK) || defined(PROGRAM_GBUFFERS_ENTITIES)
#define GBUFFER_MATERIAL_ID_VARYING
#endif

#if defined(TERRAIN_DERIVATIVE_TBN) && defined(GBUFFER_TERRAIN_ACTIVE)
#define TERRAIN_DERIVATIVE_TBN_ACTIVE
#endif

// Internal gate, not a user option; 0 isolates the gated consumers.
#define WATER_NORMAL_ENABLED 1
#if defined(PROGRAM_GBUFFERS_WATER) && WATER_NORMAL_ENABLED != 0
#define WATER_SURFACE_POSITION_ACTIVE
#endif
#if defined(WATER_SURFACE_POSITION_ACTIVE) && defined(HAS_AT_TANGENT)
#define WATER_SURFACE_TANGENT_ACTIVE
#endif

// RSM reads reflectance + shadow-view normals from every non-water caster;
// without RSM only the cutout alpha test needs the atlas.
#if GI_MODE == 2 && !defined(PROGRAM_SHADOW_WATER)
#define SHADOW_RSM_PAYLOAD_ACTIVE
#endif
#if defined(SHADOW_RSM_PAYLOAD_ACTIVE) || defined(USE_DISCARD)
#define SHADOW_TEXCOORD_ACTIVE
#endif

#if defined(TAAU) && defined(TAA)
#define TAAU_ACTIVE
#endif

#if defined(RAIN_WETNESS) && defined(WORLD_OVERWORLD) && (defined(PROGRAM_GBUFFERS_TERRAIN) || defined(PROGRAM_GBUFFERS_TERRAIN_SOLID) || defined(PROGRAM_GBUFFERS_TERRAIN_CUTOUT) || defined(PROGRAM_GBUFFERS_BLOCK))
#define RAIN_WETNESS_ACTIVE
#endif

#if defined(RAIN_WETNESS_ACTIVE) && (defined(RAIN_PUDDLES) || defined(RAIN_RIPPLES))
#define RAIN_WETNESS_POSITION_ACTIVE
#endif

#if defined(OPAQUE_REFLECTION)
#define OPAQUE_SSR
#endif

#if defined(SSR_QUARTER_DEPTH) && (defined(WATER_SSR) || defined(OPAQUE_SSR))
#define SSR_QUARTER_DEPTH_ACTIVE
#endif

#if defined(WORLD_OVERWORLD) && defined(AIR_FOG) && defined(AIR_FOG_SHADOWS) && defined(EPIPOLAR_VOLUMETRICS)
#define AIR_EPIPOLAR_ACTIVE
#endif

#if defined(WORLD_OVERWORLD) && defined(WATER_GODRAYS) && defined(EPIPOLAR_VOLUMETRICS)
#define WATER_EPIPOLAR_ACTIVE
#endif
#if defined(AIR_EPIPOLAR_ACTIVE) || defined(WATER_EPIPOLAR_ACTIVE)
#define EPIPOLAR_ACTIVE
#endif

// Standalone AO exists only without GI; guards stay numeric because
// AO_MODE/GI_MODE are enum options.
#if AO_MODE == 1 && GI_MODE == 0
#define GTAO
#endif

// Overworld RSM + GTAO only; occluders tint the sky light by direction.
#if defined(RSM_DIRECTIONAL_SKY) && GI_MODE == 2 && AO_MODE == 1 && defined(WORLD_OVERWORLD)
#define RSM_DIRECTIONAL_SKY_ACTIVE
#endif

// Overworld SSGI only; weights the sky SH by the directions that stay open.
#if defined(SSGI_DIRECTIONAL_SKY) && GI_MODE == 1 && defined(WORLD_OVERWORLD)
#define SSGI_DIRECTIONAL_SKY_ACTIVE
#endif

#if defined(AO_TEMPORAL)
#define AO_TEMPORAL_ENABLED
#endif

// 12. IRIS OPTION REGISTRATION - canonical recognition references

// A bare define becomes a user option only via a plain, comment-free
// `#ifdef NAME` / `#ifndef NAME` line in the include component; `#if
// defined(NAME)` does not count and an unregistered candidate silently drops
// from the settings screen. shaders.properties uses the numeric AO_MODE/GI_MODE gates.

// Post
#ifdef TAA
#endif
#ifdef TAAU
#endif
#ifdef DOF
#endif
#ifdef MOTION_BLUR
#endif
#ifdef BLOOM
#endif
#ifdef COLOR_DITHER
#endif
#ifdef AE
#endif
#ifdef CAS
#endif
#ifdef PURKINJE_EFFECT
#endif
// Sky
#ifdef PLANT_WIND
#endif
// Terrain
#ifdef TERRAIN_DERIVATIVE_TBN
#endif
#ifdef ATM_HORIZON_DIP
#endif
// Clouds
#ifdef VOLUMETRIC_CLOUDS
#endif
#ifdef CLOUD_SHADOWS
#endif
#ifdef CIRRUS
#endif
#ifdef CLOUD_MILKYWAY_GLOW
#endif
#ifdef CIRRUS_MILKYWAY_GLOW
#endif
// Fog
#ifdef AIR_FOG
#endif
#ifdef WATER_GODRAYS
#endif
#ifdef AIR_FOG_SHADOWS
#endif
#ifdef EPIPOLAR_VOLUMETRICS
#endif
#ifdef BOUNDARY_FOG
#endif
// Shadows
#ifdef SHADOW_PCSS
#endif
#ifdef SHADOW_SSS
#endif
#ifdef SHADOW_SSS_SCREEN
#endif
#ifdef CONTACT_SHADOW
#endif
// Ambient occlusion
#ifdef AO_TEMPORAL
#endif
#ifdef GTAO_MULTIBOUNCE
#endif
// GI
#ifdef RSM_DIRECTIONAL_SKY
#endif
#ifdef SSGI_DIRECTIONAL_SKY
#endif
// Water
#ifdef OPAQUE_REFLECTION
#endif
#ifdef OPAQUE_SSR_DEMODULATION
#endif
#ifdef WATER_SSR
#endif
#ifdef SSR_QUARTER_DEPTH
#endif
#ifdef SSR_INTERPOLATION
#endif
#ifdef WATER_POM
#endif
#ifdef RAIN_WETNESS
#endif
#ifdef RAIN_PUDDLES
#endif
#ifdef RAIN_RIPPLES
#endif
// Particles
#ifdef PARTICLE_FORWARD
#endif

#endif // LIB_CONTRACT_SETTINGS_GLSL
