#!/usr/bin/env python3
"""Generate IronZapper's original short electrical zap; no external samples."""
import math
import random
import struct
import wave
from pathlib import Path

sample_rate = 44100
duration = 0.38
rng = random.Random(42)
phase = 0.0
samples = []
for index in range(round(sample_rate * duration)):
    t = index / sample_rate
    # A quick descending electrical sweep with a soft, crackling attack.
    frequency = 150 + 1900 * math.exp(-t * 12)
    phase += 2 * math.pi * frequency / sample_rate
    attack = min(t / 0.008, 1.0)
    release = min((duration - t) / 0.06, 1.0)
    envelope = attack * release * math.exp(-t * 8)
    tone = math.sin(phase) + 0.22 * math.sin(2.03 * phase)
    crackle = rng.uniform(-1, 1) * 0.2 * math.exp(-t * 22)
    samples.append(envelope * tone + attack * release * crackle)
peak = max(abs(sample) for sample in samples)
output = Path(__file__).resolve().parent.parent / 'Resources' / 'Zap.wav'
with wave.open(str(output), 'wb') as sound:
    sound.setnchannels(1)
    sound.setsampwidth(2)
    sound.setframerate(sample_rate)
    sound.writeframes(b''.join(struct.pack('<h', round(sample / peak * 0.65 * 32767)) for sample in samples))
print(f'Generated {output.name}: {duration:.2f}s, mono PCM, {sample_rate} Hz')
