"""Independent LTE downlink synchronisation for the archived capture.

Implements PSS and SSS detection from 3GPP TS 36.211 sections 6.11.1 and 6.11.2
(FDD, normal cyclic prefix). It does not use MATLAB or srsRAN code.

Outputs (in the working directory):
  sync.json               PCI, CFO, frame start and per-peak detail
  pss_correlation.csv     normalised PSS correlation, 0.1 ms max-hold bins
  capture_15p36.cf32      capture resampled to 15.36 Msps, complex float32,
                          the input format srsRAN pdsch_ue expects

Usage: python lte_sync.py [path/to/B28LTEcapture.bb]
"""
import json
import sys
from collections import Counter

import numpy as np
from scipy.signal import resample_poly

from bbfile import read_bb

FS_SYNC = 1.92e6     # 6 RB rate: PSS/SSS/PBCH live in the central 72 subcarriers
FS_FULL = 15.36e6    # nominal rate for 50 RB (srsRAN -Q, 1024-point FFT)


# ---------------------------------------------------------------- sequences
def pss_freq(nid2):
    """62-element PSS (Zadoff-Chu, roots 25/29/34), TS 36.211 6.11.1.1."""
    u = (25, 29, 34)[nid2]
    n = np.arange(62)
    return np.where(n < 31,
                    np.exp(-1j * np.pi * u * n * (n + 1) / 63),
                    np.exp(-1j * np.pi * u * (n + 1) * (n + 2) / 63))


def to_grid(d, nfft):
    """Map 62 values onto subcarriers -31..-1, +1..+31 (DC unused)."""
    X = np.zeros(nfft, complex)
    X[-31:] = d[:31]
    X[1:32] = d[31:]
    return X


def pss_time(nid2, nfft=128):
    return np.fft.ifft(to_grid(pss_freq(nid2), nfft)) * np.sqrt(nfft)


def _mseq(fb):
    x = [0, 0, 0, 0, 1]
    for i in range(26):
        x.append(fb(x, i) % 2)
    return 1 - 2 * np.array(x)


_S = _mseq(lambda x, i: x[i + 2] + x[i])
_C = _mseq(lambda x, i: x[i + 3] + x[i])
_Z = _mseq(lambda x, i: x[i + 4] + x[i + 2] + x[i + 1] + x[i])


