#!/usr/bin/env python3

#
# This is a simple utility to enable some very basic validation of the 
# /usr/data/pellcorp/k1/fw/K1 files to make sure they include the 
# K1_Series_Klipper Version header and CRC16, which on some MCU
# can cause a soft brick which is very inconvenient.
#
import argparse
import sys
from pathlib import Path
from binascii import hexlify, unhexlify
import struct


def get_file_metadata(args):
    file = Path(args.file)
    if not file.is_file():
        print(f'File {args.file} is not exists')
        return {}
    try:
        with file.open('rb') as rfile:
            rfile.seek(0x200)    
            bytes = rfile.read(12)
            version_header = f"{str(bytes.decode('utf-8'))}"
            type = version_header[:4]
            if type == "noz0" or type == "bed0" or type == "mcu0":
                version = version_header[5:8]
                type = type[:3]
                reserved = version_header[9:12]
                if reserved == "000":
                    bytes = rfile.read(2)
                    reversed_data = bytes[::-1]
                    crc16 = f"0x{hexlify(reversed_data).decode('utf-8')}"
                    bytes = rfile.read(2)
                    reversed_data = bytes[::-1]
                    length = f"0x{hexlify(reversed_data).decode('utf-8')}"
                    return {
                        'version': version,
                        'header': version_header,
                        'type': type,
                        'crc16': crc16,
                        'length': length
                    }
        return None
    except Exception as e:
        return None


parser = argparse.ArgumentParser(description='Creality K1 MCU Firmware File Metadata')
parser.add_argument('-f', '--file', type=str, help='firmware file')
parser.add_argument('-v', '--version', action='store_true', help='Get Version')
parser.add_argument('-x', '--header', action='store_true', help='Get Version Header')
parser.add_argument('-t', '--type', action='store_true', help='Get MCU Type')
parser.add_argument('-c', '--crc16', action='store_true', help='Get CRC16')
parser.add_argument('-l', '--length', action='store_true', help='Get Length')
args = parser.parse_args(args=None if sys.argv[1:] else ['--help'])

if args.file:
    details = get_file_metadata(args)
    if details:
        if args.header:
            print(details['header'])
        if args.version:
            print(details['version'])
        if args.type:
            print(details['type'])
        if args.crc16:
            print(details['crc16'])
        if args.length:
            print(details['length'])
        sys.exit(0)
    else:
        sys.exit(1)
