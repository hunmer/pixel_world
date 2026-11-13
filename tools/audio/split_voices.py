#!/usr/bin/env python3
"""split_voices.py — 把 *_battle_voices_ja.wav 按 7 表情切成独立 wav。
策略：ffmpeg silencedetect 找所有静音区间（d>=0.25s），取时长最长的 6 个作为切点，
保证正好 7 段；切点取静音中点。输出 cut/，源文件保留。"""
import subprocess, re, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
VOICE = os.path.join(HERE, "..", "..", "assets", "audio", "voice")
OUT = os.path.join(VOICE, "cut")
os.makedirs(OUT, exist_ok=True)

EMOTIONS = ["attack", "hurt", "confused", "laugh", "shy", "cry", "panic"]
CHARS = ["elf_companion", "hero", "veteran", "mercenary", "pegasus", "priest", "hierarch", "demon"]

def detect_silences(path):
    p = subprocess.run(["ffmpeg", "-hide_banner", "-i", path,
                        "-af", "silencedetect=noise=-35dB:d=0.25", "-f", "null", "-"],
                       capture_output=True, text=True)
    text = p.stderr
    starts = [float(m) for m in re.findall(r"silence_start: ([0-9.]+)", text)]
    ends = [float(m) for m in re.findall(r"silence_end: ([0-9.]+)", text)]
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip())
    sil = []
    for i, s in enumerate(starts):
        e = ends[i] if i < len(ends) else dur
        sil.append((s, e))
    return sil, dur

def split(src, char):
    sil, dur = detect_silences(src)
    # 取最长的 6 个互不重叠静音（静音本身不重叠，直接排序取前6）
    sil.sort(key=lambda x: x[1] - x[0], reverse=True)
    cuts = sorted(s[:6] for s in sil) if len(sil) >= 6 else sorted(sil)
    while len(cuts) < 6:  # 静音不足时按剩余时长均分补点
        cuts = [(dur * (i + 1) / 7, dur * (i + 1) / 7) for i in range(6)]
    points = [(s + e) / 2 for s, e in cuts]  # 静音中点
    bounds = [0.0] + points + [dur]
    result = []
    for i, emo in enumerate(EMOTIONS):
        a, b = bounds[i], bounds[i + 1]
        if b - a < 0.15:
            print(f"  WARN {char}/{emo} seg={b-a:.2f}s")
        dst = os.path.join(OUT, f"voice_{char}_{emo}.wav")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error",
                        "-ss", f"{a:.3f}", "-to", f"{b:.3f}", "-i", src, "-c", "copy", dst],
                       check=True)
        d = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                  "-of", "csv=p=0", dst], capture_output=True, text=True).stdout.strip())
        result.append((f"voice_{char}_{emo}.wav", round(d, 2)))
    return result

def main():
    for c in CHARS:
        src = os.path.join(VOICE, f"voice_{c}_battle_voices_ja.wav")
        if not os.path.exists(src):
            print(f"MISS {src}"); continue
        print(f"== {c} ==")
        for name, d in split(src, c):
            print(f"  cut/{name}  {d}s")

if __name__ == "__main__":
    sys.exit(main())
