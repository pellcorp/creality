#!/usr/bin/env python3

import argparse
import ctypes
import fcntl
import struct

UVC_SET_CUR = 0x01
UVC_GET_CUR = 0x81
UVC_GET_LEN = 0x85
UVC_GET_INFO = 0x86

UNIT = 6
SELECTOR = 16

OFF = 0
ON = 1
AUTO = 2

MODE_NAMES = {
    OFF: "off",
    ON: "on",
    AUTO: "auto",
}

_IOC_NRBITS = 8
_IOC_TYPEBITS = 8
_IOC_SIZEBITS = 14

_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS
_IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS
_IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS

_IOC_WRITE = 1
_IOC_READ = 2


def _IOC(direction, type_, nr, size):
    return (
        (direction << _IOC_DIRSHIFT)
        | (type_ << _IOC_TYPESHIFT)
        | (nr << _IOC_NRSHIFT)
        | (size << _IOC_SIZESHIFT)
    )


class UvcXuControlQuery(ctypes.Structure):
    _fields_ = [
        ("unit", ctypes.c_uint8),
        ("selector", ctypes.c_uint8),
        ("query", ctypes.c_uint8),
        ("size", ctypes.c_uint16),
        ("data", ctypes.POINTER(ctypes.c_uint8)),
    ]


UVCIOC_CTRL_QUERY = _IOC(
    _IOC_READ | _IOC_WRITE,
    ord("u"),
    0x21,
    ctypes.sizeof(UvcXuControlQuery),
)


def xu_query(fd, unit, selector, query, size, payload=None):
    buf = (ctypes.c_uint8 * size)()
    if payload is not None:
        if len(payload) != size:
            raise ValueError(f"payload length {len(payload)} != size {size}")
        for i, value in enumerate(payload):
            buf[i] = value

    xu = UvcXuControlQuery(
        unit=unit,
        selector=selector,
        query=query,
        size=size,
        data=ctypes.cast(buf, ctypes.POINTER(ctypes.c_uint8)),
    )
    fcntl.ioctl(fd, UVCIOC_CTRL_QUERY, xu)
    return bytes(buf)


def get_info(fd):
    return xu_query(fd, UNIT, SELECTOR, UVC_GET_INFO, 1)[0]


def get_len(fd):
    raw = xu_query(fd, UNIT, SELECTOR, UVC_GET_LEN, 2)
    return struct.unpack("<H", raw)[0]


def get_cur(fd, size):
    return xu_query(fd, UNIT, SELECTOR, UVC_GET_CUR, size)


def set_cur(fd, payload):
    xu_query(fd, UNIT, SELECTOR, UVC_SET_CUR, len(payload), payload)


def get_mode(device):
    with open(device, "rb+", buffering=0) as fd:
        info = get_info(fd)
        length = get_len(fd)
        if not (info & 0x01):
            raise RuntimeError("control does not report GET support")
        if length < 1:
            raise RuntimeError("control length is zero")
        return get_cur(fd, length)[0]


def set_mode(device, mode):
    with open(device, "rb+", buffering=0) as fd:
        info = get_info(fd)
        length = get_len(fd)
        if not (info & 0x02):
            raise RuntimeError("control does not report SET support")
        if length < 1:
            raise RuntimeError("control length is zero")
        current = bytearray(get_cur(fd, length))
        if current[0] == mode:
            return current[0]
        current[0] = mode
        set_cur(fd, bytes(current))
        return get_cur(fd, length)[0]


def main():
    parser = argparse.ArgumentParser(description="Control Nebula Cam IR mode")
    parser.add_argument("command", choices=["get", "off", "on", "auto"])
    parser.add_argument("device", help="video device, e.g. /dev/video0")
    args = parser.parse_args()

    if args.command == "get":
        mode = get_mode(args.device)
    elif args.command == "off":
        mode = set_mode(args.device, OFF)
    elif args.command == "on":
        mode = set_mode(args.device, ON)
    else:
        mode = set_mode(args.device, AUTO)

    print(MODE_NAMES.get(mode, f"unknown({mode})"))


if __name__ == "__main__":
    main()
