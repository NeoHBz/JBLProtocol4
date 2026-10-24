"""Stage 5f: try to get macOS to bond over LE, then repeat the approved probe3 steps.
Sends only: standard/Fast-Pair READS (to trigger the pairing dialog), then the one captured HostType frame,
then the same five read-only GETs. Never touches the Fast Pair write characteristics."""
import sys as _sys
if "--i-understand" not in _sys.argv:
    _sys.exit("WARNING: this script WRITES one frame (HostType, a connect-time hello) to real headphones and triggers a macOS pairing dialog.\n"
              "Read mac/README.md first, then re-run with --i-understand to proceed.")
import asyncio, json, os, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "proto"))
from bleak import BleakClient, BleakScanner
import jbl_proto as P

NAME = "JBL Tune 780NC"
CHR_NOTIFY = "65786365-6c70-6f69-6e74-2e636f6d0001"
CHR_WRITE = "65786365-6c70-6f69-6e74-2e636f6d0002"
BATT = "00002a19-0000-1000-8000-00805f9b34fb"
FP_READS = ["fe2c1233-8366-4814-8eb0-01de32100bea",   # Fast Pair model ID (read only)
            "fe2c1239-8366-4814-8eb0-01de32100bea",
            "fe2c123a-8366-4814-8eb0-01de32100bea"]
HOSTTYPE_FRAME = bytes.fromhex("00dd0200010005002f00010001")   # captured at 18:11:26.937
GET_TAGS = [0x18, 0x19, 0x1A, 0x0D, 0x04]
LOG = open(ROOT / "mac" / "probe-log.txt", "a")
try:
    LOCAL = json.load(open(ROOT / "local.config.json"))
except OSError:
    LOCAL = {}
rx = []

def log(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n"); LOG.flush()

def on_notify(_, data):
    data = bytes(data); rx.append(data); log("RX", data.hex())
    try: log("   ", P.parse_frame(data))
    except Exception as e: log("    parse failed:", e)

async def main():
    log("=== probe4", time.strftime("%H:%M:%S"))
    log("scanning (headphones should be in pairing mode)...")
    # In pairing mode the headphones advertise no name. Optionally match their beacon by the first bytes of the
    # device address, given as hex in env JBL_BEACON_PREFIX or "beacon_prefix_hex" in local.config.json (gitignored).
    prefix = bytes.fromhex(os.environ.get("JBL_BEACON_PREFIX") or LOCAL.get("beacon_prefix_hex", "") or "")
    def match(d, adv):
        return (adv.local_name == NAME) or (bool(prefix) and prefix in adv.manufacturer_data.get(6, b""))
    dev = await BleakScanner.find_device_by_filter(match, timeout=25)
    if not dev: log("not found"); return
    log("found", dev.address)
    async with BleakClient(dev, timeout=30) as c:
        log("connected:", c.is_connected)
        print(">>> If macOS shows a pairing dialog now, click Connect/Accept. Waiting up to 40 s per read.")
        for u in [BATT] + FP_READS:
            try:
                v = await asyncio.wait_for(c.read_gatt_char(u), 40)
                log("READ", u[:8], v.hex())
            except Exception as e:
                log("read failed", u[:8], repr(e))
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
