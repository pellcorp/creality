#!/usr/bin/env python3
"""Find and interrogate the K1-MAX-L_V23 leveling board (CH32V203 + 4x CS1237) over its UART.

The board runs Creality's factory Klipper build (CTF_V1.0.0.16.20250320) and speaks the plain
Klipper wire protocol at 230400, 3.3 V TTL. This script talks that protocol directly, so it needs
only pyserial: no Klipper tree, no compiled chelper, no running Kalico. It runs the same on the
workstation (CH341 on /dev/ttyUSB0) and on the printer (/usr/share/klippy-env/bin/python3).

Never point it at the K1 mainboard's ttyS9 without a MAX3232 in between: that port is RS-232
(TX idles at -5.5 V), and the board can't read it. See the PR notes / INSTALL.md for the wiring.

Only read-only commands are sent by default. `send` refuses anything else unless --unsafe is given.

Usage:
  v23_leveling.py scan [-v] [--probe]       find ports carrying Klipper frames / answering identify
                                                (-v also lists ports that can't be opened)
  v23_leveling.py listen   PORT [-t SECS] [--decode]   dump frames (raw, and decoded with --decode)
  v23_leveling.py identify PORT [-o FILE]   fetch the data dictionary, summarise, optionally save
  v23_leveling.py status   PORT             identify + get_config / get_uptime / get_clock
  v23_leveling.py send     PORT "CMD [arg=val ...]" [--unsafe]   send one command
  v23_leveling.py selftest                  offline protocol checks, no hardware (takes no port)

`send` read-only commands (full table: `send -h`):
  get_uptime  get_clock  get_config  identify  debug_nop  debug_ping data=..  debug_read order= addr=

Common option: -b BAUD (default 230400), given before the subcommand. Kalico must not have the
port open as an [mcu] while this runs.
"""
import argparse
import glob
import json
import os
import re
import threading
import sys
import time
import zlib

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("needs pyserial: pip install pyserial (on the printer use /usr/share/klippy-env/bin/python3)")

BAUD = 230400
SYNC = 0x7E
MSG_MIN, MSG_MAX = 5, 64
# Read-only commands `send` allows without --unsafe: name -> (example line, what it returns).
# All present in the V23's CTF_V1.0.0.16.20250320 dictionary.
SAFE_COMMANDS = {
    "get_uptime": ("get_uptime", "uptime high= clock=  (64-bit ticks since MCU reset, 144 MHz)"),
    "get_clock":  ("get_clock", "clock clock=  (low 32 bits of the MCU clock)"),
    "get_config": ("get_config", "config is_config= crc= is_shutdown= move_count=  (0/0 = unconfigured)"),
    "identify":   ("identify offset=0 count=40", "identify_response offset= data=  (one dictionary chunk)"),
    "debug_nop":  ("debug_nop", "nothing (link check: no reply expected)"),
    "debug_ping": ("debug_ping data=hello", "pong data=  (echoes data)"),
    "debug_read": ("debug_read order=2 addr=0x1FFFF7E8", "debug_result val=  (order 0/1/2 = 8/16/32-bit read; "
                   "0x1FFFF7E8 = CH32V203 unique ID word 0)"),
}
SEND_EPILOG = ("read-only commands (allowed without --unsafe):\n" +
               "".join("  %-36s -> %s\n" % (ex, ret) for ex, ret in SAFE_COMMANDS.values()) +
               "\nargs are name=value, ints in decimal or 0x hex, %*s args as plain text.\n"
               "Everything else the board knows (73 commands, incl. config_prtouch_pres / start_prtouch_pres /\n"
               "read_prtouch_pres / stop_prtouch_pres, set_digital_out, queue_step, reset, emergency_stop)\n"
               "needs --unsafe: it can configure pins, drive outputs, or reset/shut down the MCU.\n"
               "Full list with parameter formats: `identify PORT -o dict.json`, then look at \"commands\".")


# --- wire format ---------------------------------------------------------------------------

def crc16(data):
    crc = 0xFFFF
    for b in data:
        b ^= crc & 0xFF
        b ^= (b & 0x0F) << 4
        crc = ((b << 8) | (crc >> 8)) ^ (b >> 4) ^ (b << 3)
        crc &= 0xFFFF
    return crc


def enc_vlq(v):
    out = []
    if -(1 << 26) <= v < (3 << 26):
        if -(1 << 19) <= v < (3 << 19):
            if -(1 << 12) <= v < (3 << 12):
                if -(1 << 5) <= v < (3 << 5):
                    pass
                else:
                    out.append((v >> 7) & 0x7F | 0x80)
            else:
                out += [(v >> 14) & 0x7F | 0x80, (v >> 7) & 0x7F | 0x80]
        else:
            out += [(v >> 21) & 0x7F | 0x80, (v >> 14) & 0x7F | 0x80, (v >> 7) & 0x7F | 0x80]
    else:
        out += [(v >> 28) & 0x7F | 0x80, (v >> 21) & 0x7F | 0x80,
                (v >> 14) & 0x7F | 0x80, (v >> 7) & 0x7F | 0x80]
    out.append(v & 0x7F)
    return bytes(out)


