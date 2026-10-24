"""Build a publishable command-channel fixture from a private GATT table.

usage: python3 redact_fixture.py <private gatt.tsv> <out public tsv> [report.txt]

Keeps only the vendor command frames (handle 0xb003 phone writes, 0xb005 device notifications).
Removes: device serial (tag 0x08), device address (tag 0x0a), clock-sync value (tag 0x31),
host-name hash (tag 0x07), and all real timestamps / frame numbers (replaced by a counter).
Every replaced value keeps its length, so frame sizes and parsing are unchanged.

Two layers: (1) decoded tags are rewritten in single-packet frames; (2) every distinct serial, address
(both byte orders) and clock-sync value seen anywhere in the table is also swept out of every frame, decoded or not.
The 2-byte host-name hash is only removed by tag (a 2-byte byte-sweep would corrupt unrelated data).
Verification runs on the OUTPUT only and the script exits 1 if anything is left, including a value split across
packets of one multi-packet message. The report prints counts only, never the removed values.
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
    try:
        if from_device and frame.command in (1, 2, 3):
            return p.parse_status_tlvs(frame.payload)[1]
        if (not from_device) and frame.command == 2:
            return p.parse_tlvs(frame.payload)
    except Exception:
        return None
    return None


def main(src, dst, report_path=None):
    rows = [l.rstrip("\n").split("\t") for l in open(src)]
    rows = [r for r in rows if len(r) > 5 and r[4] in CMD_HANDLES and r[5]]

    serials, macs, syncs = set(), set(), set()
    for r in rows:
        f = p.parse_frame(bytes.fromhex(r[5]))
        for t, v in (tlvs_of(f, r[4] == "0xb005") or []):
            if t == TAG_SERIAL:
                serials.add(v)
            elif t == TAG_MAC:
                macs.add(v)
            elif t == TAG_SYNC:
                syncs.add(v)
    sweep = [(s, b"X" * len(s)) for s in serials]
    for m in macs:
        sweep += [(m, bytes(len(m))), (m[::-1], bytes(len(m)))]
    sweep += [(s, bytes(len(s))) for s in syncs]
    sweep = [(a, b) for a, b in sweep if len(a) >= 6 and any(a)]

    stats = {"tag_zeroed": 0, "swept": 0}
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
        for needle, repl in sweep:
            n = raw.count(needle)
            if n:
                raw = raw.replace(needle, repl); stats["swept"] += n
        out.append(("%d" % i, "t%05d" % i, r[2], r[3], r[4], raw.hex()))

    with open(dst, "w") as fh:
        for o in out:
            fh.write("\t".join(o) + "\n")

    raws = [bytes.fromhex(o[5]) for o in out]
    problems = 0
    lines = [f"rows kept: {len(out)} (command-channel rows of the private table)",
             f"distinct serials / addresses / clock-sync values found: {len(serials)} / {len(macs)} / {len(syncs)}",
             f"tag values zeroed or masked: {stats['tag_zeroed']}",
             f"extra byte-pattern replacements outside decoded tags: {stats['swept']}"]

    left = sum(b.count(a) for a, _ in sweep for b in raws)
    problems += left
    lines.append(f"remaining exact occurrences of any serial / address (both orders) / sync value: {left}")

    # values split across the packets of one multi-packet message
    split = 0
    run, last = b"", None
    for o, b in zip(out, raws):
        fr = p.parse_frame(b)
        key = (o[4], fr.command)
        if fr.count > 1:
            run = run + fr.payload if key == last else fr.payload
            last = key
            split += sum(run.count(a) for a, _ in sweep)
        else:
            run, last = b"", None
    problems += split
    lines.append(f"values left across packet boundaries of multi-packet messages: {split}")

    partial = 0
    for s in serials:
        for k in range(len(s) - 5):
            w = s[k:k + 6]
            partial += sum(b.count(w) for b in raws) if w != b"X" * 6 else 0
    for m in macs:
        for h in (m[:3], m[3:], m[:3][::-1], m[3:][::-1]):
            if any(h):
                partial += sum(b.count(h) for b in raws)
    problems += partial
    lines.append(f"remaining 6-char serial pieces / 3-byte address halves (a hit may be chance, check by hand): {partial}")

    text = open(dst).read().lower()
    forms = 0
    for v in list(serials) + list(macs) + list(syncs):
        if not any(v):
            continue
        for form in (v.hex(), v[::-1].hex(), ":".join("%02x" % c for c in v), "-".join("%02x" % c for c in v), v.hex(" ")):
            forms += text.count(form)
    problems += forms
    lines.append(f"hex/colon/dash text forms left in the output file: {forms}")

    runs = sorted({m.group().decode() for b in raws for m in re.finditer(rb"[\x20-\x7e]{5,}", b)})
    lines.append(f"printable runs of 5+ characters left: {len(runs)} -> {runs}")
    ok = sum(1 for b in raws if p.parse_frame(b) is not None)
    lines.append(f"output frames that still parse: {ok}/{len(out)}")
    lines.append("RESULT: " + ("FAIL, do not publish" if problems else "no leftovers found by these checks"))
    report = "\n".join(lines)
    print(report)
    if report_path:
        open(report_path, "w").write(report + "\n")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
