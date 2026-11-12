# Lumen

A cozy shader pack for [Horizon](https://playhorizon.dev) in Horizon's own format, inspired by the look of Photon. All code is original; no code from Photon or any other pack, no Minecraft assets.

- Soft sun and moon shadows from a shadow map
- A warm, physically inspired sky with a round sun and golden sunsets
- Twinkling stars and a faint Milky Way at night, a rainbow after the rain
- Volumetric clouds with drifting cloud shadows
- Light shafts through trees, sun rays, bloom and haze in the distance
- Clear water with waves, refraction, depth colour, reflections, the sun's glint and a moon path at night
- Clear turquoise water with caustics when you dive
- Waving leaves, grass, flowers, vines and seagrass
- Leaves glow when the sun is behind them
- Coloured block light (soul fire blue, redstone red, amethyst purple, ...) and glowing fireflies
- Wet ground and puddles with rain ripples after rain, softer rain and snow
- Shiny ice, metal blocks, polished stone and glass, glittering snow, glowing lava
- Drifting haze and glowing embers in the Nether, a violet nebula sky in the End
- Its own anti-aliasing, and the soft effects drawn at half resolution for speed

Every effect can be changed in the game: Options > Horizon Settings > Shader Packs > Shader Options.

## Quality levels

Pick a **Quality** level that fits your PC. It sits at the top of the shader options:

| Level | Meant for | What changes |
|---|---|---|
| Low | weak PCs, laptops | fewer cloud steps, no volumetric light, simpler water, sharper shadows |
| Medium | mid-range PCs | lighter clouds, light shafts and water |
| High | default | the normal Lumen look |
| Ultra | strong GPUs | smoother clouds, light shafts and bloom, extra soft shadows |

The page *Graphics and Performance* also has shadows on/off, shadow resolution (1024 to 4096), shadow distance (64 to 256 blocks) and reflections. Those cost the most performance and can be set separately from the level.

Needs a Horizon build from 2026-11-03 or newer.

## Build

```sh
horizon-shader check .
horizon-shader pack .
```

## License

MIT, see [LICENSE](LICENSE). Made by Lutziano888.
