# V23 integration naming migration

This integration supports retrofitting the K1-MAX-L_V23 leveling board into a
K1 Max originally supplied without that board. Creality's firmware calls its
protocol `prtouch_v3`; the host integration now uses names that identify the board.

| Former public name | Current name |
|---|---|
| `prtouch_v3.py` / `[prtouch_v3]` | `load_cell_v23.py` / `[load_cell_v23]` |
| `prtouch_v3.cfg` | `loadcells_v23.cfg` |
| `--prtouch-v3` | `--loadcells-v23` |
| `PRTOUCH_PROBE` | `BED_LOAD_CELL_PROBE` |
| `PRTOUCH_DIAGNOSTIC` | `BED_LOAD_CELL_DIAGNOSTIC` |
| `PRTOUCH_PROBE_ACCURACY` | `BED_LOAD_CELL_PROBE_ACCURACY` |
| `PRTOUCH_Z_OFFSET_APPLY_PROBE` | `BED_LOAD_CELL_Z_OFFSET_APPLY_PROBE` |
| `printer.prtouch_v3` | `printer.load_cell_v23` |

`_LOAD_CELL_HOME_Z`, the standard `Z_OFFSET_APPLY_PROBE` macro, settings, units,
and sampling/force/fit/travel limits retain their behaviour. The board's wire
commands, including `config_prtouch_pres` and `resault_prtouch_pres`, are unchanged.
G-code names use an alphabetic prefix because Kalico splits extended command names
at digits such as those in `V23`.

## Existing installations

Update both contribution branches together. The new SimpleAF installer runs
`tools/migrate-v23-config.py` before detecting existing V23 configuration and when
setting up either load-cell Z-offset integration. The old installer switch remains
a compatibility alias. Old module, status-object and G-code names are not aliases;
custom macros must be migrated with the configuration.

The helper updates top-level `.cfg`, `.conf` and `.save_config` files in the active
configuration and overrides directories. It renames includes, sections, commands,
and status lookups, including saved `z_offset` values. It preserves other values
and comments except for renamed identifiers. It backs up changed files under
`/usr/data/pellcorp-backups/v23-name-migration`, and refuses conflicting old/new
files or sections before writing anything. Repeating it makes no further changes.
Configuration symlinks needing changes are refused for manual review. If custom
macros live in subdirectories, pass each such directory with `--config-dir` too.

For a manual migration, with the printer idle and heaters off, install the new
Kalico module and run:

```sh
python3 /usr/data/pellcorp/tools/migrate-v23-config.py \
  --config-dir /usr/data/printer_data/config \
  --config-dir /usr/data/pellcorp-overrides \
  --backup-dir /usr/data/pellcorp-backups/v23-name-migration
```

Preserve any unsaved calibration separately before restarting; it lives in memory
and is not part of these files. Restart the full Klipper service after the code
and configuration agree. A G-code `RESTART` does not re-import changed Python.
Remove an obsolete manually installed `prtouch_v3.py` and its cached bytecode only
after backing it up and checking that no active configuration uses the old section.

The existing `add-prtouch-v3` branch names are retained so PR references stay
valid. The previous documentation URLs remain as pointers. Dated verification records
retain the command names actually tested. Raw verification journals remain private.
