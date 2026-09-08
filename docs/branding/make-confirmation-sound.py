"""ClanTab's confirmation sound (DESIGN_BIBLE.md §5) -- one short, soft chime,
played alongside the success haptic on the single most significant confirm
(ClanTab: settled up). "Confirm, don't decorate": low, brief, a rising two-note
figure that resolves.

Writes a 16-bit mono WAV; the Makefile / this script then runs `afconvert` to
the packaged `.caf`. Run from the repo root:  python3 docs/branding/make-confirmation-sound.py
"""
import math
import struct
import subprocess
import wave

SR = 44_100
OUT_WAV = "/tmp/clantab-settled.wav"
OUT_CAF = "App/ClanTab/Resources/Sounds/settled.caf"

# A rising perfect fifth that settles: C6 -> G6, the second note entering while
# the first is still ringing, both on a gentle exponential decay. A touch of
# the octave harmonic for warmth; kept quiet (peak ~0.32) so it sits under
# speech and never startles.
NOTES = [
    (1046.50, 0.00, 0.42),  # C6
    (1567.98, 0.09, 0.46),  # G6
]
PEAK = 0.32


def tone(freq, t):
    env = math.exp(-t * 7.5)
    body = math.sin(2 * math.pi * freq * t)
    shimmer = 0.18 * math.sin(2 * math.pi * freq * 2 * t)
    # Soft attack over the first 6 ms so there's no click.
    attack = min(1.0, t / 0.006)
    return env * attack * (body + shimmer)


total = max(start + dur for _, start, dur in NOTES)
frames = int(total * SR)
samples = [0.0] * frames
for freq, start, dur in NOTES:
    s0 = int(start * SR)
    for i in range(int(dur * SR)):
        if s0 + i < frames:
            samples[s0 + i] += tone(freq, i / SR)

peak = max(abs(s) for s in samples) or 1.0
scale = PEAK / peak
with wave.open(OUT_WAV, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))

subprocess.run(
    ["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1", OUT_WAV, OUT_CAF],
    check=True,
)
print("wrote", OUT_CAF, f"({total:.2f}s)")
