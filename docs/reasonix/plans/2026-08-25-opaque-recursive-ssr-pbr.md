# Opaque Recursive SSR PBR Implementation Plan

> **For agentic workers:** implement this plan task-by-task — dispatch a fresh subagent per task with the native `task` tool (recommended for quality), or use the superpowers-executing-plans skill to work through it inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add filtered, `colortex5`-recursive screen-space indirect specular to opaque materials while moving all material and BRDF integration into one final deferred PBR pass.

**Architecture:** `deferred2` traces one visible-GGX ray per opaque pixel into the previous complete HDR scene, `deferred3` filters hit radiance with current G-buffer guidance, and the existing opaque shading program moves to `deferred4` to integrate corrected LabPBR material data, environment fallback, and filtered history. `colortex3` and `colortex11` are transient ping-pong resources; `colortex5` keeps its existing TAA, water/glass, and caustic schedule.

**Tech Stack:** Iris shaderpack programs, GLSL 4.30 compatibility profile, PowerShell, Python 3.14 `unittest`, Minecraft Fabric/Iris, Vibris, NVIDIA Nsight Graphics GPU Trace.

---

## File Map

Create `tests/test_opaque_recursive_ssr.py` as the executable source-contract
and numeric reference suite. Create `shaders/lib/raytrace/opaque_reflection.glsl`
for STBN sampling, visible-GGX sampling, current-depth pixel DDA, hit
reprojection, history confidence, mip selection, and recursion sanitization.
The existing water helper `shaders/lib/raytrace/ssr.glsl` remains unchanged.

Create `shaders/program/deferred/opaque_reflection_trace.fragment` and
`opaque_reflection_filter.fragment`. Modify the material, G-buffer, BRDF,
deferred shading, resource, uniform, setting, property, language, and world
wrapper files named in each task below. Generated captures, logs, patched
shaders, and GPU traces remain ignored artifacts.

## Task 1: Establish Executable Contracts

**Files:**

- Create: `tests/test_opaque_recursive_ssr.py`
- Test: `tests/test_opaque_recursive_ssr.py`

- [ ] **Step 1: Write failing resource and schedule tests**

Create a `unittest` suite rooted at the repository:

```python
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

class OpaqueRecursiveSSRContractTests(unittest.TestCase):
    def test_transient_formats_are_declared(self):
        source = read("shaders/lib/contract/resources.glsl")
        self.assertRegex(source, r"colortex3Format\s*=\s*R11F_G11F_B10F")
        self.assertRegex(source, r"colortex11Format\s*=\s*RG16F")

    def test_pass_wrappers_match_in_all_dimensions(self):
        worlds = {"world0": "WORLD_OVERWORLD", "world1": "WORLD_END", "world-1": "WORLD_NETHER"}
        for world, define in worlds.items():
            trace = read(f"shaders/{world}/deferred2.fsh")
            filt = read(f"shaders/{world}/deferred3.fsh")
            shade = read(f"shaders/{world}/deferred4.fsh")
            self.assertIn(define, trace)
            self.assertIn("colortex5MipmapEnabled = true", trace)
            self.assertIn("opaque_reflection_trace.fragment", trace)
            self.assertIn("opaque_reflection_filter.fragment", filt)
            self.assertIn("deferred_shading.fragment", shade)

    def test_caustic_flip_follows_final_shading(self):
        props = read("shaders/shaders.properties")
        self.assertNotIn("flip.deferred2.colortex5 = false", props)
        self.assertIn("flip.deferred4.colortex5 = false", props)
        self.assertIn("flip.composite.colortex5 = true", props)
        self.assertIn("flip.composite1.colortex5 = true", props)

    def test_water_ssr_helper_remains_separate(self):
        water = read("shaders/lib/raytrace/ssr.glsl")
        self.assertIn("bool RayTraceHIT", water)
        self.assertNotIn("TraceOpaqueReflection", water)
```

- [ ] **Step 2: Run tests and verify the red state**

Run:

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
```

Expected: failures for missing formats, `deferred3.fsh`, `deferred4.fsh`, and the
moved flip.

- [ ] **Step 3: Add exact material reference tests**

```python
def decode_lab_selector(value: int, albedo=(0.8, 0.6, 0.2)):
    if value <= 229:
        return (value / 255.0,) * 3, 1.0
    return albedo, 0.0

def decode_lab_emission(value: int) -> float:
    return 0.0 if value == 255 else value / 254.0

def decode_lab_aux(value: int):
    return (value / 64.0, 0.0) if value <= 64 else (0.0, (value - 65.0) / 190.0)