def dec_vlq(buf, pos):
    c = buf[pos]
    pos += 1
    v = c & 0x7F
    if c & 0x60 == 0x60:
        v |= -0x20
    while c & 0x80:
        c = buf[pos]
        pos += 1
        v = (v << 7) | (c & 0x7F)
    return v, pos


def frame(seq, payload):
    blk = bytes([len(payload) + MSG_MIN, 0x10 | (seq & 0x0F)]) + payload
    c = crc16(blk)
    return blk + bytes([c >> 8, c & 0xFF, SYNC])


def split_frames(buf, seqs=None):
    """Return (list of payloads from valid frames, leftover bytes, count of bytes discarded).

    If `seqs` is a list, the sequence nibble of every valid frame is appended to it. In frames
    from the MCU that nibble is the next sequence number it expects from the host; an empty
    payload is an ack/nak block.
    """
    out, junk = [], 0
    while buf:
        n = buf[0]
        if not MSG_MIN <= n <= MSG_MAX:
            buf, junk = buf[1:], junk + 1
            continue
        if len(buf) < n:
            break
        f = buf[:n]
        if f[-1] == SYNC and crc16(f[:-3]) == (f[-3] << 8 | f[-2]):
            out.append(f[2:-3])
            if seqs is not None:
                seqs.append(f[1] & 0x0F)
            buf = buf[n:]
        else:
            buf, junk = buf[1:], junk + 1
    return out, buf, junk


# --- message encoding from the data dictionary ---------------------------------------------

PARAM_RE = re.compile(r"(\w+)=(%[a-z.*]+)")
WIDTH = {"%c": (8, False), "%hu": (16, False), "%hi": (16, True), "%u": (32, False), "%i": (32, True)}


def fix_width(v, fmt):
    """Klipper sends every int as a signed VLQ; cut it back to the field's declared width."""
    bits, signed = WIDTH.get(fmt, (32, True))
    v &= (1 << bits) - 1
    return v - (1 << bits) if signed and v >> (bits - 1) else v


class Dictionary:
    def __init__(self, d):
        self.raw = d
        self.cmd_by_name = {}       # name -> (id, [(param, fmt)])
        self.resp_by_id = {}        # id -> (name, [(param, fmt)])
        for fmtstr, mid in d.get("commands", {}).items():
            name = fmtstr.split()[0]
            self.cmd_by_name[name] = (mid, PARAM_RE.findall(fmtstr))
        for fmtstr, mid in list(d.get("responses", {}).items()) + list(d.get("output", {}).items()):
            name = fmtstr.split()[0]
            self.resp_by_id[mid] = (name, PARAM_RE.findall(fmtstr))

    def encode(self, line):
        parts = line.split()
        name, args = parts[0], dict(a.split("=", 1) for a in parts[1:])
        if name not in self.cmd_by_name:
            raise SystemExit("unknown command %r (see `identify`)" % name)
        mid, params = self.cmd_by_name[name]
        out = enc_vlq(mid)
        for p, fmt in params:
            v = args.get(p, "0")
            if "s" in fmt:
                b = v.encode()
                out += enc_vlq(len(b)) + b
            else:
                out += enc_vlq(int(v, 0))
        return out

    def decode(self, payload):
        """Decode one payload into a list of (name, {param: value}) messages."""
        msgs, pos = [], 0
        while pos < len(payload):
            mid, pos = dec_vlq(payload, pos)
            if mid not in self.resp_by_id:
                msgs.append(("unknown_msgid_%d" % mid, {"rest": payload[pos:].hex(" ")}))
                break
            name, params = self.resp_by_id[mid]
            vals = {}
            for p, fmt in params:
                if "s" in fmt:
                    ln, pos = dec_vlq(payload, pos)
                    vals[p] = bytes(payload[pos:pos + ln])
                    pos += ln
                else:
                    v, pos = dec_vlq(payload, pos)
                    vals[p] = fix_width(v, fmt)
            msgs.append((name, vals))
        return msgs


# --- link ----------------------------------------------------------------------------------

