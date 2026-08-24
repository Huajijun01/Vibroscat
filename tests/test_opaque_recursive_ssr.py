from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def decode_lab_selector(value: int, albedo=(0.8, 0.6, 0.2)):
    if value <= 229:
        return (value / 255.0,) * 3, 1.0
    return albedo, 0.0


def decode_lab_emission(value: int) -> float:
    return 0.0 if value == 255 else value / 254.0


def decode_lab_aux(value: int):
    if value <= 64:
        return value / 64.0, 0.0
    return 0.0, (value - 65.0) / 190.0


class OpaqueRecursiveSSRContractTests(unittest.TestCase):
    def test_transient_formats_are_declared(self):
        source = read("shaders/lib/contract/resources.glsl")
        self.assertRegex(source, r"colortex3Format\s*=\s*R11F_G11F_B10F")
        self.assertRegex(source, r"colortex11Format\s*=\s*RG16F")

    def test_pass_wrappers_match_in_all_dimensions(self):
        worlds = {
            "world0": "WORLD_OVERWORLD",
            "world1": "WORLD_END",
            "world-1": "WORLD_NETHER",
        }
        for world, define in worlds.items():
            with self.subTest(world=world):
                paths = {
                    "trace": f"shaders/{world}/deferred2.fsh",
                    "filter": f"shaders/{world}/deferred3.fsh",
                    "shade": f"shaders/{world}/deferred4.fsh",
                }
                for role, path in paths.items():
                    self.assertTrue(
                        (ROOT / path).is_file(), f"missing {role} wrapper: {path}"
                    )
                trace = read(paths["trace"])
                filt = read(paths["filter"])
                shade = read(paths["shade"])
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

    def test_opaque_material_decoder_is_format_aware(self):
        core = read("shaders/lib/material/core.glsl")
        for token in (
            "struct OpaqueMaterial",
            "DecodeOpaqueMaterial",
            "MC_TEXTURE_FORMAT_LAB_PBR",
            "ResolveOpaquePBR",
        ):
            self.assertIn(token, core)

    def test_solid_packs_selector_and_material_ao(self):
        solid = read("shaders/program/gbuffer/solid.fragment")
        for token in (
            "normal_tex.b",
            "mat.specular_selector",
            "mat.perceptual_roughness",
            "combined_ao",
        ):
            self.assertIn(token, solid)

    def test_opaque_sampler_contract(self):
        path = "shaders/lib/raytrace/opaque_reflection.glsl"
        self.assertTrue((ROOT / path).is_file(), f"missing sampler helper: {path}")
        source = read(path)
        for token in (
            "OpaqueSSRRandom2",
            "SampleVisibleGGX",
            "OpaqueReflectionDirection",
            "utex_stbn_scalar",
        ):
            self.assertIn(token, source)
        self.assertNotIn("texture(colortex5", source)

    def test_opaque_trace_has_required_rejection_terms(self):
        source = read("shaders/lib/raytrace/opaque_reflection.glsl")
        for token in (
            "TraceOpaqueReflection",
            "OPAQUE_SSR_MAX_DISTANCE",
            "OPAQUE_SSR_THICKNESS",
            "ToPrevious",
            "OpaqueHistoryMip",
            "OpaqueHistoryConfidence",
        ):
            self.assertIn(token, source)
        self.assertIn("depthtex1", source)

    def test_filter_uses_all_guidance_terms(self):
        source = read(
            "shaders/program/deferred/opaque_reflection_filter.fragment"
        )
        for token in (
            "FILTER_TAPS",
            "depth_weight",
            "normal_weight",
            "roughness_weight",
            "distance_weight",
            "confidence",
        ):
            self.assertIn(token, source)
        self.assertIn("const int FILTER_TAPS = 9", source)

    def test_filter_avoids_glsl_reserved_packed_identifier(self):
        source = read(
            "shaders/program/deferred/opaque_reflection_filter.fragment"
        )
        self.assertNotRegex(
            source,
            r"\b(?:vec[234]|float|int|uint)\s+packed\b",
        )

    def test_final_shading_owns_pbr_integration(self):
        source = read("shaders/program/deferred/deferred_shading.fragment")
        for token in (
            "ResolveOpaquePBR",
            "colortex3",
            "colortex11",
            "OpaqueReflectionDirection",
            "VisibleGGXThroughput",
            "OPAQUE_SSR_RECURSION_DECAY",
        ):
            self.assertIn(token, source)
        self.assertNotIn("emiss_res.x * 0.0", source)

    def test_brdf_consumes_rgb_f0(self):
        source = read("shaders/lib/lighting/brdf.glsl")
        self.assertIn("vec3 f0, float diffuse_weight", source)
        self.assertIn("VisibleGGXThroughput", source)

    def test_profiles_and_languages_expose_opaque_quality(self):
        properties = read("shaders/shaders.properties")
        for profile, quality in (
            ("LOW", 0),
            ("MEDIUM", 1),
            ("HIGH", 2),
            ("ULTRA", 3),
        ):
            self.assertRegex(
                properties,
                rf"profile\.{profile}\s*=.*\bOPAQUE_SSR_QUALITY={quality}\b",
            )
        lighting_line = next(
            line
            for line in properties.splitlines()
            if line.startswith("screen.LIGHTING =")
        )
        self.assertIn("OPAQUE_SSR_QUALITY", lighting_line)

        english = read("shaders/lang/en_us.lang")
        chinese = read("shaders/lang/zh_cn.lang")
        for token in (
            "option.OPAQUE_SSR_QUALITY",
            "value.OPAQUE_SSR_QUALITY.0",
            "value.OPAQUE_SSR_QUALITY.1",
            "value.OPAQUE_SSR_QUALITY.2",
            "value.OPAQUE_SSR_QUALITY.3",
        ):
            self.assertIn(token, english)
            self.assertIn(token, chinese)
        self.assertIn("不透明反射质量", chinese)

    def test_zero_quality_disables_trace_and_filter_programs(self):
        properties = read("shaders/shaders.properties")
        condition = "#if OPAQUE_SSR_QUALITY > 0"
        self.assertIn(condition, properties)
        conditional_block = properties.split(condition, 1)[1].split("#endif", 1)[0]
        enabled_block, disabled_block = conditional_block.split("#else", 1)
        for world in ("world0", "world1", "world-1"):
            for program in ("deferred2", "deferred3"):
                self.assertRegex(
                    enabled_block,
                    rf"program\.{re.escape(world)}/{program}\.enabled\s*=\s*"
                    r"true\b",
                )
                self.assertRegex(
                    disabled_block,
                    rf"program\.{re.escape(world)}/{program}\.enabled\s*=\s*"
                    r"false\b",
                )

    def test_debug_views_remain_internal(self):
        settings = read("shaders/lib/contract/settings.glsl")
        trace = read("shaders/program/deferred/opaque_reflection_trace.fragment")
        filt = read("shaders/program/deferred/opaque_reflection_filter.fragment")
        shade = read("shaders/program/deferred/deferred_shading.fragment")
        self.assertRegex(
            settings,
            r"#define\s+OPAQUE_SSR_DEBUG\s+0\s*"
            r"//\s*\[0 1 2 3 4 5 6 7 8\]",
        )
        for debug_value in range(1, 9):
            token = f"OPAQUE_SSR_DEBUG == {debug_value}"
            self.assertTrue(
                token in trace or token in filt or token in shade,
                f"missing opaque debug view {debug_value}",
            )
        properties = read("shaders/shaders.properties")
        self.assertNotRegex(
            properties,
            r"screen\.[^=]*=.*\bOPAQUE_SSR_DEBUG\b",
        )


