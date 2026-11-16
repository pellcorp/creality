# K1-MAX-L_V23 load-cell board: installation guide

How to use Creality's **K1-MAX-L_V23** bed load-cell board on a K1 Max running SimpleAF on Kalico,
to home Z by nozzle contact. Proven on k1m (x2000 mainboard `CR4CU220812S11`, SimpleAF `f8dc056`,
Kalico `v2026.08.00-45`), including real ABS prints, over **both** wiring options below.

The board keeps **Creality's own firmware**. Nothing has to be flashed: a V23 from the factory
already runs it. The `[prtouch_v3]` Kalico module in this directory talks to that firmware
directly.

**Two ways to wire it up — pick whichever suits your printer and parts bin:**
- **A USB-UART (CH341 module), covered in section 3 below.** The simpler build: three jumper
  wires to a cheap off-the-shelf module, no soldering. Costs a USB port, and a cable has to run
  from the board out to it — on some printers that port is shared with another USB device (it was
  on k1m, see the troubleshooting table).
- **An inline MAX3232 adapter on the mainboard's own leveling port** (`MAX3232_ADAPTER.md`). Uses
  no USB port and no extra cable run, at the cost of a bit of soldering (a MAX3232 breakout plus a
  resistor divider).

Both are fully supported and kept up to date; this isn't a "start here, upgrade later" choice.
Everything else in this guide (firmware, config, verification, first print) applies to either one
— only the wiring (this guide's section 3, or `MAX3232_ADAPTER.md`) and the `serial:` line in
section 6 differ.

Background and reverse engineering: `systems/k1m_v23_leveling.md`. Test runs:
`systems/k1m_prtouch_v3_safety.todo`.

---

## 1. What you get, and what you don't

- **Z homing by nozzle contact** after the main probe has homed and meshed (e.g. a Cartographer
  scan). The module steps the nozzle onto the bed (0.05 mm coarse, then 0.01 mm fine) and fits the
  force-vs-Z line. The bed is compliant, ~250-330 counts/µm. Contact is the zero-force intercept.
- Measured: 5-tap range **2.7 µm**, standard deviation **1.0 µm**; a re-probe after `HOME=Z` reads
  −0.004…+0.009 mm (the larger value right after reaching 148 °C, as the hot end settles).
- Slow (a few tens of seconds per home) and host-stepped. The force limit is checked after each
  step; it's not an MCU endstop. It's for one Z reference per print, not for meshing.
- The board's own hardware trigger (SYNC) is **not** used. It never fired in testing.

## 2. Parts

| Part | Notes |
|---|---|
| K1-MAX-L_**V23** board | CH32V203 + 4× CS1237. Check the silkscreen. The older **V11** (GD32E230 + HX711, has a `3232E` chip) is a different board, supported by SimpleAF's own `loadcells`. |
| CH341 USB-UART module (USB ID `1a86:7523`) | Set it to **3.3 V logic**: the CH32V203 is a 3.3 V part (k1m's module setting wasn't recorded; 3.3 V is the safe choice). The K1 kernel has `ch341` built in. |
| 3 jumper wires (Dupont) | TX, RX, GND. |

## 3. Wiring

The V23's connector is `GND  TX  RX  SYNC  5V`, the same on the board and the mainboard
end of the harness.

> **Never connect the V23's TX/RX to the mainboard's leveling port.** On x2000 boards that port is
> **RS-232**: mainboard TX idles at **−5.5 V**, and it pulled the board's RX to −2.2 V when
> connected directly, outside the CH32V203's rating. The old V11 board has its own MAX3232; the V23
> doesn't. Measure idle voltages on any unknown serial port first.

| V23 pin | Goes to | Why |
|---|---|---|
| **TX** | CH341 **RXD** | crossover |
| **RX** | CH341 **TXD** | crossover |
| **GND** | CH341 **GND** *and* the harness GND | common ground for the UART |
| **5V** | harness 5V (as stock) | board power stays on the printer |
| **SYNC** | harness SYNC (as stock), or leave it | not used by the module; harmless |
| — | harness **TX/RX: disconnect** (depin or cut) | they carry RS-232 levels |

```
 K1 mainboard leveling harness            V23 board              CH341 (3.3 V)
   5V  ──────────────────────────────────  5V
   GND ──────────────────────────────────  GND ─────────────────  GND
   SYNC ─────────────────────────────────  SYNC (optional)
   TX  ──X  (RS-232, not connected)        TX  ─────────────────  RXD
   RX  ──X  (RS-232, not connected)        RX  ─────────────────  TXD
                                                                  USB ── K1 USB port
```

**Alternative without USB:** an inline MAX3232 adapter on the mainboard port (`/dev/ttyS9`), see
`MAX3232_ADAPTER.md`.

Plug the CH341 into a K1 USB port. It appears as
`/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0` (use this path; `ttyUSB0` can move).

**Don't plug or unplug the CH341 while Klipper is running.** On k1m it shares the internal USB hub
(`1-1.2`) with another Klipper MCU (the chamber-heater RP2040). A replug stalled that MCU, Klipper
shut down, and only a power cycle recovered it. Plug it in with the printer off.

## 4. Bench check (optional, before touching Klipper)

`creality/k1/v23_leveling.py` (also in this directory) needs only pyserial and speaks the
Klipper wire protocol directly: no Klipper tree, no compiled chelper, no running Kalico. On the
printer, use `/usr/share/klippy-env/bin/python3`. Nothing may have the port open, so stop Klipper
if `[prtouch_v3]` is already configured.

```sh
P=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
python3 v23_leveling.py status $P      # version CTF_V1.0.0.16.20250320, MCU ch32v203x8, 230400
python3 v23_leveling.py loadcells $P -t 10   # 4 channels streaming; press each bed corner
```

- An idle board sends a 13-byte `stats` frame every ~5 s. `listen $P --decode` shows it.
- Expected at rest: four large offsets (e.g. `+405000 −218000 −272800 −345700`) and ±2-3 k
  noise. A firm press moves one channel by about −1 M counts.
- On a desktop Linux PC, ModemManager grabs fresh CH341s for ~30 s and eats the frames. Add a udev
  rule:
  `ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", ENV{ID_MM_DEVICE_IGNORE}="1"`.

## 5. Firmware from Creality (only for recovery or an update)

The board ships with working firmware, and this guide never needs it reflashed. Extract the blob
anyway if you want a copy, or need to recover a board.

**Source:** Creality's **K1C** (2025) firmware, not the K1 Max one. The K1 Max x2000 images only
carry V11 firmware. Download the K1C OTA image from Creality's firmware download page, e.g.
`CR4SU200382C13_ota_K1C-2025_V1.0.0.26.20251024S.img` (252691232 B, sha256
`2deba01c1e56925981d7671cfe1e3a41f1b22319fb90966fed10df0e76c91589`). It's a raw image (no
password): a kernel, a squashfs root, and an **ext4 apps partition** holding the V23 firmware and
the flash tool.