def open_port(port, baud, timeout, quiet=False):
    """Open exclusively (TIOCEXCL), so ModemManager & co can't probe the port mid-session.

    A freshly plugged CH341 gets AT-probed by ModemManager for ~15-30 s, which eats or garbles
    the board's frames. If the port is busy, say who has it instead of silently hearing nothing.
    """
    if not os.path.exists(port):
        if quiet:
            raise serial.SerialException("no such port")
        sys.exit("%s does not exist (adapter not plugged in? try `scan`)" % port)
    try:
        return serial.Serial(port, baud, timeout=timeout, exclusive=True)
    except serial.SerialException as e:
        if quiet:
            raise
        sys.exit("cannot open %s exclusively (%s).\n"
                 "Something else has it: check `fuser -v %s`. If you just plugged the adapter in, "
                 "ModemManager may still be probing it; wait 30 s, or tell it to ignore CH341 "
                 "adapters (udev ENV{ID_MM_DEVICE_IGNORE}=\"1\")." % (port, e, port))

class Link:
    def __init__(self, port, baud):
        self.ser = open_port(port, baud, 0.05)
        self.seq = 0
        self.buf = b""
        self.ser.write(bytes([SYNC]) * 3)           # resync the MCU's receive state machine
        time.sleep(0.05)
        self.ser.reset_input_buffer()

    def send(self, payload):
        self.ser.write(frame(self.seq, payload))
        self.seq += 1

    def frames(self, timeout):
        end = time.time() + timeout
        while time.time() < end:
            self.buf += self.ser.read(256)
            seqs = []
            got, self.buf, _ = split_frames(self.buf, seqs)
            if seqs:
                self.mcu_seq = seqs[-1]
            for p in got:
                if p:                       # skip empty ack/nak blocks
                    yield p

    def resync(self):
        """Adopt the sequence number the MCU last said it expects (it NAKs a stale counter)."""
        if self.mcu_seq is not None:
            self.seq = self.mcu_seq

    mcu_seq = None

    def identify(self, retries=4):
        for _ in range(retries):
            data, off = b"", 0
            while True:
                self.send(enc_vlq(1) + enc_vlq(off) + enc_vlq(40))    # identify offset count
                chunk = None
                for p in self.frames(0.5):
                    try:
                        mid, pos = dec_vlq(p, 0)
                        if mid != 0:                                 # identify_response
                            continue
                        roff, pos = dec_vlq(p, pos)
                        ln, pos = dec_vlq(p, pos)
                    except IndexError:                               # truncated/foreign frame
                        continue
                    if roff == off:
                        chunk = p[pos:pos + ln]
                        break
                if chunk is None:
                    break
                if not chunk:
                    return Dictionary(json.loads(zlib.decompress(data)))
                data += chunk
                off += len(chunk)
            self.ser.write(bytes([SYNC]) * 3)
            time.sleep(0.1)
            self.resync()
        return None

    def ask(self, d, line, timeout=1.0, tries=3, want=None):
        """Send `line`, return the first reply (or the first `want`-named reply, skipping others)."""
        for _ in range(tries):
            self.send(d.encode(line))
            for p in self.frames(timeout):
                try:
                    msgs = d.decode(p)
                except IndexError:
                    msgs = [("undecodable", {"payload": p.hex(" ")})]
                msgs = [m for m in msgs if want is None or m[0] == want]
                if msgs:
                    return msgs
            self.resync()
        return []


# --- subcommands ---------------------------------------------------------------------------

def candidate_ports():
    """One entry per physical port; prefer the stable /dev/serial/by-id name when there is one."""
    ports = {}
    for dev, desc in [(p.device, p.description or "") for p in list_ports.comports()] + \
                     [(dev, "") for dev in glob.glob("/dev/ttyS*") + glob.glob("/dev/serial/by-id/*")]:
        real = os.path.realpath(dev)
        name, old_desc = ports.get(real, (None, ""))
        if name is None or "/by-id/" in dev:
            name = dev
        ports[real] = (name, desc or old_desc)
    return sorted(ports.values())


def cmd_scan(a):
    print("%-58s %-8s %s" % ("port", "frames", "result"))
    for dev, desc in candidate_ports():
        try:
            s = open_port(dev, a.baud, 0.1, quiet=True)
        except Exception as e:
            if a.verbose:   # e.g. the phantom legacy ttyS0-3 every PC kernel creates
                print("%-58s %-8s skip (%s)" % (dev, "-", str(e).split(":")[0]))
            continue
        s.reset_input_buffer()
        buf, end = b"", time.time() + a.listen
        while time.time() < end:
            buf += s.read(256)
        s.close()
        good, _, junk = split_frames(buf)
        verdict = "%d valid / %d junk bytes" % (len(good), junk)
        if good or a.probe:
            try:
                d = Link(dev, a.baud).identify()
            except Exception:
                d = None
            if d:
                c = d.raw.get("config", {})
                verdict += " -> IDENTIFIED %s %s" % (c.get("MCU"), d.raw.get("version"))
        elif junk:
            verdict += " (bytes but no Klipper framing: wrong baud/levels? RS-232 port?)"
        print("%-58s %-8d %s  %s" % (dev, len(good), verdict, desc))


