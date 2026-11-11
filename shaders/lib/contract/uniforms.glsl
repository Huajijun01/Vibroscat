#ifndef LIB_CONTRACT_UNIFORMS_GLSL
#define LIB_CONTRACT_UNIFORMS_GLSL

#include "/lib/contract/settings.glsl"

// Consolidated uniform contract. Every sampler, shadow transform, Iris
// matrix/camera built-in, and custom u_* uniform used by shared libraries is
// declared here exactly once; shared libraries do not declare their own
// copies, so no compile unit ever sees a duplicate declaration.
//
// Image uniforms (uimg_*) are not declared here: each compute entry
// needs a format layout qualifier (r8 / rgba16f) that differs per pass.

// -- Iris built-in matrices (injected by Iris; no properties line) --
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

// -- Alpha test (Iris built-in; effective reference of the current draw) --
uniform float alphaTestRef;

// -- Camera / resolution (Iris built-ins + u_* from properties) --
uniform vec3 cameraPosition;
uniform ivec3 cameraPositionInt; // absolute integer camera position (rain texture anchoring)
uniform vec3 cameraPositionFract; // absolute fractional camera position
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform vec2 u_view_pixel_size;    // 1 / (viewWidth, viewHeight)
uniform vec2 u_bloom_max_uv;       // last texel center of the ceil-sized half-resolution tile
uniform vec2 u_render_res;         // active pre-TAA scene rectangle, integer pixels
uniform vec2 u_render_pixel_size;  // 1 / u_render_res (projection UVs)
uniform vec2 u_render_scale;       // u_render_res / display allocation size
uniform float u_cam_altitude;      // camera altitude in km (cloud shell / sky LUT)

// -- Frame-constant derives (shaders.properties) --
uniform vec3 u_camera_delta;      // cameraPosition - previousCameraPosition
uniform float u_camera_delta_sq;  // |u_camera_delta|^2
uniform vec3 u_eye_world_pos;     // gbufferModelViewInverse[3].xyz
uniform vec3 u_ssr_previous_to_view_x; // rows of R_current * transpose(R_previous)
uniform vec3 u_ssr_previous_to_view_y;
uniform vec3 u_ssr_previous_to_view_z;
uniform vec4 u_ssr_previous_delta_x; // rows of M_previous - M_current, + R_previous * camera_delta
uniform vec4 u_ssr_previous_delta_y;
uniform vec4 u_ssr_previous_delta_z;
uniform vec2 u_ssr_projection_delta; // previous - current projection diagonal
uniform bool u_ssr_history_static; // identical camera/projection, independent of TAA
uniform float u_inv_clip_depth;   // gbufferProjectionInverse[2][3] + [3][3]
uniform float u_squared_depth_decode; // SQUARED_DEPTH_HALF_RCP_SQRT / u_inv_clip_depth
uniform float u_clip_far_distance; // 1 / u_inv_clip_depth
uniform float u_camera_radius_km;   // 6360.0 + u_cam_altitude
uniform float u_camera_radius_sq;   // u_camera_radius_km^2
uniform vec3 u_atmosphere_camera_pos; // (0, u_camera_radius_km, 0)
uniform float u_sky_lut_horizon_theta; // asin(R / (R + alt)) - pi/2
uniform vec3 u_sky_lut_sun_dir;      // (0, sun.y, sqrt(1 - sun.y^2))
uniform float u_cam_sun_dot;        // u_camera_radius_km * u_world_sun_dir.y
uniform vec2 u_cloud_absolute_km_offset; // cameraPosition.xz * 0.001
uniform vec2 u_r2_offset;             // R2 sub-pixel offset for frameCounter
uniform float u_water_skylight;       // clamp(eyeBrightness.y / 240, 0, 1)
uniform float u_water_column_depth;   // max((1 - skylight) * 15, 1)
uniform float u_water_light_path;     // 1 / max(refracted.y, 1e-3)
uniform vec3 u_water_ambient_transmittance;
uniform vec3 u_water_direct_transmittance;
uniform float u_water_wetness_gain;   // 1 - wetness * 0.6
uniform float u_eye_sky_access;       // SkyLightFromLm(eyeBrightness.y / 240)
uniform vec3 u_view_light_dir;        // gbufferModelView * u_world_light_dir
uniform vec3 u_view_sun_dir;          // gbufferModelView * u_world_sun_dir
uniform vec3 u_shadow_light_dir;      // shadowModelView * u_world_light_dir
uniform vec3 u_world_moon_dir;        // -u_world_sun_dir
uniform float u_light_disc_radius;    // sun or moon disc radius
uniform float u_star_night_fade;
uniform float u_wetness_weight;       // u_fast_wetness * u_rain_biome
uniform float u_rain_weight;          // rainStrength * u_rain_biome
uniform float u_rain_particle_opacity;// mix(1, 0.4, u_rain_biome)
uniform float u_plant_weather_gain;   // 1 + 0.65 * rainStrength
uniform vec2 u_plant_wind_time;       // frameTimeCounter * (3.2, 2.4)
uniform float u_caustic_time;         // fract(frameTimeCounter * 0.25)
uniform float u_caustic_source_time;  // u_caustic_time + 0.5/32
uniform vec2 u_caustic_advection;     // CAUSTIC_ADVECTION_MPS * frameTimeCounter
uniform vec2 u_sun_slope;             // sun.xz / max(sun.y, 0.02)
uniform float u_water_sun_height;     // smoothstep(0.02, 0.12, sun.y)
uniform float u_eye_height_m;         // absolute eye height (m)
uniform float u_airfog_day_weight;    // smoothstep(0, 0.25, sun.y)
uniform float u_airfog_twilight_weight; // smoothstep(-0.25, 0, sun.y)
uniform vec2 u_shadow_projection_xy;  // (SP[0].x, SP[1].y)
uniform float u_shadow_projection_z;  // SP[2].z
uniform float u_pixel_world_scale;    // max(P[1][1] * resY, 1)
uniform float u_pixel_world_scale_prev;// abs(Pprev[1][1]) * resY
uniform vec2 u_ao_half_res;           // ceil(res / 2)
uniform float u_star_cos_theta;       // star-map rotation cosine term
uniform float u_star_sin_theta;       // -sun.x
uniform ivec2 eyeBrightnessSmooth; // water sky access (block/sky brightness, /240)

