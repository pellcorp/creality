# prtouch_v3: Z homing with the K1-MAX-L_V23 load cell board

Staged as two upstream pull requests. Each directory mirrors its target repo:

| Directory | Target repo | Files |
|---|---|---|
| `kalico/` | `pellcorp/kalico` | `klippy/extras/prtouch_v3.py`, `test/test_prtouch_v3.py` |
| `creality/` | `pellcorp/creality` (SimpleAF) | `config/prtouch_v3.cfg`, `k1/patches/prtouch_v3.cfg.k1m`, `k1/v23_leveling.py` |

`creality/k1/v23_leveling.py` sits at the same level as pellcorp/creality's existing
`k1/mcu_util.py` — a standalone pyserial tool, no Klipper tree needed. It's the bench/bring-up
tool used throughout `INSTALL.md`.

**To install it on a printer** (wiring, firmware extraction, config, verification): `INSTALL.md`.
Both directories are pushed as branches on the author's own forks (`gilrim/kalico`,
`gilrim/creality`, both `add-prtouch-v3`); no PR is open against pellcorp yet.

> `INSTALL.md` and `MAX3232_ADAPTER.md` cross-reference a few files (`systems/k1m.md`,
> `systems/k1m_v23_leveling.md`, `systems/k1m_prtouch_v3_safety.todo`) from the author's private
> dev-log repo; those paths won't resolve here. They're development history and day-to-day
> operational notes, not required reading for this module.

## What it does

Some K1-family printers now ship with, or get replaced with, the **K1-MAX-L_V23** leveling board:
CH32V203 + 4× CS1237, Creality's x2600 platform. SimpleAF's `loadcells` support targets the older V11
board (GD32E230 + HX711, Kalico `hx711s` firmware). The V23 can't run Kalico firmware. It runs
Creality's own Klipper build (`CTF_V1.0.0.16.20250320`) with the `prtouch_v3` command set.

`[prtouch_v3]` talks to that firmware directly and provides load-cell Z homing. It plugs into
START_PRINT through the existing `_LOAD_CELL_HOME_Z` hook, the same one `loadcells-zoffset` uses.

**Method: step-probing plus a line fit.** It tares the summed force of the four cells, then steps Z
down (0.05 mm coarse, back off, 0.01 mm fine) and reads the settled force after each step. The bed
is compliant: past contact, force rises linearly with depth, at ~300 counts/µm on a K1 Max. So the
**zero-force intercept of a line fitted through the fine steps** gives the contact height to well
under a step. `PRTOUCH_PROBE HOME=Z` then re-references Z, using the same `set_position` logic as
`PROBE HOME=Z` in Kalico's `probe.py`.

**Why not an `[mcu]`:**
- The V23 firmware has no Kalico load-cell/trsync support, so `load_cell_probe` can't be used.
- A Klipper `reset` parks this board in its IAP bootloader for ~60 s. Creality uses
  `restart_method: script` (cmd_iap), which Kalico doesn't have.

The module therefore owns the board's serial port itself, from a worker thread, so the reactor never
blocks. Gcode commands wait with `reactor.pause()`.

Commands (no digits in the names; klippy's gcode parser splits `PRTOUCH_V3_PROBE`):
- `PRTOUCH_PROBE [HOME=Z]`: probe from the current Z (which must be homed, e.g. by a scan probe)
  at the current XY. The fit must pass `min_stiffness`/`max_stiffness` (counts/µm, default
  50-1500), `max_fit_error` (0.005 mm) and `max_extrapolation` (0.1 mm), or nothing is applied.
- `PRTOUCH_DIAGNOSTIC [TIME=5]`: per-channel tare and force noise.
- `PRTOUCH_PROBE_ACCURACY [SAMPLES=10]`: 2-100 taps; min/max/range/average/median/stddev. The
  `prtouch_v3.cfg` macro moves to the zero reference first.
- `PRTOUCH_Z_OFFSET_APPLY_PROBE`: stages `z_offset` for SAVE_CONFIG from the gcode offset;
  `prtouch_v3.cfg` routes `Z_OFFSET_APPLY_PROBE` to it. Don't set `z_offset` in the included
  cfg, or SAVE_CONFIG refuses the include conflict.

Status: `printer.prtouch_v3.last_z_result`, `last_home_z_result` (only from `HOME=Z`, cleared by
any homing, motor off or shutdown; the touch gate uses this), `last_stiffness` (counts/µm),
`last_accuracy`.

Robustness (from testing on a K1 Max, 2026-11-03): the nozzle retracts before the serial session
is closed, so a board fault can't leave it pressed into the bed. The board prints printf-style
debug messages after a cold boot; they're decoded and logged as `board says`. Closing always
stops the stream, because a board left streaming can't be identified by the next session.

## Evidence (K1 Max, Kalico v2026.08.00, SimpleAF v0.0.1-1390)

```
PRTOUCH_DIAGNOSTIC TIME=4     force noise -90 .. 382 counts (0.15 s averages, 4 cells summed)
PRTOUCH_PROBE_ACCURACY x3     0.1399 / 0.1395 / 0.1394  (0.5 um span), 314-320 counts/um
PRTOUCH_PROBE HOME=Z          0.1312 -> homed; re-probe -0.0001 / -0.0035
_LOAD_CELL_HOME_Z (148C)      contact 0.2050 (hot end expansion vs cold ~0.13), homed, gate OK
2026-11-03, after the safety changes:
PRTOUCH_PROBE_ACCURACY S=5    range 2.7 um, stddev 1.0 um, 324-335 counts/um
_LOAD_CELL_HOME_Z + gate      0.1867 cold bed; 0.2228 in a real ABS print (bed 100C, 252 counts/um)
```
`pytest test/test_prtouch_v3.py`: 30 passed, under the kalico fork's own pinned CI tooling
(Python 3.13, pytest, ruff 0.15.22). `ruff check`/`ruff format` clean. `bash -n` and a dockerized
`shellcheck` diff against the unmodified `k1/installer.sh` show zero new warnings.

## SimpleAF side

Both pieces sketched in earlier drafts of this doc are now implemented and pushed:

1. **`config/start_end.cfg`**: skips the probe's own touch/tap when the load cells home Z, the
   same way `loadcells_zoffset.cfg` does:
   ```diff
   -    {% set loadcell_touch = ('load_cell_probe' in printer.configfile.settings) %}
   +    {% set loadcell_touch = ('load_cell_probe' in printer.configfile.settings or 'prtouch_v3' in printer.configfile.settings) %}
   ```
2. **`k1/installer.sh`**: a `--prtouch-v3` switch mirroring `--loadcells-zoffset` end to end --
   standalone switch command, install-flow CLI parsing, probe-switch detection, per-model support
   check, mutual exclusivity with `--loadcells-zoffset` (both define `_LOAD_CELL_HOME_Z`), BTT
   Eddy's z-offset prerequisite accepting either option, SAVE_CONFIG section cleanup in both
   migration directions (via `save-config-helper.py`, including the overrides
   `printer.cfg.save_config` snapshot), and the final restart condition. No `pellcorp.done` entry
   is written for it, matching `--loadcells-zoffset`'s own convention of using
   `--include-exists` for idempotency instead.
3. **Detection** (still optional, not implemented): the installer could tell a V23 from a V11
   without a probe, the same handshake `creality/k1/v23_leveling.py`'s `status`/`identify`
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
  service after replacing `prtouch_v3.py`.