def cmd_listen(a):
    link = Link(a.port, a.baud)
    d = link.identify() if a.decode else None
    start = time.time()
    while time.time() - start < a.time:
        raw = link.ser.read(256)
        if not raw:
            continue
        print("%6.2f raw %s" % (time.time() - start, raw.hex(" ")))
        link.buf += raw
        got, link.buf, junk = split_frames(link.buf)
        for p in got:
            print("       frame %s%s" % (p.hex(" "), "  " + str(d.decode(p)) if d else ""))
        if junk:
            print("       (%d bytes not Klipper-framed)" % junk)


def summarise(d):
    r, c = d.raw, d.raw.get("config", {})
    print("version :", r.get("version"))
    print("build   :", r.get("build_versions"))
    print("MCU     : %s  CLOCK_FREQ=%s  SERIAL_BAUD=%s" % (c.get("MCU"), c.get("CLOCK_FREQ"), c.get("SERIAL_BAUD")))
    print("reserved: %s" % {k: v for k, v in c.items() if k.startswith(("RESERVE_", "BUS_PINS"))})
    print("commands: %d   responses: %d" % (len(r.get("commands", {})), len(r.get("responses", {}))))
    for k in sorted(r.get("commands", {})):
        if any(s in k for s in ("prtouch", "cs12", "hx7", "pres", "swap", "load_cell")):
            print("   ", k)


def cmd_identify(a):
    d = Link(a.port, a.baud).identify()
    if not d:
        sys.exit("no identify_response: board absent, wrong baud, or wrong levels (RS-232?)")
    summarise(d)
    if a.out:
        json.dump(d.raw, open(a.out, "w"), indent=1)
        print("saved", a.out)


def cmd_status(a):
    link = Link(a.port, a.baud)
    d = link.identify()
    if not d:
        sys.exit("no identify_response")
    summarise(d)
    freq = d.raw.get("config", {}).get("CLOCK_FREQ") or 1
    for line in ("get_config", "get_uptime", "get_clock"):
        if line.split()[0] not in d.cmd_by_name:
            continue
        for name, vals in link.ask(d, line):
            extra = ""
            if name == "uptime":
                ticks = (vals.get("high", 0) << 32) | vals.get("clock", 0)
                extra = "  (= %.1f s since MCU reset)" % (ticks / freq)
            print("%-11s -> %s %s%s" % (line, name, vals, extra))


def cmd_send(a):
    name = a.line.split()[0]
    if name not in SAFE_COMMANDS and not a.unsafe:
        sys.exit("%r is not on the read-only list %s; add --unsafe if you mean it" % (name, sorted(SAFE_COMMANDS)))
    link = Link(a.port, a.baud)
    d = link.identify()
    if not d:
        sys.exit("no identify_response")
    for name, vals in link.ask(d, a.line, timeout=a.wait) or [("(no reply)", {})]:
        print(name, vals)


# --- load cells (prtouch_v3 pressure path) -------------------------------------------------
# Reconstructed from Creality's prtouch_v3_wrapper.pyc (X2000E V1.1.0.27, disassembled on the
# printer's own Python 3.8): PrtouchPres._build_config, cmd_READ_PRES and
# PRTouchEndstopWrapper.unzip_data. Pins from config/k1max-x2600-cfs-c.

V23_CHANNELS = [("PB10", "PB2"), ("PB1", "PB0"), ("PA7", "PA6"), ("PA5", "PA4")]   # (clk, sdo)
V23_SWAP_PIN = "PA8"            # SYNC line to the mainboard (step_swap_pin on the host side)
CFG_REGS = 60                   # pres_cfg_regs 0x3C: CS1237 1280 Hz, PGA 128
ACQ_MS = 0.78125                # acq_tkms default when cfg_regs & 0x30 == 0x30 (1280 Hz)
DED_MS = 128                    # ded_tkms default (non-hx711) -> lmt_dead
SCRIPT_CRC = 0x7623             # finalize_config crc this script uses, to recognise its own config


def pin_number(d, name):
    """Map 'PB10' to the MCU's pin number via the dictionary's pin enumeration ranges."""
    for base, (start, count) in d.raw.get("enumerations", {}).get("pin", {}).items():
        port, first = base[:-1], int(base[-1])
        if name.startswith(port) and name[len(port):].isdigit():
            idx = int(name[len(port):]) - first
            if 0 <= idx < count:
                return start + idx
    raise SystemExit("pin %s not in the board's pin enumeration" % name)


