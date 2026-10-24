"""Stage 5c: strictly passive. Connect, READ the standard Battery level, READ the vendor notify char,
subscribe and just listen. Sends no command frames and writes nothing except the standard notify enable."""
import asyncio, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "proto"))
from bleak import BleakClient, BleakScanner
import jbl_proto as P

NAME = "JBL Tune 780NC"
BATT = "00002a19-0000-1000-8000-00805f9b34fb"
VEND = "65786365-6c70-6f69-6e74-2e636f6d0001"
LOG = open(ROOT / "mac" / "probe-log.txt", "a")

def log(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n"); LOG.flush()

def on_vendor(_, data):
    data = bytes(data); log("RX vendor", data.hex())
    try: log("   ", P.parse_frame(data))
    except Exception as e: log("    parse failed:", e)

def on_batt(_, data):
    log("RX battery notify", bytes(data).hex(), "=", bytes(data)[0], "%")

async def main():
    log("=== probe2", time.strftime("%H:%M:%S"))
    dev = await BleakScanner.find_device_by_name(NAME, timeout=15)
    if not dev: log("not found"); return
    async with BleakClient(dev, timeout=20) as c:
        log("connected:", c.is_connected)
        try:
            b = await c.read_gatt_char(BATT); log("READ battery 0x2a19:", b.hex(), "=", b[0], "%")
        except Exception as e: log("battery read failed:", e)
        try:
            v = await c.read_gatt_char(VEND); log("READ vendor ...0001:", v.hex())
        except Exception as e: log("vendor read failed:", e)
        await c.start_notify(VEND, on_vendor)
        try: await c.start_notify(BATT, on_batt)
        except Exception as e: log("battery notify failed:", e)
        log("listening 15 s, sending nothing")
        await asyncio.sleep(15)
    log("disconnected")

asyncio.run(main())
