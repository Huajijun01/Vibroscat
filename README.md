# Vibroscat

[English](README.md) | [简体中文](README.zh-CN.md)

Vibroscat is a high-end Minecraft shaderpack for Iris. It gives the world
natural daylight, deep cloud cover, clear water, soft shadows, and a restrained
cinematic finish while preserving Minecraft's block-shaped character.

## Development status

Vibroscat is in early development. Many effects are not implemented yet, and
parts of the code may have quality or maintainability issues. Expect visual
defects, incomplete settings, and breaking changes between versions.

## Screenshots

![Savanna landscape with volumetric clouds, clear water, and soft daylight](screenshots/scene1-sky.jpg)

![Underwater scene from an earlier development build](screenshots/scene3-water.jpg)

![Layered volumetric clouds and atmospheric sky](screenshots/scene4-clouds.jpg)

All screenshots were captured in game at 2560 pixels wide with the default
Vibroscat profile.

## Effects

- Layered volumetric clouds with changing density, soft edges, sunlight, and
  cloud shadows
- Selectable continuous or checkerboard cloud reconstruction under Environment /
  Clouds / Quality; both support every cloud resolution setting and work with
  TAA disabled. Continuous remains the default.
- Daylight, sunsets, moonlight, stars, Milky Way glow through clouds and in
  reflections, horizon haze, and boundary fog
- Exponential height air fog with shadow-map light shafts, thinner daytime haze,
  denser twilight/night haze, and additional rain density
- Clear water with waves, reflections, refraction, always-on analytic
  underwater fog, and moving caustics
- Selectable Water Surface Quality under Environment / Water: Low keeps the
  small waves by default; High uses larger waves with more surface detail
- Additive underwater sun shafts driven by a filtered bake of the same caustics,
  with jittered epipolar sampling; adjustable under Environment / Water,
  including a maximum march distance of 12 m by default
- Reflective rain wetness on exposed ground, with optional puddle patterns,
  adjustable raindrop ripples on ground and water, and drying after rain
- Soft sun shadows, contact detail, ambient shading, and light passing through
  foliage
- Wind-driven grass, flowers, crops, saplings and leaf blocks with matching
  shadows; adjustable under Environment / Plants. Connected cane/bamboo and
  attached or aquatic foliage remain still.
- Fragment Terrain TBN under Environment / Terrain, on by default: rebuilds the
  terrain surface basis per pixel so normals follow wind deformation; it saves
  terrain vertex work at long view distances for a marginal cost at short ones.
- Selectable no GI, SSGI, or reflective shadow map GI, rendered at half resolution with
  its own temporal denoising and guided upsampling, including with TAA disabled
- Directional sky light for RSM GI, on by default: nearby walls and overhangs
  tint the sky ambient by the directions they block; requires RSM GI with GTAO
  in the Overworld
- Directional sky light for SSGI, on by default: nearby occluders tint the
  screen-space GI sky ambient by the directions they block (an approximation:
  directional L0/L1 visibility with the L2 band scaled by open visibility, at
  extra GPU cost); requires SSGI in the Overworld
- Stable antialiasing, automatic exposure, bloom, depth of field, motion blur,
  sharpening, and filmic color
- Optional temporal upscaling (TAAU), with 50-85% render scale and the same
  reconstruction, history, motion response, color clipping, and sharpening
  controls as native TAA

## GPU support

Vibroscat targets modern desktop and laptop GPUs with current drivers.

| Vendor | Supported range | Practical starting point |
| --- | --- | --- |
| NVIDIA | GeForce GTX 900 series and newer | GTX 1060 6 GB at 1080p Low |
| AMD | Radeon RX 400 series and newer | RX 580 8 GB at 1080p Low |
| Intel | Arc A-series and newer | Arc A380 at 1080p Low |

GeForce RTX, Radeon RX 5000/6000/7000, and Intel Arc GPUs are the main target.
Integrated Intel UHD, Iris Xe, Radeon Vega, and Radeon 700M graphics are below
the intended performance range.

## Requirements

- Minecraft Java Edition 26.2
- Fabric Loader 0.19.x
- Iris and Sodium builds made for Minecraft 26.2
- Java 21
- Windows or Linux with an up-to-date GPU driver
- 8 GB system memory minimum; 16 GB recommended
- 4 GB VRAM for Low; 6 GB for Medium or High; 10 GB for Ultra at 4K
- 4 GB of Java heap and a 12 to 16 chunk render distance as a starting setup

## Quality profiles

| Profile | Suggested hardware and resolution |
| --- | --- |
| Low | GTX 1060 6 GB, RX 580 8 GB, or Arc A380 at 1080p |
| Medium | RTX 2060/3060, RX 6600/7600, or Arc A580/A750 at 1080p or 1440p |
| High | RTX 3070/4070, RX 6800/7800 XT, or Arc A770 at 1440p |
| Ultra | RTX 4080/4090, RX 7900 XT/XTX, or newer high-end GPUs at 4K |

Start with Medium at 1080p. Lower cloud and shadow quality first when more
performance is needed. Ultra renders clouds at full resolution and is intended
for high-end GPUs.

## Installation

Download the release archive and place it in the `shaderpacks` directory. Keep
the archive intact, or extract it so that `shaders` is directly inside the
Vibroscat folder. Select Vibroscat from the Iris shader-pack menu, then choose a
quality profile in Shader Pack Settings.

## License

Vibroscat is released under GPL-3.0. See [LICENSE](LICENSE) and
[third-party notices](licenses/THIRD_PARTY_NOTICES.en.md).
