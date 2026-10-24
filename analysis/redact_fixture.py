"""Build a publishable command-channel fixture from a private GATT table.

usage: python3 redact_fixture.py <private gatt.tsv> <out public tsv> [report.txt]

Keeps only the vendor command frames (handle 0xb003 phone writes, 0xb005 device notifications).
Removes: device serial (tag 0x08), device address (tag 0x0a), clock-sync value (tag 0x31),
host-name hash (tag 0x07), and all real timestamps / frame numbers (replaced by a counter).
Every replaced value keeps its length, so frame sizes and parsing are unchanged.
The serial and address are found wherever they occur, even inside frames that were never decoded.
The report prints counts only, never the removed values.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "proto"))
import jbl_proto as p  # noqa: E402

TAG_SERIAL, TAG_MAC, TAG_HOSTCRC, TAG_SYNC = 0x08, 0x0A, 0x07, 0x31
ZERO_TAGS = {TAG_MAC, TAG_HOSTCRC, TAG_SYNC}
CMD_HANDLES = ("0xb003", "0xb005")


def tlvs_of(frame, from_device):
    """TLV list of a single-packet frame, or None if it carries none."""
    if frame.count != 1:
        return None
    if frame.command == p.CMD_GET and not from_device:
        return None  # tag list only
    if from_device and frame.command in (1, 2, 3):
        return p.parse_status_tlvs(frame.payload)[1]
    if (not from_device) and frame.command == 2:
        return p.parse_tlvs(frame.payload)
    return None


def main(src, dst, report_path=None):
    rows = [l.rstrip("\n").split("\t") for l in open(src)]
    rows = [r for r in rows if len(r) > 5 and r[4] in CMD_HANDLES and r[5]]

    serial = mac = None
    for r in rows:
        f = p.parse_frame(bytes.fromhex(r[5]))
        for t, v in (tlvs_of(f, r[4] == "0xb005") or []):
            if t == TAG_SERIAL:
                serial = v
            if t == TAG_MAC:
                mac = v
    needles = [n for n in (serial, mac, mac[::-1] if mac else None) if n]

    stats = {"tag_zeroed": 0, "needle_swept": 0}
    out = []
    for i, r in enumerate(rows, 1):
        raw = bytes.fromhex(r[5])
        frame = p.parse_frame(raw)
        from_device = r[4] == "0xb005"
        tl = tlvs_of(frame, from_device)
        if tl is not None and any(t in ZERO_TAGS or t == TAG_SERIAL for t, _ in tl):
            new = []
            for t, v in tl:
                if t in ZERO_TAGS:
                    v = bytes(len(v)); stats["tag_zeroed"] += 1
                elif t == TAG_SERIAL:
                    v = b"X" * len(v); stats["tag_zeroed"] += 1
                new.append((t, v))
            if from_device:
                body = p.encode_status_tlvs(p.parse_status_tlvs(frame.payload)[0], new)
            else:
                body = p.encode_tlvs(new)
            frame = p.Frame(frame.identifier, frame.command, frame.count, frame.index, body)
            raw = frame.encode()
        for n in needles:  # sweep: anywhere else (multi-packet blobs, undecoded replies)
            while n in raw:
                raw = raw.replace(n, (b"X" * len(n)) if n is serial else bytes(len(n)))
                stats["needle_swept"] += 1
        out.append(("%d" % i, "t%05d" % i, r[2], r[3], r[4], raw.hex()))

    with open(dst, "w") as fh:
        for o in out:
            fh.write("\t".join(o) + "\n")

    lines = [f"rows kept: {len(out)} (of the command-channel rows in the private table)",
             f"tag values zeroed/masked: {stats['tag_zeroed']}",
             f"extra byte-pattern replacements outside decoded tags: {stats['needle_swept']}"]
    # verification on the output only
    leaks = 0
    for n in needles:
        hits = sum(bytes.fromhex(o[5]).count(n) for o in out)
        leaks += hits
    lines.append(f"remaining occurrences of serial / address (both byte orders): {leaks}")
    if mac:
        halves = [mac[:3], mac[3:], mac[:3][::-1], mac[3:][::-1]]
        hh = sum(bytes.fromhex(o[5]).count(h) for o in out for h in halves)
        lines.append(f"remaining occurrences of any 3-byte half of the address (may be chance matches): {hh}")
    ascii_runs = []
    for o in out:
        for m in re.finditer(rb"[\x20-\x7e]{5,}", bytes.fromhex(o[5])):
            ascii_runs.append(m.group().decode())
    lines.append(f"printable runs of 5+ characters left in the output: {len(ascii_runs)} -> {sorted(set(ascii_runs))}")
    parsed = 0
    for o in out:
        p.parse_frame(bytes.fromhex(o[5])); parsed += 1
    lines.append(f"output frames that still parse: {parsed}/{len(out)}")
    text = "\n".join(lines)
    print(text)
    if report_path:
        open(report_path, "w").write(text + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
