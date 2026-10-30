#ifndef LIB_ATMOSPHERE_CELESTIAL_GLSL
#define LIB_ATMOSPHERE_CELESTIAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/illumination.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/color/spaces.glsl"

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

// Fixed celestial-frame -> map-basis change. Beyond the base labeling (north
// at v=0, RA increasing toward -u), it carries the art-directed placement:
// the galactic-center bulge (the texture's brightest region, measured from
// the bake at RA 17.85h, dec -32.9 deg) is centered on the moon's rigid
// celestial position - the moon rides the brightest knot every night. The
// map pole ends 32.9 deg off the celestial axis (the closest any rigid
// rotation can hold it while pinning the bulge to the moon).
const mat3 STAR_MAP_ALIGNMENT = mat3(
     0.021827, -0.839993, -0.542157,
     0.033791,  0.542596, -0.839314,
     0.999191,  0.000000,  0.040228);

float CelestialAngularMask(float cos_view, float disc_radius, float glow_radius) {
    return smoothstep(cos(glow_radius), cos(disc_radius), cos_view);
}

// Fast Catmull-Rom (5-tap, "Bicubic filtering in fewer taps"): the w1/w2
// pair is one bilinear sample at their midpoint. Wraps horizontally at
// RA 0/360; v clamped so the filter never bleeds across the poles.
vec4 SampleStarMapFastBicubic(vec2 uv) {
    // Baked map is 4096x2048 (customTexture.utex_starmap).
    const vec2 resolution = vec2(4096.0, 2048.0);
    vec2 rcp_resolution = 1.0 / resolution;

    vec2 texel = uv * resolution;
    vec2 cell_fract = fract(texel - 0.5);
    vec2 base = (floor(texel - 0.5) + 0.5) * rcp_resolution;

    vec2 t2 = cell_fract * cell_fract;
    vec2 t3 = t2 * cell_fract;
    const float s = 0.5;
    vec2 w0 = -s * t3 + 2.0 * s * t2 - s * cell_fract;
    vec2 w1 = (2.0 - s) * t3 + (s - 3.0) * t2 + 1.0;
    vec2 w2 = (s - 2.0) * t3 + (3.0 - 2.0 * s) * t2 + s * cell_fract;
    vec2 w3 = s * t3 - s * t2;

    vec2 s0 = w1 + w2;
    vec2 f0 = w2 / s0;
    vec2 m0 = base + f0 * rcp_resolution;
    vec2 tc0 = base - rcp_resolution;
    vec2 tc3 = base + 2.0 * rcp_resolution;

    vec4 sample_a = textureLod(utex_starmap, vec2(m0.x, saturate(tc0.y)), 0.0);
    vec4 sample_b = textureLod(utex_starmap, vec2(tc0.x, saturate(m0.y)), 0.0);
    vec4 sample_c = textureLod(utex_starmap, vec2(m0.x, saturate(m0.y)), 0.0);
    vec4 sample_d = textureLod(utex_starmap, vec2(tc3.x, saturate(m0.y)), 0.0);
    vec4 sample_e = textureLod(utex_starmap, vec2(m0.x, saturate(tc3.y)), 0.0);

    // Weight-sum factorization: the Catmull-Rom weights partition unity
    // (w0 + w1 + w2 + w3 == 1, s0 == w1 + w2), so the outer-tap coefficients
    // collapse to 0.5*(1 -+ s0) forms and the row mix needs roughly a third
    // fewer multiplies than the expanded expression.
    float half_outer = 0.5 * w0.x + 0.5 * w3.x;
    vec4 row0 = (sample_a + sample_b) * half_outer + sample_a * s0.x;
    vec4 row1 = sample_b * w0.x + sample_c * s0.x + sample_d * w3.x;
    vec4 row2 = sample_b * (0.5 * w0.x) + sample_e * (0.5 * w0.x + s0.x)
        + sample_d * (0.5 * w3.x);
    return row0 * w0.y + row1 * s0.y + row2 * w3.y;
}

