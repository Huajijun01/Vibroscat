#ifndef LIB_LIGHTING_SPECULAR_MATERIAL_FACTOR_GLSL
#define LIB_LIGHTING_SPECULAR_MATERIAL_FACTOR_GLSL

// Fitted approximation of this pack's GGX unit-environment response
// (E = A + B, M = F0 * A + B); call only while demodulation runs.
vec3 SpecularMaterialFactor(vec3 f0, float ndotv, float roughness) {
    float r = max(roughness, 0.04472136); // sqrt(0.002): existing alpha floor
    float a = r * r;
    float t = ndotv / (ndotv + 0.96482 * a);
    float s = 1.0 - t;
    float e = 1.0 - t * (0.72599 * s * s
        + a * a * (1.95691 - 0.69662 * a));
    float x = 1.0 - ndotv;
    float x2 = x * x;
    float b = x2 * x2 * x * (1.0 + r * ndotv * (11.86487 - 11.84547 * r))
        / (1.0 + r * (0.88356 + r * (10.52149 + 14.80813 * a)));
    b = min(b, e);
    return max(f0 * (e - b) + vec3(b), vec3(1.0 / 1024.0));
}

#endif // LIB_LIGHTING_SPECULAR_MATERIAL_FACTOR_GLSL
