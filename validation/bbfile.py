"""Reader for MATLAB comm.BasebandFileWriter (.bb) captures.

The file is a binary metadata header followed by the I/Q samples. This reader
pulls the numeric header fields it needs, then takes the sample block from the
end of the file (CaptureLengthSamples x 16 bytes, complex double, little endian).
Tested on B28LTEcapture.bb (BasebandVer1.0.0, single channel, double output).
"""
import re
import struct
import numpy as np

_NUMERIC = ("CaptureLengthSamples", "CaptureLengthSeconds",
            "BasebandSampleRate", "CenterFrequency")


def _field(raw, name):
    i = raw.find(name.encode()) + len(name)
    # name, then 11 bytes of type/shape info, then one little-endian double
    return struct.unpack("<d", raw[i + 11:i + 19])[0]


def read_bb(path):
    raw = open(path, "rb").read()
    if not raw.startswith(b"BasebandVer"):
        raise ValueError("not a MATLAB baseband (.bb) file")
    meta = {k: _field(raw, k) for k in _NUMERIC}
    date = re.search(rb"\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2}", raw[:4096])
    meta["Date"] = date.group().decode() if date else None
    n = int(meta["CaptureLengthSamples"])
    nbytes = n * 16
    meta["HeaderBytes"] = len(raw) - nbytes
    if meta["HeaderBytes"] <= 0:
        raise ValueError("file shorter than CaptureLengthSamples implies")
    # sanity: length / rate must equal the recorded duration
    dur = n / meta["BasebandSampleRate"]
    if abs(dur - meta["CaptureLengthSeconds"]) > 1e-6:
        raise ValueError(f"header inconsistent: {dur} s vs {meta['CaptureLengthSeconds']} s")
    x = np.frombuffer(raw[-nbytes:], dtype="<c16").astype(np.complex128)
    return x, meta


if __name__ == "__main__":
    import sys
    x, meta = read_bb(sys.argv[1] if len(sys.argv) > 1 else "../B28LTEcapture.bb")
    for k, v in meta.items():
        print(f"{k:22s} {v}")
    print(f"{'Samples read':22s} {len(x)}")
