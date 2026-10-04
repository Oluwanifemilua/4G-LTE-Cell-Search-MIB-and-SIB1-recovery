#!/usr/bin/env bash
# Independent validation of the B28 capture: Python sync -> srsRAN decode -> ASN.1.
#
#   ./run_validation.sh [path/to/pdsch_ue] [path/to/B28LTEcapture.bb]
#
# Build pdsch_ue first (see README.md, "Building srsRAN").
set -euo pipefail

PDSCH_UE=${1:-./srsRAN_4G/build/lib/examples/pdsch_ue}
CAPTURE=${2:-../B28LTEcapture.bb}
[ -x "$PDSCH_UE" ] || { echo "pdsch_ue not found at $PDSCH_UE"; exit 1; }

echo "== 1. Synchronisation (Python, TS 36.211)"
python3 lte_sync.py "$CAPTURE"

read -r PCI CFO START < <(python3 -c "import json;d=json.load(open('sync.json'));print(d['pci'],int(round(d['cfo_hz'])),d['frame_start_15p36'])")
OFFSET=$((START - 4))   # start 4 samples early, inside the cyclic prefix
NSF=37                  # whole subframes left after the offset

decode () {  # $1 = ports, $2 = PCI
  timeout 120 "$PDSCH_UE" -i capture_15p36.cf32 -O "$OFFSET" -o "$CFO" \
      -p 50 -P "$1" -c "$2" -Q -n "$NSF" -v </dev/null 2>&1
}

echo
echo "== 2. srsRAN pdsch_ue: PCI $PCI, 2 ports, CFO $CFO Hz, offset $OFFSET"
decode 2 "$PCI" > srsran_run.log
grep -E "MIB decoded|SFN:|Nof ports|PRB:|PHICH|Decoded CFI|crc_rem=0xffff|PDCCH: f=1A|rv_idx|TB decoded" srsran_run.log | sed 's/^\[INFO\]: //'

echo
echo "== 3. Negative controls (each must fail to decode the MIB)"
{
  for case in "1 $PCI" "4 $PCI" "2 $((PCI + 1))"; do
    set -- $case
    if decode "$1" "$2" | grep -q "MIB decoded"; then r="DECODED (unexpected)"; else r="no MIB (expected)"; fi
    echo "ports=$1 PCI=$2: $r"
  done
} | tee controls.txt

echo
echo "== 4. SIB1 ASN.1 decode"
python3 decode_sib1.py srsran_run.log | tee sib1_decoded.txt
