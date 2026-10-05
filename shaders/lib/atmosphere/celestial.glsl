#ifndef LIB_ATMOSPHERE_CELESTIAL_GLSL
#define LIB_ATMOSPHERE_CELESTIAL_GLSL

#include "/lib/color/spaces.glsl"
#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/media.glsl"
#include "/lib/atmosphere/spectral.glsl"

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
// LogLuv32 -> linear sRGB, per [ERI07] Ericson, Christer. "Converting RGB to
// LogLuv in a fragment shader". 2007. R = u', G = v', B = int(Le),
// A = frac(Le), Le = 2*log2(Y) + 127. Decodes the star map's RGBA8 HDR
// encoding.
const mat3 LOGLUV32_INVERSE_M = mat3(6.0014, -2.7008, -1.7996, -1.3320, 3.1029, -5.7721, 0.3008, -1.0882, 5.6268);

vec3 LogLuv32ToLinear(vec4 v_log_luv) {
    if (all(lessThanEqual(v_log_luv, vec4(0.0)))) return vec3(0.0);
    float le = v_log_luv.z * 255.0 + v_log_luv.w;
    vec3 xyz_prime;
    xyz_prime.y = exp2((le - 127.0) * 0.5);
    xyz_prime.z = xyz_prime.y / max(v_log_luv.y, 1.0e-6);
    xyz_prime.x = v_log_luv.x * xyz_prime.z;
    return max(LOGLUV32_INVERSE_M * xyz_prime, vec3(0.0));
}

const float STAR_FADE_SUNRISE  = -0.05;   // below this sun elevation: full stars
const float STAR_FADE_SUNSET   = 0.15;    // above this sun elevation: no stars

float CelestialAngularMask(float cos_view, float disc_radius, float glow_radius) {
    return smoothstep(cos(glow_radius), cos(disc_radius), cos_view);
}

// Fast Catmull-Rom (5-tap, "Bicubic filtering in fewer taps"): the w1/w2
// pair is one bilinear sample at their midpoint (5 fetches instead of 16).
// Wraps horizontally at RA 0/360; v clamped so the filter never bleeds
// across the poles.
vec4 SampleStarMapFastBicubic(vec2 uv) {
    // Baked map is 4096x2048 (customTexture.utex_starmap).
    const vec2 resolution = vec2(4096.0, 2048.0);
    vec2 rcp_resolution = 1.0 / resolution;

    vec2 texel = uv * resolution;
    vec2 cell_fract = fract(texel - 0.5);
    vec2 base = (floor(texel - 0.5) + 0.5) * rcp_resolution;

    vec2 t = cell_fract;
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

    // Weight-sum factorization: the Catmull-Rom weights partition unity
    // (w0 + w1 + w2 + w3 == 1, s0 == w1 + w2), so the outer-tap coefficients
    // collapse to 0.5*(1 -+ s0) forms and the row mix needs roughly a third
    // fewer multiplies than the expanded expression.
    float half_outer = 0.5 * w0.x + 0.5 * w3.x;          // 0.5*(w0.x + w3.x)
    vec4 row0 = (sample_a + sample_b) * half_outer + sample_a * s0.x;
    vec4 row1 = sample_b * w0.x + sample_c * s0.x + sample_d * w3.x;
    vec4 row2 = sample_b * (0.5 * w0.x) + sample_e * (0.5 * w0.x + s0.x)
        + sample_d * (0.5 * w3.x);
    return row0 * w0.y + row1 * s0.y + row2 * w3.y;
}

// Equirectangular star-map UV from a world direction. The NaN guard absorbs
// the atan branch cut at the antimeridian; v is clamped (poles never blend)
// and u wraps through the sampler's horizontal repeat.
vec2 StarMapEquirectUV(vec3 rd) {
    float a = atan(rd.z, rd.x);
    float u = mix(a, 0.0, float(isnan(a))) * INV_TWO_PI + 0.5;
    float v = 0.5 - asin(clamp(rd.y, -1.0, 1.0)) * (1.0 / PI);
    return vec2(u, clamp(v, 0.0, 1.0));
}

// Per-ray celestial context shared by the star map and the disc renderer:
// both consume the same sun direction, camera radius, and horizon clip, so a
// caller that renders both evaluates them once. The individual expressions
// match the previous per-renderer computations exactly.
struct CelestialContext {
    vec3 sun_dir;
    vec3 camera_pos;
    float camera_r2;
    bool horizon_occluded;
};

