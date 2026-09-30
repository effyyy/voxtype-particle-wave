# voxtype-particle-wave

An effervescent particle OSD style for [voxtype](https://github.com/voxtype)
(push-to-talk voice-to-text for Linux). No pill, no chrome — just a living
particle field floating above the bottom edge, with a tiny timer below.

## What it looks like

Three layered, monochrome, single-tone particle systems on a 60 fps canvas:

| Layer | Behavior |
| --- | --- |
| **Ambient** (38) | Fine shimmer, always present. Tiny dim dots drifting upward with individual twinkle, even in silence. |
| **Influx** (50) | Effervescence bubbles. Well up from below with a wobble, swell as they rise, dissolve at the top. A trickle at rest, a fizz while speaking. |
| **Dictation spray** (90) | Exists **only while you speak**. Voice pressure emits particles from the left edge (quadratic — whisper gives wisps, loud gives the full wide wave). They ride one shared traveling wave that blooms from the source, with a randomly re-rolling burst width, then drain out the right when you stop. |

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
- Field size: `fieldW`, `fieldH`
- Wave height/speed: `wAmp`, `wSpeed` in the layer-3 draw block
- Emission pressure: `emitP` curve in the engine (`e * e * 2.0`)
- Burst width rhythm: `burstTimer` re-roll range
- Particle sizes: `sz` ranges in `_initParticles()`

## Files

- `FlowPill.qml` — the whole UI: physics engine + canvas renderer + timer
- `voxtype-osd.toml` — style package manifest (neutral palette, no frame)
