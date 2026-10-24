"""Stage 6c: Voice Aware, balance, Spatial Sound, voice prompts, Auto Power Off (last).
Safety: baseline is read first and restored after each group and again in a finally block.
Every test SET must appear byte-for-byte among the phone's captured writes (analysis/gatt.tsv) or it is skipped.
Not included: button gestures, EQ, Smart Audio & Video, LE Audio, Auracast, anything off limits."""
import asyncio, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "proto"))
from bleak import BleakClient, BleakScanner
import jbl_proto as P

NAME = "JBL Tune 780NC"
CHR_NOTIFY = "65786365-6c70-6f69-6e74-2e636f6d0001"
CHR_WRITE = "65786365-6c70-6f69-6e74-2e636f6d0002"
HOSTTYPE = bytes.fromhex("00dd0200010005002f00010001")
ACK = bytes.fromhex("00dd0200010002000000")
LOG = open(ROOT / "mac" / "probe-log.txt", "a")
rx = []
results = []

CAPTURED = set()
for line in open(ROOT / "analysis" / "gatt.tsv"):
    f = line.rstrip("\n").split("\t")
    if len(f) >= 6 and f[2] == "0x00" and f[4] == "0xb003":
        CAPTURED.add(f[5])

VA, BAL, SP, VP, VPL, APO = P.TAG_VOICE_AWARE, P.TAG_BALANCE, P.TAG_SPATIAL, P.TAG_VOICE_PROMPT, P.TAG_VOICE_PROMPT_LANG, P.TAG_AUTO_OFF
BASE_TAGS = [VA, BAL, SP, VP, VPL, APO]

# (group, label, frame, tags that must read back equal to the written TLV values)
GROUPS = [
    ("voice_aware", [("VA low", P.set_voice_aware(1)), ("VA mid", P.set_voice_aware(2)),
                     ("VA high", P.set_voice_aware(3)), ("VA off", P.set_voice_aware(3, on=False))], [VA]),
    ("balance", [("bal 0", P.set_balance(0)), ("bal -16", P.set_balance(-16)),
                 ("bal +16", P.set_balance(16)), ("bal off", P.set_balance(0, on=False))], [BAL]),
    ("spatial", [("spatial music", P.set_spatial("music")), ("spatial movie", P.set_spatial("movie")),
                 ("spatial game", P.set_spatial("game"))], [SP]),
    ("voice_prompt", [("prompts off", P.set_voice_prompt(False)), ("prompts on", P.set_voice_prompt(True))], [VP, VPL]),
    ("auto_power_off", [("apo 30 min", P.set_auto_power_off(1800)), ("apo 1 h", P.set_auto_power_off(3600)),
                        ("apo 2 h", P.set_auto_power_off(7200)), ("apo off", P.set_auto_power_off(7200, on=False))], [APO]),
]

def log(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n"); LOG.flush()

def on_notify(_, data):
    rx.append(bytes(data))

async def send(c, frame, wait=1.5):
    rx.clear()
    await c.write_gatt_char(CHR_WRITE, frame, response=True)
    await asyncio.sleep(wait)
    return list(rx)

async def get(c, tag):
    r = await send(c, P.build_get([tag]), wait=1.2)
    for f in r:
        fr = P.parse_frame(f)
        if fr.command == P.CMD_GET:
            status, tlvs = P.parse_status_tlvs(fr.payload)
            if status == 0:
                for t, v in tlvs:
                    if t == tag:
                        return v
    return None

def tlv_values(frame):
    return dict(P.parse_tlvs(P.parse_frame(frame).payload))

async def restore(c, base, tags):
    vals = [(t, base[t]) for t in tags if base.get(t) is not None]
    if not vals:
        return
    frame = P.build_set(vals)
    log("   restore", frame.hex())
    r = await send(c, frame)
    log("   restore acked:", ACK in r)

async def main():
    log("=== probe7 (suite)", time.strftime("%H:%M:%S"))
    dev = await BleakScanner.find_device_by_name(NAME, timeout=20)
    if not dev: log("not found"); return
    async with BleakClient(dev, timeout=30) as c:
        await c.start_notify(CHR_NOTIFY, on_notify)
        await asyncio.sleep(2)
        r = await send(c, HOSTTYPE, wait=2.5)
        if ACK not in r: log("no ack to HostType, stopping"); return
        base = {t: await get(c, t) for t in BASE_TAGS}
        log("baseline:", {hex(t): (v.hex() if v is not None else None) for t, v in base.items()})
        try:
            for name, steps, tags in GROUPS:
                if any(base.get(t) is None for t in tags):
                    log(f"[{name}] baseline unreadable, group skipped"); results.append((name, "-", "SKIPPED (no baseline)")); continue
                log(f"--- {name}")
                for label, frame in steps:
                    if frame.hex() not in CAPTURED:
                        log(f"   {label}: frame not in capture, skipped"); results.append((name, label, "SKIPPED")); continue
                    want = tlv_values(frame)
                    r = await send(c, frame)
                    acked = ACK in r
                    got = {t: await get(c, t) for t in want}
                    ok = acked and all(got[t] == want[t] for t in want)
                    log(f"   {label}: TX {frame.hex()} ack={acked} wrote={ {hex(t): v.hex() for t, v in want.items()} } read={ {hex(t): (v.hex() if v else None) for t, v in got.items()} } -> {'PASS' if ok else 'MISMATCH'}")
                    results.append((name, label, "PASS" if ok else "MISMATCH"))
                    if not acked:
                        raise RuntimeError("no ack, stopping the suite")
                await restore(c, base, tags)
                back = {t: await get(c, t) for t in tags}
                same = all(back[t] == base[t] for t in tags)
                log(f"   restored to baseline: {same}")
                results.append((name, "restore", "PASS" if same else "MISMATCH"))
        finally:
            log("--- final restore of everything")
            for name, _, tags in GROUPS:
                await restore(c, base, tags)
            final = {t: await get(c, t) for t in BASE_TAGS}
            log("final == baseline:", final == base, {hex(t): (v.hex() if v is not None else None) for t, v in final.items()})
    log("--- summary")
    for g, l, s in results: log(f"{g:15s} {l:14s} {s}")
    log("disconnected")

asyncio.run(main())
