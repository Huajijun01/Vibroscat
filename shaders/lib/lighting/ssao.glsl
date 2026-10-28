#ifndef LIB_LIGHTING_SSAO_GLSL
#define LIB_LIGHTING_SSAO_GLSL

// ============================================================================
// SSAO - Monte-Carlo hemisphere ambient occlusion (Crytek 2007)
// ============================================================================
//
// The AO integral
//   A(P) = (1/pi) integral_Omegan V(P,omega) <omega,n> domega
// is estimated by importance sampling with N cosine-weighted hemisphere
// directions:
//   A(P) = (1/N) sum_k V(P,w_k),   Var(A) = A(1-A)/N  (eq. 2-3)
// Each sample projects Q = P + R*omega back to the screen; the visibility test
// (cosine-weighted): the offset must point inside the center's
// normal hemisphere (<offset, n> > 0) - flat planes never pass, walls and
// corners do. Radius window smoothed, no hard cut.
//
// Variance is NOT spatially filtered: the deferred2 temporal accumulation
// (same pipeline as GTAO) is the denoiser.
//
// The depth fetch and the screen-bounds guards mirror GTAO (depthtex2:
// opaque non-hand, no transparent), but the hemisphere sample set is SSAO's
// own, so this pass carries its own copy instead of including gtao.glsl.
// ============================================================================

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"

// Screen-space SSAO at one receiver (full-res UV, pre-fetched depth and oct
// normal). stbn_noise is the SampleSTBNPair pair sampled by the pass main.
// Returns AO in [0,1].
float ComputeSSAOFromGeometry(vec2 uv, float center_depth, vec2 normal_oct, vec2 stbn_noise) {
    if (center_depth >= 1.0) {
        return 1.0;  // sky: fully open
    }
    vec3 center_view = NDCToViewSparse(uv * 2.0 - 1.0, center_depth * 2.0 - 1.0);
    // colortex4 carries the world-space geometric normal; the hemisphere
    // sampler below is built in view space. The octahedral decode returns a
    // unit vector and the camera rotation preserves its length.
    vec3 normal_view = mat3(gbufferModelView)
        * DecodeOctahedralNormal(normal_oct);

    // Tangent frame around the normal for the hemisphere sampling.
    vec3 up = abs(normal_view.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal_view));
    vec3 bitangent = cross(normal_view, tangent);

    // The golden-angle azimuth sequence phi_k = TAU*fract(x0 + k*g) is the
    // orbit of one fixed rotation (cos/sin have period TAU), so a rotation
    // recurrence seeded by one sin/cos pair reproduces it. Drift over
    // SSAO_SAMPLES steps stays near 1e-6 rad.
    float azimuth_c = cos(stbn_noise.x * TAU);
    float azimuth_s = sin(stbn_noise.x * TAU);
    const float azimuth_step_c = cos(TAU * GOLDEN_RATIO_CONJUGATE);
    const float azimuth_step_s = sin(TAU * GOLDEN_RATIO_CONJUGATE);
    float occlusion = 0.0;
    for (int k = 0; k < SSAO_SAMPLES; ++k) {
        // Cosine-weighted hemisphere sample: uniform disk point
        // (r = sqrtu1) lifted onto the hemisphere; azimuth dithered per block
        // and stratified per sample (golden angle).
        float u1 = (float(k) + stbn_noise.y) / float(SSAO_SAMPLES);
        float r = sqrt(u1);
        // 1 - r*r is exactly 1 - u1, so the lifted component is sqrt(1 - u1)
        // and the r*r round trip (one multiply per sample) drops out. With
        // k >= 0 and the [0,1] UNORM STBN noise, u1 >= 0, so 1 - u1 <= 1.
        vec3 dir = tangent * (r * azimuth_c) + bitangent * (r * azimuth_s)
            + normal_view * sqrt(saturate(1.0 - u1));
        float next_c = azimuth_c * azimuth_step_c - azimuth_s * azimuth_step_s;
        azimuth_s = azimuth_s * azimuth_step_c + azimuth_c * azimuth_step_s;
        azimuth_c = next_c;

        vec3 sample_view = center_view + dir * SSAO_RADIUS;
        // A projected point behind the eye must not be pulled back on screen
        // by the footprint cap when the receiver is closer than the radius.
        if (sample_view.z >= -1.0e-4) continue;
        // No screen-fraction cap: fetch at the projected sample point.
        vec2 sample_ndc = ViewToNDC(sample_view).xy;
        vec2 sample_uv = sample_ndc * 0.5 + 0.5;
        if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
            continue;
        }
        // sample_uv is inside [0,1] by the guard above; min() handles the
        // 1.0 edge, where the raw product would index out of bounds.
        ivec2 sample_texel = min(ivec2(sample_uv * u_render_res),
            ivec2(u_render_res) - ivec2(1));
        float sample_depth = texelFetch(depthtex2, sample_texel, 0).r;
        if (sample_depth >= 1.0) {
            continue;  // sky: not an occluder
        }
        vec3 surface_view = NDCToViewSparse(sample_ndc, sample_depth * 2.0 - 1.0);
        vec3 offset = surface_view - center_view;
        float offset_len_sq = dot(offset, offset);
        if (offset_len_sq < 1.0e-8) {  // offset_len < 1.0e-4
            continue;
        }
        float inv_offset_len = inversesqrt(offset_len_sq);
        float offset_len = offset_len_sq * inv_offset_len;
        // Cosine-weighted visibility (eq. 1): occludes only inside the
        // normal hemisphere (offset along the normal, weighted by the
        // cosine). Flat planes fail (offset in-plane), walls/corners pass.
        // Faded by a smooth window over the radius.
        float cos_theta = saturate(dot(offset, normal_view) * inv_offset_len);
        if (cos_theta <= 0.0) {
            continue;  // surface outside the normal_view hemisphere: no occlusion
        }
        float distance_falloff = 1.0 - smoothstep(0.0, SSAO_RADIUS, offset_len);
        occlusion += cos_theta * distance_falloff;
    }
    return saturate(1.0 - occlusion / float(SSAO_SAMPLES));
}

// Entry point used by the recursive-GI pass.
float ComputeSSAO(vec2 uv, vec2 texel, vec2 stbn_noise) {
    ivec2 center_texel = ivec2(texel);
    float center_depth = texelFetch(depthtex2, center_texel, 0).r;
    if (center_depth >= 1.0) return 1.0;
    vec2 normal_oct = texelFetch(colortex4, center_texel, 0).xy;
    return ComputeSSAOFromGeometry(uv, center_depth, normal_oct, stbn_noise);
}

#endif // LIB_LIGHTING_SSAO_GLSL
