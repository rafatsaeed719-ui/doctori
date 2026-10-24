"""Renders the promo with the Arabic voice-over: scenes are stretched to fit each line,
the music ducks under the voice. Usage: python3 render_voice.py out.mp4 [fps]
"""
import json
import pathlib
import subprocess
import sys

from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
VOICE = HERE / 'voice'
WORK = pathlib.Path('/tmp/claude-0/vid/work')
WORK.mkdir(parents=True, exist_ok=True)
OUT = sys.argv[1]
FPS = int(sys.argv[2]) if len(sys.argv) > 2 else 30
TEMPO = 1.07
MINS = [6.5, 5, 5.5, 8, 7, 7, 7, 6.5, 4.5, 7]
OFFS = [0.6, 0.5, 1.3, 0.8, 0.8, 0.8, 0.8, 0.8, 0.6, 0.9]   # when each line starts inside its scene


def dur(p):
    return float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(p)]))


# 1) prepare voice clips: slightly faster, trailing silence trimmed, 44.1 kHz stereo, gentle EQ + loudness
clips = []
for i in range(1, 11):
    src, dst = VOICE / f's{i}.wav', WORK / f'v{i}.wav'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(src), '-af',
                    f'atempo={TEMPO},areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,'
                    'highpass=f=80,equalizer=f=3000:t=q:w=1:g=3,acompressor=threshold=-18dB:ratio=3:attack=5:release=80,'
                    'aresample=44100,pan=stereo|c0=c0|c1=c0', str(dst)], check=True)
    clips.append(dst)
durs = [dur(c) for c in clips]
lens = [round(max(m, o + d + 0.8), 2) for m, o, d in zip(MINS, OFFS, durs)]
starts = [sum(lens[:i]) for i in range(10)]
total = sum(lens)
print('scene lengths', lens, 'total', round(total, 1))

# 2) frames
silent = WORK / 'silent.mp4'
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': 1920, 'height': 1080})
    pg.add_init_script(f'window.TIMING = {json.dumps(lens)};')
    pg.goto((HERE / 'promo.html').as_uri())
    pg.wait_for_timeout(1200)
    sfx = pg.evaluate('SFX')
    frames = int(total * FPS)
    enc = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'image2pipe', '-framerate', str(FPS), '-i', '-',
                            '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', str(silent)],
                           stdin=subprocess.PIPE)
    for i in range(frames):
        pg.evaluate(f'render({i / FPS})')
        enc.stdin.write(pg.screenshot(type='jpeg', quality=92))
        if i % 600 == 0:
            print('frame', i, '/', frames, flush=True)
    enc.stdin.close()
    enc.wait()
    b.close()

# 3) music (sections follow the stretched scenes)
meta = {'sfx': sfx, 's1_end': starts[1], 'intro_end': starts[2], 'outro': starts[9]}
json.dump(meta, open(WORK / 'meta.json', 'w'))
music = WORK / 'music.wav'
subprocess.run([sys.executable, str(HERE / 'music.py'), str(WORK / 'meta.json'), str(music), str(total)], check=True)

# 4) voice track: each clip placed at its scene start + offset
inputs, parts = [], []
for i, c in enumerate(clips):
    inputs += ['-i', str(c)]
    ms = int((starts[i] + OFFS[i]) * 1000)
    parts.append(f'[{i}]adelay={ms}|{ms}[a{i}]')
mixin = ''.join(f'[a{i}]' for i in range(10))
voice = WORK / 'voice.wav'
subprocess.run(['ffmpeg', '-v', 'error', '-y', *inputs, '-filter_complex',
                ';'.join(parts) + f';{mixin}amix=inputs=10:normalize=0,apad=whole_dur={total}[v]',
                '-map', '[v]', '-t', str(total), str(voice)], check=True)

# 5) final mix: music ducks under the voice
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(silent), '-i', str(music), '-i', str(voice), '-filter_complex',
                '[1]volume=0.55[m];[2]asplit=2[vs][vv];'
                '[m][vs]sidechaincompress=threshold=0.03:ratio=8:attack=20:release=400[md];'
                '[vv]volume=1.6[vo];[md][vo]amix=inputs=2:normalize=0,alimiter=limit=0.95[a]',
                '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
                '-shortest', '-movflags', '+faststart', OUT], check=True)
print('done', OUT, round(total, 1), 's')