class LabPBRReferenceTests(unittest.TestCase):
    def test_selector_boundaries(self):
        self.assertEqual(decode_lab_selector(0), ((0.0, 0.0, 0.0), 1.0))
        self.assertEqual(decode_lab_selector(229), ((229 / 255.0,) * 3, 1.0))
        self.assertEqual(decode_lab_selector(230), ((0.8, 0.6, 0.2), 0.0))
        self.assertEqual(decode_lab_selector(255), ((0.8, 0.6, 0.2), 0.0))

    def test_emission_and_aux_boundaries(self):
        self.assertEqual((decode_lab_emission(0), decode_lab_emission(254), decode_lab_emission(255)), (0.0, 1.0, 0.0))
        self.assertEqual(decode_lab_aux(64), (1.0, 0.0))
        self.assertEqual(decode_lab_aux(65), (0.0, 0.0))
        self.assertEqual(decode_lab_aux(255), (0.0, 1.0))

    def test_recursive_gain_is_bounded(self):
        for confidence in (0.0, 0.25, 0.5, 1.0):
            self.assertLess(0.92 * confidence, 1.0)
```

- [ ] **Step 4: Run numeric tests**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -k LabPBR -v
```

Expected: numeric tests pass while schedule tests remain red.

## Task 2: Normalize The Opaque Material Contract

**Files:**

- Modify: `shaders/lib/material/core.glsl`
- Modify: `shaders/program/gbuffer/solid.fragment`
- Modify: `tests/test_opaque_recursive_ssr.py`

- [ ] **Step 1: Add failing source assertions**

```python
    def test_opaque_material_decoder_is_format_aware(self):
        core = read("shaders/lib/material/core.glsl")
        for token in ("struct OpaqueMaterial", "DecodeOpaqueMaterial",
                      "MC_TEXTURE_FORMAT_LAB_PBR", "ResolveOpaquePBR"):
            self.assertIn(token, core)

    def test_solid_packs_selector_and_material_ao(self):
        solid = read("shaders/program/gbuffer/solid.fragment")
        for token in ("normal_tex.b", "mat.specular_selector",
                      "mat.perceptual_roughness", "combined_ao"):
            self.assertIn(token, solid)
```

Run the suite and expect these assertions to fail.

- [ ] **Step 2: Add opaque-only material types**

Keep `Material` and `MaterialDefaults` unchanged for forward translucent code.
Add:

```glsl
struct OpaqueMaterial {
    float perceptual_roughness;
    float specular_selector;
    float emission;
    float auxiliary;
};

struct PBRMaterial {
    float perceptual_roughness;
    float alpha;
    vec3 f0;
    float diffuse_weight;
    float emission;
    float auxiliary;
};

float LabPBREmission(float encoded) {
    float value = floor(encoded * 255.0 + 0.5);
    return value >= 255.0 ? 0.0 : value / 254.0;
}

OpaqueMaterial DecodeOpaqueMaterial(vec4 spec) {
    OpaqueMaterial m;
    m.perceptual_roughness = 1.0 - spec.r;
    m.specular_selector = spec.g;
#ifdef MC_TEXTURE_FORMAT_LAB_PBR
    m.emission = LabPBREmission(spec.a);
    m.auxiliary = spec.b;
#else
    m.emission = spec.b;
    m.auxiliary = spec.a;
#endif
    return m;
}

PBRMaterial ResolveOpaquePBR(vec3 albedo, float roughness, float selector,
        float emission, float auxiliary) {
    PBRMaterial m;
    float selector_byte = floor(selector * 255.0 + 0.5);
    m.perceptual_roughness = roughness;
    m.alpha = max(roughness * roughness, 0.002);
#ifdef MC_TEXTURE_FORMAT_LAB_PBR
    bool metal = selector_byte >= 230.0;
    m.f0 = metal ? albedo : vec3(selector_byte / 255.0);
    m.diffuse_weight = metal ? 0.0 : 1.0;
#else
    m.f0 = mix(vec3(0.04), albedo, selector);
    m.diffuse_weight = 1.0 - selector;
#endif
    m.emission = emission;
    m.auxiliary = auxiliary;
    return m;
}
```

- [ ] **Step 3: Pack the normalized opaque G-buffer**

Sample the normal texture once, use B as material AO only for LabPBR, and write:

```glsl
OpaqueMaterial mat = DecodeOpaqueMaterial(spec_tex);
float combined_ao = min(v_color.a, material_ao);
gbuf2 = vec4(
    Pack2x8(w_normal.x * 0.5 + 0.5, combined_ao),
    Pack2x8(w_normal.y * 0.5 + 0.5, w_normal.z * 0.5 + 0.5),
    Pack2x8(mat.perceptual_roughness, mat.specular_selector),
    Pack2x8(mat.emission, mat.auxiliary));
```