// -- Time (Iris system built-ins) --
uniform float frameTimeCounter;
uniform float frameTime;           // fractional render time (s)
uniform int frameCounter;

// -- Previous-frame transforms (world space; supplied by Iris every frame,
//    shared by TAA, cloud temporal, GTAO) --
uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

// -- Depth buffers (Iris built-ins) --
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

// -- Scene / GBuffer textures --
uniform sampler2D gtexture;       // block/entity albedo atlas
uniform sampler2D normals;        // LabPBR normal atlas (1x1 fallback = none)
uniform sampler2D specular;       // LabPBR specular atlas (1x1 fallback = none)
uniform sampler2D colortex0;      // deferred1 direct RGB + emission, then scene color
uniform sampler2D colortex1;      // GBuffer albedo sRGB / materialID
uniform sampler2D colortex2;      // AO scratch / translucent surface data
uniform sampler2D colortex3;      // direct demodulated temporal RGB mean
uniform sampler2D colortex4;      // geometric normal/lightmap main; weather alt
uniform sampler2D colortex5;      // TAA history; the deferred1 direct fragment writes the caustic BRDF to the opposite side
#if defined(OPAQUE_SSR) && OPAQUE_SSR_FILTER > 0
uniform usampler2D colortex6;     // packed 64-bit SSR metadata; integer texelFetch only
#endif
uniform sampler2D colortex8;      // merged cloud/AO history (flip pair)
uniform sampler2D colortex9;      // half-res unblurred temporal GI irradiance
uniform sampler2D colortex10;     // half-res GI receiver geometry and age
uniform sampler2D colortex11;    // RGBA16 opaque normal/material packet
uniform sampler2D colortex12;     // cloud scratch, translucent and post workspace

// -- Shadow bindings and transforms --
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex0;       // raw depth (texelFetch / B-spline)
uniform sampler2DShadow shadowtex1; // hardware PCF comparison
uniform sampler2D shadowcolor0;    // RSM: RGB565 diffuse reflectance + oct8 shadow-view normal

