#ifndef LIB_ATMOSPHERE_CELESTIAL_GLSL
#define LIB_ATMOSPHERE_CELESTIAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/core.glsl"
#include "/lib/color/color.glsl"

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

#ifdef STARMAP
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

    vec4 sample_a = textureLod(utex_starmap, vec2(m0.x, clamp(tc0.y, 0.0, 1.0)), 0.0);
    vec4 sample_b = textureLod(utex_starmap, vec2(tc0.x, clamp(m0.y, 0.0, 1.0)), 0.0);
    vec4 sample_c = textureLod(utex_starmap, vec2(m0.x, clamp(m0.y, 0.0, 1.0)), 0.0);
    vec4 sample_d = textureLod(utex_starmap, vec2(tc3.x, clamp(m0.y, 0.0, 1.0)), 0.0);
    vec4 sample_e = textureLod(utex_starmap, vec2(m0.x, clamp(tc3.y, 0.0, 1.0)), 0.0);

    return (0.5 * (sample_a + sample_b) * w0.x + sample_a * s0.x + 0.5 * (sample_a + sample_b) * w3.x) * w0.y + (sample_b * w0.x + sample_c * s0.x + sample_d * w3.x) * s0.y
         + (0.5 * (sample_b + sample_e) * w0.x + sample_e * s0.x + 0.5 * (sample_d + sample_e) * w3.x) * w3.y;
}
#endif

#ifndef STARMAP
// LOW and MEDIUM declare no star map texture, so the stars come from two hash
// layers at unrelated cell scales. Two scales matter for the look: one
// jittered lattice reads as an even grid whatever the brightness law does,
// and the union of two unrelated lattices does not. A three-octave clumping
// field drives the keep probability of both layers from nothing to
// saturating, so the sky carries real voids and dense groups instead of an
// even sprinkle. The wide layer follows the map's own bright-end census (a
// power law of exponent ~1.37 over roughly 0.07 .. 0.9), disc size grows with
// brightness and carries its own jitter, and every draw is decimated by
// cos(latitude) so the pole crowding of the equirect grid does not read as
// clusters. The galactic band is not approximated at all.
//
// Cost shape: the clumping octaves and the uv mapping are paid by every night
// sky pixel, the per-star draws only by the fraction that passes a keep test
// (about 0.37 and 0.16 per layer), and each star needs four hashes because
// each avalanche output carries two usable draws.
const vec2 STAR_FIELD_CELLS = vec2(512.0, 256.0);
const vec2 STAR_FINE_CELLS = vec2(701.0, 351.0);  // unrelated to the wide grid
const float STAR_FIELD_RADIUS = 0.30;  // wide-layer disc radius, in cells
const float STAR_FIELD_JITTER = 0.34;  // position spread inside a cell
const float STAR_LAW_DIM = 0.071;      // wide-layer dimmest star, radiometric
const float STAR_LAW_EXP = 0.73;       // 1 / power-law exponent (1.37)
const float STAR_LAW_FLOOR = 0.03;     // flattens the tail: brightest near 0.9
const float STAR_FINE_RADIUS = 0.85;   // fine-layer radius, relative to the wide one
const float STAR_FINE_DIM = 0.028;     // fine-layer dimmest star
const float STAR_FINE_EXP = 0.70;
const float STAR_FINE_KEEP = 0.42;     // fine-layer keep scale
// Octave weights per layer: the same three octaves combine differently, so the
// layers share their structure without being copies of each other.
const vec3 STAR_CLUMP_WEIGHTS = vec3(0.42, 0.30, 0.15);
const vec3 STAR_FINE_CLUMP_WEIGHTS = vec3(0.34, 0.24, 0.26);

// One hash, two draws: the low and high halves of the avalanche are
// independent enough to feed separate values.
vec2 StarHash2(vec2 cell, uint salt) {
    uint key = uint(cell.x) * 0x9e3779b9u ^ uint(cell.y) * 0x85ebca6bu;
    uint h = LowBias32Hash(key ^ salt);
    return vec2(float(h & 0xffffu), float(h >> 16)) * (1.0 / 65536.0);
}

float StarHash(vec2 cell, uint salt) {
    uint key = uint(cell.x) * 0x9e3779b9u ^ uint(cell.y) * 0x85ebca6bu;
    return float(LowBias32Hash(key ^ salt) & 0xffffu) * (1.0 / 65536.0);
}

