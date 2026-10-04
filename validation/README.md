# Independent validation of the Band 28 capture

Part of the [4G-LTE-Cell-Search-MIB-and-SIB1-recovery](https://github.com/Oluwanifemilua/4G-LTE-Cell-Search-MIB-and-SIB1-recovery) repository. The capture, `B28LTEcapture.bb`, is in the repository root.

This folder re-decodes `B28LTEcapture.bb` with a separately implemented
toolchain, independent of the MATLAB LTE Toolbox receiver in the parent folder. If both receivers
give the same cell identity, MIB and SIB1, the result does not depend on one
implementation.

```
B28LTEcapture.bb ──► lte_sync.py ──► srsRAN pdsch_ue ──► decode_sib1.py
  (Pluto, 30.72 Msps)   PSS/SSS, CFO,      MIB, PCFICH, PDCCH,    ASN.1 UPER
                        frame timing       PDSCH, CRC checks      SIB1 fields
```

## What each step does

| Step | File | Independent of MATLAB because |
| --- | --- | --- |
| Read the capture | `bbfile.py` | Parses the `.bb` header and samples directly; checks length against the recorded duration |
| Synchronise | `lte_sync.py` | PSS and SSS written from 3GPP TS 36.211 6.11; sweeps CFO, finds PCI and the frame boundary |
| Decode | srsRAN 4G `pdsch_ue` + `srsran_sibdump.patch` | Open-source receiver (Software Radio Systems). The 5-line patch only prints the decoded SIB1 bytes |
| Interpret | `decode_sib1.py` | pycrate ASN.1 decoder for `BCCH-DL-SCH-Message` (TS 36.331) |

`pdsch_ue` has no cell search in file mode: it assumes the file starts on a
frame boundary and needs the PCI. `lte_sync.py` supplies both. The decode then
confirms them, because every layer is protected by a CRC that a wrong PCI,
port count or timing breaks.

## Requirements

- Python 3.10+ with `pip install -r requirements.txt` (numpy, scipy, pycrate)
- A C/C++ toolchain, CMake, and `libfftw3-dev libmbedtls-dev libboost-program-options-dev libconfig++-dev libsctp-dev`

Tested on Ubuntu 24.04, GCC 13.3, CMake 3.28 and pycrate 0.8.1, with two srsRAN 4G builds that give byte-identical output:

- the 25.10 release, tag `release_25_10`, commit `6bcbd9e` (released 26 Jan 2026), the reference version;
- `master` at commit `bef8680` (10 Sep 2026), which still reports version 25.10.0. Between the two, the only PHY-library change is one line of 5G NR sync code, and `pdsch_ue.c` is unchanged.

## Building srsRAN

Only the physical-layer library and one example are needed; no radio driver.

```bash
git clone https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G
git checkout release_25_10     # srsRAN 4G 25.10, commit 6bcbd9e
git apply ../srsran_sibdump.patch
mkdir build && cd build
cmake .. -DENABLE_UHD=OFF -DENABLE_BLADERF=OFF -DENABLE_SOAPYSDR=OFF \
         -DENABLE_ZEROMQ=OFF -DENABLE_GUI=OFF -DENABLE_SRSUE=OFF \
         -DENABLE_SRSENB=OFF -DENABLE_SRSEPC=OFF -DCMAKE_BUILD_TYPE=Release
make -j"$(nproc)" pdsch_ue
cd ../..
```

## Running

```bash
./run_validation.sh ./srsRAN_4G/build/lib/examples/pdsch_ue ../B28LTEcapture.bb
```

It runs in a few seconds and writes `sync.json`, `pss_correlation.csv`,
`srsran_run.log`, `controls.txt` and `sib1_decoded.txt`. Reference copies of
each are in `expected/`; both srsRAN builds above reproduce them exactly.

The `pdsch_ue` arguments are: `-i` capture at 15.36 Msps, `-O` frame start
minus 4 samples (inside the cyclic prefix), `-o` CFO in Hz, `-p 50` PRB,
`-P 2` ports, `-c` PCI, `-Q` standard LTE sample rates, `-n 37` subframes.

## Expected result

| Check | Expected |
| --- | --- |
| CFO | +13.7 kHz (17.7 ppm at 773 MHz) |
| PCI | 63 (N_ID(1) = 21 at 7 of 8 PSS peaks, N_ID(2) = 0) |
| PSS spacing | 9,600 samples (5 ms) at 1.92 Msps |
| Frame boundary | 2.832 ms into the capture |
| MIB | 50 PRB, PHICH normal, Ng = 1, SFN 424 + block offset 1 = 425 |
| PDCCH | DCI 1A, SI-RNTI, CCE 0, L = 2, RIV 250, MCS 2 |
| SIB1 | SFN 426 (RV 2) and SFN 428 (RV 3), 144-bit TB, CRC pass, identical bytes `405884615828565ae0a821b0908104596000` |
| SIB1 fields | PLMN 621-30, TAC 0x5828, ECI 0x565AE0A (eNB 353710, cell 10), band 28 |

## Negative controls

Run automatically; each must fail.

| Forced setting | Why it must fail | Result |
| --- | --- | --- |
| 1 antenna port | PBCH CRC is masked by the port count | No MIB |
| 4 antenna ports | Same | No MIB |
| PCI 64 | PBCH scrambling and CRS positions depend on the PCI | No MIB |

## MATLAB rerun (October 2026)

`matlab_rerun/` holds the output of the 2022 receiver, `SIB1RecoveryExample_wCoarseFr.m`, rerun unchanged on the same capture: the console log and the four figures it draws (received spectrum, PSS/SSS correlation, PDCCH constellation, channel magnitude). The srsRAN decode in this folder agrees with it on PCI 63, 50 PRB, 2 ports, SFN 425, CFI 2, DCI format 1A with MCS 2 and RV 2 then 3, and a SIB1 CRC pass in SFN 426 and 428. The SIB1 bytes MATLAB recovered (`sib1{1}`, printed at the end of the log) are byte-identical to srsRAN's: `405884615828565ae0a821b0908104596000`.

## Limits

- One 40 ms capture: two SIB1 transmissions, no statistics.
- PCI, CFO and timing come from `lte_sync.py`, not from srsRAN's own cell
  search (unavailable in file mode). The CRCs and controls confirm them.
- SNR figures in the srsRAN log are estimator outputs, not calibrated measurements.