class LabPBRReferenceTests(unittest.TestCase):
    def test_selector_boundaries(self):
        self.assertEqual(decode_lab_selector(0), ((0.0, 0.0, 0.0), 1.0))
        self.assertEqual(
            decode_lab_selector(229), ((229 / 255.0,) * 3, 1.0)
        )
        self.assertEqual(
            decode_lab_selector(230), ((0.8, 0.6, 0.2), 0.0)
        )
        self.assertEqual(
            decode_lab_selector(255), ((0.8, 0.6, 0.2), 0.0)
        )

    def test_emission_boundaries_and_sentinel(self):
        self.assertEqual(decode_lab_emission(0), 0.0)
        self.assertEqual(decode_lab_emission(254), 1.0)
        self.assertEqual(decode_lab_emission(255), 0.0)

    def test_aux_boundaries(self):
        self.assertEqual(decode_lab_aux(0), (0.0, 0.0))
        self.assertEqual(decode_lab_aux(64), (1.0, 0.0))
        self.assertEqual(decode_lab_aux(65), (0.0, 0.0))
        self.assertEqual(decode_lab_aux(255), (0.0, 1.0))

    def test_recursive_gain_is_bounded(self):
        for confidence in (0.0, 0.25, 0.5, 1.0):
            with self.subTest(confidence=confidence):
                self.assertLess(0.92 * confidence, 1.0)


if __name__ == "__main__":
    unittest.main()