Beacon and spider-eye emission overrides remain `1.0`.

- [ ] **Step 4: Run tests, inspect, and commit**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git diff -- shaders/lib/material/core.glsl shaders/program/gbuffer/solid.fragment
git add -- shaders/lib/material/core.glsl shaders/program/gbuffer/solid.fragment
git add -f -- tests/test_opaque_recursive_ssr.py
git commit -m "feat: normalize opaque PBR material data"
```

Expected: material tests pass; schedule tests remain red.

## Task 3: Allocate Transients And Reorder Deferred Passes

**Files:**

- Modify: `shaders/lib/contract/resources.glsl`
- Modify: `shaders/lib/contract/uniforms.glsl`
- Modify: `shaders/shaders.properties`
- Create: `shaders/program/deferred/opaque_reflection_trace.fragment`
- Create: `shaders/program/deferred/opaque_reflection_filter.fragment`
- Create/modify: `deferred2`, `deferred3`, and `deferred4` fragment/vertex wrappers under all three `shaders/world*` directories

- [ ] **Step 1: Declare transient formats and samplers**

```glsl
const int colortex3Format  = R11F_G11F_B10F;
const int colortex11Format = RG16F;
const bool colortex3Clear  = false;
const bool colortex11Clear = false;

uniform sampler2D colortex3;
uniform sampler2D colortex11;
```

Place formats/clear flags in `resources.glsl` and samplers in `uniforms.glsl`.

- [ ] **Step 2: Create compilable trace and filter shells**

Trace shell:

```glsl
/* RENDERTARGETS: 3,11 */
#include "/lib/contract/settings.glsl"
layout(location = 0) out vec3 out_reflection_radiance;
layout(location = 1) out vec2 out_reflection_metadata;
void main() {
    out_reflection_radiance = vec3(0.0);
    out_reflection_metadata = vec2(0.0);
}
```

Filter shell:

```glsl
/* RENDERTARGETS: 3,11 */
#include "/lib/contract/uniforms.glsl"
layout(location = 0) out vec3 out_reflection_radiance;
layout(location = 1) out vec2 out_reflection_metadata;
void main() {
    ivec2 tx = ivec2(gl_FragCoord.xy);
    out_reflection_radiance = texelFetch(colortex3, tx, 0).rgb;
    out_reflection_metadata = texelFetch(colortex11, tx, 0).rg;
}
```

- [ ] **Step 3: Rebuild all world wrappers**

Each `deferred2.fsh` defines its world, declares
`const bool colortex5MipmapEnabled = true;`, and includes the trace fragment.
Each `deferred3.fsh` includes the filter. Each `deferred4.fsh` includes the
existing shading fragment. Their vertex wrappers include
`/program/common/fullscreen.vertex`.

- [ ] **Step 4: Move the caustic flip and add enables**

```properties
flip.deferred4.colortex5 = false
flip.composite.colortex5 = true
flip.composite1.colortex5 = true
program.world0/deferred2.enabled = OPAQUE_SSR
program.world1/deferred2.enabled = OPAQUE_SSR
program.world-1/deferred2.enabled = OPAQUE_SSR
program.world0/deferred3.enabled = OPAQUE_SSR
program.world1/deferred3.enabled = OPAQUE_SSR
program.world-1/deferred3.enabled = OPAQUE_SSR
```

- [ ] **Step 5: Run tests and commit scheduling**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git add -- shaders/lib/contract/resources.glsl shaders/lib/contract/uniforms.glsl shaders/shaders.properties shaders/program/deferred shaders/world0 shaders/world1 shaders/world-1
git commit -m "feat: schedule opaque reflection passes"
```

Expected: schedule and resource tests pass.

## Task 4: Implement Deterministic Visible-GGX Sampling

**Files:**

- Create: `shaders/lib/raytrace/opaque_reflection.glsl`
- Modify: `shaders/program/deferred/opaque_reflection_trace.fragment`
- Modify: `tests/test_opaque_recursive_ssr.py`

- [ ] **Step 1: Add failing sampler assertions**

```python
    def test_opaque_sampler_contract(self):
        source = read("shaders/lib/raytrace/opaque_reflection.glsl")
        for token in ("OpaqueSSRRandom2", "SampleVisibleGGX",
                      "OpaqueReflectionDirection", "utex_stbn_scalar"):
            self.assertIn(token, source)
        self.assertNotIn("texture(colortex5", source)
```

Run the test and expect failure because the helper does not exist.

- [ ] **Step 2: Implement deterministic STBN sampling**

