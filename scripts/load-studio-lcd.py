#!/usr/bin/env python3
"""Load native GBA Studio firmware into the Nano 20K LCD platform over USB."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import time
import zlib
import serial
from studio_game import find_game

def status(connection,timeout=5):
    deadline=time.monotonic()+timeout; data=bytearray()
    while time.monotonic()<deadline:
        data.extend(connection.read(16)); start=data.find(b'TGST')
        if start>=0 and len(data)>=start+16:
            loaded,count,crc,frames,fault=struct.unpack('<BIIHB',data[start+4:start+16])
            return dict(loaded=bool(loaded),bytes=count,crc32=f'{crc:08x}',frames=frames,cpu_fault=bool(fault))
    raise RuntimeError('No TGST reply. Program the studio_lcd FPGA image first.')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',required=True)
    parser.add_argument('--firmware',type=Path)
    parser.add_argument('--keys',type=lambda s:int(s,0))
    parser.add_argument('--hold',type=float,default=.3)
    parser.add_argument('--benchmark',type=float,default=5,help='Seconds to count rendered game frames (0 disables)')
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    if args.keys is not None and not 0<=args.keys<=255: parser.error('Key mask must fit one byte')
    if not 0<=args.hold<=60 or not 0<=args.benchmark<=60: parser.error('Durations must be 0–60 seconds')
    report={}; payload=None
    if args.firmware:
        try: args.firmware=find_game(args.firmware)
        except ValueError as error: parser.error(str(error))
        payload=args.firmware.read_bytes()
        manifest=json.loads(args.firmware.with_name('build.json').read_text(encoding='utf-8'))
        digest=hashlib.sha256(payload).hexdigest()
        if manifest.get('target')!='tangnano20k-rv32im' or manifest.get('sha256')!=digest:
            parser.error('Firmware must match a Tang RV32IM build.json manifest')
        if not 4<=len(payload)<=1048576: parser.error('Firmware must fit 1 MiB')
        report.update(firmware=str(args.firmware.resolve()),sha256=digest,bytes=len(payload))
    with serial.Serial(port=None,baudrate=115200,timeout=.1,write_timeout=5) as c:
        c.dtr=c.rts=False; c.port=args.port; c.open(); c.reset_input_buffer()
        c.write(b'Q'); c.flush(); print('Platform: '+json.dumps(status(c)),flush=True)
        if payload is not None:
            c.write(b'TGLD'+struct.pack('<I',len(payload)))
            for offset in range(0,len(payload),1024):
                c.write(payload[offset:offset+1024]); c.flush()
            crc=zlib.crc32(payload); c.write(struct.pack('<I',crc)); c.flush()
            result=status(c)
            if not result['loaded'] or result['bytes']!=len(payload) or result['crc32']!=f'{crc:08x}':
                raise RuntimeError('Firmware rejected: '+json.dumps(result))
            report['transfer']=result; print('CRC verified: '+json.dumps(result),flush=True)
            time.sleep(2)
        if args.keys is not None:
            c.write(bytes((ord('K'),args.keys))); c.flush()
            try: time.sleep(args.hold)
            finally: c.write(b'K\0'); c.flush()
        c.write(b'Q'); c.flush(); first=status(c)
        if args.benchmark:
            start=time.monotonic(); time.sleep(args.benchmark)
            c.write(b'Q'); c.flush(); last=status(c)
            elapsed=time.monotonic()-start
            report['benchmark']={'seconds':round(elapsed,3),'rendered_frames':(last['frames']-first['frames'])&65535,
                                 'fps':round(((last['frames']-first['frames'])&65535)/elapsed,3)}
        else: last=first
        report['status']=last
        debug={}
        for command in ('P','H','A'):
            c.write(command.encode()); c.flush(); debug[command]=status(c)['frames']
        report['debug']={'instruction_address':f"{(debug['H']<<16)|debug['P']:08x}",
                         'last_bus_address_low16':f"{debug['A']:04x}"}
        print(json.dumps(report),flush=True)
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    if report['status']['cpu_fault']: raise RuntimeError('RISC-V CPU trapped; see debug fields')

if __name__=='__main__': main()
