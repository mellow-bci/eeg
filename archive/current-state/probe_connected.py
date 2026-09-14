import asyncio,json
from bleak.backends.corebluetooth.CentralManagerDelegate import CentralManagerDelegate
from CoreBluetooth import CBUUID
async def main():
 manager=CentralManagerDelegate.alloc().init()
 devices=manager.central_manager.retrieveConnectedPeripheralsWithServices_([CBUUID.UUIDWithString_('81072f40-9f3d-11e3-a9dc-0002a5d5c51b')])
 print(json.dumps([{'name':str(p.name()),'id':str(p.identifier().UUIDString())} for p in devices]))
asyncio.run(main())
