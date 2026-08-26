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


def source_weight(center_environment, sample_environment):
    return 1.0 if center_environment == sample_environment else 0.0


def normalize(weights):
    total = sum(weights)
    return [w / total for w in weights] if total > 1e-6 else []


class OpaqueReflectionSpatialFilterContractTests(unittest.TestCase):
    WORLDS = ("world0", "world1", "world-1")

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
                self.assertIn("opaque_reflection_spatial_filter.compute", source)
                self.assertIn(f"#define OPAQUE_SPATIAL_STAGE {stage - 3}", source)
            shading = read(f"shaders/{world}/deferred6.fsh")
            self.assertIn("deferred_shading.fragment", shading)
            self.assertNotIn("deferred_shading.fragment", read(f"shaders/{world}/deferred4.fsh"))
        self.assertIn("flip.deferred6.colortex5 = false", properties)
        self.assertNotIn("flip.deferred4.colortex5 = false", properties)

    def test_spatial_scratch_resources_are_transient(self):
        resources = read("shaders/lib/contract/resources.glsl")
        uniforms = read("shaders/lib/contract/uniforms.glsl")
        self.assertIn("const int colortex6Format  = R11F_G11F_B10F;", resources)
        self.assertIn("const int colortex7Format  = RG16F;", resources)
        self.assertIn("const bool colortex6Clear = true", resources)
        self.assertIn("const bool colortex7Clear = true", resources)
        self.assertRegex(uniforms, r"uniform sampler2D colortex6\s*;")
        self.assertRegex(uniforms, r"uniform sampler2D colortex7\s*;")

    def test_quality_branches_select_spatial_tap_radius(self):
        settings = read("shaders/lib/contract/settings.glsl")
        self.assertRegex(settings, r"#define OPAQUE_SSR_SPATIAL_TAP_RADIUS 1")
        self.assertRegex(settings, r"#define OPAQUE_SSR_SPATIAL_TAP_RADIUS 2")

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
            "source_weight",
        ):
            self.assertIn(token, helpers)

    def test_spatial_radius_is_bounded(self):
        self.assertEqual(spatial_radius(0.2, 4.0, 6.0), 0.2**2 * 2.0)
        self.assertEqual(spatial_radius(1.0, 1000.0, 6.0), 6.0)

    def test_source_classes_do_not_cross_filter(self):
        self.assertEqual(source_weight(True, False), 0.0)
        self.assertEqual(source_weight(False, True), 0.0)
        self.assertEqual(source_weight(True, True), 1.0)

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