```glsl
vec2 OpaqueSSRRandom2(ivec2 tx) {
    ivec3 size = textureSize(utex_stbn_scalar, 0);
    ivec2 p0 = ivec2((tx.x % size.x + size.x) % size.x,
                     (tx.y % size.y + size.y) % size.y);
    int z = (frameCounter % size.z + size.z) % size.z;
    ivec2 p1 = (p0 + ivec2(47, 83)) % size.xy;
    float u0 = texelFetch(utex_stbn_scalar, ivec3(p0, z), 0).r;
    float u1 = texelFetch(utex_stbn_scalar,
        ivec3(p1, (z + 29) % size.z), 0).r;
    return clamp(vec2(u0, u1), vec2(1e-6), vec2(1.0 - 1e-6));
}
```

- [ ] **Step 3: Implement Dupuy-Heitz visible-GGX sampling**

Implement the spherical-cap sampler with finite square-root clamps:

```glsl
mat3 BuildOrthonormalBasis(vec3 N) {
    vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0)
        : vec3(1.0, 0.0, 0.0);
    vec3 T = normalize(cross(up, N));
    return mat3(T, cross(N, T), N);
}

vec3 SampleVisibleGGX(vec3 local_v, float alpha, vec2 u) {
    vec3 wi_std = normalize(vec3(local_v.xy * alpha, local_v.z));
    float phi = 2.0 * PI * u.x;
    float z = (1.0 - u.y) * (1.0 + wi_std.z) - wi_std.z;
    float sin_theta = sqrt(clamp(1.0 - z * z, 0.0, 1.0));
    vec3 cap = vec3(sin_theta * cos(phi), sin_theta * sin(phi), z);
    vec3 wm_std = cap + wi_std;
    return normalize(vec3(wm_std.xy * alpha, wm_std.z));
}
```

Expose one shared direction function:

```glsl
vec3 OpaqueReflectionDirection(vec3 N, vec3 V,
        float perceptual_roughness, ivec2 tx, out vec3 H) {
    float alpha = max(perceptual_roughness * perceptual_roughness, 0.002);
    mat3 frame = BuildOrthonormalBasis(N);
    vec3 local_v = transpose(frame) * V;
    vec3 local_h = SampleVisibleGGX(local_v, alpha, OpaqueSSRRandom2(tx));
    H = normalize(frame * local_h);
    vec3 L = normalize(reflect(-V, H));
    return dot(N, L) > 1e-5 ? L : vec3(0.0);
}
```

- [ ] **Step 4: Decode trace inputs and call the sampler**

The trace program includes uniforms, packing, coordinates, material, and the
new helper. It decodes depth, shading/geometric normals, roughness, position,
and view vector using the same TAA jitter convention as final shading. It calls
`OpaqueReflectionDirection` and writes zero confidence for sky or a direction
below the geometric normal.

- [ ] **Step 5: Test and commit sampling**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git add -- shaders/lib/raytrace/opaque_reflection.glsl shaders/program/deferred/opaque_reflection_trace.fragment
git add -f -- tests/test_opaque_recursive_ssr.py
git commit -m "feat: sample opaque visible GGX reflections"
```

## Task 5: Implement Current-Depth DDA And History Reprojection

**Files:**

- Modify: `shaders/lib/raytrace/opaque_reflection.glsl`
- Modify: `shaders/program/deferred/opaque_reflection_trace.fragment`
- Modify: `shaders/lib/contract/settings.glsl`
- Modify: `tests/test_opaque_recursive_ssr.py`

- [ ] **Step 1: Add failing traversal assertions**

```python
    def test_opaque_trace_has_required_rejection_terms(self):
        source = read("shaders/lib/raytrace/opaque_reflection.glsl")
        for token in ("TraceOpaqueReflection", "OPAQUE_SSR_MAX_DISTANCE",
                      "OPAQUE_SSR_THICKNESS", "ToPrevious",
                      "OpaqueHistoryMip", "OpaqueHistoryConfidence"):
            self.assertIn(token, source)
        self.assertIn("depthtex1", source)
```

- [ ] **Step 2: Add dedicated trace settings**

```glsl
#define OPAQUE_SSR
#define OPAQUE_SSR_STEPS 40
#define OPAQUE_SSR_REFINE_STEPS 6
#define OPAQUE_SSR_MAX_DISTANCE 96.0
#define OPAQUE_SSR_THICKNESS 0.35
#define OPAQUE_SSR_FILTER_RADIUS 6.0
#define OPAQUE_SSR_RECURSION_DECAY 0.92
```

Do not reuse water's `SSR_STEPS`.

- [ ] **Step 3: Implement perspective-correct pixel DDA**

Add the exact interface:

```glsl
struct OpaqueTraceHit {
    vec3 screen;
    float path_length;
    float thickness_error;
    bool valid;
};

