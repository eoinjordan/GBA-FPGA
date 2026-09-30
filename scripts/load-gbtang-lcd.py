#!/usr/bin/env python3
"""Load a local DMG ROM into the volatile GBTang LCD build over USB UART."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import time
import zlib
import serial


def status(port, timeout=5):
    deadline=time.monotonic()+timeout
    data=bytearray()
    while time.monotonic()<deadline:
        data.extend(port.read(16))
        start=data.find(b'GBST')
        if start>=0 and len(data)>=start+16:
            loaded,count,crc,address,fault=struct.unpack('<BIIHB',data[start+4:start+16])
            return dict(loaded=bool(loaded),bytes=count,crc32=f'{crc:08x}',cart_address=f'{address:04x}',cpu_fault=bool(fault))
    raise RuntimeError('No GBST response from the LCD firmware')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',required=True)
    parser.add_argument('--rom',type=Path)
    parser.add_argument('--keys',type=lambda v:int(v,0),help='GB mask: A=1 B=2 Select=4 Start=8 Right=16 Left=32 Up=64 Down=128')
    parser.add_argument('--hold',type=float,default=.2)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    if args.keys is not None and not 0<=args.keys<=255:
        parser.error('Key mask must fit one byte')
    if not 0<=args.hold<=30:
        parser.error('Hold time must be 0–30 seconds')
    report={}
    payload=None
    if args.rom:
        payload=args.rom.read_bytes()
        if not 32768<=len(payload)<=1048576 or payload[0x143]&0x80:
            parser.error('This bring-up build accepts DMG ROMs of 32 KiB to 1 MiB')
        if (sum(payload[0x134:0x14d])+25+payload[0x14d])&255:
            parser.error('Game Boy header checksum failed')
        if payload[0x147] not in (0,0x13,0x19,0x1a,0x1b):
            parser.error('Unverified mapper; supported: ROM-only, MBC3 RAM without RTC, MBC5 without rumble')
        report.update(rom=str(args.rom.resolve()),sha256=hashlib.sha256(payload).hexdigest(),bytes=len(payload))
    with serial.Serial(port=None,baudrate=115200,timeout=.1,write_timeout=5) as connection:
        connection.dtr=connection.rts=False
        connection.port=args.port
        connection.open()
        connection.reset_input_buffer()
        connection.write(b'Q'); connection.flush()
        print('Firmware: '+json.dumps(status(connection)),flush=True)
        if payload is not None:
            crc=zlib.crc32(payload)
            connection.write(b'GBLD'+struct.pack('<I',len(payload)))
            last=time.monotonic()
            for offset in range(0,len(payload),1024):
                connection.write(payload[offset:offset+1024]); connection.flush()
                if time.monotonic()-last>=10:
                    print(f'ROM {min(offset+1024,len(payload))}/{len(payload)} bytes',flush=True)
                    last=time.monotonic()
            connection.write(struct.pack('<I',crc)); connection.flush()
            result=status(connection)
            if not result['loaded'] or result['bytes']!=len(payload) or result['crc32']!=f'{crc:08x}':
                raise RuntimeError('ROM transfer rejected: '+json.dumps(result))
            report['transfer']=result
            print('CRC verified: '+json.dumps(result),flush=True)
            # Start only after the full ROM has passed CRC verification.
            time.sleep(2)
        if args.keys is not None:
            connection.write(bytes((ord('K'),args.keys))); connection.flush()
            try:
                time.sleep(args.hold)
            finally:
                connection.write(b'K\0'); connection.flush()
        connection.write(b'Q'); connection.flush()
        report['status']=status(connection)
        print(json.dumps(report),flush=True)
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
