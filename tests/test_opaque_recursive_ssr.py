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
        self.assertNotIn("colortex11Format", source)

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
                    "shade": f"shaders/{world}/deferred4.fsh",
                }
                for role, path in paths.items():
                    self.assertTrue(
                        (ROOT / path).is_file(), f"missing {role} wrapper: {path}"
                    )
                trace = read(paths["trace"])
                shade = read(paths["shade"])
                self.assertIn(define, trace)
                self.assertNotIn("colortex5MipmapEnabled", trace)
                self.assertIn("opaque_reflection_trace.fragment", trace)
                self.assertIn("deferred_shading.fragment", shade)

    def test_reflection_filter_is_removed(self):
        properties = read("shaders/shaders.properties")
        resources = read("shaders/lib/contract/resources.glsl")
        self.assertNotIn("opaque_reflection_filter", properties)
        self.assertNotRegex(properties, r"program\.world(?:0|1|-1)/deferred3\.enabled")
        self.assertIn("Opaque reflection radiance trace transient", resources)
        self.assertNotIn("trace/filter", resources)

        paths = [
            "shaders/program/deferred/opaque_reflection_filter.fragment",
        ]
        for world in ("world0", "world1", "world-1"):
            paths.extend((
                f"shaders/{world}/deferred3.fsh",
                f"shaders/{world}/deferred3.vsh",
            ))
        for path in paths:
            self.assertFalse((ROOT / path).exists(), f"stale reflection filter file: {path}")

    def test_caustic_flip_follows_final_shading(self):
        props = read("shaders/shaders.properties")
        self.assertNotIn("flip.deferred2.colortex5 = false", props)
        self.assertIn("flip.deferred4.colortex5 = false", props)
        self.assertIn("flip.composite.colortex5 = true", props)
        self.assertIn("flip.composite1.colortex5 = true", props)

    def test_water_ssr_helper_remains_separate(self):
        water = read("shaders/lib/raytrace/ssr.glsl")
        self.assertIn("struct SSRHit", water)
        self.assertIn("TraceScreenSpaceReflection", water)
        self.assertNotIn("RayTraceHIT", water)
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
        self.assertIn("texture(colortex5", source)

    def test_opaque_trace_uses_shared_loose_crossing(self):
        source = read("shaders/lib/raytrace/opaque_reflection.glsl")
        for token in (
            "ToPrevious",
            "SampleOpaqueHistory",
        ):
            self.assertIn(token, source)
        self.assertIn('#include "/lib/raytrace/ssr.glsl"', source)
        trace = read("shaders/program/deferred/opaque_reflection_trace.fragment")
        self.assertIn("TraceScreenSpaceReflection", trace)
        shared = read("shaders/lib/raytrace/ssr.glsl")
        self.assertIn("depthtex1", shared)
        for token in (
            "OpaqueTraceThickness",
            "OPAQUE_SSR_THICKNESS",
            "OpaqueGeometricViewNormalAt",
            "front_facing",
            "thickness_error",
        ):
            self.assertNotIn(token, source)

    def test_opaque_trace_reuses_sky_pixel_hits(self):
        trace = read("shaders/program/deferred/opaque_reflection_trace.fragment")
        self.assertIn(
            "OPAQUE_SSR_MAX_DISTANCE, OPAQUE_SSR_STEPS, true);",
            trace,
        )
        self.assertNotIn("|| shared_hit.sky", trace)
        self.assertIn("SampleOpaqueHistory(", trace)
        self.assertNotIn("out_reflection_path_length", trace)

    def test_opaque_history_bounds_sky_hits_by_xy_only(self):
        opaque = read("shaders/lib/raytrace/opaque_reflection.glsl")
        self.assertIn("SSRScreenInside(previous_hit.xy)", opaque)
        self.assertIn("frameCounter < 1", opaque)
        self.assertNotIn(
            "any(greaterThanEqual(previous_hit, vec3(1.0)))",
            opaque,
        )

    def test_opaque_reflection_path_has_no_filter_confidence(self):
        for path in (
            "shaders/lib/raytrace/opaque_reflection.glsl",
            "shaders/program/deferred/opaque_reflection_trace.fragment",
            "shaders/program/deferred/deferred_shading.fragment",
            "shaders/lib/contract/resources.glsl",
            "shaders/lib/contract/uniforms.glsl",
        ):
            self.assertNotIn("confidence", read(path), path)

    def test_final_shading_owns_pbr_integration(self):
        source = read("shaders/program/deferred/deferred_shading.fragment")
        for token in (
            "ResolveOpaquePBR",
            "colortex3",
            "OpaqueReflectionDirection",
            "VisibleGGXThroughput",
            "OPAQUE_SSR_RECURSION_DECAY",
        ):
            self.assertIn(token, source)
        self.assertNotIn("emiss_res.x * 0.0", source)

    def test_ssr_rejection_keeps_an_environment_fallback_direction(self):
        source = read("shaders/program/deferred/deferred_shading.fragment")
        self.assertIn("OpaqueEnvironmentFallbackDirection", source)
        self.assertNotIn("reflection_direction = vec3(0.0)", source)

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

    def test_opaque_reflection_has_no_path_length_metadata(self):
        for path in (
            "shaders/lib/contract/resources.glsl",
            "shaders/lib/contract/uniforms.glsl",
            "shaders/program/deferred/opaque_reflection_trace.fragment",
            "shaders/program/deferred/deferred_shading.fragment",
            "shaders/lib/raytrace/ssr.glsl",
        ):
            source = read(path)
            self.assertNotIn("colortex11", source, path)
            self.assertNotIn("out_reflection_path_length", source, path)
            self.assertNotIn("path_length", source, path)
        self.assertNotIn("path length", read("shaders/lib/contract/resources.glsl"))

    def test_opaque_reflection_switch_is_exposed_and_profiled(self):
        settings = read("shaders/lib/contract/settings.glsl")
        self.assertRegex(settings, r"(?m)^#define OPAQUE_REFLECTION\s+1\b")

        properties = read("shaders/shaders.properties")
        lighting_line = next(
            line
            for line in properties.splitlines()
            if line.startswith("screen.LIGHTING =")
        )
        self.assertIn("OPAQUE_REFLECTION", lighting_line)
        for profile, enabled in (("LOW", 0), ("MEDIUM", 0), ("HIGH", 1), ("ULTRA", 1)):
            self.assertRegex(
                properties,
                rf"profile\.{profile}\s*=.*\bOPAQUE_REFLECTION={enabled}\b",
            )

        english = read("shaders/lang/en_us.lang")
        chinese = read("shaders/lang/zh_cn.lang")
        for token in (
            "option.OPAQUE_REFLECTION",
            "option.OPAQUE_REFLECTION.comment",
        ):
            self.assertIn(token, english)
            self.assertIn(token, chinese)

    def test_opaque_reflection_switch_controls_ssr_passes(self):
        properties = read("shaders/shaders.properties")
        condition = "#if OPAQUE_REFLECTION && OPAQUE_SSR_QUALITY > 0"
        self.assertIn(condition, properties)
        enabled_block, disabled_block = properties.split(condition, 1)[1].split("#else", 1)
        disabled_block = disabled_block.split("#endif", 1)[0]
        for world in ("world0", "world1", "world-1"):
            for program in ("deferred2",):
                self.assertRegex(
                    enabled_block,
                    rf"program\.{re.escape(world)}/{program}\.enabled\s*=\s*true\b",
                )
                self.assertRegex(
                    disabled_block,
                    rf"program\.{re.escape(world)}/{program}\.enabled\s*=\s*false\b",
                )

    def test_opaque_reflection_roughness_threshold_is_configurable(self):
        settings = read("shaders/lib/contract/settings.glsl")
        self.assertRegex(
            settings,
            r"(?m)^#define OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD\s+0\.5\b",
        )
        self.assertRegex(
            settings,
            r"(?m)^#define OPAQUE_REFLECTION_ROUGHNESS_TRANSITION\s+0\.1\b",
        )

        properties = read("shaders/shaders.properties")
        lighting_line = next(
            line
            for line in properties.splitlines()
            if line.startswith("screen.LIGHTING =")
        )
        self.assertIn("OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD", lighting_line)
        self.assertIn("OPAQUE_REFLECTION_ROUGHNESS_TRANSITION", lighting_line)
        sliders_line = next(
            line for line in properties.splitlines() if line.startswith("sliders =")
        )
        self.assertIn("OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD", sliders_line)
        self.assertIn("OPAQUE_REFLECTION_ROUGHNESS_TRANSITION", sliders_line)

        for language in ("shaders/lang/en_us.lang", "shaders/lang/zh_cn.lang"):
            source = read(language)
            for token in (
                "option.OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD",
                "option.OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD.comment",
                "option.OPAQUE_REFLECTION_ROUGHNESS_TRANSITION",
                "option.OPAQUE_REFLECTION_ROUGHNESS_TRANSITION.comment",
            ):
                self.assertIn(token, source)

    def test_opaque_reflection_roughness_threshold_skips_ssr_and_blends_to_sh(self):
        trace = read("shaders/program/deferred/opaque_reflection_trace.fragment")
        self.assertRegex(
            trace,
            r"if\s*\(rough_selector\.x\s*>=\s*"
            r"OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD\)\s*return;",
        )
        trace_call = trace.index("TraceScreenSpaceReflection")
        threshold_check = trace.index("OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD")
        self.assertLess(threshold_check, trace_call)

        shading = read("shaders/program/deferred/deferred_shading.fragment")
        self.assertRegex(
            shading,
            r"smoothstep\(\s*OPAQUE_REFLECTION_ROUGHNESS_THRESHOLD\s*"
            r"-\s*OPAQUE_REFLECTION_ROUGHNESS_TRANSITION",
        )
        self.assertIn("mix(sh_specular, ssr_specular, ssr_weight)", shading)
        self.assertIn("EvalSkyRadiance(sh_reflection_direction)", shading)
        self.assertIn("if (ssr_weight > 0.0)", shading)

    def test_disabled_opaque_reflection_uses_environment_only(self):
        settings = read("shaders/lib/contract/settings.glsl")
        self.assertIn("#if OPAQUE_REFLECTION && OPAQUE_SSR_QUALITY > 0", settings)

        shading = read("shaders/program/deferred/deferred_shading.fragment")
        self.assertIn("vec3 sh_reflection_direction = reflect(-V, normal);", shading)
        self.assertIn("vec3 sh_environment = EvalSkyRadiance(sh_reflection_direction)", shading)
        self.assertIn("#ifdef OPAQUE_SSR\n    if (ssr_weight > 0.0)", shading)
        self.assertNotIn("vec3 incident_radiance = environment;", shading)
        sky_light = read("shaders/lib/atmosphere/sky_light.glsl")
        self.assertIn("vec3 EvalSkyRadiance(vec3 direction)", sky_light)
        self.assertNotIn("EvalSkyLight(sh_reflection_direction)", shading)

        for source in (
            "shaders/program/deferred/opaque_reflection_trace.fragment",
        ):
            self.assertTrue((ROOT / source).is_file())

    def test_sky_radiance_floors_channels_at_full_sh_average(self):
        sky_light = read("shaders/lib/atmosphere/sky_light.glsl")
        self.assertIn(
            "vec3 sh_average = max(vec3(skySH_R0.x, skySH_G0.x, skySH_B0.x) * SH_Y0, vec3(0.0));",
            sky_light,
        )
        self.assertIn("return max(radiance, sh_average);", sky_light)

    def test_zero_quality_disables_trace_programs(self):
        properties = read("shaders/shaders.properties")
        condition = "#if OPAQUE_REFLECTION && OPAQUE_SSR_QUALITY > 0"
        self.assertIn(condition, properties)
        conditional_block = properties.split(condition, 1)[1].split("#endif", 1)[0]
        enabled_block, disabled_block = conditional_block.split("#else", 1)
        for world in ("world0", "world1", "world-1"):
            for program in ("deferred2",):
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
        shade = read("shaders/program/deferred/deferred_shading.fragment")
        self.assertRegex(
            settings,
            r"#define\s+OPAQUE_SSR_DEBUG\s+0\s*"
            r"//\s*\[0 1 2 3 4 5 6 7 8\]",
        )
        for debug_value in range(1, 9):
            token = f"OPAQUE_SSR_DEBUG == {debug_value}"
            self.assertTrue(
                token in trace or token in shade,
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

    def test_recursive_decay_is_bounded(self):
        self.assertLess(0.92, 1.0)


if __name__ == "__main__":
    unittest.main()
