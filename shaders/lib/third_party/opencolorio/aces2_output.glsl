#ifndef LIB_THIRD_PARTY_OPENCOLORIO_ACES2_OUTPUT_GLSL
#define LIB_THIRD_PARTY_OPENCOLORIO_ACES2_OUTPUT_GLSL

// OpenColorIO 2.6.0 ACES 2.0 SDR 100-nit Rec.709 output transform.
// Generated from the official ACES-OUTPUT builtin; source:
// https://github.com/AcademySoftwareFoundation/OpenColorIO/tree/v2.6.0
// Modified for Vibroscat: piecewise polynomials approximate hue boundaries;
// the final RGB-to-XYZ conversion is omitted to return display-linear Rec.709;
// the pack's saturate() helper replaces the explicit min/max range clamps.
// The achromatic tonescale uses a rational fit and hue uses FastAtan2;
// near-neutral colors bypass the display-gamut intersection calculation.
// See licenses/THIRD_PARTY_NOTICES.md, section 3.
// Copyright Contributors to the OpenColorIO Project.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
// * Redistributions of source code must retain the above copyright
//   notice, this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
// * Neither the name of the copyright holder nor the names of its
//   contributors may be used to endorse or promote products derived from
//   this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include "/lib/core/math_scalar.glsl"

// Piecewise boundary fits over hue in degrees, with joins at gamut corners.