OpaqueTraceHit TraceOpaqueReflection(vec3 view_origin,
    vec3 view_direction, float jitter);
```

The function clips a projected segment to viewport and maximum distance,
advances no more than `OPAQUE_SSR_STEPS` pixel-space samples, compares ray and
surface in linear view depth, and performs six bisection refinements. Reject
sky depth, out-of-bounds samples, back-facing hits, negative travel, and
crossings outside the distance-scaled thickness.

- [ ] **Step 4: Reproject accepted hits and sample history mip**

```glsl
vec3 previous_hit = ToPrevious(vec3(hit.screen.xy, hit_depth));
float cone_pixels = max(1.0, hit.path_length * roughness * roughness
    * viewHeight / max(-view_pos.z, 1.0));
float lod = clamp(log2(cone_pixels), 0.0,
    float(textureQueryLevels(colortex5) - 1));
vec3 history = textureLod(colortex5, previous_hit.xy, lod).rgb;
float confidence = OpaqueHistoryConfidence(hit, previous_hit,
    hit_geo_normal, ray_dir);
out_reflection_radiance = max(history, vec3(0.0));
out_reflection_metadata = vec2(hit.path_length, confidence);
```

Confidence is zero for `frameCounter < 2`, camera discontinuity, invalid
previous UV, non-finite history, screen edges, excessive distance, or poor
thickness agreement.

- [ ] **Step 5: Test water isolation and commit traversal**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git diff --exit-code f416ab56a6d6114f30793d9001f57943a5c443fd -- shaders/lib/raytrace/ssr.glsl
git add -- shaders/lib/raytrace/opaque_reflection.glsl shaders/program/deferred/opaque_reflection_trace.fragment shaders/lib/contract/settings.glsl
git commit -m "feat: trace recursive opaque SSR history"
```

Expected: all tests pass and water SSR has no diff.

## Task 6: Implement Nine-Tap Reflection Filtering

**Files:**

- Modify: `shaders/program/deferred/opaque_reflection_filter.fragment`
- Modify: `tests/test_opaque_recursive_ssr.py`

- [ ] **Step 1: Add failing filter assertions**

```python
    def test_filter_uses_all_guidance_terms(self):
        source = read("shaders/program/deferred/opaque_reflection_filter.fragment")
        for token in ("FILTER_TAPS", "depth_weight", "normal_weight",
                      "roughness_weight", "distance_weight", "confidence"):
            self.assertIn(token, source)
        self.assertIn("const int FILTER_TAPS = 9", source)
```

- [ ] **Step 2: Implement the full-resolution gather**

Use center, cardinal, and diagonal taps:

```glsl
const int FILTER_TAPS = 9;
const vec2 FILTER_OFFSETS[FILTER_TAPS] = vec2[](
    vec2(0.0), vec2(1.0, 0.0), vec2(-1.0, 0.0),
    vec2(0.0, 1.0), vec2(0.0, -1.0),
    vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071),
    vec2(0.7071, -0.7071), vec2(-0.7071, -0.7071));
```

Radius is zero below perceptual roughness `0.08` and grows with roughness
squared and hit distance to `OPAQUE_SSR_FILTER_RADIUS`. Each tap multiplies
spatial, linear-depth, geometric-normal, shading-normal, roughness,
hit-distance, and source-confidence weights. Coordinates are explicitly
clamped.

- [ ] **Step 3: Normalize outputs safely**

```glsl
if (radiance_weight > 1e-5) {
    out_reflection_radiance = radiance_sum / radiance_weight;
    out_reflection_metadata = vec2(distance_sum / radiance_weight,
        clamp(confidence_sum / max(geometry_weight, 1e-5), 0.0, 1.0));
} else {
    out_reflection_radiance = vec3(0.0);
    out_reflection_metadata = vec2(center_distance, 0.0);
}
```

