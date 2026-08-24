#ifndef LIB_ATMOSPHERE_CELESTIAL_GLSL
#define LIB_ATMOSPHERE_CELESTIAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/color/color.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/core.glsl"

// Sun/moon discs in linear HDR: TOA irradiance / disc solid angle,
// attenuated by the view-ray transmittance (dims + reddens near the
// horizon). Runs BEFORE the cloud compositor (clouds occlude the discs).
const float BRIGHTNESS_FACT = 0.03;

// Night star map: NASA Deep Star Maps 2020 4K (SVS #4851), Public Domain.
// Image credit: NASA's Scientific Visualization Studio / ESA-ESO-Sky-Survey.
// Baked from the linear EXR into a LogLuv32 RGBA8 PNG so the HDR range
// survives the 8-bit texture. Plate carree equirectangular, centered on RA 0h.

// STAR_MAP_INTENSITY (linear gain after LogLuv32 decode) is a user
// option declared in contract/settings.glsl.
const float STAR_FADE_SUNRISE  = -0.05;   // below this sun elevation: full stars
const float STAR_FADE_SUNSET   = 0.15;    // above this sun elevation: no stars

float CelestialAngularMask(float cos_view, float disc_radius, float glow_radius) {
    return smoothstep(cos(glow_radius), cos(disc_radius), cos_view);
}

bool CelestialBlockedByEarth(vec3 origin, float origin_r2, vec3 dir) {
    float b = 2.0 * dot(origin, dir);
    float c = origin_r2 - ATM_PLANET_R2;
    float discriminant = b * b - 4.0 * c;
    if (discriminant <= 0.0) return false;
    float ground_near = 0.5 * (-b - sqrt(discriminant));
    return ground_near > 1.0e-5;
}

// Fast Catmull-Rom (5-tap, "Bicubic filtering in fewer taps"): the w1/w2
// pair is one bilinear sample at their midpoint (5 fetches instead of 16).
// Wraps horizontally at RA 0/360; v clamped so the filter never bleeds
// across the poles.
vec4 SampleStarMapFastBicubic(vec2 uv) {
    vec2 resolution = vec2(textureSize(utex_starmap, 0));
    vec2 rcp_resolution = 1.0 / resolution;

    vec2 st = uv * resolution;
    vec2 frac = fract(st - 0.5);
    vec2 base = (floor(st - 0.5) + 0.5) * rcp_resolution;

    vec2 t = frac;
    vec2 t2 = t * t;
    vec2 t3 = t2 * t;
    const float s = 0.5;
    vec2 w0 = -s * t3 + 2.0 * s * t2 - s * t;
    vec2 w1 = (2.0 - s) * t3 + (s - 3.0) * t2 + 1.0;
    vec2 w2 = (s - 2.0) * t3 + (3.0 - 2.0 * s) * t2 + s * t;
    vec2 w3 = s * t3 - s * t2;

    vec2 s0 = w1 + w2;
    vec2 f0 = w2 / s0;
    vec2 m0 = base + f0 * rcp_resolution;
    vec2 tc0 = base - rcp_resolution;
    vec2 tc3 = base + 2.0 * rcp_resolution;

    vec4 A = textureLod(utex_starmap, vec2(m0.x, clamp(tc0.y, 0.0, 1.0)), 0.0);
    vec4 B = textureLod(utex_starmap, vec2(tc0.x, clamp(m0.y, 0.0, 1.0)), 0.0);
    vec4 C = textureLod(utex_starmap, vec2(m0.x, clamp(m0.y, 0.0, 1.0)), 0.0);
    vec4 D = textureLod(utex_starmap, vec2(tc3.x, clamp(m0.y, 0.0, 1.0)), 0.0);
    vec4 E = textureLod(utex_starmap, vec2(m0.x, clamp(tc3.y, 0.0, 1.0)), 0.0);

    return (0.5 * (A + B) * w0.x + A * s0.x + 0.5 * (A + B) * w3.x) * w0.y + (B * w0.x + C * s0.x + D * w3.x) * s0.y
         + (0.5 * (B + E) * w0.x + E * s0.x + 0.5 * (D + E) * w3.x) * w3.y;
}

