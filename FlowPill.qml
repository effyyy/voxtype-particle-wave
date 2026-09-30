// Flow — cosmic particle field for Voxtype.
//
// A dominant dictation wave over atmospheric layers, floating above the
// bottom edge with a deep-space aesthetic:
//
//   Layer 1 · STARFIELD — cosmic dust and stars, always present. Tiny
//     points of light in nebula colors drifting slowly with twinkle.
//
//   Layer 2 · INFLUX — effervescent cosmic bubbles in teal and purple.
//     They well up from below with a wobble, live briefly, and dissolve.
//
//   Layer 3 · DICTATION — the dominant element: a multi-layered spray of
//     fine particles in cosmic colors (purple, blue, teal, pink, gold).
//     Three overlapping sine waves create a rich, nebula-like ribbon.
//     Density proportional to voice loudness.
//
//   Processing (transcribing): influx + dictation collapse into a
//     rotating cosmic orbit ring with colored particles.
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

    // Layer 1 · starfield: {x, y, sz, ph, tw, rise, drift, ci}
    property var ambient: []
    // Layer 2 · influx bubbles: {x, life, rate, sz, ph, wob, spd, ci}
    property var influx: []
    // Layer 3 · dictation stream: {t, alive, b, wf, spd, sz, ph, tw, ng,
    //   a, r, rf, ci}  (ng = gaussian scatter, ci = color index)
    property var stream: []
    // Batched spray draw scratch: x, y, r, alpha bucket, color bucket.
    property var sprayX: null
    property var sprayY: null
    property var sprayR: null
    property var sprayB: null
    property var sprayC: null

    readonly property bool active: daemonState === "recording" || daemonState === "streaming" || daemonState === "transcribing"
    readonly property bool isThinking: daemonState === "transcribing"
    readonly property real voiceEnergy: Math.min(1.0, Math.max(0.0, smoothRms * 2.6 + smoothPeak * 0.9 + vadLevel * 0.08))

    readonly property int ambientCount: 90
    readonly property int influxCount: 140
    readonly property int streamCount: 3200
    readonly property real fieldW: 320
    readonly property real fieldH: 64

    // Cosmic color palette: vibrant nebula colors
    readonly property var cosmicColors: [
        [0.65, 0.20, 1.00],
        [0.20, 0.50, 1.00],
        [0.00, 0.95, 0.85],
        [1.00, 0.30, 0.60],
        [1.00, 0.75, 0.10],
        [0.80, 0.30, 1.00],
        [0.10, 0.80, 1.00],
        [1.00, 0.20, 0.40],
        [0.40, 0.90, 1.00],
        [1.00, 0.50, 0.20],
        [0.90, 0.10, 0.80],
        [0.30, 1.00, 0.60]
    ]
    readonly property int colorCount: 12

    // Shared traveling-wave state (layer 3)
    property real waveTurns: 1.8
    property real tWaveTurns: 1.8
    property real waveTurns2: 3.4
    property real tWaveTurns2: 3.4
    property real waveTurns3: 5.2
    property real tWaveTurns3: 5.2
    property real waveRetimer: 0.0
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

    function _gauss() {
        var z = (Math.random() + Math.random() + Math.random() - 1.5) / 0.45;
        if (z > 2.5) {
            z = 2.5;
        } else if (z < -2.5) {
            z = -2.5;
        }
        return z;
    }

    // ---- Field geometry ----
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
                sz: _rand(0.3, 1.0),
                ph: _rand(0, Math.PI * 2),
                tw: _rand(0.6, 3.0),
                rise: _rand(0.005, 0.025),
                drift: _rand(-0.010, 0.010),
                ci: Math.floor(Math.random() * colorCount)
            };
        }
        ambient = a;

        var b = new Array(influxCount);
        for (var j = 0; j < influxCount; j++) {
            b[j] = {
                x: Math.random(),
                life: Math.random(),
                rate: _rand(0.20, 0.65),
                sz: _rand(0.5, 1.6),
                ph: _rand(0, Math.PI * 2),
                wob: _rand(1.2, 4.5),
                spd: _rand(0.6, 1.5),
                r: 0.3 + Math.random() * 0.5,
                rf: 0.72 + Math.random() * 0.5,
                oa: Math.random() * Math.PI * 2,
                ci: Math.floor(Math.random() * colorCount)
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
                sz: _rand(0.3, 0.75),
                ph: _rand(0, Math.PI * 2),
                tw: _rand(1.4, 4.8),
                ng: _gauss(),
                a: Math.random() * Math.PI * 2,
                r: 0.3 + Math.random() * 0.5,
                rf: 0.72 + Math.random() * 0.5,
                ci: Math.floor(Math.random() * colorCount),
                strand: Math.floor(Math.random() * 18)
            };
        }
        stream = s;
        sprayX = new Float32Array(streamCount);
        sprayY = new Float32Array(streamCount);
        sprayR = new Float32Array(streamCount);
        sprayB = new Uint8Array(streamCount);
        sprayC = new Uint8Array(streamCount);
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
            root.gust = root._approach(root.gust, root.energy, 2.2, dt);

            var targetOrbit = root.isThinking ? 1.0 : 0.0;
            root.orbitMix = root._approach(root.orbitMix, targetOrbit, targetOrbit > root.orbitMix ? 2.6 : 2.0, dt);

            var e = root.voiceEnergy;
            var i, p;

            // Layer 1: starfield drift
            var am = root.ambient;
            for (i = 0; i < am.length; i++) {
                p = am[i];
                p.y -= p.rise * (0.6 + e * 1.8) * dt;
                if (p.y < -0.05) {
                    p.y += 1.1;
                    p.x = Math.random();
                }
                p.x += (p.drift + Math.sin(root.phase * 0.35 + p.ph) * 0.006) * dt;
                if (p.x < -0.05) {
                    p.x += 1.1;
                } else if (p.x > 1.05) {
                    p.x -= 1.1;
                }
            }

            // Layer 2: influx bubbles
            var ix = root.influx;
            var bubbleRate = 0.25 + e * 1.6;
            for (i = 0; i < ix.length; i++) {
                p = ix[i];
                p.life += dt * p.rate * bubbleRate * p.spd;
                if (p.life >= 1.0) {
                    if (Math.random() < (0.08 + 0.92 * e)) {
                        p.life = 0.0;
                        p.x = Math.random();
                        p.ph = Math.random() * Math.PI * 2;
                    } else {
                        p.life = 1.0;
                    }
                }
                p.oa += dt * 2.8 * (0.85 + (p.spd - 0.6) * 0.3);
                var ringR = 0.76 + 0.04 * Math.sin(root.phase * 2.0 + p.ph);
                var amount = 1.0 - Math.exp(-3.0 * dt);
                p.r += (ringR * p.rf - p.r) * amount;
            }

            // Layer 3: dictation spray
            var st = root.stream;
            var flowSpeed = 0.12 + e * 0.42;
            root.waveRetimer -= dt;
            if (root.waveRetimer <= 0) {
                root.tWaveTurns = _rand(1.2, 2.0);
                root.tWaveTurns2 = _rand(2.6, 3.8);
                root.tWaveTurns3 = _rand(4.5, 6.0);
                root.waveRetimer = _rand(5.0, 9.0);
            }
            var wApproach = 1.0 - Math.exp(-0.5 * dt);
            root.waveTurns += (root.tWaveTurns - root.waveTurns) * wApproach;
            root.waveTurns2 += (root.tWaveTurns2 - root.waveTurns2) * wApproach;
            root.waveTurns3 += (root.tWaveTurns3 - root.waveTurns3) * wApproach;
            root.burstTimer -= dt;
            if (root.burstTimer <= 0) {
                root.burstW = _rand(0.25, 0.45 + 0.55 * root.gust);
                root.burstTimer = _rand(0.7, 2.0);
            }
            var density = (live && e >= 0.06) ? Math.min(1, e) : 0;
            var target = Math.floor(st.length * density);
            var aliveCount = 0;
            for (i = 0; i < st.length; i++) {
                if (st[i].alive) {
                    aliveCount++;
                }
            }
            var emitP = density > 0 ? 4.5 : 0.0;
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
                        p.sz = _rand(0.25, 0.65);
                        p.b = 0.25 + 0.75 * Math.min(1, e * 1.8);
                        p.ci = Math.floor(Math.random() * root.colorCount);
                        p.strand = Math.floor(Math.random() * 18);
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

                p.a += dt * 2.8 * (0.85 + (p.spd - 0.5) * 0.3);
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
            var TAU = 6.2831853;

            // Cosmic nebula halo — layered radial gradients
            var haloR = root.fieldW * (0.35 + g * 0.06 + om * 0.03);
            var hg1 = ctx.createRadialGradient(cx, cy, 2, cx, cy, haloR);
            hg1.addColorStop(0.0, "rgba(120, 80, 220," + (0.03 + g * 0.04 + om * 0.02).toFixed(3) + ")");
            hg1.addColorStop(0.4, "rgba(60, 120, 200," + (0.02 + g * 0.03).toFixed(3) + ")");
            hg1.addColorStop(0.7, "rgba(0, 180, 170," + (0.01 + g * 0.02).toFixed(3) + ")");
            hg1.addColorStop(1.0, "rgba(0, 0, 0, 0)");
            ctx.fillStyle = hg1;
            ctx.beginPath();
            ctx.arc(cx, cy, haloR, 0, TAU);
            ctx.fill();

            var haloR2 = root.fieldW * (0.18 + g * 0.04);
            var hg2 = ctx.createRadialGradient(cx, cy, 1, cx, cy, haloR2);
            hg2.addColorStop(0.0, "rgba(255, 200, 100," + (0.015 + g * 0.02).toFixed(3) + ")");
            hg2.addColorStop(0.5, "rgba(255, 100, 150," + (0.01 + g * 0.01).toFixed(3) + ")");
            hg2.addColorStop(1.0, "rgba(0, 0, 0, 0)");
            ctx.fillStyle = hg2;
            ctx.beginPath();
            ctx.arc(cx, cy, haloR2, 0, TAU);
            ctx.fill();

            // ---- Layer 1 · cosmic starfield ----
            var am = root.ambient;
            var ambDim = 1.0 - om * 0.5;
            for (i = 0; i < am.length; i++) {
                p = am[i];
                x = left + p.x * root.fieldW
                    + Math.sin(root.phase * 0.6 + p.ph * 2.0) * 3.5;
                y = cy - root.fieldH / 2 + p.y * root.fieldH
                    + Math.cos(root.phase * 0.4 + p.ph) * 2.5;
                var tw = 0.5 + 0.5 * Math.sin(root.phase * p.tw + p.ph);
                var ci = p.ci;
                var cr = root.cosmicColors[ci][0];
                var cg = root.cosmicColors[ci][1];
                var cb = root.cosmicColors[ci][2];
                a = (0.02 + 0.04 * tw + g * 0.02) * ambDim;
                if (a <= 0.015) {
                    continue;
                }
                size = p.sz * (0.85 + g * 0.25) * (0.8 + tw * 0.4);
                ctx.fillStyle = "rgba(" + (cr * 255 | 0) + "," + (cg * 255 | 0) + "," + (cb * 255 | 0) + "," + a.toFixed(3) + ")";
                ctx.beginPath();
                ctx.arc(x, y, size, 0, TAU);
                ctx.fill();
            }

            // ---- Layer 2 · cosmic influx bubbles ----
            var ix = root.influx;
            for (i = 0; i < ix.length; i++) {
                p = ix[i];
                if (p.life >= 1.0 && om < 0.02) {
                    continue;
                }
                var env = Math.sin(Math.PI * Math.min(1, Math.max(0, p.life)));
                var bx = left + p.x * root.fieldW
                    + Math.sin(root.phase * p.wob + p.ph) * (3.5 + g * 6.0);
                var by = cy + root.fieldH / 2 + 6 - p.life * (root.fieldH + 14);
                var ox = cx + Math.cos(p.oa) * p.r * ringPx;
                var oy = cy + Math.sin(p.oa) * p.r * ringPx * 0.92;
                x = bx * (1 - om) + ox * om;
                y = by * (1 - om) + oy * om;
                var bs = p.sz * (0.7 + env * 0.7) * (0.9 + g * 0.4);
                ci = p.ci;
                cr = root.cosmicColors[ci][0];
                cg = root.cosmicColors[ci][1];
                cb = root.cosmicColors[ci][2];
                a = (0.12 + 0.28 * Math.min(1, g * 1.5 + 0.15) + om * 0.18) * (env * (1 - om) + om);
                if (a > 0.95) {
                    a = 0.95;
                }
                if (a <= 0.015) {
                    continue;
                }
                // Glow pass for larger bubbles
                if (bs > 1.0 && a > 0.15) {
                    var glowR = bs * 3.0;
                    var bhg = ctx.createRadialGradient(x, y, 0, x, y, glowR);
                    bhg.addColorStop(0, "rgba(" + (cr * 255 | 0) + "," + (cg * 255 | 0) + "," + (cb * 255 | 0) + "," + (a * 0.25).toFixed(3) + ")");
                    bhg.addColorStop(1, "rgba(" + (cr * 255 | 0) + "," + (cg * 255 | 0) + "," + (cb * 255 | 0) + ",0)");
                    ctx.fillStyle = bhg;
                    ctx.beginPath();
                    ctx.arc(x, y, glowR, 0, TAU);
                    ctx.fill();
                }
                ctx.fillStyle = "rgba(" + (cr * 255 | 0) + "," + (cg * 255 | 0) + "," + (cb * 255 | 0) + "," + a.toFixed(3) + ")";
                ctx.beginPath();
                ctx.arc(x, y, bs, 0, TAU);
                ctx.fill();
            }

            // ---- Layer 3 · cosmic dictation wave (dense parallel strands) ----
            var st = root.stream;
            var turns = root.waveTurns;
            var turns2 = root.waveTurns2;
            var eW = g * 0.6 + e * 0.4;
            var travel = root.phase * (1.5 + g * 1.1);
            var breadth = 0.6 + 0.85 * root.burstW;
            var amp = 5.0 + eW * 48.0 * breadth;
            if (amp > 64) {
                amp = 64;
            }
            var amp2 = amp * 0.22;
            var strandCount = 18;
            var strandSpacing = 5.5 + eW * 4.0;

            var nb = 8;
            var n = 0;
            for (i = 0; i < st.length; i++) {
                p = st[i];
                if (!p.alive) {
                    continue;
                }
                var tt = p.t;
                var strandIdx = p.strand % strandCount;
                var strandOff = (strandIdx - strandCount / 2 + 0.5) * strandSpacing;
                var ph1 = tt * turns * TAU - travel + strandOff * 0.06;
                var ph2 = tt * turns2 * TAU - travel * 0.62 + strandOff * 0.04;
                var waveY = cy + Math.sin(ph1) * amp
                    + Math.sin(ph2) * amp2
                    + strandOff;
                var slope = Math.cos(ph1) * (amp * turns * TAU) / root.fieldW
                    + Math.cos(ph2) * (amp2 * turns2 * TAU) / root.fieldW;
                var inv = 1 / Math.sqrt(1 + slope * slope);
                var off = p.ng * 1.2 * (0.5 + p.wf * 0.3)
                    + Math.sin(root.phase * 2.0 + p.ph * 2.5) * 0.4;
                var sx2 = left + tt * root.fieldW - slope * inv * off;
                var sy2 = waveY + inv * off;
                ox = cx + Math.cos(p.a) * p.r * ringPx;
                oy = cy + Math.sin(p.a) * p.r * ringPx * 0.92;
                x = sx2 * (1 - om) + ox * om;
                y = sy2 * (1 - om) + oy * om;

                var tenv = Math.min(1, tt / 0.05) * Math.min(1, (1 - tt) / 0.10);
                if (tenv < 0) {
                    tenv = 0;
                }
                tenv = tenv * (1 - om) + om;
                var gcore = Math.exp(-(p.ng * p.ng) * 3.5);
                var ptw = 0.75 + 0.25 * Math.sin(root.phase * p.tw + p.ph);
                a = (0.10 + 0.75 * gcore) * (0.5 + 0.5 * p.b) * ptw * tenv * (1.0 - 0.2 * tt);
                a *= (0.5 + 0.5 * g) * (1 - om) + om * 1.15;
                if (a > 0.92) {
                    a = 0.92;
                }
                if (a <= 0.02) {
                    continue;
                }
                size = p.sz * (0.9 + gcore * 0.5) * (0.9 + eW * 0.5) * (0.95 + om * 0.2);
                if (size < 0.3) {
                    size = 0.3;
                }

                sprayX[n] = x;
                sprayY[n] = y;
                sprayR[n] = size;
                sprayC[n] = p.ci;
                var bk = (a * nb) | 0;
                sprayB[n] = bk >= nb ? nb - 1 : bk;
                n++;
            }

            // Draw spray batched by alpha bucket, colored per particle
            for (var bkt = 0; bkt < nb; bkt++) {
                for (var cIdx = 0; cIdx < root.colorCount; cIdx++) {
                    var anyC = false;
                    ctx.beginPath();
                    for (var j2 = 0; j2 < n; j2++) {
                        if (sprayB[j2] !== bkt || sprayC[j2] !== cIdx) {
                            continue;
                        }
                        anyC = true;
                        ctx.moveTo(sprayX[j2] + sprayR[j2], sprayY[j2]);
                        ctx.arc(sprayX[j2], sprayY[j2], sprayR[j2], 0, TAU);
                    }
                    if (!anyC) {
                        continue;
                    }
                    var cc = root.cosmicColors[cIdx];
                    ctx.fillStyle = "rgba(" + (cc[0] * 255 | 0) + "," + (cc[1] * 255 | 0) + "," + (cc[2] * 255 | 0) + "," + ((bkt + 0.5) / nb).toFixed(3) + ")";
                    ctx.fill();
                }
            }

            // Bright core pass — white-hot center on the wave spine
            if (om < 0.5) {
                ctx.globalCompositeOperation = "lighter";
                var coreN = 0;
                for (i = 0; i < st.length; i++) {
                    p = st[i];
                    if (!p.alive) {
                        continue;
                    }
                    var ctt = p.t;
                    if (Math.abs(p.ng) > 0.6) {
                        continue;
                    }
                    var cStrandIdx = p.strand % 18;
                    var cStrandOff = (cStrandIdx - 18 / 2 + 0.5) * (5.5 + eW * 4.0);
                    var cph = ctt * turns * TAU - travel + cStrandOff * 0.06;
                    var cwaveY = cy + Math.sin(cph) * amp
                        + Math.sin(ctt * turns2 * TAU - travel * 0.62 + cStrandOff * 0.04) * amp2
                        + cStrandOff;
                    var cslope = Math.cos(cph) * (amp * turns * TAU) / root.fieldW;
                    var cinv = 1 / Math.sqrt(1 + cslope * cslope);
                    var coff = p.ng * spread * 0.3
                        + Math.sin(root.phase * 2.4 + p.ph * 3.1) * shimmer * 0.3;
                    var cx2 = left + ctt * root.fieldW - cslope * cinv * coff;
                    var cy2 = cwaveY + cinv * coff;
                    var cenv = Math.min(1, ctt / 0.07) * Math.min(1, (1 - ctt) / 0.12);
                    if (cenv < 0) {
                        cenv = 0;
                    }
                    var ca = 0.35 * cenv * (1 - om) * (0.5 + 0.5 * g);
                    if (ca <= 0.03) {
                        continue;
                    }
                    var csz = p.sz * 0.6 * (0.8 + eW * 0.4);
                    if (csz < 0.2) {
                        csz = 0.2;
                    }
                    var cglow = ctx.createRadialGradient(cx2, cy2, 0, cx2, cy2, csz * 4);
                    cglow.addColorStop(0, "rgba(255,255,255," + ca.toFixed(3) + ")");
                    cglow.addColorStop(0.4, "rgba(200,220,255," + (ca * 0.4).toFixed(3) + ")");
                    cglow.addColorStop(1, "rgba(200,220,255,0)");
                    ctx.fillStyle = cglow;
                    ctx.beginPath();
                    ctx.arc(cx2, cy2, csz * 4, 0, TAU);
                    ctx.fill();
                    coreN++;
                }
                ctx.globalCompositeOperation = "source-over";
            }

            // Cosmic orbit particles during transcription
            if (om > 0.02) {
                ctx.globalCompositeOperation = "lighter";
                var orbitCount = 60;
                for (i = 0; i < orbitCount; i++) {
                    var oa = (i / orbitCount) * TAU + root.phase * 1.8;
                    var orad = ringPx * (0.7 + 0.3 * Math.sin(root.phase * 0.8 + i * 0.5));
                    var oxx = cx + Math.cos(oa) * orad;
                    var oyy = cy + Math.sin(oa) * orad * 0.85;
                    var oci = i % root.colorCount;
                    var occ = root.cosmicColors[oci];
                    var otw = 0.5 + 0.5 * Math.sin(root.phase * 3.0 + i * 1.3);
                    var oaa = om * (0.2 + 0.5 * otw);
                    var osz = 0.6 + otw * 0.8;
                    var oglow = ctx.createRadialGradient(oxx, oyy, 0, oxx, oyy, osz * 3);
                    oglow.addColorStop(0, "rgba(" + (occ[0] * 255 | 0) + "," + (occ[1] * 255 | 0) + "," + (occ[2] * 255 | 0) + "," + oaa.toFixed(3) + ")");
                    oglow.addColorStop(1, "rgba(" + (occ[0] * 255 | 0) + "," + (occ[1] * 255 | 0) + "," + (occ[2] * 255 | 0) + ",0)");
                    ctx.fillStyle = oglow;
                    ctx.beginPath();
                    ctx.arc(oxx, oyy, osz * 3, 0, TAU);
                    ctx.fill();
                }
                ctx.globalCompositeOperation = "source-over";
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