- [ ] **Step 4: Test and commit the filter**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git add -- shaders/program/deferred/opaque_reflection_filter.fragment
git add -f -- tests/test_opaque_recursive_ssr.py
git commit -m "feat: filter opaque SSR hit radiance"
```

## Task 7: Unify Opaque PBR Integration In Deferred4

**Files:**

- Modify: `shaders/lib/lighting/brdf.glsl`
- Modify: `shaders/program/deferred/deferred_shading.fragment`
- Modify: `tests/test_opaque_recursive_ssr.py`

- [ ] **Step 1: Add failing BRDF ownership assertions**

```python
    def test_final_shading_owns_pbr_integration(self):
        source = read("shaders/program/deferred/deferred_shading.fragment")
        for token in ("ResolveOpaquePBR", "colortex3", "colortex11",
                      "OpaqueReflectionDirection", "VisibleGGXThroughput",
                      "OPAQUE_SSR_RECURSION_DECAY"):
            self.assertIn(token, source)
        self.assertNotIn("emiss_res.x * 0.0", source)

    def test_brdf_consumes_rgb_f0(self):
        source = read("shaders/lib/lighting/brdf.glsl")
        self.assertIn("vec3 f0, float diffuse_weight", source)
        self.assertIn("VisibleGGXThroughput", source)
```

- [ ] **Step 2: Add F0-explicit opaque BRDF overloads**

```glsl
vec3 EvaluateDiffuseReflectance(vec3 albedo, vec3 f0,
        float diffuse_weight) {
    return albedo * (vec3(1.0) - f0) * diffuse_weight;
}

vec3 EvaluateDirectBRDF(vec3 albedo, vec3 f0, float diffuse_weight,
        float roughness, float ndotv, float ndotl, float ndoth,
        float vdoth, float ldoth) {
    float alpha = max(roughness * roughness, 0.002);
    vec3 F = FresnelSchlick(vdoth, f0);
    vec3 diffuse = albedo * (vec3(1.0) - F) * diffuse_weight
        * DiffuseBurley(ndotv, ndotl, ldoth, roughness);
    return diffuse + F * DistributionGGX(ndoth, alpha)
        * VisibilitySmithGGXCorrelated(ndotv, ndotl, alpha)
        * step(1e-5, ndotv);
}
```

Keep legacy scalar-metalness wrappers for forward water/glass compilation.

- [ ] **Step 3: Implement visible-GGX throughput**

Define matching Smith terms and specular occlusion in `brdf.glsl`:

```glsl
float SmithGGXLambda(float ndotx, float alpha) {
    float a2 = alpha * alpha;
    return 0.5 * (-1.0 + sqrt(1.0 + a2
        * (1.0 - ndotx * ndotx) / max(ndotx * ndotx, 1e-6)));
}

float SmithGGXG1(float ndotv, float alpha) {
    return 1.0 / (1.0 + SmithGGXLambda(ndotv, alpha));
}

float SmithGGXG2Correlated(float ndotv, float ndotl, float alpha) {
    return 1.0 / (1.0 + SmithGGXLambda(ndotv, alpha)
        + SmithGGXLambda(ndotl, alpha));
}

float SpecularOcclusion(float ndotv, float ao, float roughness) {
    float exponent = exp2(-16.0 * roughness - 1.0);
    return clamp(pow(ndotv + ao, exponent) - 1.0 + ao, 0.0, 1.0);
}
```

```glsl
vec3 VisibleGGXThroughput(vec3 f0, float vdoth, float ndotv,
        float ndotl, float alpha) {
    if (ndotv <= 0.0 || ndotl <= 0.0 || vdoth <= 0.0) return vec3(0.0);
    float ratio = clamp(SmithGGXG2Correlated(ndotv, ndotl, alpha)
        / max(SmithGGXG1(ndotv, alpha), 1e-5), 0.0, 1.0);
    return FresnelSchlick(vdoth, f0) * ratio;
}
```

- [ ] **Step 4: Integrate material, environment, and filtered history once**

Include `sky_lut.glsl` and `exposure_data.glsl` in final shading. Define the
fallback and sanitizer there so the raytrace helper remains independent of the
lighting and exposure contracts:

```glsl
vec3 SampleOpaqueEnvironment(vec3 direction, float sky_light) {
    return SkyLightFromLm(sky_light)
        * texture(usam_skylut_cloud, CloudSkyboxUV(direction)).rgb;
}

vec3 SanitizeOpaqueHistory(vec3 history, float average_luminance) {
    if (any(isnan(history)) || any(isinf(history))
            || any(lessThan(history, vec3(0.0)))) return vec3(0.0);
    float luminance = dot(history, vec3(0.2126, 0.7152, 0.0722));
    float ceiling = max(16.0, average_luminance * 64.0);
    return history * min(1.0, ceiling / max(luminance, 1e-5));
}
```

```glsl
PBRMaterial material = ResolveOpaquePBR(albedo, rough_selector.x,
    rough_selector.y, emission_aux.x, emission_aux.y);
vec3 H;
vec3 reflection_dir = OpaqueReflectionDirection(normal, V,
    material.perceptual_roughness, tx, H);
