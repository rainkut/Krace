#!/usr/bin/env python3
"""Original cinematic synthwave tracks (public-domain, generated). Writes assets/audio/music.pcm (day) and music_night.pcm."""
import math, random, struct, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
random.seed(7)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

def render(bpm, bars, prog, arp_pat, name, lead=None, swing=0.0):
    beat = 60 / bpm
    total = int(SR * beat * 4 * bars)
    buf = [0.0] * total
    def add(at, smp, vol=1.0):
        for k, s in enumerate(smp):
            j = at + k
            if j >= total: break
            buf[j] += s * vol
    def tone(f, dur, vol, kind, a=0.01, r=0.2, det=0.0):
        n = int(SR * dur); out = []
        for i in range(n):
            t = i / SR
            ph = (t * f) % 1.0; ph2 = (t * f * (1 + det)) % 1.0
            if kind == "saw": v = (2 * ph - 1) * 0.6 + (2 * ph2 - 1) * 0.6
            elif kind == "sq": v = (1 if ph < 0.5 else -1) * 0.5
            else: v = math.sin(2 * math.pi * f * t)
            e = min(1.0, t / a) * min(1.0, (dur - t) / r)
            out.append(v * vol * max(0.0, e))
        return out
    def lp(smp, k):
        y = 0.0; o = []
        for s in smp:
            y += k * (s - y); o.append(y)
        return o
    kick = [math.sin(2 * math.pi * (120 - 80 * min(1, i / (SR * 0.15))) * i / SR) * math.exp(-i / (SR * 0.09)) for i in range(int(SR * 0.3))]
    snare = [(random.uniform(-1, 1) * 0.7 + math.sin(2 * math.pi * 190 * i / SR) * 0.4) * math.exp(-i / (SR * 0.07)) for i in range(int(SR * 0.25))]
    hat = [random.uniform(-1, 1) * math.exp(-i / (SR * 0.012)) for i in range(int(SR * 0.05))]
    for bar in range(bars):
        root, chord = prog[bar % len(prog)]
        b0 = bar * 4
        # pad: sustained detuned saw chord, low-passed
        for m in chord:
            add(int(SR * b0 * beat), lp(tone(hz(m), beat * 4, 0.07, "saw", 0.5, 0.8, 0.004), 0.08))
        # bass: driving eighths
        for e in range(8):
            f = hz(root - 12)
            add(int(SR * (b0 + e * 0.5) * beat), lp(tone(f * (2 if e % 4 == 3 else 1), beat * 0.45, 0.30, "saw", 0.005, 0.1), 0.18))
        # drums
        for b in range(4):
            add(int(SR * (b0 + b) * beat), kick, 0.85)
        for b in (1, 3):
            add(int(SR * (b0 + b) * beat), snare, 0.30)
        for e in range(8):
            add(int(SR * (b0 + e * 0.5 + 0.25) * beat), hat, 0.10)
        # arp (16ths) with simple echo
        notes = [root + 12 + chord_i for chord_i in arp_pat(chord, root)]
        for s16 in range(16):
            m = notes[s16 % len(notes)]
            at = int(SR * (b0 + s16 * 0.25) * beat)
            t = tone(hz(m), beat * 0.2, 0.09, "sq", 0.003, 0.08)
            add(at, t); add(at + int(SR * beat * 0.75), t, 0.35)
        # lead melody every 2nd bar
        if lead and bar % 2 == 1:
            for k, (m, d, st) in enumerate(lead[(bar // 2) % len(lead)]):
                add(int(SR * (b0 + st) * beat), lp(tone(hz(m), beat * d, 0.12, "saw", 0.02, 0.25, 0.006), 0.25))
    peak = max(abs(x) for x in buf)
    pcm = struct.pack("<%dh" % total, *[max(-32767, min(32767, int(x / peak * 0.85 * 32767))) for x in buf])
    open(os.path.join(OUT, name + ".pcm"), "wb").write(pcm)
    print(name, total / SR, "s")

# Night: 100 bpm, A minor: Am F C G
night_prog = [(57, [57, 60, 64]), (53, [53, 57, 60]), (48, [55, 60, 64]), (55, [55, 59, 62])]
arp = lambda ch, r: [c - 12 - r + 12 for c in ch] and [0, 7, 12, 7]  # root, fifth, octave, fifth relative to root
night_lead = [[(81, 1.5, 0), (79, 0.5, 1.5), (76, 2.0, 2.0)], [(77, 1.5, 0), (79, 0.5, 1.5), (72, 2.0, 2.0)]]
render(100, 16, night_prog, lambda ch, r: [0, 12, 7, 12, 0, 7, 12, 19], "music_night", night_lead)
# Day: 124 bpm, D minor feel: Dm Bb F C, brighter
day_prog = [(50, [57, 62, 65]), (46, [58, 62, 65]), (53, [57, 60, 65]), (48, [55, 60, 64])]
day_lead = [[(74, 1.0, 0), (77, 1.0, 1.0), (81, 2.0, 2.0)], [(79, 1.0, 0), (77, 1.0, 1.0), (74, 2.0, 2.0)]]
render(124, 16, day_prog, lambda ch, r: [0, 7, 12, 16, 12, 7, 12, 19], "music", day_lead)
# Cruise: 70 bpm, warm major, slow 80s/soft-country feel: C G Am F
cr_prog = [(48, [60, 64, 67]), (43, [59, 62, 67]), (45, [60, 64, 69]), (41, [60, 65, 69])]
cr_lead = [[(79, 2.0, 0), (76, 1.0, 2.0), (79, 1.0, 3.0)], [(81, 1.5, 0), (79, 0.5, 1.5), (72, 2.0, 2.0)]]
render(70, 16, cr_prog, lambda ch, r: [0, 7, 12, 7, 0, 7, 16, 7], "music_cruise", cr_lead)
