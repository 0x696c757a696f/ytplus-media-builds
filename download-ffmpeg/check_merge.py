"""Merges sample streams with the given ffmpeg folder the way yt-dlp does.

    check_merge.py <folder with ffmpeg and ffprobe>   (run inside the samples)
"""
import sys, os, shutil, subprocess
from yt_dlp import YoutubeDL
from yt_dlp.postprocessor import FFmpegMergerPP, FFmpegFixupM3u8PP, FFmpegFixupM4aPP
loc = os.path.abspath(sys.argv[1])
exe = '.exe' if os.name == 'nt' else ''
ydl = YoutubeDL({'ffmpeg_location': loc, 'quiet': True})
cases = [('v_h264.mp4','a.m4a','mp4'),('v_vp9.webm','a.webm','webm'),('v_av1.mp4','a.m4a','mp4'),('v_hevc.mp4','a.m4a','mp4'),('v_vp9.webm','a.m4a','mkv'),('v_av1.mp4','a.webm','mkv'),('v_vp9.webm','a.webm','mp4'),('v_av1.mp4','a.webm','mp4'),('v_h264.mp4','a.m4a','mkv')]
ok = True
for v, a, ext in cases:
    out = f'out_{v}_{a}.{ext}'
    info = {'filepath': out, '__files_to_merge': [v, a], 'ext': ext, 'id': 'x'}
    pp = FFmpegMergerPP(ydl)
    try:
        shutil.copy(v, 'w_' + v); shutil.copy(a, 'w_' + a)
        info['__files_to_merge'] = ['w_' + v, 'w_' + a]
        info['requested_formats'] = [{'vcodec': 'x', 'acodec': 'none', 'protocol': 'https', 'ext': 'mp4'}, {'vcodec': 'none', 'acodec': 'x', 'protocol': 'https', 'ext': 'm4a'}]
        pp.run(info)
        probe = subprocess.run([os.path.join(loc, 'ffprobe' + exe), '-v', 'error', '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', out], capture_output=True, text=True).stdout.split()
        print('OK  ', out, probe)
    except Exception as e:
        ok = False; print('FAIL', out, e)
# HLS remux as yt-dlp's ffmpeg downloader and the m3u8 fixup do
r = subprocess.run([os.path.join(loc, 'ffmpeg' + exe), '-y', '-loglevel', 'error', '-i', 'hls.m3u8', '-c', 'copy', '-bsf:a', 'aac_adtstoasc', '-f', 'mp4', 'hls.mp4'])
print('OK  ' if r.returncode == 0 else 'FAIL', 'hls.m3u8 -> mp4'); ok &= r.returncode == 0
shutil.copy('hls0.ts', 'fix.mp4')
info = {'filepath': 'fix.mp4', 'ext': 'mp4', 'protocol': 'm3u8_native', 'id': 'x', 'container': None, '__real_download': True}
try:
    FFmpegFixupM3u8PP(ydl).run(info); print('OK   FixupM3u8')
except Exception as e:
    ok = False; print('FAIL FixupM3u8', e)
sys.exit(0 if ok else 1)
