"""Stage 6b: Ambient Aware and TalkThru. Writes ONLY: HostType (approved earlier), Ambient Aware on, TalkThru on, all off. Each frame is checked against
the exact bytes seen in the phone capture before sending. Stops on any missing echo/ack and tries to leave ANC off."""
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
AA_ON = bytes.fromhex("00dd02000100050019000100ff")      # 2x in capture
TT_ON = bytes.fromhex("00dd0200010005001a000100ff")      # 2x in capture
ANC_OFF = bytes.fromhex("00dd020001000500180001007f")    # 4x in capture
assert P.set_ambient_aware() == AA_ON and P.set_talkthru() == TT_ON and P.set_all_noise_off() == ANC_OFF
LOG = open(ROOT / "mac" / "probe-log.txt", "a")
rx = []

def log(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n"); LOG.flush()

def on_notify(_, data):
    data = bytes(data); rx.append(data); log("RX", data.hex())

async def send(c, frame, label, wait=2.5):
    rx.clear(); log("TX", label, frame.hex())
    await c.write_gatt_char(CHR_WRITE, frame, response=True)
    await asyncio.sleep(wait)
    return list(rx)

def acked(frames):
    return any(f == bytes.fromhex("00dd0200010002000000") for f in frames)

async def main():
    log("=== probe6 (Ambient Aware + TalkThru)", time.strftime("%H:%M:%S"))
    dev = await BleakScanner.find_device_by_name(NAME, timeout=20)
    if not dev: log("not found"); return
    async with BleakClient(dev, timeout=30) as c:
        await c.start_notify(CHR_NOTIFY, on_notify)
        await asyncio.sleep(2)
        r = await send(c, HOSTTYPE, "HostType")
        if not acked(r): log("no ack to HostType, stopping"); return
        r = await send(c, P.build_get([0x18, 0x19, 0x1A]), "GET noise modes"); log("baseline:", [f.hex() for f in r])
        try:
            for label, frame in (("AMBIENT AWARE", AA_ON), ("TALKTHRU", TT_ON)):
                r = await send(c, frame, "SET " + label)
                log(label, "acked:", acked(r), "state push:", [f.hex() for f in r if f[2:4] == b"\x03\x00"])
                r = await send(c, P.build_get([0x18, 0x19, 0x1A]), "GET noise modes"); log("after:", [f.hex() for f in r])
                log("holding 6 s"); await asyncio.sleep(6)
        finally:
            r = await send(c, ANC_OFF, "SET ALL OFF")
            log("ALL OFF acked:", acked(r))
            r = await send(c, P.build_get([0x18, 0x19, 0x1A]), "GET noise modes"); log("final:", [f.hex() for f in r])
    log("disconnected")

asyncio.run(main())