// The three clumping octaves, evaluated once per pixel and combined per layer.
// The range is wide on purpose: the low end empties a region out completely,
// the high end saturates it.
vec3 StarClumpOctaves(vec3 rd) {
    return vec3(
        sin(1.7 * rd.x + 1.7) * sin(2.3 * rd.y - 0.6) * sin(1.9 * rd.z + 2.4),
        sin(4.1 * rd.x - 1.1) * sin(5.3 * rd.y + 0.3) * sin(4.7 * rd.z + 0.9),
        sin(8.9 * rd.z + 0.4) * sin(9.7 * rd.x - 2.1) * sin(9.1 * rd.y + 1.3));
}

float StarClumping(vec3 octaves, vec3 weights) {
    return clamp(0.58 + dot(octaves, weights), 0.0, 1.6);
}

// One jittered lattice layer. clump arrives scaled by the layer's density, so
// the two layers can share the field without sharing its structure.
vec3 StarLayer(vec2 uv, float latitude_cos, float clump, vec2 cells, uint salt,
        float dim, float exponent, float radius_scale) {
    vec2 cell = floor(uv * cells);
    // RA wraps at 0/360, so the first and last column share their draw.
    vec2 seed = vec2(mod(cell.x, cells.x), cell.y);
    if (StarHash(seed, salt) > clamp(latitude_cos * clump, 0.0, 1.0)) {
        return vec3(0.0);
    }

    vec2 jitter = StarHash2(seed, salt + 0x1111u);
    vec2 shape = StarHash2(seed, salt + 0x2222u);   // size jitter, magnitude
    vec2 tint_profile = StarHash2(seed, salt + 0x3333u);
    float brightness = dim * pow(max(shape.y, STAR_LAW_FLOOR), -exponent);

    vec2 centre = (cell + 0.5 + (jitter - 0.5) * (2.0 * STAR_FIELD_JITTER))
        / cells;
    vec2 delta = (uv - centre) * cells * vec2(latitude_cos, 1.0);
    float radius = radius_scale * STAR_FIELD_RADIUS
        * (0.55 + 0.85 * clamp(brightness * 2.0, 0.0, 1.0))
        * (0.75 + 0.5 * shape.x);
    float core = clamp(1.0 - length(delta) / radius, 0.0, 1.0);
    // Two fixed integer powers blended by a per-star draw: a generic pow would
    // cost an SFU slot per covered pixel for the same visual spread.
    float disc = mix(Pow4(core), Pow4(Pow4(core)), tint_profile.y);

    vec3 colour = mix(vec3(0.72, 0.85, 1.0), vec3(1.0, 0.82, 0.62),
        tint_profile.x);
    return colour * (brightness * disc);
}

vec3 ProceduralStarField(vec3 rd) {
    float a = atan(rd.z, rd.x);
    float u = mix(a, 0.0, float(isnan(a))) * (0.5 / PI) + 0.5;
    float v = 0.5 - asin(clamp(rd.y, -1.0, 1.0)) * (1.0 / PI);
    v = clamp(v, 0.0, 1.0);
    float latitude_cos = sqrt(max(1.0 - rd.y * rd.y, 1.0e-6));

    vec2 uv = vec2(u, v);
    vec3 octaves = StarClumpOctaves(rd);
    vec3 stars = StarLayer(uv, latitude_cos,
        StarClumping(octaves, STAR_CLUMP_WEIGHTS),
        STAR_FIELD_CELLS, 0x1234u, STAR_LAW_DIM, STAR_LAW_EXP, 1.0);
    stars += StarLayer(uv, latitude_cos,
        StarClumping(octaves, STAR_FINE_CLUMP_WEIGHTS) * STAR_FINE_KEEP,
        STAR_FINE_CELLS, 0x9abcu, STAR_FINE_DIM, STAR_FINE_EXP,
        STAR_FINE_RADIUS);
    return stars;
}
#endif

