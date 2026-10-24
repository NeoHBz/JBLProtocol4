"""Stage 5b: connect, list services, subscribe, send READ-ONLY GET frames. No SET is ever built here."""
import asyncio, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "proto"))
from bleak import BleakClient, BleakScanner
import jbl_proto as P

NAME = "JBL Tune 780NC"
CHR_NOTIFY = "65786365-6c70-6f69-6e74-2e636f6d0001"
CHR_WRITE = "65786365-6c70-6f69-6e74-2e636f6d0002"
GET_TAGS = [0x18, 0x19, 0x1A, 0x0D, 0x04]   # ANC, Ambient, TalkThru, battery candidate, ProductID
LOG = open(ROOT / "mac" / "probe-log.txt", "a")

def log(*a):
    s = " ".join(str(x) for x in a)
    print(s); LOG.write(s + "\n"); LOG.flush()

def on_notify(_, data):
    data = bytes(data)
    log("RX", data.hex())
    try:
        f = P.parse_frame(data)
        log("   ", f)
    except Exception as e:
        log("    parse failed:", e)

async def main():
    log("=== probe", time.strftime("%H:%M:%S"))
    dev = await BleakScanner.find_device_by_name(NAME, timeout=15)
    if not dev:
        log("not found"); return
    async with BleakClient(dev, timeout=20) as c:
        log("connected:", c.is_connected)
        for s in c.services:
            log("SVC", s.uuid)
            for ch in s.characteristics:
                log("   CHR", ch.uuid, ch.properties)
        await c.start_notify(CHR_NOTIFY, on_notify)
        await asyncio.sleep(2)
        for t in GET_TAGS:
            frame = P.build_get([t])
            log("TX GET", hex(t), frame.hex())
            await c.write_gatt_char(CHR_WRITE, frame, response=True)
            await asyncio.sleep(1.5)
        await asyncio.sleep(2)
        await c.stop_notify(CHR_NOTIFY)
    log("disconnected")

asyncio.run(main())
