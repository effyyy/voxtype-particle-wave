# voxtype-particle-wave

An effervescent particle OSD style for [voxtype](https://github.com/voxtype)
(push-to-talk voice-to-text for Linux). No pill, no chrome — just a living
particle field floating above the bottom edge, with a tiny timer below.

## What it looks like

Aurora — a sculpted sine ribbon wrapped in translucent silk on a 60 fps
canvas, with a fine stellar spray that ignites only while you speak:

| Layer | Behavior |
| --- | --- |
| **Starfield** (90) | Cosmic dust and stars, always present. Tiny points of light in nebula colors drifting slowly with individual twinkle, even in silence. |
| **Influx** (140) | Effervescent cosmic bubbles in teal and purple. Well up from below with a wobble, swell as they rise, dissolve at the top. A trickle at rest, a fizz while speaking. |
| **Aurora ribbon + stellar spray** (900) | The dominant element. A pearl-bright twin-core ribbon flows violet → turquoise along one sculpted sine spine. A river of fine star-grains flows through it **only while you speak** — voice intensity controls spray density, fan width, and travel speed. It drains out the right when you stop. Rare gold/pink glints sparkle among the violet-ice-teal grains. |

While the model transcribes, influx + spray collapse into a rotating ring
with a hairline orbit guide. A tiny monospace timer sits below the field.

## Install

```bash
mkdir -p ~/.config/voxtype/osd/flow
cp FlowPill.qml voxtype-osd.toml ~/.config/voxtype/osd/flow/
voxtype config set osd.style flow
systemctl --user restart voxtype
```

Hold your push-to-talk key and speak — the wave should breathe with you.

## Tuning

All knobs live in `FlowPill.qml`:

- Counts: `ambientCount`, `influxCount`, `streamCount`
- Star/orbit field size: `fieldW`, `fieldH`
- Ribbon height: `amp` / `amp2` and spine turns `waveTurns` / `waveTurns2` in the layer-3 draw block
- Wave travel speed: `travel` in the layer-3 draw block
- Spray width and aggressiveness: `eW` in the layer-3 draw block; grain size via the particle `sz` ranges
- Density: alive-fraction governance in the engine (`target = pool × voiceEnergy`, proportional to loudness)
- Particle sizes: `sz` ranges in `_initParticles()`

## Files

- `FlowPill.qml` — the whole UI: physics engine + canvas renderer + timer
- `voxtype-osd.toml` — style package manifest (neutral palette, no frame)