def sss_freq(nid1, nid2, subframe):
    """62-element SSS, TS 36.211 6.11.2.1; subframe is 0 or 5."""
    q1 = nid1 // 30
    q = (nid1 + q1 * (q1 + 1) // 2) // 30
    mp = nid1 + q * (q + 1) // 2
    m0 = mp % 31
    m1 = (m0 + mp // 31 + 1) % 31
    n = np.arange(31)
    s0, s1 = _S[(n + m0) % 31], _S[(n + m1) % 31]
    c0, c1 = _C[(n + nid2) % 31], _C[(n + nid2 + 3) % 31]
    z0, z1 = _Z[(n + m0 % 8) % 31], _Z[(n + m1 % 8) % 31]
    d = np.zeros(62)
    if subframe == 0:
        d[0::2], d[1::2] = s0 * c0, s1 * c1 * z0
    else:
        d[0::2], d[1::2] = s1 * c0, s0 * c1 * z1
    return d


# ---------------------------------------------------------------- search
def pss_search(y, fs, offsets):
    t = np.arange(len(y)) / fs
    best = None
    for fo in offsets:
        z = y * np.exp(-2j * np.pi * fo * t)
        for nid2 in range(3):
            c = np.abs(np.correlate(z, pss_time(nid2), "valid"))
            score = c.max() / np.sqrt(np.mean(c ** 2))
            if best is None or score > best[0]:
                best = (score, fo, nid2)
    return best[1], best[2]


def main(path):
    x, meta = read_bb(path)
    fs = meta["BasebandSampleRate"]
    print(f"Capture: {meta['Date']}, {meta['CenterFrequency']/1e6:.3f} MHz, "
          f"{fs/1e6:.2f} Msps, {len(x)} samples")

    # 1. central 6 RB at 1.92 Msps
    y = resample_poly(x, 1, int(round(fs / FS_SYNC)))
    t = np.arange(len(y)) / FS_SYNC

    # 2. PSS search over CFO: coarse 1 kHz over +/-30 kHz (Pluto is +/-25 ppm,
    #    i.e. +/-19.3 kHz at 773 MHz), then 100 Hz around the best
    fo, nid2 = pss_search(y, FS_SYNC, np.arange(-30000, 30001, 1000))
    fo, nid2 = pss_search(y, FS_SYNC, np.arange(fo - 1000, fo + 1001, 100))
    z = y * np.exp(-2j * np.pi * fo * t)
    corr = [np.abs(np.correlate(z, pss_time(k), "valid")) for k in range(3)]
    c = corr[nid2]
    peaks = [i for i in range(len(c))
             if c[i] > 0.5 * c.max() and c[i] == c[max(0, i - 50):i + 50].max()]

    # 3. SSS per PSS peak: equalise with the PSS channel, correlate 168 x 2
    #    hypotheses. FDD normal CP: SSS starts 137 samples before PSS at 1.92 Msps.
    per_peak = []
    for p in peaks:
        P = np.fft.fft(z[p:p + 128])
        S = np.fft.fft(z[p - 137:p - 137 + 128])
        H = np.r_[P[-31:], P[1:32]] / pss_freq(nid2)
        Sr = np.r_[S[-31:], S[1:32]] / H
        scores = sorted(((np.real(np.vdot(sss_freq(n1, nid2, sf), Sr)), n1, sf)
                         for n1 in range(168) for sf in (0, 5)), reverse=True)
        (s_best, n1, sf), (s_next, _, _) = scores[0], scores[1]
        per_peak.append({"sample_1p92": int(p), "ms": round(p / FS_SYNC * 1e3, 3),
                         "nid1": n1, "subframe": sf,
                         "margin": round(float(s_best / s_next), 2),
                         "corr_norm": round(float(c[p] / c.max()), 3)})
    nid1 = Counter(r["nid1"] for r in per_peak).most_common(1)[0][0]
    agree = sum(r["nid1"] == nid1 for r in per_peak)
    pci = 3 * nid1 + nid2
    thr = 1.3 * max(corr[k].max() for k in range(3) if k != nid2) / c.max()

    # 4. frame start: refine the first subframe-0 PSS at 15.36 Msps
    first_sf0 = next(r for r in per_peak if r["nid1"] == nid1 and r["subframe"] == 0)
    y15 = resample_poly(x, 1, int(round(fs / FS_FULL)))
    t15 = np.arange(len(y15)) / FS_FULL
    z15 = y15 * np.exp(-2j * np.pi * fo * t15)
    p15 = np.fft.ifft(to_grid(pss_freq(nid2), 1024))
    k0 = int(first_sf0["sample_1p92"] * FS_FULL / FS_SYNC)
    seg = z15[k0 - 200:k0 + 200 + 1024]
    k = int(np.argmax(np.abs(np.correlate(seg, p15, "valid")))) + k0 - 200
    sym6 = 80 + 1024 + 5 * (72 + 1024) + 72   # PSS useful part, slot 0 symbol 6
    frame_start = (k - sym6) % int(FS_FULL * 0.010)

    y15.astype(np.complex64).tofile("capture_15p36.cf32")
    bins = 192
    with open("pss_correlation.csv", "w") as f:
        f.write("ms,corr\n")
        cn = c / c.max()
        for b in range(len(cn) // bins):
            f.write(f"{(b*bins + bins/2)/FS_SYNC*1e3:.2f},{cn[b*bins:(b+1)*bins].max():.3f}\n")

    out = {"capture": meta, "cfo_hz": float(fo), "cfo_ppm": round(fo / meta["CenterFrequency"] * 1e6, 2),
           "nid2": nid2, "nid1": nid1, "pci": pci, "sss_votes": f"{agree}/{len(per_peak)}",
           "pss_spacing_samples": [int(b - a) for a, b in zip(peaks, peaks[1:])],
           "weak_corr_threshold": round(float(thr), 3),
           "frame_start_15p36": int(frame_start),
           "frame_start_ms": round(frame_start / FS_FULL * 1e3, 3),
           "peaks": per_peak}
    json.dump(out, open("sync.json", "w"), indent=2)

    print(f"CFO            {fo:+.0f} Hz ({out['cfo_ppm']} ppm)")
    print(f"N_ID(2)        {nid2}")
    print(f"N_ID(1)        {nid1}  (agrees at {agree} of {len(per_peak)} PSS peaks)")
    print(f"PCI            {pci}")
    print(f"PSS spacing    {out['pss_spacing_samples']} samples at 1.92 Msps")
    print(f"Peaks vs threshold: min {min(r['corr_norm'] for r in per_peak)} vs {out['weak_corr_threshold']}")
    print(f"Frame start    sample {frame_start} at 15.36 Msps ({out['frame_start_ms']} ms)")
    print("Wrote sync.json, pss_correlation.csv, capture_15p36.cf32")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "../B28LTEcapture.bb")
