from pathlib import Path
import math
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def spatial_radius(roughness, distance, limit):
    return min(
        limit,
        roughness * roughness * (1.0 + 0.5 * (max(distance, 0.0) ** 0.5)),
    )


def source_mix_weight(center_environment, sample_environment):
    return 1.0


def normalize(weights):
    total = sum(weights)
    return [w / total for w in weights] if total > 1e-6 else []


def stage_candidate_count(tap_radius, stages=3):
    return stages * (2 * tap_radius + 1) ** 2


def spatial_kernel_weight(x, y, radius):
    center = 2.0 if radius == 1 else 6.0
    adjacent = 1.0 if radius == 1 else 4.0

    def axis_weight(value):
        value = abs(value)
        return center if value == 0 else adjacent if value == 1 else 1.0

    return axis_weight(x) * axis_weight(y) / (center * center)


class OpaqueReflectionSpatialFilterContractTests(unittest.TestCase):
    WORLDS = ("world0", "world1", "world-1")
    WORLD_DEFINES = {
        "world0": "WORLD_OVERWORLD",
        "world1": "WORLD_END",
        "world-1": "WORLD_NETHER",
    }

    def test_spatial_pass_schedule_has_three_ping_pong_stages(self):
        properties = read("shaders/shaders.properties")
        for world in self.WORLDS:
            self.assertIn(f"program.{world}/deferred2.enabled", properties)
            for stage in (3, 4, 5):
                self.assertRegex(
                    properties,
                    rf"program\.{re.escape(world)}/deferred{stage}\.enabled\s*=\s*true",
                )
            self.assertRegex(
                properties,
                rf"program\.{re.escape(world)}/deferred6\.enabled\s*=\s*true",
            )
            for stage in (3, 4, 5):
                source = read(f"shaders/{world}/deferred{stage}.csh")
                self.assertIn(self.WORLD_DEFINES[world], source)
                self.assertIn("opaque_reflection_spatial_filter.compute", source)
                self.assertIn(f"#define OPAQUE_SPATIAL_STAGE {stage - 3}", source)
            shading = read(f"shaders/{world}/deferred6.fsh")
            self.assertIn("deferred_shading.fragment", shading)
            self.assertFalse(
                (ROOT / f"shaders/{world}/deferred4.fsh").exists()
            )
        self.assertIn("flip.deferred6.colortex5 = false", properties)
        self.assertNotIn("flip.deferred4.colortex5 = false", properties)

    def test_spatial_scratch_resources_are_transient(self):
        resources = read("shaders/lib/contract/resources.glsl")
        uniforms = read("shaders/lib/contract/uniforms.glsl")
        self.assertIn("const int colortex6Format  = R11F_G11F_B10F;", resources)
        self.assertIn("const int colortex7Format  = RG16F;", resources)
        self.assertRegex(resources, r"const bool colortex6Clear\s*=\s*true")
        self.assertRegex(resources, r"const bool colortex7Clear\s*=\s*true")
        self.assertRegex(uniforms, r"uniform sampler2D colortex6\s*;")
        self.assertRegex(uniforms, r"uniform sampler2D colortex7\s*;")

    def test_quality_branches_select_spatial_tap_radius(self):
        settings = read("shaders/lib/contract/settings.glsl")
        self.assertRegex(settings, r"#define OPAQUE_SSR_SPATIAL_TAP_RADIUS 1")
        self.assertRegex(settings, r"#define OPAQUE_SSR_SPATIAL_TAP_RADIUS 2")

    def test_spatial_filter_is_exposed_and_defaults_enabled(self):
        settings = read("shaders/lib/contract/settings.glsl")
        self.assertRegex(settings, r"(?m)^#define OPAQUE_SSR_SPATIAL_FILTER\s*$")

        properties = read("shaders/shaders.properties")
        lighting_line = next(
            line
            for line in properties.splitlines()
            if line.startswith("screen.LIGHTING =")
        )
        self.assertIn("OPAQUE_SSR_SPATIAL_FILTER", lighting_line)

        english = read("shaders/lang/en_us.lang")
        chinese = read("shaders/lang/zh_cn.lang")
        for token in (
            "option.OPAQUE_SSR_SPATIAL_FILTER",
            "option.OPAQUE_SSR_SPATIAL_FILTER.comment",
        ):
            self.assertIn(token, english)
            self.assertIn(token, chinese)

    def test_spatial_filter_switch_controls_passes_and_shading_source(self):
        properties = read("shaders/shaders.properties")
        self.assertIn("#if OPAQUE_SSR_SPATIAL_FILTER", properties)
        spatial_switch = properties.split("#if OPAQUE_SSR_SPATIAL_FILTER", 1)[1]
        spatial_block, no_spatial_block = spatial_switch.split("#else", 1)
        no_spatial_block = no_spatial_block.split("#endif", 1)[0]
        for world in self.WORLDS:
            for stage in (3, 4, 5):
                self.assertRegex(
                    spatial_block,
                    rf"program\.{re.escape(world)}/deferred{stage}\.enabled\s*=\s*true",
                )
        for world in self.WORLDS:
            for stage in (3, 4, 5):
                self.assertRegex(
                    no_spatial_block,
                    rf"program\.{re.escape(world)}/deferred{stage}\.enabled\s*=\s*false",
                )

        shading = read("shaders/program/deferred/deferred_shading.fragment")
        history_region = re.search(
            r"#ifdef OPAQUE_SSR\s*\n"
            r"(?P<body>.*?)"
            r"\n#endif\s*\n"
            r"\s*float recursion_decay",
            shading,
            re.DOTALL,
        )
        self.assertIsNotNone(history_region)
        body = history_region.group("body")
        self.assertIn("#ifdef OPAQUE_SSR_SPATIAL_FILTER", body)
        filtered = body.split("#ifdef OPAQUE_SSR_SPATIAL_FILTER", 1)[1]
        filtered, unfiltered = filtered.split("#else", 1)
        unfiltered = unfiltered.split("#endif", 1)[0]
        self.assertIn("texelFetch(colortex6", filtered)
        self.assertIn("texelFetch(colortex7", filtered)
        self.assertIn("texelFetch(colortex3", unfiltered)
        self.assertIn("texelFetch(colortex11", unfiltered)

    def test_compute_pass_uses_shared_tiles_and_disjoint_bindings(self):
        source = read("shaders/program/deferred/opaque_reflection_spatial_filter.compute")
        for token in (
            "layout(local_size_x",
            "shared vec4 tile_radiance",
            "shared vec4 tile_metadata",
            "shared vec4 tile_surface",
            "shared vec4 tile_geometry",
            "barrier()",
            "imageLoad",
            "imageStore",
            "OPAQUE_SPATIAL_STAGE",
            "const vec2 workGroupsRender = vec2(1.0, 1.0);",
        ):
            self.assertIn(token, source)
        for token in ("dFdx", "dFdy", "gl_FragCoord", "layout(location"):
            self.assertNotIn(token, source)
        self.assertRegex(source, r"#define SRC_RADIANCE\s+colorimg3")
        self.assertRegex(source, r"#define DST_RADIANCE\s+colorimg6")
        self.assertRegex(source, r"#define SRC_RADIANCE\s+colorimg6")
        self.assertRegex(source, r"#define DST_RADIANCE\s+colorimg3")
        self.assertNotRegex(
            source,
            r"#define SRC_RADIANCE\s+(\w+).*?#define DST_RADIANCE\s+\1",
        )

    def test_filter_helpers_have_material_aware_contract(self):
        helpers = read("shaders/lib/lighting/opaque_reflection_filter.glsl")
        for token in (
            "OpaqueSpatialRadius",
            "OpaqueSpatialStride",
            "OpaqueSpatialWeight",
            "depth_weight",
            "normal_weight",
            "roughness_weight",
            "distance_weight",
        ):
            self.assertIn(token, helpers)

    def test_spatial_filter_has_no_temporal_or_svgf_path(self):
        sources = (
            read("shaders/lib/lighting/opaque_reflection_filter.glsl"),
            read("shaders/program/deferred/opaque_reflection_spatial_filter.compute"),
        )
        for source in sources:
            for token in ("SVGF", "temporal", "history_length"):
                self.assertNotIn(token, source)

    def test_filter_support_is_adaptive_and_coarse_to_fine(self):
        compute = read("shaders/program/deferred/opaque_reflection_spatial_filter.compute")
        self.assertIn("tap_radius", compute)
        self.assertIn("SPATIAL_STRIDE", compute)
        self.assertEqual(stage_candidate_count(1), 27)
        self.assertEqual(stage_candidate_count(2), 75)

    def test_filter_uses_a_full_square_kernel_without_diamond_cutoff(self):
        compute = read("shaders/program/deferred/opaque_reflection_spatial_filter.compute")
        helpers = read("shaders/lib/lighting/opaque_reflection_filter.glsl")

        self.assertNotIn("length(vec2(tap))", compute)
        self.assertNotRegex(
            compute,
            r"tap_distance\s*>\s*tap_radius",
        )
        self.assertIn("OpaqueSpatialKernelWeight", helpers)
        self.assertIn("kernel_weight", compute)

    def test_spatial_kernel_is_normalized_and_tapered(self):
        helpers = read("shaders/lib/lighting/opaque_reflection_filter.glsl")
        self.assertIn("center_weight * center_weight", helpers)

        center = spatial_kernel_weight(0, 0, 2)
        adjacent = spatial_kernel_weight(1, 0, 2)
        corner = spatial_kernel_weight(2, 2, 2)
        self.assertEqual(center, 1.0)
        self.assertGreater(adjacent, corner)
        self.assertGreater(corner, 0.0)

    def test_filter_mixes_geometry_and_environment_radiance(self):
        compute = read("shaders/program/deferred/opaque_reflection_spatial_filter.compute")

        for token in (
            "radiance_sum",
            "distance_magnitude_sum",
            "source_sign_sum",
            "sample_environment ? -1.0 : 1.0",
        ):
            self.assertIn(token, compute)
        self.assertNotIn("geometry_radiance", compute)
        self.assertNotIn("environment_radiance", compute)

        helpers = read("shaders/lib/lighting/opaque_reflection_filter.glsl")
        self.assertNotIn("center_environment == sample_environment", helpers)

    def test_valid_reflections_keep_a_minimum_neighborhood(self):
        helpers = read("shaders/lib/lighting/opaque_reflection_filter.glsl")
        self.assertRegex(
            helpers,
            r"return min\(float\(OPAQUE_SSR_FILTER_RADIUS\),\s*"
            r"max\(0\.5,\s*support\)\)",
        )

        compute = read("shaders/program/deferred/opaque_reflection_spatial_filter.compute")
        self.assertIn("ceil(center_radius", compute)
        self.assertRegex(
            compute,
            r"float tap_radius\s*=\s*max\(1\.0,\s*ceil\(",
        )

    def test_invalid_center_can_pull_valid_neighbor_radiance(self):
        helpers = read("shaders/lib/lighting/opaque_reflection_filter.glsl")
        self.assertIn("center_distance <= 0.0", helpers)

        compute = read("shaders/program/deferred/opaque_reflection_spatial_filter.compute")
        self.assertIn("center_surface_valid", compute)
        self.assertIn("center_source_known", compute)
        self.assertRegex(compute, r"if \(center_surface_valid\) \{")
        self.assertNotRegex(
            compute,
            r"if \(center_valid\) \{\s*\n\s*float center_radius",
        )

    def test_filter_preserves_environment_source_class(self):
        compute = read("shaders/program/deferred/opaque_reflection_spatial_filter.compute")
        self.assertIn("metadata.x < 0.0", compute)
        self.assertIn("sample_metadata.w > 0.5", compute)
        self.assertIn("abs(center_distance)", compute)
        self.assertIn("center_source_known", compute)
        self.assertRegex(
            compute,
            r"output_sign\s*=\s*center_source_known\s*\?\s*"
            r"sign\(center_distance\)",
        )

    def test_spatial_radius_is_bounded(self):
        self.assertEqual(spatial_radius(0.2, 4.0, 6.0), 0.2**2 * 2.0)
        self.assertEqual(spatial_radius(1.0, 1000.0, 6.0), 6.0)

    def test_source_classes_can_cross_filter(self):
        self.assertEqual(source_mix_weight(True, False), 1.0)
        self.assertEqual(source_mix_weight(False, True), 1.0)
        self.assertEqual(source_mix_weight(True, True), 1.0)

    def test_normalized_weights_sum_to_one(self):
        weights = normalize([0.5, 1.0, 1.5])
        self.assertAlmostEqual(sum(weights), 1.0)
        self.assertEqual(normalize([0.0, 0.0]), [])

    def test_zero_confidence_tap_cannot_increase_radiance(self):
        radiance = [2.0, 4.0]
        confidence = [1.0, 0.0]
        weights = [0.75, 0.25]
        effective = normalize([w * c for w, c in zip(weights, confidence)])
        result = sum(value * weight for value, weight in zip(radiance, effective))
        self.assertEqual(result, radiance[0])
        self.assertTrue(math.isfinite(result))


if __name__ == "__main__":
    unittest.main()