// Star map rigidly attached to the celestial sphere: rotation about world Y
// recovered from sunDir (the vanilla sun/moon path is in a vertical plane,
// so sunDir.x/y give the path angle without an atan2 branch cut). Gated by
// view-ray transmittance; the cloud compositor multiplies the contribution
// by real cloud transmittance.
vec3 RenderStarMap(vec3 view_dir) {
    vec3 sun_dir = normalize(u_world_sun_dir);

    // Day/night fade based on sun elevation (smoothstep transition).
    float night_fade = 1.0 - smoothstep(STAR_FADE_SUNRISE, STAR_FADE_SUNSET, sun_dir.y);
    if (night_fade <= 0.0) return vec3(0.0);

    vec3 camera_pos = vec3(0.0, ATM_PLANET_R + u_cam_altitude, 0.0);
    float r = length(camera_pos);
    float r2 = r * r;
    if (CelestialBlockedByEarth(camera_pos, r2, view_dir)) return vec3(0.0);

    // Rotation about world Y keeping the map fixed on the sphere.
    float c = clamp(sun_dir.x, -1.0, 1.0);
    float s = clamp(sun_dir.y, -1.0, 1.0);
    vec3 rd = vec3(c * view_dir.x - s * view_dir.z, view_dir.y, s * view_dir.x + c * view_dir.z);

    // Equirectangular sampling, Catmull-Rom bicubic; horizontal wrap at
    // RA 0/360, v clamped (poles never blend).
    float a = atan(rd.z, rd.x);
    float u = mix(a, 0.0, float(isnan(a))) * (0.5 / PI) + 0.5;
    float v = 0.5 - asin(clamp(rd.y, -1.0, 1.0)) * (1.0 / PI);
    v = clamp(v, 0.0, 1.0);
    // LogLuv32 HDR: bicubic in the encoded space, decode restores linear
    // radiance.
    vec3 star_color = LogLuv32ToLinear(SampleStarMapFastBicubic(vec2(u, v)));

    // View-ray transmittance: dims and reddens stars toward the horizon.
    float mu = dot(camera_pos, view_dir) / r;
    vec3 transmittance = TransmittanceToLinearSRGB(SampleTransmittance(TRANSMITTANCE_LUT, r, r2, mu), vec4(1.0));

    return star_color * transmittance * night_fade * STAR_MAP_INTENSITY;
}

vec3 RenderCelestialDiscs(vec3 view_dir, vec3 sky_color) {
    vec3 camera_pos = vec3(0.0, ATM_PLANET_R + u_cam_altitude, 0.0);
    float r = length(camera_pos);
    float r2 = r * r;

    // Per-ray horizon clip: rays below the spherical horizon hit the planet
    // (ground LUT region) and must not receive the discs (the centre-ray
    // test alone would leak the lower disc/glow below the horizon).
    if (CelestialBlockedByEarth(camera_pos, r2, view_dir)) return sky_color;

    vec3 sun_dir = normalize(u_world_sun_dir);
    vec3 moon_dir = -sun_dir;

    vec3 contribution = vec3(0.0);

    float cos_sun = dot(view_dir, sun_dir);
    if (cos_sun > cos(SUN_GLOW_RADIUS)
            && !CelestialBlockedByEarth(camera_pos, r2, sun_dir)) {
        float mu = dot(camera_pos, sun_dir) / r;
        vec3 transmittance = TransmittanceToLinearRec2020(SampleTransmittance(TRANSMITTANCE_LUT, r, r2, mu), ATM_SOLAR);
        vec3 sun_radiance = SpectralToLinearRec2020(ATM_SOLAR)
            / (PI * SUN_DISC_RADIUS * SUN_DISC_RADIUS) * ATM_EXPOSURE * BRIGHTNESS_FACT;
        contribution += sun_radiance * transmittance
            * CelestialAngularMask(cos_sun, SUN_DISC_RADIUS, SUN_GLOW_RADIUS);
    }

    float cos_moon = dot(view_dir, moon_dir);
    if (cos_moon > cos(MOON_GLOW_RADIUS)
            && !CelestialBlockedByEarth(camera_pos, r2, moon_dir)) {
        float mu = dot(camera_pos, moon_dir) / r;
        vec3 transmittance = TransmittanceToLinearRec2020(SampleTransmittance(TRANSMITTANCE_LUT, r, r2, mu), ATM_MOON_IRR);
        vec3 moon_radiance = SpectralToLinearRec2020(ATM_MOON_IRR)
            / (PI * MOON_DISC_RADIUS * MOON_DISC_RADIUS) * ATM_EXPOSURE * BRIGHTNESS_FACT;
        contribution += moon_radiance * transmittance
            * CelestialAngularMask(cos_moon, MOON_DISC_RADIUS, MOON_GLOW_RADIUS);
    }

    return sky_color + Rec2020ToSRGB(contribution);
}

#endif