#ifndef LIB_ATMOSPHERE_CELESTIAL_GLSL
#define LIB_ATMOSPHERE_CELESTIAL_GLSL

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/atmosphere_geometry.glsl"
#include "/lib/atmosphere/illumination.glsl"
#include "/lib/atmosphere/spectral.glsl"
#include "/lib/color/spaces.glsl"

// Disc rendering runs BEFORE the cloud compositor (clouds occlude the discs).
const float BRIGHTNESS_FACT = 0.03;

// Star map: plate carree equirectangular centered on RA 0h, LogLuv32 in RGBA8.

// LogLuv32 packing: R = u', G = v', B = int(Le), A = frac(Le), Le = 2*log2(Y) + 127.
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

// Celestial frame -> map labeling (north at v=0, RA toward -u); art-directed so the
// galactic-center bulge (RA 17.85h, dec -32.9) centers on the moon's rigid position.
const mat3 STAR_MAP_ALIGNMENT = mat3(
     0.021827, -0.839993, -0.542157,
     0.033791,  0.542596, -0.839314,
     0.999191,  0.000000,  0.040228);

float CelestialAngularMask(float cos_view, float disc_radius, float glow_radius) {
    return smoothstep(cos(glow_radius), cos(disc_radius), cos_view);
}

// Catmull-Rom in 5 taps ("Bicubic filtering in fewer taps"). u wraps at RA 0/360;
// v clamped so the filter never bleeds across the poles.
vec4 SampleStarMapFastBicubic(vec2 uv) {
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

    float half_outer = 0.5 * w0.x + 0.5 * w3.x;
    vec4 row0 = (sample_a + sample_b) * half_outer + sample_a * s0.x;
    vec4 row1 = sample_b * w0.x + sample_c * s0.x + sample_d * w3.x;
    vec4 row2 = sample_b * (0.5 * w0.x) + sample_e * (0.5 * w0.x + s0.x)
        + sample_d * (0.5 * w3.x);
    return row0 * w0.y + row1 * s0.y + row2 * w3.y;
}

// Cubic B-spline in 4 hardware bilinear taps (Sigg & Hadwiger, "Fast Third-Order Texture
// Filtering"): C1, non-ringing. u wraps at RA 0/360 via sampler repeat; v clamped at the poles.
vec4 SampleStarMapLowresBspline(vec2 uv) {
    const vec2 resolution = vec2(256.0, 128.0);
    vec2 rcp_resolution = 1.0 / resolution;

    vec2 texel = uv * resolution - 0.5;
    vec2 base = floor(texel);
    vec2 f = texel - base;

    vec2 f2 = f * f;
    vec2 f3 = f2 * f;
    vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) * (1.0 / 6.0);
    vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) * (1.0 / 6.0);
    vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) * (1.0 / 6.0);
    vec2 w3 = f3 * (1.0 / 6.0);

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

// The NaN guard absorbs the atan branch cut at the antimeridian.
vec2 StarMapEquirectUV(vec3 rd) {
    float a = atan(rd.z, rd.x);
    float u = mix(a, 0.0, float(isnan(a))) * INV_TWO_PI + 0.5;
    float v = 0.5 - asin(clamp(rd.y, -1.0, 1.0)) * (1.0 / PI);
    return vec2(u, saturate(v));
}

// Per-ray context shared by the star and glow renderers; evaluate once per ray.
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

// View direction into the baked map's labeling (see STAR_MAP_ALIGNMENT); shared by star and glow.
vec3 StarMapDirection(vec3 view_dir, vec3 sun_dir) {
    const float path_cos = cos(radians(sunPathRotation));
    const float path_sin = sin(radians(sunPathRotation));

    // World -> celestial frame: R_z(-T) * R_y(+90).
    vec3 d = vec3(view_dir.z * path_cos + view_dir.y * path_sin,
                  view_dir.y * path_cos - view_dir.z * path_sin,
                  -view_dir.x);
    vec3 celestial = vec3(d.x, d.y * u_star_cos_theta + d.z * u_star_sin_theta,
                          d.z * u_star_cos_theta - d.y * u_star_sin_theta);
    return STAR_MAP_ALIGNMENT * celestial;
}

// Art grade applied before transmittance and night fades; shared by star and glow renders.
// The decoded map's luma stays below ~0.5, so the luminance-keyed gain caps near 4x.
vec3 StarMapGrade(vec3 star_color) {
    star_color = pow(star_color, vec3(STAR_MAP_CONTRAST));
    star_color *= exp2(Luminance(star_color) * STAR_MAP_BRIGHT_BOOST);

    float lum = Luminance(star_color);
    return star_color * (min(lum, 6.0) / max(lum, 0.001));
}

// Host builds the sun direction as R_y(-90) * R_z(T) * R_x(theta) * up, so the path angle is
// recovered branch-free. The cloud compositor multiplies this by real cloud transmittance.
vec3 RenderStarMap(vec3 view_dir, vec4 view_transmittance, CelestialContext context) {
    if (u_star_night_fade <= 0.0) return vec3(0.0);

    if (context.horizon_occluded) return vec3(0.0);

    vec3 rd = StarMapDirection(view_dir, context.sun_dir);

    vec3 star_color = LogLuv32ToLinear(SampleStarMapFastBicubic(StarMapEquirectUV(rd)));

    star_color = StarMapGrade(star_color);

    vec3 transmittance = TransmittanceToLinearSRGB(view_transmittance, vec4(1.0));

    return star_color * transmittance * u_star_night_fade * STAR_MAP_INTENSITY;
}

// Low-res glow for area-source consumers (clouded reflection skybox, volumetric transmitted glow);
// grade, fade and intensity match RenderStarMap. Pass vec4(1.0) when the consumer applies its own fades.
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
    // Clip must stay per-ray: a disc-center test pops the disc out at the horizon.
    if (context.horizon_occluded) return sky_color;

    vec3 contribution = vec3(0.0);

    float sun_cos = dot(view_dir, context.sun_dir);
    if (sun_cos > cos(SUN_GLOW_RADIUS)) {
        vec3 transmittance = TransmittanceToLinearSRGB(view_transmittance, ATM_SOLAR);
        vec3 sun_radiance = SpectralToLinearSRGB(ATM_SOLAR)
            / (PI * SUN_DISC_RADIUS * SUN_DISC_RADIUS) * ATM_EXPOSURE * BRIGHTNESS_FACT;
        contribution += sun_radiance * transmittance
            * CelestialAngularMask(sun_cos, SUN_DISC_RADIUS, SUN_GLOW_RADIUS);
    }

    // Host moon dir is the exact negation of the sun dir: bit-identical to dot(view_dir, moon_dir).
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