// Cubic B-spline in 4 taps: each axis's four kernel weights pair into two
// hardware bilinear positions (Sigg & Hadwiger, "Fast Third-Order Texture
// Filtering"), so the 2D filter costs 4 bilinear fetches and stays C1
// across texel boundaries where bilinear shows its C0 creases. The kernel
// is non-negative, so the pre-blurred map never rings the way a
// Catmull-Rom kernel would. Wraps horizontally at RA 0/360 through the
// sampler's repeat; v clamps so the filter never bleeds across the poles.
vec4 SampleStarMapLowresBspline(vec2 uv) {
    // Baked map is 256x128 (customTexture.utex_starmap_lowres).
    const vec2 resolution = vec2(256.0, 128.0);
    vec2 rcp_resolution = 1.0 / resolution;

    vec2 texel = uv * resolution - 0.5;
    vec2 base = floor(texel);
    vec2 f = texel - base;

    // Cubic B-spline kernel at texels base-1..base+2: B(x) = (4 - 6|x|^2 +
    // 3|x|^3)/6 for |x| <= 1, (2 - |x|)^3/6 for 1 < |x| < 2.
    vec2 f2 = f * f;
    vec2 f3 = f2 * f;
    vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) * (1.0 / 6.0);
    vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) * (1.0 / 6.0);
    vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) * (1.0 / 6.0);
    vec2 w3 = f3 * (1.0 / 6.0);

    // Fold (w0, w1) and (w2, w3) into bilinear taps: hardware bilinear at
    // the folded fraction reproduces each pair's exact weights, so the 4
    // fetches equal the full 16-tap cubic filter.
    vec2 weight_a = w0 + w1;
    vec2 weight_b = w2 + w3;
    vec2 offset_a = w1 / weight_a;
    vec2 offset_b = w3 / weight_b;

    vec2 coord_a = base - 1.0 + offset_a + 0.5;
    vec2 coord_b = base + 1.0 + offset_b + 0.5;
    vec2 uv_a = vec2(coord_a.x * rcp_resolution.x, saturate(coord_a.y * rcp_resolution.y));
    vec2 uv_b = vec2(coord_b.x * rcp_resolution.x, saturate(coord_b.y * rcp_resolution.y));

    vec4 sample_aa = textureLod(utex_starmap_lowres, uv_a, 0.0);
    vec4 sample_ba = textureLod(utex_starmap_lowres, vec2(uv_b.x, uv_a.y), 0.0);
    vec4 sample_ab = textureLod(utex_starmap_lowres, vec2(uv_a.x, uv_b.y), 0.0);
    vec4 sample_bb = textureLod(utex_starmap_lowres, uv_b, 0.0);

    return sample_aa * (weight_a.x * weight_a.y) + sample_ba * (weight_b.x * weight_a.y)
        + sample_ab * (weight_a.x * weight_b.y) + sample_bb * (weight_b.x * weight_b.y);
}

// Equirectangular star-map UV from a world direction. The NaN guard absorbs
// the atan branch cut at the antimeridian; v is clamped (poles never blend)
// and u wraps through the sampler's horizontal repeat.
vec2 StarMapEquirectUV(vec3 rd) {
    float a = atan(rd.z, rd.x);
    float u = mix(a, 0.0, float(isnan(a))) * INV_TWO_PI + 0.5;
    float v = 0.5 - asin(clamp(rd.y, -1.0, 1.0)) * (1.0 / PI);
    return vec2(u, saturate(v));
}

// Per-ray celestial context shared by the star map and the disc renderer:
// both consume the same sun direction, camera radius, and horizon clip, so a
// caller that renders both evaluates them once.
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
    context.camera_r2 = u_camera_radius_sq;
    context.horizon_occluded = PlanetHorizonOccluded(context.camera_pos,
        context.camera_r2, view_dir, ATM_PLANET_R2);
    return context;
}

// World view direction into the baked map's labeling, rigidly attached to
// the celestial sphere (see STAR_MAP_ALIGNMENT). Shared by the full-res
// star render and the low-res glow so both stay locked to one placement.
vec3 StarMapDirection(vec3 view_dir, vec3 sun_dir) {
    const float path_cos = cos(radians(sunPathRotation));
    const float path_sin = sin(radians(sunPathRotation));

    // World -> celestial frame: R_z(-T) * R_y(+90).
    vec3 d = vec3(view_dir.z * path_cos + view_dir.y * path_sin,
                  view_dir.y * path_cos - view_dir.z * path_sin,
                  -view_dir.x);
    // Undo the celestial rotation about the frame's pole axis.
    vec3 celestial = vec3(d.x, d.y * u_star_cos_theta + d.z * u_star_sin_theta,
                          d.z * u_star_cos_theta - d.y * u_star_sin_theta);
    // Celestial frame -> baked map labeling (see STAR_MAP_ALIGNMENT).
    return STAR_MAP_ALIGNMENT * celestial;
}

// Artistic grade: the contrast exponent lifts faint map structure so
// the Milky Way and dim stars read better, then a luminance-keyed
// exponential gain (unity at black) magnifies only the brightest stars
// for magnitude-like variation. The decoded map's luma stays below
// ~0.5, so the default gain caps near 4x. Runs before the physical
// transmittance and night fades so the grade describes the map itself.
// Shared by the full-res star render and the low-res glow, so every
// consumer of the map stays one art direction.
vec3 StarMapGrade(vec3 star_color) {
    star_color = pow(star_color, vec3(STAR_MAP_CONTRAST));
    star_color *= exp2(Luminance(star_color) * STAR_MAP_BRIGHT_BOOST);

    float lum = Luminance(star_color);
    return star_color * (min(lum, 6.0) / max(lum, 0.001));
}

