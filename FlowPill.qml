// Flow — effervescent particle field for Voxtype.
//
// No pill, no chrome — a dominant dictation wave over two subtle
// atmospheric layers, floating above the bottom edge:
//
//   Layer 1 · AMBIENT — subtle single-tone shimmer, always present. Small
//     dim dots drifting upward with individual twinkle, even in silence.
//
//   Layer 2 · INFLUX — understated effervescence bubbles, single toned.
//     They well up from below with a wobble, live briefly, and dissolve.
//     A light trickle always shimmers; speaking turns it into a rising fizz.
//
//   Layer 3 · DICTATION — the dominant element: a spray of fine particles
//     that only exists while you speak. Ultra-fine dust is emitted from the
//     left by voice pressure, density proportional to dictation intensity
//     (quiet = sparse wisps, loud = a dense wave), and drains out the right
//     when dictation stops. Every grain rides the same traveling sine —
//     fundamental plus a slow secondary swell — scattered along the wave
//     normal with gaussian falloff, so the spray piles onto the line and
//     mists outward. Amplitude, mist thickness, and grain size all scale
//     with loudness and are re-rolled at random, so loud passages fan wide
//     and thick while quiet ones collapse to a tight hairline. All single toned.
//
//   Processing (transcribing): influx + dictation collapse into a rotating
//     ring; ambient dims but stays. Tiny timer below, nothing else.
//
// The host (OsdSurface.qml) loads this fullscreen and hides the whole window
// when idle, so this file only worries about the visible states.

import QtQuick