// Star map rigidly attached to the celestial sphere: rotation about world Y
// recovered from sunDir (the vanilla sun/moon path is in a vertical plane,
// so sunDir.x/y give the path angle without an atan2 branch cut). Gated by
// view-ray transmittance; the cloud compositor multiplies the contribution
// by real cloud transmittance.
vec3 RenderStarMap(vec3 view_dir, vec4 view_transmittance) {
    vec3 sun_dir = normalize(u_world_sun_dir);

    // Day/night fade based on sun elevation (smoothstep transition).
    float night_fade = 1.0 - smoothstep(STAR_FADE_SUNRISE, STAR_FADE_SUNSET, sun_dir.y);
    if (night_fade <= 0.0) return vec3(0.0);

    vec3 camera_pos = vec3(0.0, ATM_PLANET_R + u_cam_altitude, 0.0);
    float r = length(camera_pos);
    float r2 = r * r;
    if (PlanetHorizonOccluded(camera_pos, r2, view_dir, ATM_PLANET_R2)) return vec3(0.0);

    // Rotation about world Y keeping the map fixed on the sphere.
    float c = clamp(sun_dir.x, -1.0, 1.0);
    float s = clamp(sun_dir.y, -1.0, 1.0);
    vec3 rd = vec3(c * view_dir.x - s * view_dir.z, view_dir.y, s * view_dir.x + c * view_dir.z);

#ifdef STARMAP
    // Equirectangular sampling, Catmull-Rom bicubic; horizontal wrap at
    // RA 0/360, v clamped (poles never blend).
    float a = atan(rd.z, rd.x);
    float u = mix(a, 0.0, float(isnan(a))) * (0.5 / PI) + 0.5;
    float v = 0.5 - asin(clamp(rd.y, -1.0, 1.0)) * (1.0 / PI);
    v = clamp(v, 0.0, 1.0);
    // LogLuv32 HDR: bicubic in the encoded space, decode restores linear
    // radiance.
    vec3 star_color = LogLuv32ToLinear(SampleStarMapFastBicubic(vec2(u, v)));
#else
    vec3 star_color = ProceduralStarField(rd);
#endif

    // View-ray transmittance: dims and reddens stars toward the horizon.
    vec3 transmittance = TransmittanceToLinearSRGB(view_transmittance, vec4(1.0));

    return star_color * transmittance * night_fade * STAR_MAP_INTENSITY;
}

vec3 RenderCelestialDiscs(vec3 view_dir, vec3 sky_color, vec4 view_transmittance) {
    vec3 camera_pos = vec3(0.0, ATM_PLANET_R + u_cam_altitude, 0.0);
    float r = length(camera_pos);
    float r2 = r * r;

    // Per-ray horizon clip: rays below the spherical horizon hit the planet
    // (ground LUT region) and must not receive the discs. The clip must stay
    // per-ray: the disc/glow is still partly above the horizon while the
    // disc centre is below it, so a centre-ray test would over-cull and
    // pop the disc out at the horizon.
    if (PlanetHorizonOccluded(camera_pos, r2, view_dir, ATM_PLANET_R2)) return sky_color;

    vec3 sun_dir = normalize(u_world_sun_dir);
    vec3 moon_dir = -sun_dir;

    vec3 contribution = vec3(0.0);

    float cos_sun = dot(view_dir, sun_dir);
    if (cos_sun > cos(SUN_GLOW_RADIUS)) {
        vec3 transmittance = TransmittanceToLinearRec2020(view_transmittance, ATM_SOLAR);
        vec3 sun_radiance = SpectralToLinearRec2020(ATM_SOLAR)
            / (PI * SUN_DISC_RADIUS * SUN_DISC_RADIUS) * ATM_EXPOSURE * BRIGHTNESS_FACT;
        contribution += sun_radiance * transmittance
            * CelestialAngularMask(cos_sun, SUN_DISC_RADIUS, SUN_GLOW_RADIUS);
    }

    float cos_moon = dot(view_dir, moon_dir);
    if (cos_moon > cos(MOON_GLOW_RADIUS)) {
        vec3 transmittance = TransmittanceToLinearRec2020(view_transmittance, ATM_MOON_IRR);
        vec3 moon_radiance = SpectralToLinearRec2020(ATM_MOON_IRR)
            / (PI * MOON_DISC_RADIUS * MOON_DISC_RADIUS) * ATM_EXPOSURE * BRIGHTNESS_FACT;
        contribution += moon_radiance * transmittance
            * CelestialAngularMask(cos_moon, MOON_DISC_RADIUS, MOON_GLOW_RADIUS);
    }

    return sky_color + Rec2020ToSRGB(contribution);
}

#endif