float ocio_reach_m_table_0_sample(float h)
{
    if (h < 25.0) {
        float x = (h - 0.0) * 0.08 - 1.0;
        float value = -0.6509330816;
        value = value * x + -0.4758378939;
        value = value * x + 0.9612694965;
        value = value * x + 0.5504984136;
        value = value * x + 0.1832135625;
        value = value * x + 0.1815332215;
        value = value * x + -4.569299609;
        value = value * x + 13.53165625;
        value = value * x + 184.654363;
        return value;
    }
    if (h < 147.0) {
        float x = (h - 25.0) * 0.01639344262 - 1.0;
        float value = 24.28988306;
        value = value * x + -16.48072854;
        value = value * x + -11.02618106;
        value = value * x + 8.821122649;
        value = value * x + 30.92021027;
        value = value * x + -10.91443096;
        value = value * x + 44.8885747;
        value = value * x + -6.666810343;
        value = value * x + 80.05278436;
        return value;
    }
    if (h < 148.0) {
        float x = (h - 147.0) * 2.0 - 1.0;
        float value = 3.60822483e-14;
        value = value * x + -2.387245275e-14;
        value = value * x + -4.286571098e-13;
        value = value * x + 1.079508662e-14;
        value = value * x + 4.007905119e-14;
        value = value * x + 2.221124771e-14;
        value = value * x + -1.345590306e-13;
        value = value * x + -1.095581;
        value = value * x + 142.788696;
        return value;
    }
    if (h < 268.0) {
        float x = (h - 148.0) * 0.01666666667 - 1.0;
        float value = 4.048306966;
        value = value * x + -3.032073999;
        value = value * x + 2.967248941;
        value = value * x + 0.1475575774;
        value = value * x + 15.23548958;
        value = value * x + -3.718799249;
        value = value * x + 36.51391262;
        value = value * x + -3.739061403;
        value = value * x + 72.58575749;
        return value;
    }
    if (h < 269.0) {
        float x = (h - 268.0) * 2.0 - 1.0;
        float value = 1.542446726e-13;
        value = value * x + 4.428126036e-15;
        value = value * x + -3.19130139e-13;
        value = value * x + -3.640257438e-15;
        value = value * x + 1.15272375e-13;
        value = value * x + -2.298861179e-15;
        value = value * x + -7.828113158e-14;
        value = value * x + -0.036621;
        value = value * x + 120.97168;
        return value;
    }
    {
        float x = (h - 269.0) * 0.02197802198 - 1.0;
        float value = -0.2935437193;
        value = value * x + -2.012299369;
        value = value * x + -2.700553185;
        value = value * x + -1.642741641;
        value = value * x + 4.391688499;
        value = value * x + 5.543634883;
        value = value * x + 31.34445091;
        value = value * x + 21.03924463;
        value = value * x + 111.1208656;
        return value;
    }
}
// Achromatic response A -> tone-scaled A, before converting back to J.
// Degree-5/5 rational fit of the SDR 100-nit response for A in [0, 16];
// the AP1 [0, 1024] input clamp bounds A by 11.763.
float ocio_tonescale_A_fwd0(float A)
{
    float numerator = 1.31923832592 + A * (8.97608382843
        + A * (6.36423190656 + A * 17.5673996807));
    float denominator = 1.0 + A * A * (10.9063556048
        + A * (11.6549632251 + A * (6.02356267315 + A * 17.5159191248)));
    return A * A * numerator / denominator;
}
float ocio_toe_fwd0(float x, float limit, float k1_in, float k2_in)
{
  float k2 = max(k2_in, 0.001);
  float k1 = sqrt(k1_in * k1_in + k2 * k2);
  float k3 = (limit + k1) / (limit + k2);
  return (x > limit) ? x : 0.5 * (k3 * x - k1 + sqrt((k3 * x - k1) * (k3 * x - k1) + 4.0 * k2 * k3 * x));
}
vec3 ocio_gamut_cusp_table_0_sample(float h)
{
    if (h < 26.251) {
        float x = (h - 0.0) * 0.07618757381 - 1.0;
        vec3 value = vec3(-0.003514314798, -0.007256971387, 0.0002319389887);
        value = value * x + vec3(0.0003116398202, 0.001239240412, -5.858608452e-05);
        value = value * x + vec3(-0.008176314127, 0.0643894734, -0.0002753226347);
        value = value * x + vec3(-0.02813381213, 0.01940274705, -1.808014767e-05);
        value = value * x + vec3(0.6428657327, 0.281405465, -0.002127384069);
        value = value * x + vec3(-2.362884389, 3.200004154, 0.01040094803);
        value = value * x + vec3(51.22882911, 73.71552896, 1.138109886);
        return value;
    }
    if (h < 106.548775) {
        float x = (h - 26.251) * 0.0249072904 - 1.0;
        vec3 value = vec3(0.1888247293, 2.779368938, 0.2408177499);
        value = value * x + vec3(1.2287459, -2.969882764, 0.1542459774);
        value = value * x + vec3(0.2928026148, 2.869041357, -0.2566471251);
        value = value * x + vec3(2.868393288, -2.123023063, -0.1453480709);
        value = value * x + vec3(1.013062615, 14.08016514, 0.07665937298);
        value = value * x + vec3(16.92272466, -6.157252367, -0.02297285351);
        value = value * x + vec3(68.99450304, 46.29578541, 1.071381669);
        return value;
    }
    if (h < 140.300812) {
        float x = (h - 106.548775) * 0.05925568285 - 1.0;
        vec3 value = vec3(0.0006070972777, -0.005420492356, 0.0003004755246);
        value = value * x + vec3(-0.01007911113, 0.04499425859, -0.0005763874772);
        value = value * x + vec3(-0.03641150775, 0.2218699304, 0.001257725554);
        value = value * x + vec3(-0.2266906696, 0.6112482954, -0.002797962056);
        value = value * x + vec3(-0.4779992982, 3.413449262, 0.009186112895);
        value = value * x + vec3(-6.173616592, 6.678552237, -0.01945371245);
        value = value * x + vec3(85.61251194, 58.47898847, 1.084636886);
        return value;
    }
    if (h < 195.824158) {
        float x = (h - 140.300812) * 0.0360208839 - 1.0;
        vec3 value = vec3(0.04890596471, 0.8371038018, 0.001262373004);
        value = value * x + vec3(-0.04677725053, -1.606997852, -0.002403914784);
        value = value * x + vec3(-0.04210015121, 1.820712667, 0.003243178775);
        value = value * x + vec3(0.3438761295, -3.458521941, -0.004402537304);
        value = value * x + vec3(-0.5058250498, 8.832139289, 0.01321181179);
        value = value * x + vec3(4.615887929, -12.50892367, -0.01763317119);
        value = value * x + vec3(84.10032528, 40.37924195, 1.030396061);
        return value;
    }
    if (h < 276.260681) {
        float x = (h - 195.824158) * 0.02486432687 - 1.0;
        vec3 value = vec3(-0.1657698311, 0.7045780357, 0.04734007278);
        value = value * x + vec3(-0.8716181271, 1.168200846, -0.0284977895);
        value = value * x + vec3(-0.823456346, 2.057542502, -0.05331887287);
        value = value * x + vec3(-3.22640897, 2.290333541, 0.02813448813);
        value = value * x + vec3(-2.507621173, 8.87951974, 0.01649265732);
        value = value * x + vec3(-18.65847892, 5.832509774, 0.004908460758);
        value = value * x + vec3(69.2546245, 31.94414251, 1.017678999);
        return value;
    }
    if (h < 332.62442) {
        float x = (h - 276.260681) * 0.03548380635 - 1.0;
        vec3 value = vec3(0.03957894222, 0.04267062561, 0.08051354381);
        value = value * x + vec3(0.1425352388, 0.1419686282, 0.0814323169);
        value = value * x + vec3(0.3262551233, 0.6278214289, -0.05683679268);
        value = value * x + vec3(1.037926671, 1.157086706, -0.05709737272);
        value = value * x + vec3(2.14247307, 6.523765354, 0.007816060083);
        value = value * x + vec3(9.765782486, 6.982083697, 0.00472151159);
        value = value * x + vec3(51.43921216, 53.96372718, 1.030301635);
        return value;
    }
    {
        float x = (h - 332.62442) * 0.07305781284 - 1.0;
        vec3 value = vec3(-0.005505949645, -0.005277362284, 9.327700279e-05);
        value = value * x + vec3(-0.00377350363, -0.0001752403675, -0.0001232144823);
        value = value * x + vec3(0.03071400896, 0.006560819369, -0.0001131309668);
        value = value * x + vec3(-0.04172406971, -0.1890210098, -7.504787854e-05);
        value = value * x + vec3(0.7381975996, 1.131456832, -0.0008499495288);
        value = value * x + vec3(-5.276028418, 0.8863459586, 0.01758503774);
        value = value * x + vec3(58.80883111, 69.00353047, 1.10909791);
        return value;
    }
}
float ocio_get_focus_gain0(float J, float cuspJ)
{
    float result;
    float thr = mix(cuspJ, 100.000000, 0.300000);
    if (J > thr) {
        float gain = ( 100. - thr) / max(0.0001, 100. - J);
        gain = log(gain)/log(10.0);
        result = gain * gain + 1.0;
    } else {
        result = 1.0;
    }
    return result;
}
float ocio_solve_J_intersect0(float J, float M, float focusJ, float slope_gain)
{
    float result;
    float M_scaled = M / slope_gain;
    float a = M_scaled / focusJ;
    if (J < focusJ) {
        float b = 1.0 - M_scaled;
        float c = -J;
        float det =  b * b - 4.f * a * c;
        float root =  sqrt(det);
        result = -2.0 * c / (b + root);
    } else {
        float b = - (1.0 + M_scaled + 100. * a);
        float c = 100. * M_scaled + J;
        float det =  b * b - 4.f * a * c;
        float root =  sqrt(det);
        result = -2.0 * c / (b - root);
    }
    return result;
}
float ocio_find_gamut_boundary_intersection0(vec2 JM_cusp, float gamma_top_inv, float gamma_bottom_inv, float J_intersect_source, float J_intersect_cusp, float slope)
{
  float M_boundary_lower = J_intersect_cusp * pow(J_intersect_source / J_intersect_cusp, gamma_bottom_inv) / (JM_cusp.r / JM_cusp.g - slope);
  float M_boundary_upper = JM_cusp.g * (100. - J_intersect_cusp) * pow((100. - J_intersect_source) / (100. - J_intersect_cusp), gamma_top_inv) / (slope * JM_cusp.g + 100. - JM_cusp.r);
  float smin = 0.0;
  {
    float a = M_boundary_lower;
    float b = M_boundary_upper;
    float s = 0.119999997 * JM_cusp.g;
    float h = max(s - abs(a - b), 0.0) / s;
    smin = min(a, b) - h * h * h * s * 0.16666666666666666;
  }
  return smin;
}
float ocio_remap_M_fwd0(float M, float gamut_boundary_M, float reach_boundary_M)
{
    float result;
    float boundary_ratio = gamut_boundary_M / reach_boundary_M;
    float proportion = max(boundary_ratio, 0.75);
    float threshold = proportion * gamut_boundary_M;
    if (proportion >= 1.0f || M <= threshold) {
        result = M;
    } else {
        float m_offset = M - threshold;
        float gamut_offset = gamut_boundary_M - threshold;
        float reach_offset = reach_boundary_M - threshold;
        float scale = reach_offset / ((reach_offset / gamut_offset) - 1.0f);
        float nd = m_offset / scale;
        result = threshold + scale * nd / (1.0f + nd);
    }
    return result;
}
vec3 ocio_gamut_compress0(vec3 JMh, float Jx, vec3 JMGcusp, float reachMaxM)
{
  float J = JMh.r;
  float M = JMh.g;
  float h = JMh.b;
  if (M <= 0.0 || J > 100.)
  {
    return vec3(J, 0.0, h);
  }
  else
  {
    vec2 JMcusp = JMGcusp.rg;
    float focusJ = mix(JMcusp.r, 34.096539, saturate(1.300000 - (JMcusp.r / 100.000000)));
    float slope_gain = 135. * ocio_get_focus_gain0(Jx, JMcusp.r);
    float J_intersect_source = ocio_solve_J_intersect0(JMh.r, JMh.g, focusJ, slope_gain);
    float gamut_slope = (J_intersect_source < focusJ) ? J_intersect_source : (100. - J_intersect_source);
    gamut_slope = gamut_slope * (J_intersect_source - focusJ) / (focusJ * slope_gain);
    float gamma_top_inv = JMGcusp.b;
    float gamma_bottom_inv = 0.877192974;
    float J_intersect_cusp = ocio_solve_J_intersect0(JMcusp.r, JMcusp.g, focusJ, slope_gain);
    float gamutBoundaryM = ocio_find_gamut_boundary_intersection0(JMcusp, gamma_top_inv, gamma_bottom_inv, J_intersect_source, J_intersect_cusp, gamut_slope);
    if (gamutBoundaryM <= 0.0)
    {
      return vec3(J, 0.0, h);
    }
    float reachBoundaryM = 100. * pow(J_intersect_source / 100.,  0.879464149);
    reachBoundaryM = reachBoundaryM / ((100. / reachMaxM) - gamut_slope);
    float remapped_M = ocio_remap_M_fwd0(M, gamutBoundaryM, reachBoundaryM);
    float remapped_J = J_intersect_source + remapped_M * gamut_slope;
    return vec3(remapped_J, remapped_M, h);
  }
}

