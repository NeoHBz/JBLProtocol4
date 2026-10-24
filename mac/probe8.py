"""Stage 6d: direct power off. Writes ONLY: HostType (approved earlier) and ONE power-off frame (tag 0x0011 = 0000), the exact
bytes the phone sent at 18:46:14 (captures/bugreport2.zip). Sent once, never retried. The headphones switch off and the link drops;
press the power button on the headset to bring them back. Needs --i-understand --power-off --now, then a 5 second countdown (Ctrl-C cancels)."""
import sys as _sys
if not {"--i-understand", "--power-off", "--now"} <= set(_sys.argv):
    _sys.exit("WARNING: this script SWITCHES OFF the real headphones (one captured frame, sent once).\n"
              "Audio stops and you must press the power button on the headset to turn them back on.\n"
              "Re-run with: --i-understand --power-off --now   (5 second countdown, Ctrl-C cancels)")
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
POWER_OFF = bytes.fromhex("00dd020001000600110002000000")   # 1x in capture, tag 0x0011 ManualPowerOff = 0
ACK = bytes.fromhex("00dd0200010002000000")
# sanity: header, length 6, then tag 0x0011, value length 2, value 0000
assert POWER_OFF[:8] == bytes.fromhex("00dd020001000600") and POWER_OFF[8:] == bytes.fromhex("110002000000")
LOG = open(ROOT / "mac" / "probe-log.txt", "a")
rx = []
dropped = None  # created inside main (Python 3.9 binds Event to the loop at creation)
loop = None

def log(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n"); LOG.flush()

def on_notify(_, data):
    data = bytes(data); rx.append(data); log("RX", data.hex())

def on_disconnect(_):
    log("LINK DROPPED", time.strftime("%H:%M:%S")); loop.call_soon_threadsafe(dropped.set)

async def send(c, frame, label, wait=2.5):
    rx.clear(); log("TX", label, frame.hex())
    await c.write_gatt_char(CHR_WRITE, frame, response=True)
    await asyncio.sleep(wait)
    return list(rx)

async def main():
    global dropped, loop
    dropped = asyncio.Event(); loop = asyncio.get_running_loop()
    log("=== probe8 (power off)", time.strftime("%H:%M:%S"))
    dev = await BleakScanner.find_device_by_name(NAME, timeout=20)
    if not dev: log("not found. Are the headphones on and not in another app?"); return
    async with BleakClient(dev, timeout=30, disconnected_callback=on_disconnect) as c:
        await c.start_notify(CHR_NOTIFY, on_notify)
        await asyncio.sleep(2)
        r = await send(c, HOSTTYPE, "HostType")
        if ACK not in r: log("no ack to HostType, stopping (nothing sent)"); return
        r = await send(c, P.build_get([0x0D]), "GET battery"); log("battery frames:", [f.hex() for f in r])
        for n in range(5, 0, -1):
            print(f"Powering off in {n} s (Ctrl-C to cancel)", flush=True); await asyncio.sleep(1)
        rx.clear(); log("TX SET power off (once)", POWER_OFF.hex())
        try:
            await c.write_gatt_char(CHR_WRITE, POWER_OFF, response=True)
        except Exception as e:
            log("write ended with", repr(e), "(the link may drop before the response)")
        try:
            await asyncio.wait_for(dropped.wait(), 10)
        except asyncio.TimeoutError:
            log("link still up after 10 s: power off did NOT take effect")
        log("frames after write:", [f.hex() for f in rx], "| acked:", ACK in rx)
    log("done. Press the power button on the headset to turn it back on, then re-run mac/scan.py to see it advertise again.")

asyncio.run(main())