Item {
    id: root
    anchors.fill: parent

    // ---- Host-provided properties (names must match OsdSurface._syncCustomItem) ----
    property string daemonState: "idle"
    property var audio: null
    property var theme: null
    property var recipe: null
    property string assetRoot: ""

    // ---- Live audio state ----
    property real peak: 0.0
    property real rms: 0.0
    property real vadLevel: 0.0
    property real smoothPeak: 0.0
    property real smoothRms: 0.0
    property real energy: 0.0
    property real gust: 0.0
    property real phase: 0.0
    property real orbitMix: 0.0
    property real lastTickMs: Date.now()
    property real recordStartMs: 0
    property string elapsedText: "0:00"

    // Layer 1 · ambient: {x, y, sz, ph, tw, rise, drift}
    property var ambient: []
    // Layer 2 · influx bubbles: {x, life, rate, sz, ph, wob, spd}
    property var influx: []
    // Layer 3 · dictation stream: {t, alive, b, wf, spd, sz, ph, tw, ng,
    //   a, r, rf}  (ng = gaussian scatter offset from the wave line)
    property var stream: []
    // Batched spray draw scratch: x, y, r, alpha bucket.
    property var sprayX: null
    property var sprayY: null
    property var sprayR: null
    property var sprayB: null

    readonly property bool active: daemonState === "recording" || daemonState === "streaming" || daemonState === "transcribing"
    readonly property bool isThinking: daemonState === "transcribing"
    // Voice energy 0..1 driving the whole field.
    readonly property real voiceEnergy: Math.min(1.0, Math.max(0.0, smoothRms * 2.6 + smoothPeak * 0.9 + vadLevel * 0.08))

    readonly property int ambientCount: 38
    readonly property int influxCount: 50
    readonly property int streamCount: 820
    readonly property real fieldW: 320
    readonly property real fieldH: 64

    // Shared traveling-wave state (layer 3): wavelengths drift slowly so
    // the ribbon keeps evolving without ever looking random per-particle.
    property real waveTurns: 1.8
    property real tWaveTurns: 1.8
    property real waveTurns2: 3.4
    property real tWaveTurns2: 3.4
    property real waveRetimer: 0.0
    // Spray burst state: re-rolling width makes the wave randomly wide.
    property real burstW: 0.7
    property real burstTimer: 0.0

    // ---- Config helpers ----
    function _configValue(key, fallback) {
        if (theme && theme.config && theme.config[key] !== undefined) {
            return theme.config[key];
        }
        return fallback;
    }

    function _clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    function _approach(current, target, stiffness, dt) {
        var amount = 1.0 - Math.exp(-Math.max(0.01, stiffness) * dt);
        return current + (target - current) * amount;
    }

    function _rand(lo, hi) {
        return lo + Math.random() * (hi - lo);
    }

    // Rough standard normal, clamped to about [-2, 2]. Used for the spray's
    // gaussian scatter: grains pile up on the wave line and thin out fast.
    function _gauss() {
        var z = (Math.random() + Math.random() + Math.random() - 1.5) / 0.5;
        if (z > 2) {
            z = 2;
        } else if (z < -2) {
            z = -2;
        }
        return z;
    }

    // ---- Field geometry (bottom-docked, room below for the timer) ----
    function _fieldX() {
        var pos = String(_configValue("position", "bottom-center"));
        var margin = Math.max(0, Number(_configValue("margin_px", 24)));
        if (pos.indexOf("left") >= 0) {
            return margin;
        }
        if (pos.indexOf("right") >= 0) {
            return Math.max(margin, root.width - fieldW - margin);
        }
        return Math.max(margin, (root.width - fieldW) / 2);
    }

    function _fieldBaseY() {
        var margin = Math.max(0, Number(_configValue("margin_px", 24)));
        var bottomGap = Math.max(78, margin + 54);
        var pos = String(_configValue("position", "bottom-center"));
        if (pos === "top-left" || pos === "top-right") {
            return margin + 8;
        }
        if (pos === "top-center") {
            return Math.max(margin, root.height * 0.12);
        }
        return Math.max(margin, root.height - fieldH - bottomGap);
    }

    function _formatElapsed(ms) {
        var totalSec = Math.max(0, Math.floor(ms / 1000));
        var m = Math.floor(totalSec / 60);
        var s = totalSec % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    function _initParticles() {
        var a = new Array(ambientCount);
        for (var i = 0; i < ambientCount; i++) {
            a[i] = {
                x: Math.random(),
                y: Math.random(),
                sz: _rand(0.4, 0.9),
                ph: _rand(0, Math.PI * 2),
                tw: _rand(0.8, 2.6),
                rise: _rand(0.008, 0.030),
                drift: _rand(-0.012, 0.012)
            };
        }
        ambient = a;

        var b = new Array(influxCount);
        for (var j = 0; j < influxCount; j++) {
            b[j] = {
                x: Math.random(),
                life: Math.random(),
                rate: _rand(0.25, 0.7),
                sz: _rand(0.6, 1.4),
                ph: _rand(0, Math.PI * 2),
                wob: _rand(1.5, 4.0),
                spd: _rand(0.7, 1.4),
                r: 0.3 + Math.random() * 0.5,
                rf: 0.72 + Math.random() * 0.5,
                oa: Math.random() * Math.PI * 2
            };
        }
        influx = b;

        var s = new Array(streamCount);
        for (var k = 0; k < streamCount; k++) {
            s[k] = {
                t: 0.0,
                alive: false,
                b: 0.5,
                wf: _rand(0.35, 1.0),
                spd: _rand(0.7, 1.35),
                sz: _rand(0.3, 0.6),
                ph: _rand(0, Math.PI * 2),
                tw: _rand(1.6, 4.4),
                ng: _gauss(),
                a: Math.random() * Math.PI * 2,
                r: 0.3 + Math.random() * 0.5,
                rf: 0.72 + Math.random() * 0.5
            };
        }
        stream = s;
        sprayX = new Float32Array(streamCount);
        sprayY = new Float32Array(streamCount);
        sprayR = new Float32Array(streamCount);
        sprayB = new Uint8Array(streamCount);
    }

    Component.onCompleted: _initParticles()

    // ---- Audio input ----
    Connections {
        target: root.audio
        enabled: root.audio !== null

        function onFrameReceived(framePeak, frameRms, vad, tsMs) {
            root.peak = _clamp(framePeak, 0.0, 1.0);
            root.rms = _clamp(frameRms, 0.0, 1.0);
            root.vadLevel = vad ? 1.0 : 0.0;
        }

        function onDisconnected() {
            root.peak = 0.0;
            root.rms = 0.0;
            root.vadLevel = 0.0;
        }
    }

    onDaemonStateChanged: {
        if (daemonState === "recording" || daemonState === "streaming") {
            if (recordStartMs === 0) {
                recordStartMs = Date.now();
            }
            elapsedText = _formatElapsed(0);
        } else if (daemonState === "transcribing") {
            // freeze the timer; revive the whole field for the orbit ring
            var stRev = root.stream;
            for (var ri = 0; ri < stRev.length; ri++) {
                stRev[ri].alive = true;
                stRev[ri].t = Math.random();
                stRev[ri].b = 0.8;
            }
            var ixRev = root.influx;
            for (var rj = 0; rj < ixRev.length; rj++) {
                if (ixRev[rj].life >= 1.0) {
                    ixRev[rj].life = Math.random() * 0.9;
                }
            }
        } else {
            recordStartMs = 0;
            elapsedText = "0:00";
            peak = 0.0;
            rms = 0.0;
            vadLevel = 0.0;
            smoothPeak = 0.0;
            smoothRms = 0.0;
            energy = 0.0;
            gust = 0.0;
        }
        particleCanvas.requestPaint();
    }

    // ---- 60fps physics engine ----
    Timer {
        id: engine
        interval: 16
        repeat: true
        running: true
        onTriggered: {
            var now = Date.now();
            var dt = Math.min(0.06, Math.max(0.001, (now - root.lastTickMs) / 1000.0));
            root.lastTickMs = now;
            root.phase += dt;

            var live = root.active && !root.isThinking;
            var tPeak = live ? _clamp(root.peak, 0, 1) : 0;
            var tRms = live ? _clamp(root.rms, 0, 1) : 0;
            root.smoothPeak = root._approach(root.smoothPeak, tPeak, 14.0, dt);
            root.smoothRms = root._approach(root.smoothRms, tRms, 9.0, dt);
            root.vadLevel = root._approach(root.vadLevel, (root.audio && root.audio.vad && live) ? 1.0 : 0.0, 8.0, dt);
            root.energy = root._approach(root.energy, Math.max(root.smoothPeak, root.smoothRms * 1.7), 6.5, dt);
            // Slow gust follows the same energy — swells and settles waves.
            root.gust = root._approach(root.gust, root.energy, 2.2, dt);

            // Ease between stream mode (0) and orbit mode (1).
            var targetOrbit = root.isThinking ? 1.0 : 0.0;
            root.orbitMix = root._approach(root.orbitMix, targetOrbit, targetOrbit > root.orbitMix ? 2.6 : 2.0, dt);

            var e = root.voiceEnergy;
            var i, p, w;

            // Layer 1: ambient drift (always alive).
            var am = root.ambient;
            for (i = 0; i < am.length; i++) {
                p = am[i];
                p.y -= p.rise * (0.7 + e * 1.6) * dt;
                if (p.y < -0.05) {
                    p.y += 1.1;
                    p.x = Math.random();
                }
                p.x += (p.drift + Math.sin(root.phase * 0.4 + p.ph) * 0.008) * dt;
                if (p.x < -0.05) {
                    p.x += 1.1;
                } else if (p.x > 1.05) {
                    p.x -= 1.1;
                }
            }

            // Layer 2: influx bubbles rise faster / denser with voice.
            var ix = root.influx;
            var bubbleRate = 0.3 + e * 1.4;
            for (i = 0; i < ix.length; i++) {
                p = ix[i];
                p.life += dt * p.rate * bubbleRate * p.spd;
                if (p.life >= 1.0) {
                    // Gate respawns on intensity: trickle at rest, fizz on voice.
                    if (Math.random() < (0.10 + 0.90 * e)) {
                        p.life = 0.0;
                        p.x = Math.random();
                        p.ph = Math.random() * Math.PI * 2;
                    } else {
                        p.life = 1.0;
                    }
                }
                p.oa += dt * 2.6 * (0.85 + (p.spd - 0.7) * 0.3);
                var ringR = 0.76 + 0.04 * Math.sin(root.phase * 2.0 + p.ph);
                var amount = 1.0 - Math.exp(-3.0 * dt);
                p.r += (ringR * p.rf - p.r) * amount;
            }

            // Layer 3: dictation spray — voice pressure emits fine dust at
            // the left; the grains ride one shared sine and drain out the
            // right. Silence = empty field.
            var st = root.stream;
            var flowSpeed = 0.12 + e * 0.42;
            root.waveRetimer -= dt;
            if (root.waveRetimer <= 0) {
                root.tWaveTurns = _rand(1.2, 2.0);
                root.tWaveTurns2 = _rand(2.6, 3.8);
                root.waveRetimer = _rand(5.0, 9.0);
            }
            var wApproach = 1.0 - Math.exp(-0.5 * dt);
            root.waveTurns += (root.tWaveTurns - root.waveTurns) * wApproach;
            root.waveTurns2 += (root.tWaveTurns2 - root.waveTurns2) * wApproach;
            // Breadth roll: while quiet the ribbon can only ever re-roll
            // narrow; a loud voice re-rolls wide as often as tight.
            root.burstTimer -= dt;
            if (root.burstTimer <= 0) {
                root.burstW = _rand(0.25, 0.45 + 0.55 * root.gust);
                root.burstTimer = _rand(0.7, 2.0);
            }
            // Density proportional to loudness: the alive fraction of the
            // pool tracks voice energy, so quiet dictation is a sparse spray
            // and loud dictation a dense one. Emission tops up toward the
            // target; excess grains are recycled, weighted toward the drain
            // end so the tail recedes instead of popping mid-flight. When
            // dictation stops, no recycling — the wave drains naturally.
            var density = (live && e >= 0.06) ? Math.min(1, e) : 0;
            var target = Math.floor(st.length * density);
            var aliveCount = 0;
            for (i = 0; i < st.length; i++) {
                if (st[i].alive) {
                    aliveCount++;
                }
            }
            var emitP = density > 0 ? 3.0 : 0.0;
            var killP = (density > 0 && aliveCount > target) ? 2.0 : 0.0;
            for (i = 0; i < st.length; i++) {
                p = st[i];
                if (!p.alive) {
                    if (aliveCount < target && Math.random() < emitP * dt) {
                        p.alive = true;
                        p.t = 0.0;
                        p.wf = _rand(0.35, 1.0);
                        p.ng = _gauss();
                        p.spd = _rand(0.7, 1.35);
                        p.sz = _rand(0.3, 0.6);
                        p.b = 0.25 + 0.75 * Math.min(1, e * 1.8);
                        aliveCount++;
                    }
                } else {
                    if (killP > 0 && Math.random() < killP * (0.5 + p.t) * dt) {
                        p.alive = false;
                        p.t = 1.0;
                        aliveCount--;
                    } else {
                        p.t += flowSpeed * p.spd * dt;
                        if (p.t >= 1.0) {
                            p.t = 1.0;
                            p.alive = false;
                            aliveCount--;
                        }
                    }
                }

                p.a += dt * 2.6 * (0.85 + (p.spd - 0.5) * 0.3);
                var rr = 0.76 + 0.04 * Math.sin(root.phase * 2.0 + p.ph);
                var am2 = 1.0 - Math.exp(-3.0 * dt);
                p.r += (rr * p.rf - p.r) * am2;
            }
            particleCanvas.requestPaint();
        }
    }

    // ---- 10Hz clock for the timer ----
    Timer {
        id: clock
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if ((root.daemonState === "recording" || root.daemonState === "streaming") && root.recordStartMs > 0) {
                root.elapsedText = root._formatElapsed(Date.now() - root.recordStartMs);
            }
        }
    }

    // ============ PARTICLE CANVAS (the whole UI) ============
    Canvas {
        id: particleCanvas
        // Generous pad so particles and glow never clip.
        width: root.fieldW + 140
        height: root.fieldH + 110
        x: root._fieldX() - 70
        y: root._fieldBaseY() - 55 + (root.active ? -root.voiceEnergy * 4 : 30)
        opacity: root.active ? 1.0 : 0.0
        antialiasing: true

        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!root.active) {
                return;
            }
            var e = root.voiceEnergy;
            var g = root.gust;
            var om = root.orbitMix;
            var cx = width / 2;
            var cy = 55 + root.fieldH / 2;
            var left = cx - root.fieldW / 2;
            var ringPx = 34;
            var i, p, x, y, size, a;

            // Faint neutral halo so particles read on any background.
            var haloR = root.fieldW * (0.42 + g * 0.08 + om * 0.04);
            var haloA = 0.07 + g * 0.10 + om * 0.04;
            var hg = ctx.createRadialGradient(cx, cy, 4, cx, cy, haloR);
            hg.addColorStop(0.0, "rgba(255,255,255," + (haloA * 0.5).toFixed(3) + ")");
            hg.addColorStop(0.55, "rgba(255,255,255," + (haloA * 0.18).toFixed(3) + ")");
            hg.addColorStop(1.0, "rgba(255,255,255,0)");
            ctx.fillStyle = hg;
            ctx.beginPath();
            ctx.arc(cx, cy, haloR, 0, Math.PI * 2);
            ctx.fill();

            // ---- Layer 1 · ambient shimmer (always present) ----
            var am = root.ambient;
            var ambDim = 1.0 - om * 0.6;
            for (i = 0; i < am.length; i++) {
                p = am[i];
                x = left + p.x * root.fieldW
                    + Math.sin(root.phase * 0.7 + p.ph * 2.0) * 3.0;
                y = cy - root.fieldH / 2 + p.y * root.fieldH
                    + Math.cos(root.phase * 0.5 + p.ph) * 2.0;
                var tw = 0.55 + 0.45 * Math.sin(root.phase * p.tw + p.ph);
                a = (0.035 + 0.06 * tw + g * 0.03) * ambDim;
                if (a <= 0.015) {
                    continue;
                }
                size = p.sz * (0.9 + g * 0.2);
                // Single tone: one fine dot, no halo pass.
                ctx.fillStyle = "rgba(255,255,255," + a.toFixed(3) + ")";
                ctx.beginPath();
                ctx.arc(x, y, size, 0, Math.PI * 2);
                ctx.fill();
            }

            // ---- Layer 2 · influx bubbles (fizz with voice, orbit when done) ----
            var ix = root.influx;
            for (i = 0; i < ix.length; i++) {
                p = ix[i];
                if (p.life >= 1.0 && om < 0.02) {
                    continue;
                }
                var env = Math.sin(Math.PI * Math.min(1, Math.max(0, p.life)));
                // Bubble rises from below, wobbling side to side.
                var bx = left + p.x * root.fieldW
                    + Math.sin(root.phase * p.wob + p.ph) * (3.0 + g * 5.0);
                var by = cy + root.fieldH / 2 + 6 - p.life * (root.fieldH + 14);
                var ox = cx + Math.cos(p.oa) * p.r * ringPx;
                var oy = cy + Math.sin(p.oa) * p.r * ringPx * 0.92;
                x = bx * (1 - om) + ox * om;
                y = by * (1 - om) + oy * om;
                // Bubbles swell as they rise, shrink as they dissolve.
                var bs = p.sz * (0.7 + env * 0.7) * (0.9 + g * 0.4);
                a = (0.14 + 0.30 * Math.min(1, g * 1.5 + 0.15) + om * 0.15) * (env * (1 - om) + om);
                if (a > 0.95) {
                    a = 0.95;
                }
                if (a <= 0.015) {
                    continue;
                }
                // Single tone: one clean dot.
                ctx.fillStyle = "rgba(255,255,255," + a.toFixed(3) + ")";
                ctx.beginPath();
                ctx.arc(x, y, bs, 0, Math.PI * 2);
                ctx.fill();
            }

            // ---- Layer 3 · dictation spray (voice-emitted -> orbit) ----
            var st = root.stream;
            var TAU = 6.2831853;
            var turns = root.waveTurns;
            var turns2 = root.waveTurns2;
            // Fast voice + slow gust, so crests flicker with syllables but
            // the wave still breathes instead of jittering.
            var eW = g * 0.6 + e * 0.4;
            var travel = root.phase * (1.5 + g * 1.1);
            // Breadth = intensity x a randomly re-rolled roll.
            var breadth = 0.6 + 0.85 * root.burstW;
            var amp = 4.0 + eW * 42.0 * breadth;
            if (amp > 58) {
                amp = 58;
            }
            var amp2 = amp * 0.22;
            var spread = (1.5 + eW * 9.0) * (0.4 + 0.6 * root.burstW);

            // Fine grain: every particle samples the shared sine and is
            // scattered along the wave normal by its gaussian offset, so the
            // spray piles onto the line and mists away from it. Collected
            // into alpha buckets, then one fill per bucket.
            var nb = 8;
            var n = 0;
            var shimmer = 0.35 + g * 0.7;
            for (i = 0; i < st.length; i++) {
                p = st[i];
                if (!p.alive) {
                    continue;
                }
                var tt = p.t;
                var ph1 = tt * turns * TAU - travel + p.ph * 0.03;
                var waveY = cy + Math.sin(ph1) * amp
                    + Math.sin(tt * turns2 * TAU - travel * 0.62 + p.ph * 0.05) * amp2;
                // Unit normal of the sine at this point; scatter along it.
                var slope = Math.cos(ph1) * (amp * turns * TAU) / root.fieldW;
                var inv = 1 / Math.sqrt(1 + slope * slope);
                var off = p.ng * spread * (0.55 + p.wf * 0.45)
                    + Math.sin(root.phase * 2.4 + p.ph * 3.1) * shimmer;
                var sx2 = left + tt * root.fieldW
                    + Math.sin(root.phase * 3.1 + p.ph * 2.0) * (0.5 + g * 1.2)
                    - slope * inv * off;
                var sy2 = waveY + inv * off;
                ox = cx + Math.cos(p.a) * p.r * ringPx;
                oy = cy + Math.sin(p.a) * p.r * ringPx * 0.92;
                x = sx2 * (1 - om) + ox * om;
                y = sy2 * (1 - om) + oy * om;

                var env = Math.min(1, tt / 0.07) * Math.min(1, (1 - tt) / 0.12);
                if (env < 0) {
                    env = 0;
                }
                env = env * (1 - om) + om;
                // Bright core on the line, falloff into the mist.
                var gcore = Math.exp(-(p.ng * p.ng) * 2.2);
                var tw = 0.72 + 0.28 * Math.sin(root.phase * p.tw + p.ph);
                a = (0.07 + 0.82 * gcore) * (0.5 + 0.5 * p.b) * tw * env * (1.0 - 0.3 * tt);
                a *= (0.5 + 0.5 * g) * (1 - om) + om * 1.15;
                if (a > 0.92) {
                    a = 0.92;
                }
                if (a <= 0.02) {
                    continue;
                }
                size = p.sz * (0.75 + gcore * 0.45) * (0.8 + eW * 0.5) * (0.95 + om * 0.2);
                if (size < 0.35) {
                    size = 0.35;
                }

                sprayX[n] = x;
                sprayY[n] = y;
                sprayR[n] = size;
                var bk = (a * nb) | 0;
                sprayB[n] = bk >= nb ? nb - 1 : bk;
                n++;
            }
            for (var bkt = 0; bkt < nb; bkt++) {
                var any = false;
                ctx.beginPath();
                for (var j2 = 0; j2 < n; j2++) {
                    if (sprayB[j2] !== bkt) {
                        continue;
                    }
                    any = true;
                    ctx.moveTo(sprayX[j2] + sprayR[j2], sprayY[j2]);
                    ctx.arc(sprayX[j2], sprayY[j2], sprayR[j2], 0, TAU);
                }
                if (!any) {
                    continue;
                }
                ctx.fillStyle = "rgba(255,255,255," + ((bkt + 0.5) / nb).toFixed(3) + ")";
                ctx.fill();
            }

            // Orbit guide: hairline ring fades in while processing.
            if (om > 0.02) {
                ctx.strokeStyle = "rgba(255,255,255," + (om * 0.16).toFixed(3) + ")";
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.ellipse(cx, cy, ringPx * 0.8, ringPx * 0.74, 0, 0, Math.PI * 2);
                ctx.stroke();
            }
        }
    }

    // ============ TIMER (tiny, below the field) ============
    Text {
        id: timerText
        x: root._fieldX()
        y: root._fieldBaseY() + root.fieldH + 8 + (root.active ? 0 : 8)
        width: root.fieldW
        horizontalAlignment: Text.AlignHCenter
        text: root.elapsedText
        font.family: "JetBrains Mono, JetBrainsMono Nerd Font, monospace"
        font.pixelSize: 11
        color: Qt.rgba(1, 1, 1, 0.52)
        opacity: root.active ? 1.0 : 0.0

        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }
}
