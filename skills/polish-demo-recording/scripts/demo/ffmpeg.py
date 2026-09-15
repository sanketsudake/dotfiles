"""ffmpeg and ffprobe process helpers plus the encode settings shared by every segment.

Every ffmpeg invocation in the package goes through ff(), so a test can log argv with a PATH shim.
"""
import subprocess

# Identical settings for every segment so runs can be joined with -c copy.
AENC = ['-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2']


def venc(fps):
    """Video encode arguments for a segment at the master frame rate."""
    return ['-r', str(fps), '-c:v', 'libx264', '-crf', '16', '-preset', 'medium', '-pix_fmt', 'yuv420p', '-video_track_timescale', '30000']


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)


def ff(*args):
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *args])


def dur(path):
    """Duration of the first video stream in seconds (ffprobe)."""
    out = subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=duration', '-of', 'default=nw=1:nk=1', path])
    return float(out.strip())
