"""Passive scan, prints every BLE advertiser with its name, signal and services. No connect, no writes."""
import asyncio
from bleak import BleakScanner

async def main():
    found = await BleakScanner.discover(timeout=20, return_adv=True)
    for addr, (dev, adv) in sorted(found.items(), key=lambda kv: -kv[1][1].rssi):
        print(adv.rssi, addr, repr(adv.local_name or dev.name), [u[:8] for u in adv.service_uuids],
              {k: v.hex()[:12] for k, v in adv.manufacturer_data.items()})
    print("total:", len(found))

asyncio.run(main())
