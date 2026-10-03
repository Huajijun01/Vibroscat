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

// -- Camera / resolution (Iris built-ins + u_* from properties) --
uniform vec3 cameraPosition;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform vec2 u_view_pixel_size;    // 1 / (viewWidth, viewHeight)
uniform float u_cam_altitude;      // camera altitude in km (cloud shell / sky LUT)
uniform float centerDepthSmooth;   // DOF focus distance
uniform ivec2 eyeBrightnessSmooth; // eye adaptation (block/sky brightness, /240)

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
uniform sampler2D colortex0;      // scene color (post chain input)
uniform sampler2D colortex1;      // GBuffer albedo sRGB / materialID
uniform sampler2D colortex2;      // opaque GBuffer, then translucent surface data
uniform sampler2D colortex3;      // opaque reflection incident radiance transient
uniform sampler2D colortex4;      // opaque geometric world normal (RG) + lightmap (BA)
uniform sampler2D colortex5;      // TAA / composite history
uniform sampler2D colortex8;      // merged cloud/AO history (flip pair)
uniform sampler2D colortex9;      // deferred3 GI irradiance including uncovered SH (raw)
uniform sampler2D colortex11;    // weather
uniform sampler2D colortex12;     // sequential post workspace

// -- Shadow bindings and transforms --
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex0;       // raw depth (texelFetch / B-spline)
uniform sampler2DShadow shadowtex1; // hardware PCF comparison
uniform sampler2D shadowcolor0;    // RSM: RGB565 diffuse reflectance + oct8 shadow-view normal

// -- Custom textures (customTexture bindings, shaders.properties) --
uniform sampler2D utex_starmap;               // NASA star map (LogLuv32 RGBA8)
uniform sampler2D utex_tslut;                 // atmosphere transmittance LUT
uniform sampler2D utex_mslut;                 // atmosphere multiscatter LUT
uniform sampler2D utex_mother_river;         // periodic 128x128 R8 river height (32 m)
uniform sampler2D utex_cloud_distribution_tex; // cloud coverage atlas (R8, 1024x1024)
uniform sampler3D utex_cloud_voronoise_tex;   // experimental voronoise volume (R8, 32^3, periodic)
uniform sampler3D utex_stbn_scalar;           // 128x128x64 STBN volume
uniform sampler3D utex_caustics;              // baked water caustics volume

// -- Custom images (image bindings; sampler side only) --
uniform sampler2D usam_skylut;        // sky view LUT (128x128 RGBA16F)
uniform sampler2D usam_sky_radiance;  // cloud skybox LUT (256x256 RGBA16F)
uniform sampler2D usam_clouds_current; // low-res cloud current frame
uniform sampler2D usam_ao;            // half-res AO (full evaluation every frame)
#ifdef SSR_QUARTER_DEPTH_ACTIVE
uniform sampler2D usam_ssr_depth;     // quarter-size squared linear depth, clip endpoint = sky
#endif
#ifdef EPIPOLAR_VOLUMETRICS
uniform sampler2D usam_epipolar_endpoints; // epipolar slice endpoints
uniform sampler2D usam_epipolar_term;      // epipolar E/column-key terms (shared: water in composite1, air in composite2)
#endif

// -- Status (Iris built-in) --
uniform int isEyeInWater;

// -- Per-entity (Iris built-ins) --
uniform int entityId;
uniform vec4 entityColor;

// -- Custom uniforms (declared in shaders.properties) --
uniform vec3 u_world_light_dir;   // active light direction, world space
uniform vec3 u_world_sun_dir;     // sun direction only (LUT / SH reference frame)
uniform vec2 u_taa_offset;        // NDC jitter applied by opaque GBuffer vertices
uniform vec2 u_taa_offset_previous; // previous frame's NDC jitter for RSM history
uniform vec2 u_screen_res;        // viewport resolution in pixels
uniform float rainStrength;
uniform float wetness;
uniform vec3 u_water_absorption;
uniform vec3 u_water_scattering;

#endif // LIB_CONTRACT_UNIFORMS_GLSL
