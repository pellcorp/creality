# V23 leveling-board retrofit support

This directory is the shared hardware and installation documentation for the
Creality/SimpleAF and Kalico contributions. The code lives in two repositories:

| Contribution | Source | Upstream target |
|---|---|---|
| SimpleAF integration | [config and macros](../../config/loadcells_v23.cfg), [K1 Max defaults](../../k1/patches/loadcells_v23.cfg.k1m), [installer](../../k1/installer.sh), [print-start hook](../../config/start_end.cfg), [bench tool](../../k1/v23_leveling.py) | `pellcorp/creality:main` |
| Kalico module | [load_cell_v23.py][kalico-module], [host tests][kalico-tests], [configuration reference][kalico-config], [commands][kalico-commands], [status][kalico-status] | `pellcorp/kalico:aug2026` |

The public names are `[load_cell_v23]`, `--loadcells-v23`, and `BED_LOAD_CELL_*`.
See [migration from the former names](MIGRATION.md).

The feature branches are [gilrim/creality:add-prtouch-v3][creality-branch] and
[gilrim/kalico:add-prtouch-v3][kalico-branch]. The Kalico source links below pin the
current renamed module; dated verification reports identify the revisions tested.

- [Installation guide](INSTALL.md): parts, USB-UART wiring, firmware recovery,
  configuration, and verification.
- [MAX3232 adapter guide](MAX3232_ADAPTER.md): wiring through the mainboard port,
  circuit, build photos, and troubleshooting.
- [Latest printer verification](VERIFICATION_2026-11-17.md): naming migration,
  sampling, homing and repeatability results.
- [Validation record](VALIDATION.md): dated hardware observations, test results,
  limitations, and commands to reproduce the software checks.

The [bench tool](../../k1/v23_leveling.py) needs only pyserial; it can identify and
read the board without a Klipper checkout. All three build photos are in [img/](img/)
and are embedded in the adapter guide. The validation record contains the relevant
evidence from the development notes, so these guides require no private repository.

## What it does

This contribution supports retrofitting a **K1-MAX-L_V23** leveling board
(CH32V203 + 4× CS1237) into an existing K1 Max that did not originally have this
board. The board was designed for Creality's x2600 platform. SimpleAF's `loadcells` support targets the older V11
board (GD32E230 + HX711, Kalico `hx711s` firmware). That V11 firmware/integration does not apply to the V23. It runs
Creality's own Klipper build (`CTF_V1.0.0.16.20250320`) with the `prtouch_v3` firmware protocol.

`[load_cell_v23]` talks to that firmware directly and provides load-cell Z homing. It plugs into
START_PRINT through the existing `_LOAD_CELL_HOME_Z` hook, the same one `loadcells-zoffset` uses.

**Method: step-probing plus a line fit.** It tares the summed force of the four cells, then steps Z
down (0.05 mm coarse, back off, 0.01 mm fine) and reads the settled force after each step. The bed
is compliant: past contact, force rises linearly with depth, at ~300 counts/µm on a K1 Max. So the
**zero-force intercept of a line fitted through the fine steps** gives the contact height to well
under a step. `BED_LOAD_CELL_PROBE HOME=Z` then re-references Z, using the same `set_position` logic as
`PROBE HOME=Z` in Kalico's `probe.py`.

**Why not an `[mcu]`:**
- The V23 firmware has no Kalico load-cell/trsync support, so `load_cell_probe` can't be used.
- A Klipper `reset` parks this board in its IAP bootloader for ~60 s. Creality uses
  `restart_method: script` (cmd_iap), which Kalico doesn't have.

The module therefore owns the board's serial port itself, from a worker thread, so the reactor never
blocks. Gcode commands wait with `reactor.pause()`.

After settling, each force reading requires at least five samples per channel
within a rolling 150 ms window. If coverage is incomplete, it retries every
20 ms for up to 500 ms after settling (`sample_timeout`), without moving the
nozzle or widening the freshness window. A timeout reports each channel's sample
count and newest sample age before the normal abort/retraction path. Native CRC
calculation reduces decoder CPU overhead; the 200 ms stale-batch limit remains.

