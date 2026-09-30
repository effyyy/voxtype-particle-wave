# voxtype-particle-wave

An effervescent particle OSD style for [voxtype](https://github.com/voxtype)
(push-to-talk voice-to-text for Linux). No pill, no chrome — just a living
particle field floating above the bottom edge, with a tiny timer below.

## What it looks like

Three layered, monochrome, single-tone particle systems on a 60 fps canvas:

| Layer | Behavior |
| --- | --- |
| **Ambient** (38) | Subtle shimmer, always present. Tiny dim dots drifting upward with individual twinkle, even in silence. |
| **Influx** (50) | Understated effervescence bubbles. Well up from below with a wobble, swell as they rise, dissolve at the top. A trickle at rest, a fizz while speaking. |
| **Dictation spray** (820) | The dominant element. Exists **only while you speak**. Fine particles emit from the screen's left edge and travel across the viewport along a gently undulating spine. The plume opens downstream like a perfume mist; voice intensity controls particle density, fan width, and travel speed. It drains out the right when you stop. |

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
- Spray height: `amp` and `spread` in the layer-3 draw block
- Wave travel speed: `travel` in the layer-3 draw block
- Spray width and aggressiveness: `eW` in the layer-3 draw block; grain size via the particle `sz` ranges
- Density: alive-fraction governance in the engine (`target = pool × voiceEnergy`, proportional to loudness)
- Particle sizes: `sz` ranges in `_initParticles()`

## Files

- `FlowPill.qml` — the whole UI: physics engine + canvas renderer + timer
- `voxtype-osd.toml` — style package manifest (neutral palette, no frame)