// Declaration of the OCIO shader function

vec4 ACES2Output(vec4 inPixel)
{
  vec4 outColor = inPixel;

  // Add Matrix processing

  {
    vec4 res = vec4(outColor.rgb.r, outColor.rgb.g, outColor.rgb.b, outColor.a);
    vec4 tmp = res;
    res = mat4(1.4514393161456653, -0.07655377339602043, 0.008316148425697719, 0., -0.23651074689374019, 1.1762296998335731, -0.0060324497910210278, 0., -0.21492856925192524, -0.099675926437552201, 0.9977163013653233, 0., 0., 0., 0., 1.) * tmp;
    outColor.rgb = vec3(res.x, res.y, res.z);
    outColor.a = res.w;
  }

  // Add Range processing

  {
    outColor.rgb = max(vec3(0., 0., 0.), outColor.rgb);
    outColor.rgb = min(vec3(1024., 1024., 1024.), outColor.rgb);
  }

  // Add Matrix processing

  {
    vec4 res = vec4(outColor.rgb.r, outColor.rgb.g, outColor.rgb.b, outColor.a);
    vec4 tmp = res;
    res = mat4(0.69545224135745176, 0.044794563372037632, -0.0055258825581135443, 0., 0.14067869647029416, 0.85967111845642163, 0.0040252103059786586, 0., 0.16386906217225403, 0.095534318171540358, 1.0015006722521349, 0., 0., 0., 0., 1.) * tmp;
    outColor.rgb = vec3(res.x, res.y, res.z);
    outColor.a = res.w;
  }

  // Add FixedFunction 'ACES_OutputTransform20 (Forward)' processing

  {

    // Convert RGB to achromatic response A, chroma M and hue h.

    vec3 AMh;
    vec3 Aab;
    vec2 hue_direction = vec2(1.0, 0.0);
    {
      {
        vec3 lms = mat3(0.445181042, 0.123734146, 0.0117007261, 0.34964928, 0.613643706, 0.0280607939, -0.00112973212, 0.0563228019, 0.753939033) * outColor.rgb;
        vec3 F_L_v = pow(abs(lms), vec3(0.419999987, 0.419999987, 0.419999987));
        vec3 rgb_a = (sign(lms) * F_L_v) / ( 27.1299992 + F_L_v);
        Aab = mat3(20.25881, 15480., 1720., 10.129405, -16887.2734, 1720., 0.506470263, 1407.27271, -3440.) * rgb_a.rgb;
      }
      {
        if (Aab.r <= 0.0)
        {
          AMh = vec3(0.0);
        }
        else
        {
          float M = length(Aab.gb);
          // Match the reference's zero-a hue convention, including gray.
          if (Aab.g != 0.0) hue_direction = Aab.gb / M;
          float h = FastAtan2(hue_direction) * 180.0;
          h = h - floor(h / 360.0) * 360.0;
          h = (h < 0.0) ? h + 360.0 : h;
          AMh = vec3(Aab.r, M, h);
        }
      }
      outColor.rgb = AMh;
    }
    float cos_hr = hue_direction.x;
    float sin_hr = hue_direction.y;

    // Add ToneScale and ChromaCompress (fwd)

    float A_ts = ocio_tonescale_A_fwd0(outColor.r);
    float J_ts = 100.0 * pow(A_ts, 1.13705599);
    // Evaluate the analytic reach boundary.
    float reachMaxM = ocio_reach_m_table_0_sample(outColor.b);

    {
      float M = outColor.g;
      float h = outColor.b;
      float M_cp = M;
      if (M != 0.0)
      {
        float nJ = J_ts / 100.;
        float snJ = saturate(1.0 - nJ);
        float Mnorm;
        {
          float cos_hr2 = 2.0 * cos_hr * cos_hr - 1.0;
          float sin_hr2 = 2.0 * cos_hr * sin_hr;
          float cos_hr3 = 4.0 * cos_hr * cos_hr * cos_hr - 3.0 * cos_hr;
          float sin_hr3 = 3.0 * sin_hr - 4.0 * sin_hr * sin_hr * sin_hr;
          vec3 cosines = vec3(cos_hr, cos_hr2, cos_hr3);
          vec3 cosine_weights = vec3(11.341321604032515, 16.469863649185896, 7.8842182208776475);
          vec3 sines = vec3(sin_hr, sin_hr2, sin_hr3);
          vec3 sine_weights = vec3(14.665187919584513, -6.3725780354404442, 9.1941277054452897);
          Mnorm = dot(cosines, cosine_weights) + dot(sines, sine_weights) + 77.133051547393805;
        }
        float limit = A_ts * reachMaxM / Mnorm;
        M_cp = M * A_ts / Aab.r;
        M_cp = M_cp / Mnorm;
        M_cp = limit - ocio_toe_fwd0(limit - M_cp, limit - 0.001, snJ * 1.29999995, sqrt(nJ * nJ + 0.00499999989));
        M_cp = ocio_toe_fwd0(M_cp, limit, nJ * 2.4000001, snJ);
        M_cp = M_cp * Mnorm;
      }
      outColor.rgb = vec3(J_ts, M_cp, h);
    }

    // Add GamutCompress (fwd)

    {
      vec3 JMGcusp = ocio_gamut_cusp_table_0_sample(outColor.b);
      // An interior triangle approximates the inactive compression region.
      // Inside it, retain the tone-scaled response without solving a focus ray.
      float inner = 0.6 * JMGcusp.g * min(outColor.r / JMGcusp.r,
          (100.0 - outColor.r) / (100.0 - JMGcusp.r));
      if (outColor.g > inner) {
        outColor.rgb = ocio_gamut_compress0(outColor.rgb, outColor.r, JMGcusp, reachMaxM);
        A_ts = pow(outColor.r * 0.00999999978, 0.879464149);
      }
    }

    // Add JMh to RGB

    {
      vec3 JMh = outColor.rgb;
      vec3 Aab;
      {
        Aab.r = A_ts;
        Aab.g = JMh.g * cos_hr;
        Aab.b = JMh.g * sin_hr;
      }
      {
        vec3 rgb_a = mat3(0.0323680267, 0.0323680267, 0.0323680267, 2.07657631e-05, -4.10250432e-05, -1.01296409e-05, 1.3260621e-05, -1.20174373e-05, -0.000290076074) * Aab.rgb;
        vec3 rgb_a_lim = min( abs(rgb_a), vec3(0.99000001, 0.99000001, 0.99000001) );
        vec3 lms = sign(rgb_a) * pow( 27.1299992 * rgb_a_lim / (1.0f - rgb_a_lim), vec3(2.38095236, 2.38095236, 2.38095236));
        JMh.rgb = mat3(7.45048571, -1.4750675, 0.0106288502, -6.1301837, 3.11835742, -0.31857267, -0.0603808537, -0.383369029, 1.56786489) * lms;
      }
      outColor.rgb = JMh;
    }
  }

  // Add Range processing

  {
    outColor.rgb = saturate(outColor.rgb);
  }

  return outColor;
}

#endif // LIB_THIRD_PARTY_OPENCOLORIO_ACES2_OUTPUT_GLSL
