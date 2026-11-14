#ifndef LIB_CLOUD_SIGNAL_GLSL
#define LIB_CLOUD_SIGNAL_GLSL

// Unlit scalar weights, not RGB: scattering.x is the folded sun/moon weight,
// scattering.y the independently attenuated sky weight. Transmittance is the true cloud T.
struct CloudSignal {
    vec2 scattering;
    float transmittance;
};

struct CloudFrame {
    CloudSignal signal;
    // Representative hit distance, or shell distance for a clear interval.
    float distance_km;
};

// Shared colortex12-current / colortex8-history encoding: R = primary scattering, G = sky scattering,
// B = true T, A = distance in km. A <= 0 or the merged AO NaN marker is rejected by temporal validation.
CloudFrame DecodeCloudFrame(vec4 packed_frame) {
    return CloudFrame(CloudSignal(packed_frame.xy, packed_frame.z), packed_frame.w);
}

vec4 EncodeCloudFrame(CloudFrame frame) {
    return vec4(frame.signal.scattering, frame.signal.transmittance, frame.distance_km);
}

#endif // LIB_CLOUD_SIGNAL_GLSL