// Star map rigidly attached to the celestial sphere. Vanilla rotates the sky
// about the axis tilted from world +Z by sunPathRotation (the host builds the
// sun direction as R_y(-90) * R_z(T) * R_x(theta) * up, so the path angle
// theta falls out branch-free from the normalized sun direction). The map
// direction is recovered in three steps: world -> celestial-aligned frame
// (undo the fixed path tilt), undo the celestial rotation, then the fixed
// STAR_MAP_ALIGNMENT basis into the baked map's labeling. Gated by view-ray
// transmittance; the cloud compositor multiplies the contribution by real
// cloud transmittance.
vec3 RenderStarMap(vec3 view_dir, vec4 view_transmittance, CelestialContext context) {
    // Day/night fade based on sun elevation (smoothstep transition).
    if (u_star_night_fade <= 0.0) return vec3(0.0);

    if (context.horizon_occluded) return vec3(0.0);

    vec3 rd = StarMapDirection(view_dir, context.sun_dir);

    // Equirectangular sampling, Catmull-Rom bicubic; horizontal wrap at
    // RA 0/360, v clamped (poles never blend).
    // LogLuv32 HDR: bicubic in the encoded space, decode restores linear
    // radiance.
    vec3 star_color = LogLuv32ToLinear(SampleStarMapFastBicubic(StarMapEquirectUV(rd)));

    star_color = StarMapGrade(star_color);

    // View-ray transmittance: dims and reddens stars toward the horizon.
    vec3 transmittance = TransmittanceToLinearSRGB(view_transmittance, vec4(1.0));

    return star_color * transmittance * u_star_night_fade * STAR_MAP_INTENSITY;
}

// Low-res Milky Way glow for area-source consumers (the clouded reflection
// skybox and the volumetric layer's transmitted glow). The box-filtered
// sibling texture carries no per-star detail; a 4-tap cubic B-spline
// samples it without bilinear's C0 creases on the coarse grid and without
// Catmull-Rom's ringing. Grade, night fade and intensity match
// RenderStarMap, so the glow stays the same art direction as the drawn sky;
// pass vec4(1.0) transmittance when the consumer handles atmospheric
// propagation through its own fades.
vec3 RenderMilkyWayGlow(vec3 view_dir, vec4 view_transmittance, CelestialContext context) {
    if (u_star_night_fade <= 0.0) return vec3(0.0);

    if (context.horizon_occluded) return vec3(0.0);

    vec2 uv = StarMapEquirectUV(StarMapDirection(view_dir, context.sun_dir));
    vec3 glow_color = LogLuv32ToLinear(SampleStarMapLowresBspline(uv));
    return StarMapGrade(glow_color)
        * TransmittanceToLinearSRGB(view_transmittance, vec4(1.0))
        * u_star_night_fade * STAR_MAP_INTENSITY;
}

vec3 RenderCelestialDiscs(vec3 view_dir, vec3 sky_color, vec4 view_transmittance,
    CelestialContext context) {
    // Per-ray horizon clip: rays below the spherical horizon hit the planet
    // (ground LUT region) and must not receive the discs. The clip must stay
    // per-ray: the disc/glow is still partly above the horizon while the
    // disc center is below it, so a center-ray test would over-cull and
    // pop the disc out at the horizon.
    if (context.horizon_occluded) return sky_color;

    vec3 contribution = vec3(0.0);

    float sun_cos = dot(view_dir, context.sun_dir);
    if (sun_cos > cos(SUN_GLOW_RADIUS)) {
        // The raw sRGB ratio is clamped in the display space, then the scene
        // white balance is applied to the summed disc contribution below.
        vec3 transmittance = TransmittanceToLinearSRGB(view_transmittance, ATM_SOLAR);
        vec3 sun_radiance = SpectralToLinearSRGB(ATM_SOLAR)
            / (PI * SUN_DISC_RADIUS * SUN_DISC_RADIUS) * ATM_EXPOSURE * BRIGHTNESS_FACT;
        contribution += sun_radiance * transmittance
            * CelestialAngularMask(sun_cos, SUN_DISC_RADIUS, SUN_GLOW_RADIUS);
    }

    // The host's moon direction is the exact IEEE negation of the sun
    // direction, and negation distributes exactly through the dot product,
    // so this is bit-identical to dot(view_dir, moon_dir).
    float moon_cos = -sun_cos;
    if (moon_cos > cos(MOON_GLOW_RADIUS)) {
        vec3 transmittance = TransmittanceToLinearSRGB(view_transmittance, ATM_MOON_IRR);
        vec3 moon_radiance = SpectralToLinearSRGB(ATM_MOON_IRR)
            / (PI * MOON_DISC_RADIUS * MOON_DISC_RADIUS) * ATM_EXPOSURE * BRIGHTNESS_FACT;
        contribution += moon_radiance * transmittance
            * CelestialAngularMask(moon_cos, MOON_DISC_RADIUS, MOON_GLOW_RADIUS);
    }

    return sky_color + contribution * SRGB_WHITE_BALANCE;
}

#endif // LIB_ATMOSPHERE_CELESTIAL_GLSL
