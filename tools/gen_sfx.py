"""Generate Inkland's original sound effects as small mono 16-bit WAVs.

All sounds are synthesized from scratch (sine/square/triangle/noise) — no
sampled or third-party audio. Re-run to regenerate: python tools/gen_sfx.py
Output: assets/sfx/*.wav (22050 Hz, mono, ~2-8 KB each).
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def env(i, n, attack=0.01, release=0.5):
    """Attack/decay envelope, 0..1 over n samples."""
    t = i / n
    a = min(1.0, t / max(attack, 1e-6))
    d = 1.0 if t < (1.0 - release) else max(0.0, (1.0 - t) / max(release, 1e-6))
    return a * d


def synth(dur, fn, amp=0.5):
    n = int(SR * dur)
    return [max(-1.0, min(1.0, fn(i, n) * amp)) for i in range(n)]


def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print(f"{name}: {len(samples) / SR * 1000:.0f} ms")


def sine(f, i):
    return math.sin(2 * math.pi * f * i / SR)


def square(f, i):
    return 1.0 if sine(f, i) >= 0 else -1.0


def tri(f, i):
    return 2.0 / math.pi * math.asin(sine(f, i))


random.seed(7)  # deterministic noise


def main():
    # UI tap — short soft square blip.
    write_wav("click.wav", synth(
        0.06, lambda i, n: square(1050 - 350 * i / n, i) * env(i, n, 0.02, 0.7), 0.22))

    # Countdown tick.
    write_wav("tick.wav", synth(
        0.07, lambda i, n: tri(520, i) * env(i, n, 0.02, 0.6), 0.30))

    # GO! — brighter, longer.
    write_wav("go.wav", synth(
        0.16, lambda i, n: (tri(784, i) + 0.3 * sine(1568, i)) * env(i, n, 0.01, 0.5), 0.32))

    # Territory captured — cheerful upward "plop" sweep.
    write_wav("capture.wav", synth(
        0.16, lambda i, n: sine(320 + 420 * (i / n) ** 1.5, i) * env(i, n, 0.02, 0.45), 0.42))

    # Coin / reward — two-note bright ding (B5 -> E6) with a 2nd harmonic.
    def coin(i, n):
        f = 988 if i < n * 0.35 else 1319
        return (sine(f, i) + 0.3 * sine(2 * f, i)) * env(i, n, 0.005, 0.55)
    write_wav("coin.wav", synth(0.22, coin, 0.30))

    # Enemy eliminated — descending zap + noise crackle.
    def kill(i, n):
        f = 820 - 600 * i / n
        return (0.8 * square(f, i) + 0.35 * (random.random() * 2 - 1)) * env(i, n, 0.005, 0.6)
    write_wav("kill.wav", synth(0.18, kill, 0.30))

    # Own death — low thud with noise tail.
    def death(i, n):
        f = 170 - 110 * i / n
        noise = (random.random() * 2 - 1) * max(0.0, 1.0 - i / (n * 0.35))
        return (sine(f, i) + 0.4 * noise) * env(i, n, 0.004, 0.7)
    write_wav("death.wav", synth(0.34, death, 0.55))


if __name__ == "__main__":
    main()