```sh
IMG=CR4SU200382C13_ota_K1C-2025_V1.0.0.26.20251024S.img
mkdir k1c && cd k1c

# 1. find the apps partition (offset and size differ per release)
binwalk ../$IMG | grep -i 'ext4'
#   105888534  0x64FBB16  Linux EXT filesystem, ... image size: 146800640, ... ext4

# 2. carve it out (byte offset and size from binwalk)
dd if=../$IMG of=apps.ext4 bs=1M iflag=skip_bytes,count_bytes skip=105888534 count=146800640

# 3. extract the blobs (7z reads ext4; no mount, no root)
7z x apps.ext4 lib/firmware/klipper_leveling_serial_app.bin \
               usr/bin/cmd_iap usr/bin/mcu_iap_upgrade.sh usr/bin/leveling_klipper_mcu_restart.sh \
               usr/share/klipper/config/k1max-x2600/printer.cfg
sha256sum lib/firmware/klipper_leveling_serial_app.bin usr/bin/cmd_iap
```

| File | What it is | V1.0.0.26 sha256 |
|---|---|---|
| `lib/firmware/klipper_leveling_serial_app.bin` | V23 firmware (39053 B, CH32V203, Creality's Klipper build with `prtouch_v3`) | `b5cb2590…ec2ced6b8d5d6` |
| `usr/bin/cmd_iap` | Creality's IAP flash tool, MIPS32 ELF (runs on the K1) | `37329d84…e46960c1c36` |
| `usr/bin/mcu_iap_upgrade.sh`, `leveling_klipper_mcu_restart.sh` | Creality's wrappers around `cmd_iap` | |
| `k1max-x2600/printer.cfg` | Creality's own V23 settings (`pres_cs*_pin`, `pres_swap_pin`, `pres_cfg_regs`) | |

**Versions:**
- The blob identifies as `K1C-2025_V1.0.0.26.20251024S`. The factory firmware on k1m's board was
  `CTF_V1.0.0.16.20250320`.
- Their command dictionaries are **identical** (73 commands, 28 responses, same formats), so the
  module works with either.
- The version is in the zlib-compressed data dictionary inside the blob, at offset 34032 for
  V1.0.0.26. Inflate it with Python's `zlib` to check.

**Flashing (untested over a CH341; read before trying):**
- Creality flashes the board on **every** Klipper restart on x2600 printers:
  ```sh
  cmd_iap --device <port> --baudrate 230400 --dtype 0xA3 --upgrade \
          --firmware klipper_leveling_serial_app.bin
  ```
  Here that would be `--device /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`, run on the
  printer. k1m's stock x2000 system has no `cmd_iap`; copy the extracted one over.
- Only attempted on k1m through the RS-232 port, where it couldn't connect and wrote nothing.
- Background: a Klipper `reset` puts the board into its IAP bootloader. The bootloader starts the
  app by itself after ~60 s. A power-on boots straight into the app.
- If a board ends up without a working app, a power cycle shows whether the bootloader still
  answers `cmd_iap`. There's also an unpopulated SWD header (`NRST GND CLK DIO 3V3`; square pad =
  3V3) for a WCH-LinkE as a last resort.

