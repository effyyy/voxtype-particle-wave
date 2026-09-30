// Flow — effervescent particle field for Voxtype.
//
// No pill, no chrome — three layered particle systems floating above the
// bottom edge:
//
//   Layer 1 · AMBIENT — fine single-tone shimmer, always present. Small dim
//     dots drifting upward with individual twinkle, even in silence.
//
//   Layer 2 · INFLUX — effervescence bubbles, single toned. They well up
//     from below with a wobble, live briefly, and dissolve. A light trickle
//     always shimmers; speaking turns it into a rising fizz.
//
//   Layer 3 · DICTATION — a spray-wave that only exists while you speak.
//     Particles are emitted from the left by voice pressure (quadratic, so
//     quiet = sparse wisps, loud = full wide wave) and drain out the right
//     when dictation stops. Each emission gets a fresh random lane and
//     width; a slowly re-rolling burst width makes the ribbon randomly
//     wide over time. In flight they ride one shared traveling wave that
//     blooms from the source edge. All single toned.
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
    // Layer 3 · dictation stream: {t, alive, b, wf, spd, sz, ph, lane,
    //   wave jitter fields, a, r, rf}
    property var stream: []

    readonly property bool active: daemonState === "recording" || daemonState === "streaming" || daemonState === "transcribing"
    readonly property bool isThinking: daemonState === "transcribing"
    // Voice energy 0..1 driving the whole field.
    readonly property real voiceEnergy: Math.min(1.0, Math.max(0.0, smoothRms * 2.6 + smoothPeak * 0.9 + vadLevel * 0.08))

    readonly property int ambientCount: 38
    readonly property int influxCount: 50
    readonly property int streamCount: 90
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

    function _rollWave() {
        return {
            amp: _rand(0.5, 1.0),
            freq: _rand(1.0, 4.2),
            ph: _rand(0, Math.PI * 2)
        };
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
            var w = _rollWave();
            var w2 = _rollWave();
            s[k] = {
                t: 0.0,
                alive: false,
                b: 0.5,
                wf: 1.0,
                spd: _rand(0.8, 1.2),
                sz: _rand(0.8, 2.0),
                ph: _rand(0, Math.PI * 2),
                lane: _rand(-1, 1),
                wAmp: w.amp, wFreq: w.freq, wPh: w.ph,
                tAmp: w.amp, tFreq: w.freq, tPh: w.ph,
                wAmp2: w2.amp, wFreq2: w2.freq, wPh2: w2.ph,
                tAmp2: w2.amp, tFreq2: w2.freq, tPh2: w2.ph,
                re: _rand(0.5, 3.5),
                a: Math.random() * Math.PI * 2,
                r: 0.3 + Math.random() * 0.5,
                rf: 0.72 + Math.random() * 0.5
            };
        }
        stream = s;
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

            // Layer 3: dictation spray — voice pressure emits particles at
            // the left; they drain out the right. Silence = empty field.
            var st = root.stream;
            var flowSpeed = 0.08 + e * 0.5;
            root.waveRetimer -= dt;
            if (root.waveRetimer <= 0) {
                root.tWaveTurns = _rand(1.4, 2.2);
                root.tWaveTurns2 = _rand(2.8, 4.0);
                root.waveRetimer = _rand(4.0, 7.0);
            }
            var wApproach = 1.0 - Math.exp(-0.5 * dt);
            root.waveTurns += (root.tWaveTurns - root.waveTurns) * wApproach;
            root.waveTurns2 += (root.tWaveTurns2 - root.waveTurns2) * wApproach;
            root.burstTimer -= dt;
            if (root.burstTimer <= 0) {
                root.burstW = _rand(0.3, 1.0);
                root.burstTimer = _rand(0.6, 1.8);
            }
            // Quadratic pressure: whisper = sparse wisps, loud = full wave.
            var emitP = (!live || e < 0.06) ? 0.0 : Math.min(1.0, e * e * 2.0);
            for (i = 0; i < st.length; i++) {
                p = st[i];
                if (!p.alive) {
                    if (emitP > 0 && Math.random() < emitP * 0.9 * dt) {
                        p.alive = true;
                        p.t = 0.0;
                        p.lane = _rand(-1, 1);
                        p.wf = _rand(0.35, 1.0);
                        p.b = 0.25 + 0.75 * Math.min(1, e * 1.8);
                    }
                } else {
                    p.t += flowSpeed * p.spd * dt;
                    if (p.t >= 1.0) {
                        p.t = 0.0;
                        p.alive = false;
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
            var haloA = 0.06 + g * 0.08 + om * 0.04;
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
                a = (0.08 + 0.13 * tw + g * 0.08) * ambDim;
                if (a <= 0.015) {
                    continue;
                }
                size = p.sz * (1.0 + g * 0.4);
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
                var bs = p.sz * (0.8 + env * 0.9) * (1.0 + g * 0.7);
                a = (0.30 + 0.55 * Math.min(1, g * 1.5 + 0.15) + om * 0.15) * (env * (1 - om) + om);
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
            var laneAmp = 1.5 + g * 2.0;
            var wt = root.waveTurns;
            var wt2 = root.waveTurns2;
            var wSpeed = 1.6 + g * 1.4;
            var wAmp = 2.5 + g * 13.0;
            for (i = 0; i < st.length; i++) {
                p = st[i];
                if (!p.alive) {
                    continue;
                }
                // Shared wave + shared chop, tiny fixed jitters only.
                // Grows from the left: small at the source, blooming right.
                // Randomly wide: burst width x per-particle width factor.
                var grow = 0.3 + 0.7 * Math.min(1, p.t / 0.45);
                var wave = (Math.sin(p.t * wt * 6.2832 - root.phase * wSpeed + Math.sin(p.ph) * 0.4) * wAmp
                    + Math.sin(p.t * wt2 * 6.2832 - root.phase * wSpeed * 1.5 + Math.cos(p.ph * 1.3) * 0.5) * wAmp * 0.28) * grow;
                var spray = 0.6 + g * 2.0;
                var sx = left + p.t * root.fieldW
                    + Math.sin(root.phase * 2.6 + p.ph * 2.1) * spray;
                var effW = (0.4 + 0.6 * root.burstW) * p.wf;
                var sy = cy + wave + p.lane * laneAmp * effW
                    + Math.cos(root.phase * 1.7 + p.ph) * 1.2;
                ox = cx + Math.cos(p.a) * p.r * ringPx;
                oy = cy + Math.sin(p.a) * p.r * ringPx * 0.92;
                x = sx * (1 - om) + ox * om;
                y = sy * (1 - om) + oy * om;

                var endFade = Math.min(1, Math.min(p.t, 1 - p.t) / 0.07);
                if (endFade < 0) {
                    endFade = 0;
                }
                var headFade = Math.min(1, p.t / 0.06);
                var sFade = (endFade * headFade) * (1 - om) + om;
                size = p.sz * (1.0 + p.b * 0.9) * (0.95 + om * 0.2);
                a = (0.30 + 0.60 * p.b + om * 0.12) * sFade;
                if (a > 0.95) {
                    a = 0.95;
                }
                if (a <= 0.015) {
                    continue;
                }
                // Single tone: one clean dot.
                ctx.fillStyle = "rgba(255,255,255," + a.toFixed(3) + ")";
                ctx.beginPath();
                ctx.arc(x, y, size, 0, Math.PI * 2);
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
