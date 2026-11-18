# 仮の効果音（F-05）を作るスクリプト。外部素材は使わず、数式で波形を作る
# 使い方: python tools/make_placeholder_sounds.py tools/placeholder_sounds
# （11/18 からゲームでは Kenney の CC0 の音を使っている。作った仮の音は tools/placeholder_sounds に保管）
import math, random, struct, sys, wave
RATE = 22050
OUT = sys.argv[1]
random.seed(1)

def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, s / peak * 0.9)) * 32767)) for s in samples)
    with wave.open(f"{OUT}/{name}", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data)

def env(t, attack, decay):
    return (t / attack if t < attack else math.exp(-(t - attack) / decay))

def lowpass(xs, a):
    y = 0.0; out = []
    for x in xs:
        y += a * (x - y); out.append(y)
    return out

# ヒット：短い「ドスッ」（低い音＋ノイズ）
n = int(RATE * 0.14); s = []
for i in range(n):
    t = i / RATE
    f = 180 - 900 * t
    s.append(math.sin(2 * math.pi * f * t) * env(t, 0.002, 0.04) + random.uniform(-1, 1) * env(t, 0.001, 0.015) * 0.8)
write("hit.wav", lowpass(s, 0.5))

# パリィ：金属の「キィン」（倍音でない周波数を重ねる＝金属っぽい）
n = int(RATE * 0.5); s = []
for i in range(n):
    t = i / RATE
    v = sum(a * math.sin(2 * math.pi * f * t) for f, a in [(1760, 1.0), (2637, 0.6), (3951, 0.4), (5280, 0.25)])
    s.append(v * env(t, 0.001, 0.12) + random.uniform(-1, 1) * env(t, 0.0005, 0.004) * 2.0)
write("parry.wav", s)

# ジャスト回避：「フワッ」（だんだん高くなるノイズ＋音）
n = int(RATE * 0.4); s = []; y = 0.0
for i in range(n):
    t = i / RATE
    a = 0.05 + 0.5 * (t / 0.4)
    y += a * (random.uniform(-1, 1) - y)
    tone = math.sin(2 * math.pi * (400 + 1400 * t / 0.4) * t) * 0.3
    s.append((y * 1.5 + tone) * math.sin(math.pi * t / 0.4))
write("perfect_dodge.wav", s)

# 体幹ブレイク：重い「ドゴォン」（下がっていく低音＋ノイズ）
n = int(RATE * 0.7); s = []
for i in range(n):
    t = i / RATE
    f = 110 * math.exp(-t * 2.0) + 40
    s.append(math.sin(2 * math.pi * f * t) * env(t, 0.003, 0.25) + random.uniform(-1, 1) * env(t, 0.002, 0.08) * 0.9)
write("break.wav", lowpass(s, 0.35))
print("ok")