vec3 environment = SampleOpaqueEnvironment(reflection_dir, lm.g);
vec3 history = SanitizeOpaqueHistory(texelFetch(colortex3, tx, 0).rgb,
    smooth_lum);
float confidence = clamp(texelFetch(colortex11, tx, 0).g, 0.0, 1.0);
vec3 Li = mix(environment,
    OPAQUE_SSR_RECURSION_DECAY * history, confidence);
vec3 throughput = VisibleGGXThroughput(material.f0,
    Max0(dot(V, H)), ndotv, Max0(dot(normal, reflection_dir)), material.alpha);
color += Li * throughput * SpecularOcclusion(ndotv,
    dot(ao_effective, vec3(1.0 / 3.0)), material.perceptual_roughness);
color += albedo * material.emission * OPAQUE_PBR_EMISSION_SCALE;
```

Quality zero uses confidence zero and still evaluates environment specular.
Retain `RENDERTARGETS: 0,2,5`, sky output, `out_gbuf_clear`, and the caustic
`out_direct_brdf` output.

- [ ] **Step 5: Test and commit unified PBR**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git add -- shaders/lib/lighting/brdf.glsl shaders/program/deferred/deferred_shading.fragment
git add -f -- tests/test_opaque_recursive_ssr.py
git commit -m "feat: integrate opaque recursive SSR PBR"
```

## Task 8: Add Profiles, Public Settings, And Debug Views

**Files:**

- Modify: `shaders/lib/contract/settings.glsl`
- Modify: `shaders/shaders.properties`
- Modify: `shaders/lang/en_us.lang`
- Modify: `shaders/lang/zh_cn.lang`
- Modify: new trace/filter and moved shading fragments
- Modify: `tests/test_opaque_recursive_ssr.py`

- [ ] **Step 1: Add failing profile and language tests**

Assert LOW/MEDIUM/HIGH/ULTRA select quality 0/1/2/3, both language files have
labels, and the lighting screen contains `OPAQUE_SSR_QUALITY`.

- [ ] **Step 2: Derive internal constants from one public option**

```glsl
#define OPAQUE_SSR_QUALITY 2 // [0 1 2 3]
#if OPAQUE_SSR_QUALITY > 0
#define OPAQUE_SSR
#endif
#if OPAQUE_SSR_QUALITY == 1
#define OPAQUE_SSR_STEPS 24
#define OPAQUE_SSR_FILTER_RADIUS 4.0
#elif OPAQUE_SSR_QUALITY == 2
#define OPAQUE_SSR_STEPS 40
#define OPAQUE_SSR_FILTER_RADIUS 6.0
#elif OPAQUE_SSR_QUALITY == 3
#define OPAQUE_SSR_STEPS 64
#define OPAQUE_SSR_FILTER_RADIUS 8.0
#endif
```

Profiles set the four values in order. Keep refinement, max distance,
thickness, recursion decay, and emission scale internal.

- [ ] **Step 3: Add internal debug outputs**

`OPAQUE_SSR_DEBUG` defaults to zero and selects raw radiance, confidence, hit
distance, selected mip, filtered radiance, F0, roughness, or final indirect
specular. It is not added to the public screen.

- [ ] **Step 4: Add language labels**

```properties
option.OPAQUE_SSR_QUALITY=Opaque Reflection Quality
option.OPAQUE_SSR_QUALITY.comment=Screen-space indirect specular quality for opaque PBR materials
value.OPAQUE_SSR_QUALITY.0=Environment Only
value.OPAQUE_SSR_QUALITY.1=Medium
value.OPAQUE_SSR_QUALITY.2=High
value.OPAQUE_SSR_QUALITY.3=Ultra
```

Chinese labels use `不透明反射质量`, `仅环境`, `中`, `高`, and `极高`.

- [ ] **Step 5: Test and commit settings**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git add -- shaders/lib/contract/settings.glsl shaders/shaders.properties shaders/lang/en_us.lang shaders/lang/zh_cn.lang shaders/program/deferred shaders/lib/raytrace/opaque_reflection.glsl
git add -f -- tests/test_opaque_recursive_ssr.py
git commit -m "feat: expose opaque SSR quality controls"
```

## Task 9: Iris Compile And Runtime Debug Loop

**Files:**

- Modify only files implicated by concrete compile or runtime failures
- Generated: `.vibris/`, patched shaders, screenshots, and logs remain ignored

- [ ] **Step 1: Run the complete static gate**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git status --short
```

Expected: all tests pass, no whitespace errors, and a clean source tree.

- [ ] **Step 2: Capture the environment-only runtime baseline**

