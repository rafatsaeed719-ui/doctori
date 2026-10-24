"""Renders promo.html frame by frame into an MP4 with the soundtrack.
Usage: python3 render.py out.mp4 [fps]
"""
import json
import pathlib
import subprocess
import sys

from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
OUT = sys.argv[1]
FPS = int(sys.argv[2]) if len(sys.argv) > 2 else 30
silent = str(pathlib.Path(OUT).with_suffix('.silent.mp4'))

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': 1920, 'height': 1080})
    pg.goto((HERE / 'promo.html').as_uri())
    pg.wait_for_timeout(1200)
    dur = pg.evaluate('DURATION')
    sfx = pg.evaluate('SFX')
    json.dump(sfx, open(HERE / 'sfx.json', 'w'))
    frames = int(dur * FPS)
    enc = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'image2pipe', '-framerate', str(FPS), '-i', '-',
                            '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', silent],
                           stdin=subprocess.PIPE)
    for i in range(frames):
        pg.evaluate(f'render({i / FPS})')
        enc.stdin.write(pg.screenshot(type='jpeg', quality=92))
        if i % 300 == 0:
            print('frame', i, '/', frames, flush=True)
    enc.stdin.close()
    enc.wait()
    b.close()

wav = str(HERE / 'music.wav')
subprocess.run([sys.executable, str(HERE / 'music.py'), str(HERE / 'sfx.json'), wav, str(dur)], check=True)
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', silent, '-i', wav, '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
                '-shortest', '-movflags', '+faststart', OUT], check=True)
pathlib.Path(silent).unlink()
print('done', OUT)
