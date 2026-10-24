"""Stage 5d: send ONE captured frame (SET HostType=01, byte-for-byte from the capture), then the same read-only GETs.
Nothing else is ever written. Stops at the first unexpected reply."""
import sys as _sys
if "--i-understand" not in _sys.argv:
    _sys.exit("WARNING: this script WRITES one frame (HostType, a connect-time hello) to real headphones.\n"
              "Read mac/README.md first, then re-run with --i-understand to proceed.")
import asyncio, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "proto"))
from bleak import BleakClient, BleakScanner
import jbl_proto as P

NAME = "JBL Tune 780NC"
CHR_NOTIFY = "65786365-6c70-6f69-6e74-2e636f6d0001"
CHR_WRITE = "65786365-6c70-6f69-6e74-2e636f6d0002"
HOSTTYPE_FRAME = bytes.fromhex("00dd0200010005002f00010001")   # captured at 18:11:26.937, the only write allowed here
GET_TAGS = [0x18, 0x19, 0x1A, 0x0D, 0x04]
LOG = open(ROOT / "mac" / "probe-log.txt", "a")
rx = []

def log(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n"); LOG.flush()

def on_notify(_, data):
    data = bytes(data); rx.append(data); log("RX", data.hex())
    try: log("   ", P.parse_frame(data))
    except Exception as e: log("    parse failed:", e)

async def main():
    log("=== probe3", time.strftime("%H:%M:%S"))
    dev = await BleakScanner.find_device_by_name(NAME, timeout=15)
    if not dev: log("not found"); return
    async with BleakClient(dev, timeout=20) as c:
        log("connected:", c.is_connected)
        await c.start_notify(CHR_NOTIFY, on_notify)
        await asyncio.sleep(2)
        log("TX HostType", HOSTTYPE_FRAME.hex())
        await c.write_gatt_char(CHR_WRITE, HOSTTYPE_FRAME, response=True)
        await asyncio.sleep(2.5)
        if not rx:
            log("no reply to HostType; stopping, not sending GETs"); return
        for t in GET_TAGS:
            frame = P.build_get([t]); log("TX GET", hex(t), frame.hex())
            await c.write_gatt_char(CHR_WRITE, frame, response=True)
            await asyncio.sleep(1.5)
        await asyncio.sleep(2)
    log("disconnected")

asyncio.run(main())
