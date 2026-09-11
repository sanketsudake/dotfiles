#!/usr/bin/env python3
"""Measure voice.offset for a separately recorded track: the master time at which the track's t=0 lands.
Run with: uv run --with numpy voice-offset.py <video-or-audio-with-reference-sound> <track.wav> [--window a:b] [--rate 16000]

Both inputs are decoded to mono at --rate, cross-correlated by FFT, and the lag of the peak is printed as
`offset: -0.350` (negative when the track starts early, i.e. carries extra lead-in; positive when it starts late).
Use --window a:b (seconds of the reference) around a clap or the first word so the peak is unambiguous on long
recordings. The track is searched over [a - PAD, b + PAD] so the matching sound is found whether it lands before
or after the reference window in track time, i.e. offsets in either direction up to PAD seconds are measured.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import wave
import numpy as np

PAD = 5.0  # seconds the track window extends past the reference window on each side


def decode(path, rate, window):
    """Mono float samples at `rate`; `window` is (a, b) in seconds of the file, or None for the whole file."""
    seek = ['-ss', f'{window[0]:.3f}', '-t', f'{window[1] - window[0]:.3f}'] if window else []
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
    ap.add_argument('--window', help=f'a:b seconds of the reference to correlate (the track is searched over a-{PAD:g}..b+{PAD:g})')
    ap.add_argument('--rate', type=int, default=16000)
    args = ap.parse_args()
    if args.window:
        a, b = (float(x) for x in args.window.split(':'))
        ref_win, trk_win = (a, b), (max(0.0, a - PAD), b + PAD)
    else:
        ref_win, trk_win = None, None
    ref = decode(args.reference, args.rate, ref_win)
    trk = decode(args.track, args.rate, trk_win)
    n = 1
    while n < len(ref) + len(trk):
        n *= 2
    corr = np.fft.irfft(np.fft.rfft(trk, n) * np.conj(np.fft.rfft(ref, n)), n)
    k = int(np.argmax(corr))
    if k > n // 2:
        k -= n
    lag = k / args.rate  # track sample k (of its window) lines up with reference sample 0 (of its window)
    # Each decode starts at its own origin: reference at a, track at max(0, a - PAD). The offset is the master time at
    # which track t=0 lands, so put both lags back on the master axis before subtracting.
    ref_t0 = ref_win[0] if ref_win else 0.0
    trk_t0 = trk_win[0] if trk_win else 0.0
    print(f'offset: {(ref_t0 - trk_t0) - lag:.3f}')
    print(f'peak: {corr[int(np.argmax(corr))] / (np.linalg.norm(ref) * np.linalg.norm(trk) + 1e-12):.2f} (above 0.3 is a clean lock)', file=sys.stderr)


if __name__ == '__main__':
    main()