```powershell
node tools/vibris_preset_screenshot_gputrace.mjs --preset scene1 --config-values '{"OPAQUE_SSR_QUALITY":0}' --no-gputrace
```

Expected: Iris reload succeeds without a compile error and returns a screenshot.

- [ ] **Step 3: Compile and capture HIGH plus debug modes**

Run quality 2 normally, then capture raw radiance, confidence, hit distance,
filtered radiance, F0, and final indirect specular modes. Inspect screenshots
with `view_image`. Sky must be blank in hit buffers, edges must fade, polished
detail must remain sharp, and rough reflections must broaden without crossing
depth or normal edges.

- [ ] **Step 4: Fix compile and rendering failures from evidence**

Read exact Iris patched `deferred2`, `deferred3`, or `deferred4` errors. Make the
smallest source correction, add a regression assertion, rerun static tests, and
reload. Do not suppress a pass or alter water SSR to hide a failure.

- [ ] **Step 5: Run regression scenes**

Capture water, glass, underwater caustics, foliage, emission, mirror pairs,
screen edges, camera motion, teleport, reload, resize, rain, and all three
dimensions. Compare quality zero, raw trace, filtered trace, and final output.

- [ ] **Step 6: Commit runtime fixes when present**

```powershell
git add -- shaders
git add -f -- tests/test_opaque_recursive_ssr.py
git commit -m "fix: stabilize opaque recursive SSR runtime"
```

Skip only when runtime validation required no source changes.

## Task 10: GPU Trace And Performance Tuning

**Files:**

- Modify only measured settings or shader bottlenecks
- Update: `docs/reasonix/specs/2026-08-25-opaque-recursive-ssr-pbr-design.md`
- Generated: `.vibris/nsight-output/` remains ignored

- [ ] **Step 1: Dry-run the Nsight command**

```powershell
node tools/vibris_preset_screenshot_gputrace.mjs --preset scene1 --gputrace --frames 240 --duration-ms 5000 --limit-frames 120 --no-auto-export --dry-run
```

Expected: the command resolves Java, the Minecraft classpath, `ngfx.exe`, the
current worktree, and an output directory.

- [ ] **Step 2: Capture quality-zero baseline**

```powershell
node tools/vibris_preset_screenshot_gputrace.mjs --preset scene1 --config-values '{"OPAQUE_SSR_QUALITY":0}' --gputrace --frames 240 --duration-ms 5000 --limit-frames 120 --no-auto-export
```

Record total frame and `deferred4` time after the fixed warm-up.

- [ ] **Step 3: Capture MEDIUM, HIGH, and ULTRA**

Repeat with values 1, 2, and 3. Record trace, filter, final shading, total
deferred interval, total frame, GPU, resolution, preset, and artifact path.

- [ ] **Step 4: Tune only measured bottlenecks**

Traversal cost is addressed by step count or max distance. Filter cost is
addressed by profile radius or tap branch. Shading cost is addressed by
eliminating duplicated environment or VNDF work. Hi-Z, a second filter pass,
and dedicated history remain excluded until baseline measurements justify them.

- [ ] **Step 5: Recapture and document measured results**

Repeat the changed profile trace. Add exact before/after milliseconds and
artifact names to the design document. Do not commit binary captures.

- [ ] **Step 6: Commit performance changes and results**

```powershell
git add -- shaders
git add -f -- docs/reasonix/specs/2026-08-25-opaque-recursive-ssr-pbr-design.md tests/test_opaque_recursive_ssr.py
git commit -m "perf: tune opaque recursive SSR"
```

## Task 11: Final Verification And Rollback Audit

**Files:**

- Modify only defects found by final verification

- [ ] **Step 1: Run static verification from a clean prompt**

```powershell
python -m unittest discover -s tests -p "test_opaque_recursive_ssr.py" -v
git diff --check
git status --short
git log --oneline --decorate -12
```

Expected: tests pass, worktree is clean, and commits remain separated by
responsibility.

- [ ] **Step 2: Verify rollback references**

```powershell
git rev-parse main
git rev-parse v0.1.0-alpha
git merge-base main codex/opaque-recursive-ssr-pbr
```

Expected: every command reports
`f416ab56a6d6114f30793d9001f57943a5c443fd`.

- [ ] **Step 3: Perform final Iris captures**

Capture quality zero and the accepted quality after a fresh reload. Inspect
screenshots and logs. Confirm recursive opaque reflection, environment miss,
water/glass stability, caustics, emission, material decode, and all dimensions.

- [ ] **Step 4: Report the measured outcome**

Report final commit, tests, Iris compile result, screenshot and trace paths,
per-pass cost, total frame delta, DOF/entity-motion limitations, and the exact
rollback commit.
