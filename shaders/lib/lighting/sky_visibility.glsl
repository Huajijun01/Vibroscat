#ifndef LIB_LIGHTING_SKY_VISIBILITY_GLSL
#define LIB_LIGHTING_SKY_VISIBILITY_GLSL

#include "/lib/contract/sky_light_data.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/atmosphere/sky_light.glsl"

// Integrates (w, cos(theta)*w, sin(theta)*w) for w = max(a*cos+b*sin,0)*sin over
// the blocked arc of the sky's affine SH L(omega) = C + G . omega.
vec3 SkySideArcMoments(float a, float b, float sin_beta, float cos_beta,
        float beta, float horizon_cos) {
    vec3 result = vec3(0.0);
    bool valid;
    float theta_lo;
    float sin_lo;
    float cos_lo;
    float theta_hi;
    float sin_hi;
    float cos_hi;
    if (a >= 0.0) {
        // Positive band: upper end beta + pi/2 with trig (a/R, -b/R).
        theta_hi = beta + 0.5 * PI;
        sin_hi = cos_beta;
        cos_hi = -sin_beta;
        theta_lo = acos(horizon_cos);
        sin_lo = sqrt(saturate(1.0 - horizon_cos * horizon_cos));
        cos_lo = horizon_cos;
        valid = !(theta_hi <= theta_lo);
    } else {
        // Band wraps past pi: upper end pi; lower end max(horizon, beta - pi/2).
        theta_hi = PI;
        sin_hi = 0.0;
        cos_hi = -1.0;
        if (horizon_cos <= sin_beta) {
            theta_lo = acos(horizon_cos);
            sin_lo = sqrt(saturate(1.0 - horizon_cos * horizon_cos));
            cos_lo = horizon_cos;
        } else {
            theta_lo = beta - 0.5 * PI;
            sin_lo = -cos_beta;
            cos_lo = sin_beta;
        }
        valid = !(theta_lo >= PI);
    }
    if (valid) {
        float sin_hi2 = sin_hi * sin_hi;
        float sin_lo2 = sin_lo * sin_lo;
        float cos_hi3 = cos_hi * cos_hi * cos_hi;
        float cos_lo3 = cos_lo * cos_lo * cos_lo;
        float d_jcs = 0.5 * (sin_hi2 - sin_lo2);
        float d_jss = 0.5 * ((theta_hi - theta_lo)
            - (sin_hi * cos_hi - sin_lo * cos_lo));
        float d_jccs = (cos_lo3 - cos_hi3) * (1.0 / 3.0);
        float d_jcss = (sin_hi2 * sin_hi - sin_lo2 * sin_lo) * (1.0 / 3.0);
        float d_jsss = (cos_hi3 - cos_lo3) * (1.0 / 3.0) - (cos_hi - cos_lo);
        result = vec3(a * d_jcs + b * d_jss,
            a * d_jccs + b * d_jcss,
            a * d_jcss + b * d_jsss);
    }
    return result;
}

// Returns (blocked mass, view-axis moment, signed tangent moment); the negative
// half-slice negates both its tangent terms. Do not clamp or normalize.
vec3 IntegrateSkyBlockedArcPairMoments(float ndotv, float ndott, vec2 horizon_cos) {
    if (horizon_cos.x <= -1.0 && horizon_cos.y <= -1.0) {
        return vec3(0.0);
    }
    float projected_length2 = ndotv * ndotv + ndott * ndott;
    if (projected_length2 < 1.0e-8) {
        return vec3(0.0);
    }
    float inv_r = inversesqrt(projected_length2);
    float beta_raw = atan(ndott, ndotv);
    float beta = beta_raw < -0.5 * PI ? beta_raw + TAU : beta_raw;
    float beta_neg = -beta_raw;
    if (beta_neg < -0.5 * PI) beta_neg += TAU;
    float sin_beta = ndott * inv_r;
    float cos_beta = ndotv * inv_r;
    vec3 positive = SkySideArcMoments(ndotv, ndott, sin_beta, cos_beta,
        beta, horizon_cos.x);
    vec3 negative = SkySideArcMoments(ndotv, -ndott, -sin_beta, cos_beta,
        beta_neg, horizon_cos.y);
    return vec3(positive.xy + negative.xy, positive.z - negative.z);
}

// Input is the unnormalized slice sum in world axes (+Y up); the caller applies
// PI/GTAO_SLICES exactly once. No SH_A convolution here.
vec3 EvalSkyBlockedMoments(float blocked_mass, vec3 blocked_direction_world) {
    vec4 basis = vec4(SH_Y0 * blocked_mass, SH_Y1 * blocked_direction_world.yzx);
    return vec3(dot(sky_sh_r0, basis), dot(sky_sh_g0, basis), dot(sky_sh_b0, basis));
}

#endif // LIB_LIGHTING_SKY_VISIBILITY_GLSL