// -- Custom textures (customTexture bindings, shaders.properties) --
uniform sampler2D utex_plant_wind;            // 64x64 RGBA16F: grass/canopy XZ drag response
uniform sampler2D utex_starmap;               // NASA star map (LogLuv32 RGBA8)
uniform sampler2D utex_starmap_lowres;        // box-filtered Milky Way glow map (LogLuv32 RGBA8)
uniform sampler2D utex_tslut;                 // atmosphere transmittance LUT (dip/no-dip pair per ATM_HORIZON_DIP)
uniform sampler2D utex_mslut;                 // atmosphere multiscatter LUT (dip/no-dip pair per ATM_HORIZON_DIP)
uniform sampler2D utex_mother_river;         // selected periodic 128x128 R8 wave height basis
uniform sampler2D utex_mother_river_slope;   // selected periodic 128x128 RG8 mother UV slopes
uniform sampler2D utex_cloud_distribution_tex; // cloud coverage atlas (R8, 1024x1024)
uniform sampler3D utex_cloud_voronoise_tex;   // experimental voronoise volume (R8, 32^3, periodic)
#if defined(CIRRUS)
uniform sampler2D utex_cirrus_body;  // base-only R8, 1024x1024, bilinear/repeat
uniform sampler2D utex_cirrus_noise; // base-only R8, 128x128, bilinear/repeat
#endif
uniform sampler3D utex_stbn_scalar;           // 128x128x64 STBN volume
uniform sampler3D utex_caustics;              // baked water caustics volume
uniform sampler3D utex_godray_caustics;       // 32^3 R8: linear caustic irradiance / 2
uniform sampler3D utex_rain_ripples;          // periodic linear XZ slopes (RG8, 256x256x64)

// -- Custom images (image bindings; sampler side only) --
#if defined(EPIPOLAR_ACTIVE)
uniform sampler2D usam_epipolar_endpoints; // slice endpoints, composite1 compute -> composite2
uniform sampler2D usam_epipolar_term; // RGBA16F: air E or underwater additive radiance in RGB, viewZ in A
#endif
uniform sampler2D usam_skylut;        // sky view LUT (128x128 RGBA16F)
uniform sampler2D usam_sky_radiance;  // cloud skybox LUT (256x256 RGBA16F)
// (no cloud-current image: the pass borrows colortex12 alt)
// (no AO image: ao.compute writes colortex2 alt)
#if defined(SSR_QUARTER_DEPTH_ACTIVE)
uniform sampler2D usam_ssr_depth;     // quarter-size squared linear depth, clip endpoint = sky
#endif

// -- Status (Iris built-in) --
uniform int isEyeInWater;

// -- Per-entity (Iris built-ins) --
uniform int entityId;
uniform vec4 entityColor;

// -- Custom uniforms (declared in shaders.properties) --
uniform vec3 u_world_light_dir;   // active light direction, world space
// Host contract: shaders.properties builds u_world_sun_dir normalized
// (1/sqrt(sum x^2) then an orthonormal model-view-inverse rotation), so
// consumers may treat it as unit without re-normalizing per pixel.
uniform vec3 u_world_sun_dir;     // sun direction only (LUT / SH reference frame)
uniform vec2 u_taa_offset;        // NDC jitter applied by opaque GBuffer vertices
uniform vec2 u_taa_offset_previous; // previous frame's NDC jitter for scene-grid history
uniform vec2 u_screen_res;        // viewport resolution in pixels
uniform float rainStrength;
uniform float wetness;
uniform float u_fast_wetness;
uniform float u_rain_biome; // smoothed rain eligibility of the camera biome, [0, 1]
uniform float u_snow_biome; // smoothed snow eligibility of the camera biome, [0, 1]
uniform float u_rain_ripple_time_uv; // CPU-corrected volume Z, including half-texel alignment
uniform float u_rain_ripple_gain; // CPU-fitted subframe slope gain, [1, 1.534]

#endif // LIB_CONTRACT_UNIFORMS_GLSL