## 6. Install on the printer

Files, all in this directory:
- `kalico/klippy/extras/prtouch_v3.py`: the module.
- `creality/config/prtouch_v3.cfg`: config and macros.
- `kalico/test/test_prtouch_v3.py`: host tests (`pytest`, 20 pass).

The module is self-contained: no extra MCU, no Kalico patch.

1. **Module:**
   ```sh
   cp prtouch_v3.py /usr/data/klipper/klippy/extras/prtouch_v3.py
   ```
   It isn't part of the Kalico tree, so a Kalico git update keeps it. A SimpleAF reinstall may not:
   keep a copy and restore it after updates (k1m does this in its own `post-update.sh`).
2. **Config:** copy `prtouch_v3.cfg` to `/usr/data/printer_data/config/` and add
   `[include prtouch_v3.cfg]` to `printer.cfg`. Fill in the three "installer will set" values:
   ```ini
   [prtouch_v3]
   serial: /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
   swap_pin: PA8
   channel_pins: PB10:PB2, PB1:PB0, PA7:PA6, PA5:PA4
   ```
   - The pins are the board's own (`clk:sdo` per CS1237, from Creality's `k1max-x2600` config).
   - `swap_pin` is the board's SYNC output, which the module configures but doesn't use.
   - Keep the defaults for the rest: `trigger_force: 10000`, `fit_min_force: 2000`,
     `force_safety_limit: 300000`, `max_travel: 3.0`.
   - Fit acceptance limits: `min_stiffness: 50`, `max_stiffness: 1500` (counts/µm),
     `max_fit_error: 0.005`, `max_extrapolation: 0.1` (mm).
   - **Don't set `z_offset` in this file.** `SAVE_CONFIG` refuses to save a value that's also set
     in an included file (see step 9).
3. **Start of print:** SimpleAF's `START_PRINT` already calls `_LOAD_CELL_HOME_Z` when that macro
   exists. The cfg defines it: M109 to `start_preheat_nozzle_temp`, move to
   `bed_mesh.zero_reference_position`, Z1.0, `PRTOUCH_PROBE HOME=Z`, Z8.
   - With a Cartographer, turn its own touch off so only one thing references Z:
     `variable_touch_mode: False` in `cartographer.cfg`. Scan homing and the mesh stay.
4. **`Z_OFFSET_APPLY_PROBE`:** the cfg renames the existing command to `_Z_OFFSET_APPLY_PROBE`
   and routes it to the load cells. This needs some probe that registers `Z_OFFSET_APPLY_PROBE`
   (Cartographer, Beacon, `[probe]`). Without one, delete that macro, or klippy refuses to start.
5. **Load it with a full service restart**, heaters off:
   ```sh
   rm -f /usr/data/klipper/klippy/extras/prtouch_v3.pyc
   /etc/init.d/S55klipper_service restart
   ```
   - `RESTART` and `FIRMWARE_RESTART` keep the old module in klippy's memory.
   - A stale sibling `.pyc` may also be loaded. The symptom: `Option 'min_stiffness' is not valid in
     section 'prtouch_v3'`.
   - Restarting with a heater on can shut down an MCU (then run `FIRMWARE_RESTART`).
6. **Optional print gate:** k1m's `touch_gate.cfg` refuses to print unless `last_home_z_result`
   is set and plausible. Use `last_home_z_result`, not `last_z_result`: only `HOME=Z` sets it, and
   any homing, motor-off or shutdown clears it.

## 7. Verify

