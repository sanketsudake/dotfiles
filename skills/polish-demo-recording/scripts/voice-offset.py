#!/usr/bin/env python3
"""Measure voice.offset for a separately recorded track: the master time at which the track's t=0 lands.
Run with: uv run --with numpy voice-offset.py <video-or-audio-with-reference-sound> <track.wav> [--window a:b] [--rate 16000]

Both inputs are decoded to mono at --rate, cross-correlated by FFT, and the lag of the peak is printed as
`offset: -0.350` (negative when the track starts early, i.e. carries extra lead-in). Use --window a:b (seconds of the
reference) around a clap or the first word so the peak is unambiguous on long recordings.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import wave
import numpy as np


def decode(path, rate, window):
    seek = ['-ss', window[0], '-t', str(float(window[1]) - float(window[0]))] if window else []
    fd, tmp = tempfile.mkstemp(suffix='.wav')
    os.close(fd)
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *seek, '-i', path, '-vn', '-ac', '1', '-ar', str(rate), '-c:a', 'pcm_s16le', tmp], check=True)
    with wave.open(tmp) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
    os.unlink(tmp)
    return data / 32768.0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('reference')
    ap.add_argument('track')
    ap.add_argument('--window', help='a:b seconds of the reference to correlate (the track is searched over the same span plus 5 s)')
    ap.add_argument('--rate', type=int, default=16000)
    args = ap.parse_args()
    win = args.window.split(':') if args.window else None
    ref = decode(args.reference, args.rate, win)
    trk = decode(args.track, args.rate, [win[0], str(float(win[1]) + 5.0)] if win else None)
    n = 1
    while n < len(ref) + len(trk):
        n *= 2
    corr = np.fft.irfft(np.fft.rfft(trk, n) * np.conj(np.fft.rfft(ref, n)), n)
    k = int(np.argmax(corr))
    if k > n // 2:
        k -= n
    lag = k / args.rate  # track sample k lines up with reference sample 0: the track lags by k
    print(f'offset: {-lag:.3f}')
    print(f'peak: {corr[int(np.argmax(corr))] / (np.linalg.norm(ref) * np.linalg.norm(trk) + 1e-12):.2f} (above 0.3 is a clean lock)', file=sys.stderr)


if __name__ == '__main__':
    main()
