"""Decode SIB1 bytes printed by the patched srsRAN pdsch_ue (SIBDUMP lines).

Reads srsran_run.log, checks that every SIB1 copy is identical, decodes it as a
BCCH-DL-SCH-Message (ASN.1 UPER, TS 36.331) and derives the cell identifiers.

Usage: python decode_sib1.py [srsran_run.log]
"""
import re
import sys

from pycrate_asn1dir import RRCLTE


def main(log):
    dumps = re.findall(r"SIBDUMP sfn=(\d+) sf=(\d+) tbs=(\d+) hex=([0-9a-f]+)", open(log).read())
    if not dumps:
        sys.exit("No SIBDUMP lines found: SIB1 was not decoded")
    for sfn, sf, tbs, hx in dumps:
        print(f"SFN {sfn} subframe {sf}: TBS {tbs} bits, CRC pass, {hx}")
    payloads = {d[3] for d in dumps}
    print(f"Identical copies: {'yes' if len(payloads) == 1 else 'NO'} ({len(dumps)} decoded)\n")

    msg = RRCLTE.EUTRA_RRC_Definitions.BCCH_DL_SCH_Message
    msg.from_uper(bytes.fromhex(dumps[0][3]))
    print(msg.to_asn1())

    sib1 = msg.get_val()["message"][1][1]
    cari = sib1["cellAccessRelatedInfo"]
    plmn = cari["plmn-IdentityList"][0]["plmn-Identity"]
    mcc = "".join(map(str, plmn["mcc"]))
    mnc = "".join(map(str, plmn["mnc"]))
    tac = int.from_bytes(cari["trackingAreaCode"][0].to_bytes(2, "big"), "big")
    eci = cari["cellIdentity"][0]
    print("\nDerived:")
    print(f"  PLMN           {mcc}-{mnc}")
    print(f"  TAC            0x{tac:04X} ({tac})")
    print(f"  ECI            0x{eci:07X} -> eNB ID {eci >> 8}, cell {eci & 0xFF}")
    print(f"  q-RxLevMin     {sib1['cellSelectionInfo']['q-RxLevMin']} -> "
          f"{2 * sib1['cellSelectionInfo']['q-RxLevMin']} dBm")
    print(f"  Band           {sib1['freqBandIndicator']}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "srsran_run.log")