def unzip_data(data, signed):
    """Creality's packing: data[0]=count, then 2-bit length codes (4 per byte, stored from the
    end of the header backwards), then little-endian delta-coded values."""
    n = data[0]
    ptr = -(-n // 4) + 1                      # ceil(n/4) + 1
    idx, out = ptr, []
    for i in range(n):
        v_len = 1 + ((data[ptr - ((i >> 2) + 1)] >> ((i & 3) << 1)) & 3)
        out.append(int.from_bytes(data[idx:idx + v_len], "little", signed=True))
        out[-1] += 0 if len(out) == 1 else out[-2]
        idx += v_len
    return out if signed else [v & 0xFFFFFFFF for v in out]


def prtouch_open(port, baud):
    """Connect and make sure the board carries this script's prtouch config (configure if fresh)."""
    link = Link(port, baud)
    d = link.identify()
    if not d:
        sys.exit("no identify_response")
    cfg = dict(link.ask(d, "get_config", want="config")).get("config", {})
    if cfg.get("is_config") and cfg.get("crc") == SCRIPT_CRC:
        print("board still configured by a previous run of this script: reusing that config")
    elif cfg.get("is_config"):
        # A Klipper `reset` on this board drops it into its IAP bootloader, which waits for
        # Creality's cmd_iap to start the app. Don't do that from here; power-cycle instead.
        sys.exit("board is configured by something else (Kalico? crc=%s). Power-cycle the board "
                 "(or restart Kalico without it) so it comes up unconfigured, then rerun." % cfg.get("crc"))
    else:
        swap = pin_number(d, V23_SWAP_PIN)
        link.send(d.encode("allocate_oids count=1"))
        for idx, (clk, sdo) in enumerate(V23_CHANNELS):
            link.send(d.encode("config_prtouch_pres oid=0 idx=%d swp_pin=%d clk_pin=%d sdo_pin=%d"
                               % (idx, swap, pin_number(d, clk), pin_number(d, sdo))))
        link.send(d.encode("finalize_config crc=%d" % SCRIPT_CRC))
        time.sleep(0.2)
        print("get_config ->", link.ask(d, "get_config", want="config"))
    return link, d


def start_line(d, arm=False, hold=None):
    """Plain read (cmd_READ_PRES): filters 0, holds 128/128/0. Armed (cmd_TEST_PRES): Creality's
    pres_tri_fter (5, 1, 0.8 -> ned_lftr x1000) and the x2600 K1 Max pres_tri_hold 10000,15000,500."""
    tftr, hftr, lftr, hmin, hmax, hadd = (5, 1, 800, 10000, 15000, 500) if arm else (0, 0, 0, 128, 128, 0)
    if hold:
        hmin, hmax, hadd = (int(x) for x in hold.split(","))
    freq = d.raw["config"]["CLOCK_FREQ"]
    return ("start_prtouch_pres oid=0 cfg_regs=%d acq_tick=%d ned_tftr=%d ned_hftr=%d ned_lftr=%d "
            "min_hold=%d max_hold=%d add_hold=%d lmt_dead=%d"
            % (CFG_REGS, round(freq * ACQ_MS / 1000), tftr, hftr, lftr, hmin, hmax, hadd, DED_MS)), (hmin, hmax, hadd)


def cmd_loadcells(a):
    link, d = prtouch_open(a.port, a.baud)
    start, (hmin, hmax, hadd) = start_line(d, a.arm, a.hold)
    print("start      ->", link.ask(d, start, want="ack_prtouch"))
    if a.arm:
        print("armed: holds %d,%d,%d. The board keeps samples to itself in this mode; watch SYNC "
              "(mainboard PC10) for the trigger, e.g. Kalico [gcode_button] on PC10." % (hmin, hmax, hadd))
    data = {ch: [] for ch in range(len(V23_CHANNELS))}
    window = {ch: [] for ch in data}
    seen = {ch: 0 for ch in data}
    last_tri = 0
    t0 = last = time.time()
    try:
        while time.time() - t0 < a.time:
            for p in link.frames(0.1):
                for name, v in d.decode(p):
                    if name == "resault_prtouch_pres":
                        if v["tri_chxs"] != last_tri:
                            print("%5.1f  tri_chxs 0x%02x -> 0x%02x  (board trigger state, ch%d frame)"
                                  % (time.time() - t0, last_tri, v["tri_chxs"], v["ch"]), flush=True)
                            last_tri = v["tri_chxs"]
                        vals = unzip_data(v["datas"], True)
                        skip = max(0, a.discard - seen[v["ch"]])     # like cmd_READ_PRES DISCARD=20:
                        seen[v["ch"]] += len(vals)                   # the first samples after start
                        vals = vals[skip:]                           # include a doubled-value artifact
                        data[v["ch"]] += vals
                        window[v["ch"]] += vals
                    elif a.verbose:
                        print("   ", name, v)
            if a.arm and time.time() - last >= a.interval:
                # Armed: the board doesn't stream, so ask it. tri_chxs = channels that triggered.
                for ch in data:
                    link.send(d.encode("read_prtouch_pres oid=0 is_src=1 ch=%d idx=0 len=4" % ch))
            if time.time() - last >= a.interval:
                last = time.time()
                cols = []
                for ch in data:
                    w = window[ch]
                    cols.append("ch%d %9s ±%-6s n=%-4d" % (ch, int(sum(w) / len(w)) if w else "-",
                                                         (max(w) - min(w)) // 2 if w else "-", len(w)))
                    window[ch] = []
                print("%5.1f  %s" % (last - t0, "   ".join(cols)), flush=True)
    finally:
        print("stop       ->", link.ask(d, "stop_prtouch_pres oid=0 sta_swap=1", want="ack_prtouch"))
    for ch, vals in data.items():
        if vals:
            print("ch%d: n=%d mean=%d min=%d max=%d span=%d" % (ch, len(vals), sum(vals) // len(vals),
                                                                min(vals), max(vals), max(vals) - min(vals)))
        else:
            print("ch%d: no samples" % ch)


# --- path 1: z-offset by step-probing -----------------------------------------------------

class Streamer(threading.Thread):
    """Drain plain-read sample frames continuously (so nothing backs up while we wait on motion),
    keeping (host_time, value) per channel. Creality discards the first samples after start."""

    def __init__(self, link, d, discard=20):
        super().__init__(daemon=True)
        self.link, self.d, self.discard = link, d, discard
        self.samples = {ch: [] for ch in range(len(V23_CHANNELS))}
        self.seen = {ch: 0 for ch in self.samples}
        self.lock = threading.Lock()
        self.running = True

    def run(self):
        while self.running:
            for p in self.link.frames(0.05):
                try:
                    msgs = self.d.decode(p)
                except IndexError:
                    continue
                for name, v in msgs:
                    if name != "resault_prtouch_pres":
                        continue
                    vals = unzip_data(v["datas"], True)
                    ch, now = v["ch"], time.time()
                    skip = max(0, self.discard - self.seen[ch])
                    self.seen[ch] += len(vals)
                    with self.lock:
                        self.samples[ch] += [(now, x) for x in vals[skip:]]
                        del self.samples[ch][:-20000]          # keep ~30 s per channel

    def means(self, t_from):
        with self.lock:
            out = {}
            for ch, s in self.samples.items():
                w = [x for t, x in s if t >= t_from]
                if not w:
                    return None
                out[ch] = sum(w) / len(w)
            return out

    def stop(self):
        self.running = False
        self.join(1.0)


def moonraker(base, path, script=None):
    import urllib.request
    data = json.dumps({"script": script}).encode() if script is not None else None
    req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)["result"]


def force_of(m, tare):
    """Every channel goes negative under load: force = -(sum of deviations from tare), in counts."""
    return -sum(m[ch] - tare[ch] for ch in tare)


def fit_contact(points, fit_min):
    """The bed is compliant: past contact, force rises ~linearly with depth. Least-squares fit
    force = slope*(z0 - z) through the points above fit_min and return (z0, slope per mm, n),
    i.e. where the line meets zero force. None if fewer than 3 usable points."""
    pts = [(z, f) for z, f in points if f > fit_min]
    if len(pts) < 3:
        return None
    n = len(pts)
    mz = sum(z for z, _ in pts) / n
    mf = sum(f for _, f in pts) / n
    sxx = sum((z - mz) ** 2 for z, _ in pts)
    if sxx == 0:
        return None
    b = sum((z - mz) * (f - mf) for z, f in pts) / sxx        # df/dz, negative (force grows as z drops)
    if b >= 0:
        return None
    return mz - mf / b, -b, n


def cmd_zprobe(a):
    q = lambda: moonraker(a.moonraker, "/printer/objects/query?toolhead=homed_axes,position&gcode_move=gcode_position")["status"]
    st = q()
    if not a.dry_run and "z" not in st["toolhead"]["homed_axes"]:
        sys.exit("Z is not homed (homed_axes=%r): home first (Cartographer), then run this" % st["toolhead"]["homed_axes"])
    link, d = prtouch_open(a.port, a.baud)
    start, _ = start_line(d)
    print("start      ->", link.ask(d, start, want="ack_prtouch"))
    s = Streamer(link, d)
    s.start()

    def measure():
        time.sleep(a.settle)
        t = time.time()
        time.sleep(a.window)
        m = s.means(t)
        if m is None:
            raise SystemExit("no samples from some channel: board stopped streaming?")
        return m

    def move(script):
        moonraker(a.moonraker, "/printer/gcode/script", script + "\nM400")

    moved = False
    try:
        time.sleep(0.5)
        if a.dry_run:
            tare = measure()
            print("dry run: tare taken; force (counts) every %.2f s, press/tap the bed to see it" % (a.settle + a.window))
            t0 = time.time()
            while time.time() - t0 < a.time:
                print("%6.1f  force %8d" % (time.time() - t0, force_of(measure(), tare)), flush=True)
            return
        if a.xy or a.start_z is not None:
            z_now = st["toolhead"]["position"][2]
            if a.xy:
                x, y = (float(v) for v in a.xy.split(","))
                move("G90\nG1 Z%.3f F600\nG1 X%.2f Y%.2f F6000" % (max(z_now, (a.start_z or z_now) + 3), x, y))
            if a.start_z is not None:
                move("G90\nG1 Z%.3f F600" % a.start_z)
            moved = True
        tare = measure()
        traveled, contact, fine_pts = 0.0, None, []
        for phase, step in (("coarse", a.coarse), ("fine", a.fine)):
            while True:
                if traveled + step > a.max_travel:
                    raise SystemExit("no contact within --max-travel %.2f mm (threshold %d counts)" % (a.max_travel, a.threshold))
                move("G91\nG1 Z%.4f F%d\nG90" % (-step, a.feed))
                moved = True
                traveled += step
                f = force_of(measure(), tare)
                z = q()["gcode_move"]["gcode_position"][2]
                print("%-6s Z=%8.4f  force %8d" % (phase, z, f), flush=True)
                if f > a.limit:
                    raise SystemExit("force %d over --limit %d: aborting" % (f, a.limit))
                if phase == "fine":
                    fine_pts.append((z, f))
                if f > a.threshold:
                    contact = z
                    break
            if phase == "coarse":
                back = step * 3
                move("G91\nG1 Z%.4f F%d\nG90" % (back, a.feed))
                traveled -= back
                tare = measure()                        # re-tare off the bed before the fine pass
        fit = fit_contact(fine_pts, a.fit_min)
        if fit:
            z0, slope, n = fit
            print("CONTACT at gcode Z=%.4f  (zero-force intercept of a line through %d fine steps over %d counts; "
                  "stiffness %.0f counts/um; threshold step was Z=%.4f)" % (z0, n, a.fit_min, slope / 1000, contact))
        else:
            print("CONTACT at gcode Z=%.4f (first fine step over %d counts; too few ramp points to fit)"
                  % (contact, a.threshold))
    finally:
        if moved:
            move("G91\nG1 Z%.3f F600\nG90" % a.retract)
        s.stop()
        print("stop       ->", link.ask(d, "stop_prtouch_pres oid=0 sta_swap=1", want="ack_prtouch"))


def cmd_selftest(a):
    for v in (0, 1, 31, 32, 95, 96, -1, -32, -33, 4095, 12287, 12288, 2 ** 31 - 1, -2 ** 31, 144000000):
        got, end = dec_vlq(enc_vlq(v), 0)
        assert got == v and end == len(enc_vlq(v)), (v, got)
    # A real frame captured from the V23 board on 2026-10-27.
    real = bytes.fromhex("06104a97257e")
    payloads, rest, junk = split_frames(b"\x00\xff" + real + real[:3])
    assert payloads == [bytes.fromhex("4a")] and rest == real[:3] and junk == 2, (payloads, rest, junk)
    assert frame(0, bytes.fromhex("4a")) == real
    assert fix_width(-10, "%hu") == 65526 and fix_width(-10, "%hi") == -10
    assert fix_width(-1, "%u") == 0xFFFFFFFF and fix_width(200, "%c") == 200 and fix_width(-2, "%i") == -2
    # unzip_data: 3 values 100, +5, -300 -> lengths 1,1,2 bytes -> codes 0,0,1 in one header byte
    packed = bytes([3, 0b010000]) + (100).to_bytes(1, "little", signed=True) + \
        (5).to_bytes(1, "little", signed=True) + (-300).to_bytes(2, "little", signed=True)
    assert unzip_data(packed, True) == [100, 105, -195], unzip_data(packed, True)
    # fit_contact on the 2026-10-28 first real run: ramp points 0.17..0.11 -> contact ~0.180
    run = [(0.19, -233), (0.18, 350), (0.17, 3081), (0.16, 5630), (0.15, 8679), (0.14, 11687),
           (0.13, 14839), (0.12, 18493), (0.11, 21564)]
    z0, slope, n = fit_contact(run, 2000)
    assert n == 7 and abs(z0 - 0.180) < 0.003 and 2.8e5 < slope < 3.3e5, (z0, slope, n)
    assert fit_contact(run[:3], 2000) is None
    seqs = []
    nak = frame(7, b"")                              # empty block = ack/nak; nibble = expected seq
    payloads, _, _ = split_frames(nak + frame(9, b"\x01"), seqs)
    assert payloads == [b"", b"\x01"] and seqs == [7, 9], (payloads, seqs)
    d = Dictionary({"commands": {"identify offset=%u count=%c": 1},
                    "responses": {"identify_response offset=%u data=%.*s": 0}})
    assert d.encode("identify offset=40 count=40") == enc_vlq(1) + enc_vlq(40) + enc_vlq(40)
    assert d.decode(enc_vlq(0) + enc_vlq(40) + enc_vlq(3) + b"abc") == [("identify_response", {"offset": 40, "data": b"abc"})]
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-b", "--baud", type=int, default=BAUD)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("scan", help="find ports with Klipper traffic and identify them")
    p.add_argument("--listen", type=float, default=6.0, help="seconds to listen per port (frames come every ~5 s)")
    p.add_argument("--probe", action="store_true", help="also send identify on silent ports")
    p.add_argument("-v", "--verbose", action="store_true", help="also list ports that could not be opened")
    p.set_defaults(fn=cmd_scan)
    p = sub.add_parser("listen")
    p.add_argument("port")
    p.add_argument("-t", "--time", type=float, default=15.0)
    p.add_argument("--decode", action="store_true", help="identify first, then decode frames")
    p.set_defaults(fn=cmd_listen)
    p = sub.add_parser("identify")
    p.add_argument("port")
    p.add_argument("-o", "--out")
    p.set_defaults(fn=cmd_identify)
    p = sub.add_parser("status")
    p.add_argument("port")
    p.set_defaults(fn=cmd_status)
    p = sub.add_parser("send", help="send one command", epilog=SEND_EPILOG,
                       formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("port")
    p.add_argument("line", help='command and args, quoted: e.g. "get_uptime" or "debug_ping data=hi"')
    p.add_argument("--unsafe", action="store_true", help="allow commands outside the read-only list")
    p.add_argument("--wait", type=float, default=1.0, help="seconds to wait for a reply (default 1)")
    p.set_defaults(fn=cmd_send)
    p = sub.add_parser("loadcells", help="configure the 4 CS1237 channels and stream raw counts (configures the MCU)")
    p.add_argument("port")
    p.add_argument("-t", "--time", type=float, default=10.0, help="seconds to stream (default 10)")
    p.add_argument("-i", "--interval", type=float, default=0.5, help="seconds per printed row (default 0.5)")
    p.add_argument("-v", "--verbose", action="store_true", help="also print non-sample messages (acks etc)")
    p.add_argument("--arm", action="store_true",
                   help="arm the board's touch trigger (Creality cmd_TEST_PRES thresholds); it drives SYNC on a press")
    p.add_argument("--hold", metavar="MIN,MAX,ADD",
                   help="override trigger thresholds (min_hold,max_hold,add_hold); with --arm, default 10000,15000,500")
    p.add_argument("--discard", type=int, default=20, help="samples per channel to drop after start (default 20)")
    p.set_defaults(fn=cmd_loadcells)
    p = sub.add_parser("zprobe", help="path 1: find nozzle-bed contact by stepping Z down while reading the load cells "
                                      "(MOVES THE PRINTER via Moonraker)")
    p.add_argument("port")
    p.add_argument("--moonraker", default="http://localhost:7125")
    p.add_argument("--xy", metavar="X,Y", help="move here first (at a safe height)")
    p.add_argument("--start-z", type=float, help="absolute Z to start stepping from (e.g. 1.0 after homing)")
    p.add_argument("--coarse", type=float, default=0.05, help="coarse step mm (default 0.05)")
    p.add_argument("--fine", type=float, default=0.01, help="fine step mm (default 0.01)")
    p.add_argument("--threshold", type=int, default=10000, help="stop the fine pass at this force, counts above tare (default 10000)")
    p.add_argument("--fit-min", type=int, default=2000, help="fine points above this force are fitted for the contact line (default 2000)")
    p.add_argument("--limit", type=int, default=300000, help="abort above this force, counts (default 300000)")
    p.add_argument("--max-travel", type=float, default=3.0, help="max downward travel mm (default 3)")
    p.add_argument("--feed", type=int, default=120, help="step feedrate mm/min (default 120)")
    p.add_argument("--settle", type=float, default=0.15, help="s to wait after each step (default 0.15)")
    p.add_argument("--window", type=float, default=0.15, help="s of samples to average per reading (default 0.15)")
    p.add_argument("--retract", type=float, default=2.0, help="mm to lift at the end (default 2)")
    p.add_argument("--dry-run", action="store_true", help="no motion: tare, then print force readings (noise check)")
    p.add_argument("-t", "--time", type=float, default=20.0, help="dry-run duration s (default 20)")
    p.set_defaults(fn=cmd_zprobe)
    sub.add_parser("selftest").set_defaults(fn=cmd_selftest)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(file=sys.stderr)
        sys.exit(130)
    except BrokenPipeError:                     # e.g. `listen ... | head`
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
    except (serial.SerialException, OSError) as e:
        sys.exit("serial error: %s (adapter unplugged or board powered off?)" % e)
