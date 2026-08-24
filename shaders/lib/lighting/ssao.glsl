#ifndef LIB_LIGHTING_SSAO_GLSL
#define LIB_LIGHTING_SSAO_GLSL

// ════════════════════════════════════════════════════════════════════════════
// SSAO — Monte-Carlo hemisphere ambient occlusion (Crytek 2007)
// ════════════════════════════════════════════════════════════════════════════
//
// The AO integral
//   A(P) = (1/π) ∫_Ωn V(P,ω) ⟨ω,n⟩ dω
// is estimated by importance sampling with N cosine-weighted hemisphere
// directions:
//   A(P) = (1/N) sum_k V(P,w_k),   Var(A) = A(1-A)/N  (eq. 2-3)
// Each sample projects Q = P + R·ω back to the screen; the visibility test
// (cosine-weighted): the offset must point inside the center's
// normal hemisphere (⟨offset, n⟩ > 0) — flat planes never pass, walls and
// corners do. Radius window smoothed, no hard cut.
//
// Variance is NOT spatially filtered: the deferred1 temporal accumulation
// (same pipeline as GTAO) is the denoiser.
//
// Shared plumbing from gtao.glsl (guarded); depth source matches GTAO
// (depthtex1: opaque + hand, no transparent).
// ════════════════════════════════════════════════════════════════════════════

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"
#include "/lib/core/coordinates.glsl"
#include "/lib/core/math_scalar.glsl"
#include "/lib/core/packing.glsl"
#include "/lib/lighting/gtao.glsl"

// Screen-space SSAO at one pixel (full-res UV and texel). Returns AO in [0,1].
float ComputeSSAO(vec2 uv, vec2 texel, int frame) {
    ivec2 center_texel = ivec2(texel);
    float center_depth = texelFetch(depthtex1, center_texel, 0).r;
    if (center_depth >= 1.0) {
        return 1.0;  // sky: fully open
    }
    vec3 center_view = NDCToView(vec3(uv * 2.0 - 1.0, center_depth * 2.0 - 1.0));
    vec4 geometry_data = texelFetch(colortex4, center_texel, 0);
    vec3 normal = DecodeOctahedralNormal(geometry_data.xy);  // geometric view normal

    // Tangent frame around the normal for the hemisphere sampling.
    vec3 up = abs(normal.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    vec2 noise = GTAOSTBNNoise(texel, frame);
    float occlusion = 0.0;
    for (int k = 0; k < SSAO_SAMPLES; ++k) {
        // Cosine-weighted hemisphere sample: uniform disk point
        // (r = √u1) lifted onto the hemisphere; azimuth dithered per block
        // and stratified per sample (golden angle).
        float u1 = (float(k) + noise.y) / float(SSAO_SAMPLES);
        float u2 = fract(noise.x + float(k) * 0.61803398875);
        float r = sqrt(u1);
        float phi = u2 * TAU;
        vec3 dir = tangent * (r * cos(phi)) + bitangent * (r * sin(phi))
            + normal * sqrt(max(1.0 - r * r, 0.0));

        vec3 sample_view = center_view + dir * SSAO_RADIUS;
        vec2 sample_ndc = ViewToNDC(sample_view).xy;
        vec2 sample_uv = sample_ndc * 0.5 + 0.5;
        if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
            continue;
        }
        // Clamp the 1.0 edge (the integer texel would be out of bounds).
        ivec2 sample_texel = ivec2(clamp(sample_uv, vec2(0.0), vec2(1.0) - 1.0e-5)
            * vec2(viewWidth, viewHeight));
        float sample_depth = texelFetch(depthtex1, sample_texel, 0).r;
        if (sample_depth >= 1.0) {
            continue;  // sky: not an occluder
        }
        // Cosine-weighted visibility (eq. 1): occludes only inside the
        // normal hemisphere (offset along the normal, weighted by the
        // cosine). Flat planes fail (offset in-plane), walls/corners pass.
        // Faded by a smooth window over the radius.
        vec3 surface_view = NDCToView(vec3(sample_uv * 2.0 - 1.0, sample_depth * 2.0 - 1.0));
        vec3 offset = surface_view - center_view;
        float offset_len = length(offset);
        if (offset_len < 1.0e-4) {
            continue;
        }
        float cos_theta = clamp(dot(offset, normal) / offset_len, 0.0, 1.0);
        if (cos_theta <= 0.0) {
            continue;  // surface outside the normal hemisphere: no occlusion
        }
        float distance_falloff = 1.0 - smoothstep(0.0, SSAO_RADIUS, offset_len);
        occlusion += cos_theta * distance_falloff;
    }
    return Saturate(1.0 - occlusion / float(SSAO_SAMPLES));
}

#endif