Commands (no digits in the names; klippy's gcode parser splits `BED_LOAD_CELL_V23_PROBE`):
- `BED_LOAD_CELL_PROBE [HOME=Z]`: probe from the current Z (which must be homed, e.g. by a scan probe)
  at the current XY. The fit must pass `min_stiffness`/`max_stiffness` (counts/µm, default
  50-1500), `max_fit_error` (0.005 mm) and `max_extrapolation` (0.1 mm), or nothing is applied.
- `BED_LOAD_CELL_DIAGNOSTIC [TIME=5]`: per-channel tare and force noise.
- `BED_LOAD_CELL_PROBE_ACCURACY [SAMPLES=10]`: 2-100 taps; min/max/range/average/median/stddev. The
  `loadcells_v23.cfg` macro moves to the zero reference first.
- `BED_LOAD_CELL_Z_OFFSET_APPLY_PROBE`: stages `z_offset` for SAVE_CONFIG from the gcode offset;
  `loadcells_v23.cfg` routes `Z_OFFSET_APPLY_PROBE` to it. Don't set `z_offset` in the included
  cfg, or SAVE_CONFIG refuses the include conflict.

Status: `printer.load_cell_v23.last_z_result`, `last_home_z_result` (only from `HOME=Z`, cleared by
any homing, motor off or shutdown; the touch gate uses this), `last_stiffness` (counts/µm),
`last_accuracy`.

The module attempts to retract before closing the serial session and attempts to stop
streaming even if the normal stop acknowledgement is lost. This does not provide an
MCU endstop or guarantee motion after a printer shutdown. Cold-boot debug messages
are decoded and logged as `board says`. See the [fault-handling evidence](VALIDATION.md#fault-handling-and-limitations).

## Evidence

The [2026-11-17 naming verification](VERIFICATION_2026-11-17.md) records the
renamed integration and migration checks.

**Sampling-fix hardware run (2026-11-16):** the sampling fix completed three consecutive
60-second stationary diagnostics and three five-tap runs without missing samples.
Five-tap ranges were 21.6, 7.9 and 6.3 µm; the wider first run and changing contact
height remain part of the result. See the [verification summary](VERIFICATION_2026-11-16.md)
for the full outcome, homing checks and limits of this retest.

The [validation record](VALIDATION.md) distinguishes historical K1 Max hardware runs
from software checks after the rebase. The 2026-11-16 checks passed all 82 Kalico host
tests (including 42 V23 load-cell cases), all 13 Creality tests, the bench tool's
self-test, and the V23 load-cell Ruff checks using the pinned Ruff 0.9.3. The installer
passes `bash -n` and adds no ShellCheck diagnostics over the upstream installer.

Historical hardware results include a five-tap range of 2.7 µm on USB-UART and a
ten-tap range of 1.68 µm through the MAX3232 adapter, plus real prints with both
connections. These are observations on one printer, not a repeatability guarantee
or a hardware retest of the rebased branches.

## SimpleAF side

The SimpleAF branch includes:

1. **[config/start_end.cfg](../../config/start_end.cfg)**: skips the probe's own touch/tap when the load cells home Z, the
   same way `loadcells_zoffset.cfg` does:
   ```diff
   -    {% set loadcell_touch = ('load_cell_probe' in printer.configfile.settings) %}
   +    {% set loadcell_touch = ('load_cell_probe' in printer.configfile.settings or 'load_cell_v23' in printer.configfile.settings) %}
   ```
2. **[k1/installer.sh](../../k1/installer.sh)**: a `--loadcells-v23` switch mirroring `--loadcells-zoffset` end to end --
   standalone switch command, install-flow CLI parsing, probe-switch detection, per-model support
   check, mutual exclusivity with `--loadcells-zoffset` (both define `_LOAD_CELL_HOME_Z`), BTT
   Eddy's z-offset prerequisite accepting either option, SAVE_CONFIG section cleanup in both
   migration directions (via `save-config-helper.py`, including the overrides
   `printer.cfg.save_config` snapshot), and the final restart condition. No `pellcorp.done` entry
   is written for it, matching `--loadcells-zoffset`'s own convention of using
   `--include-exists` for idempotency instead.
3. **Detection** (still optional, not implemented): the installer could tell a V23 from a V11
   without a probe, the same handshake [k1/v23_leveling.py](../../k1/v23_leveling.py)'s `status`/`identify`
   commands already do. Left for a future PR; not needed for this one since the installer takes
   the board type as an explicit flag.

## Wiring caveat (x2000 mainboards: K1/K1C/K1 Max with CR4CU220812S1x)

The x2000 mainboard's leveling port (`/dev/ttyS9`) uses **RS-232 levels**: TX idles at −5.5 V. The
V11 board carries a MAX3232 (`3232E`); the V23, made for x2600 mainboards with a TTL port, doesn't. On
an x2000 printer the V23 needs either:
- a MAX3232 TTL↔RS-232 module in TX/RX (then `serial: /dev/ttyS9`, as in the k1m patch), or
- a USB-UART on the board's TX/RX (`serial: /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`).

GND, 5V and SYNC go to the mainboard either way. SYNC (board PA8 → mainboard `PC10`) isn't used by
this module. **Never connect the V23's RX straight to an x2000 ttyS9:** it sees −5.5 V.

On x2600 mainboards the board sits on a TTL port (`/dev/ttyS4` in Creality's config) and needs no
converter. That's untested here.

## Known limitations

- It's a step probe, not a triggered one: ~25 steps, about 10–15 s per probe. The board's own touch
  trigger (`start_prtouch_pres` thresholds driving SYNC) never fired in testing.
- Thresholds are in raw counts. There's no grams calibration yet.
- Developer note: klippy's soft `RESTART` doesn't re-import Python modules. Restart the Klipper
  service after replacing `load_cell_v23.py`.

[creality-branch]: https://github.com/gilrim/creality/tree/add-prtouch-v3
[kalico-branch]: https://github.com/gilrim/kalico/tree/add-prtouch-v3
[kalico-module]: https://github.com/gilrim/kalico/blob/49f5b242f1a258ae5f4c510f91651e84ef6b6c48/klippy/extras/load_cell_v23.py
[kalico-tests]: https://github.com/gilrim/kalico/blob/49f5b242f1a258ae5f4c510f91651e84ef6b6c48/test/test_load_cell_v23.py
[kalico-config]: https://github.com/gilrim/kalico/blob/49f5b242f1a258ae5f4c510f91651e84ef6b6c48/docs/Config_Reference.md#load_cell_v23
[kalico-commands]: https://github.com/gilrim/kalico/blob/49f5b242f1a258ae5f4c510f91651e84ef6b6c48/docs/G-Codes.md#load_cell_v23
[kalico-status]: https://github.com/gilrim/kalico/blob/49f5b242f1a258ae5f4c510f91651e84ef6b6c48/docs/Status_Reference.md#load_cell_v23
