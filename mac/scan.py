"""Stage 5a: passive BLE scan only. No connect, no writes."""
import asyncio
from bleak import BleakScanner

SVC = "65786365-6c70-6f69-6e74-2e636f6d0000"

async def main():
    found = await BleakScanner.discover(timeout=12, return_adv=True)
    for addr, (dev, adv) in sorted(found.items(), key=lambda kv: -kv[1][1].rssi):
        name = adv.local_name or dev.name or ""
        hit = SVC in [u.lower() for u in adv.service_uuids]
        if hit or any(k in name.lower() for k in ("jbl", "tune", "harman")):
            print("MATCH", addr, repr(name), adv.rssi, adv.service_uuids)
    print("total devices seen:", len(found))

asyncio.run(main())