CelestialContext CelestialContextFor(vec3 view_dir) {
    CelestialContext context;
    context.sun_dir = u_world_sun_dir;
    context.camera_pos = AtmosphereCameraPosition();
    // Same +y pin as AtmosphereCameraPosition: the radius is R + altitude.
    float camera_r = ATM_PLANET_R + u_cam_altitude;
    context.camera_r2 = camera_r * camera_r;
    context.horizon_occluded = PlanetHorizonOccluded(context.camera_pos,
        context.camera_r2, view_dir, ATM_PLANET_R2);
    return context;
}

// Star map rigidly attached to the celestial sphere: rotation about world Y
// recovered from sunDir (the vanilla sun/moon path is in a vertical plane,
// so sunDir.x/y give the path angle without an atan2 branch cut). Gated by
// view-ray transmittance; the cloud compositor multiplies the contribution
// by real cloud transmittance.
vec3 RenderStarMap(vec3 view_dir, vec4 view_transmittance, CelestialContext context) {
    // Day/night fade based on sun elevation (smoothstep transition).
    float night_fade = 1.0 - smoothstep(STAR_FADE_SUNRISE, STAR_FADE_SUNSET, context.sun_dir.y);
    if (night_fade <= 0.0) return vec3(0.0);

    if (context.horizon_occluded) return vec3(0.0);

    // Rotation about world Y keeping the map fixed on the sphere.
    float c = clamp(context.sun_dir.x, -1.0, 1.0);
    float s = clamp(context.sun_dir.y, -1.0, 1.0);
    vec3 rd = vec3(c * view_dir.x - s * view_dir.z, view_dir.y, s * view_dir.x + c * view_dir.z);

    // Equirectangular sampling, Catmull-Rom bicubic; horizontal wrap at
    // RA 0/360, v clamped (poles never blend).
    // LogLuv32 HDR: bicubic in the encoded space, decode restores linear
    // radiance.
    vec3 star_color = LogLuv32ToLinear(SampleStarMapFastBicubic(StarMapEquirectUV(rd)));

    // Artistic grade (technique after Alpha Piscium v1.9.1, GPL-3.0; our
    // own expression): the contrast exponent lifts faint map structure so
    // the Milky Way and dim stars read better, then a luminance-keyed
    // exponential gain (unity at black) magnifies only the brightest stars
    // for magnitude-like variation. The decoded map's luma stays below
    // ~0.5, so the default gain caps near 4x. Runs before the physical
    // transmittance and night fades so the grade describes the map itself.
    star_color = pow(star_color, vec3(STAR_MAP_CONTRAST));
    star_color *= exp2(Luminance(star_color) * STAR_MAP_BRIGHT_BOOST);

    // View-ray transmittance: dims and reddens stars toward the horizon.
    vec3 transmittance = TransmittanceToLinearSRGB(view_transmittance, vec4(1.0));

    return star_color * transmittance * night_fade * STAR_MAP_INTENSITY;
}

vec3 RenderCelestialDiscs(vec3 view_dir, vec3 sky_color, vec4 view_transmittance,
    CelestialContext context) {
    // Per-ray horizon clip: rays below the spherical horizon hit the planet
    // (ground LUT region) and must not receive the discs. The clip must stay
    // per-ray: the disc/glow is still partly above the horizon while the
    // disc center is below it, so a center-ray test would over-cull and
    // pop the disc out at the horizon.
    if (context.horizon_occluded) return sky_color;

    vec3 sun_dir = context.sun_dir;
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

    // moon_dir above is the exact IEEE negation of sun_dir, and negation
    // distributes exactly through the dot product, so this is bit-identical
    // to dot(view_dir, moon_dir).
    float cos_moon = -cos_sun;
    if (cos_moon > cos(MOON_GLOW_RADIUS)) {
        vec3 transmittance = TransmittanceToLinearRec2020(view_transmittance, ATM_MOON_IRR);
        vec3 moon_radiance = SpectralToLinearRec2020(ATM_MOON_IRR)
            / (PI * MOON_DISC_RADIUS * MOON_DISC_RADIUS) * ATM_EXPOSURE * BRIGHTNESS_FACT;
        contribution += moon_radiance * transmittance
            * CelestialAngularMask(cos_moon, MOON_DISC_RADIUS, MOON_GLOW_RADIUS);
    }

    return sky_color + Rec2020ToSRGB(contribution);
}

#endif // LIB_ATMOSPHERE_CELESTIAL_GLSL