Home first (`G28`). Use nozzle temperature 148 °C for numbers comparable to a print start.

| Command | Expect (k1m) |
|---|---|
| `PRTOUCH_DIAGNOSTIC TIME=5` | tare per channel, ~16 readings, noise a few hundred counts (e.g. −47…665) |
| `PRTOUCH_PROBE_ACCURACY SAMPLES=5` | range < 5 µm, ~250-335 counts/µm, no fit rejected |
| `_LOAD_CELL_HOME_Z` | `contact at z=0.18…0.22 (fit over 4 steps, ~300 counts/um)`, then `z homed` |
| `G0 Z1 F900` + `PRTOUCH_PROBE` | contact ≈ 0.000 ± 0.01 |

Status variables: `printer.prtouch_v3.last_z_result`, `last_home_z_result`, `last_stiffness`,
`last_accuracy`.

## 8. First print

Print normally. The log shows `prtouch_v3: contact at z=…` before the purge line. Expect to
babystep the first layer once: the probe runs at the 148 °C preheat, and the hot end grows a little
at print temperature.

## 9. Save the Z offset

Babystep during the first layer. After the print, run `Z_OFFSET_APPLY_PROBE`, then `SAVE_CONFIG`.
That writes `[prtouch_v3] z_offset` into the printer.cfg `SAVE_CONFIG` block. The babystep is
lost when the print ends, so apply it before starting another print.

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Option 'min_stiffness' is not valid` after an upgrade | old module still loaded | section 6, step 5: delete the `.pyc`, restart the service |
| `no identify response from board` | the board is still streaming from an interrupted session; its identify reply gets lost among sample frames | power cycle the printer (fixed in the module: closing always stops the stream) |
| `no samples from the board` | CH341 unplugged, wiring, or the worker died | check `dmesg`, wiring; look for `prtouch_v3: board worker died` in klippy.log |
| `board cleanup failed; restart Klipper` | stop wasn't acknowledged; the worker shut itself down | `FIRMWARE_RESTART`; if it repeats, check the serial link |
| `unreliable contact fit (stiffness …, residual …, extrapolation …)` | dirty nozzle (residue holds it off the bed), or limits too tight | clean the nozzle hot; widen the one limit that tripped |
| `no contact within 3.00mm` | started too high, or Z homed wrong | `approach_z` in `_LOAD_CELL_HOME_Z` (default 1.0) |
| `too few points past contact to fit; lower fit_min_force or raise trigger_force`, once in a while | normal tap-to-tap variation: that tap's fine steps landed mostly on the flat, near-zero part of the curve, then jumped past `trigger_force` in 1-2 steps, leaving under 3 points above `fit_min_force` | just retry — if it keeps failing on most taps, then lower `fit_min_force` or raise `trigger_force` as the message says |
| `board says …` lines in klippy.log | the board's printf debug output (alloc/timer messages after a cold boot) | informational |
| Scrambled frames, no answers on `/dev/ttyS9` | wired straight to the RS-232 mainboard port, no level conversion | use the CH341 (section 3), or a MAX3232 adapter (`MAX3232_ADAPTER.md`) |
| Silence on `/dev/ttyS9` with a MAX3232 adapter fitted | TX/RX swapped at the harness or the module; pin position doesn't carry across the stock harness | `MAX3232_ADAPTER.md` sections 4 and 7 |
| `unreliable contact fit` with numbers far from this board's own history (e.g. stiffness well under 250 counts/µm, or a contact height that jumped) | likely mechanical, not wiring: a loose bed/load-cell mount or a Z-reference shift, especially after moving the printer | check the gap/mounts by hand before re-probing; see `MAX3232_ADAPTER.md` section 8 for a worked example |
| Another USB MCU drops when the CH341 is plugged in or under heavy heater load | shared USB hub / ground noise | plug the CH341 in with the power off. For the load case see `systems/k1m.md` "Print failed mid-way" |

## 11. References

- `MAX3232_ADAPTER.md` (this directory): the no-USB alternative to section 3 — wiring, circuit,
  bring-up, current status.
- `systems/k1m_v23_leveling.md`: hardware, firmware sources, reconstructed protocol, all
  measurements.
- `systems/k1m_prtouch_v3_safety.todo`: on-printer validation, steps 1-7.
- `README.md` (this directory): module design and the SimpleAF PR plan.
- `creality/k1/v23_leveling.py` (this directory): the standalone bench tool used in section 4.
- Creality GPL trees (`CrealityOfficial/K2_Series_Klipper`, `Hi_Klipper`): `prtouch_v3_compile.c`
  (command declarations).
