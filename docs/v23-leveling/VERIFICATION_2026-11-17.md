# V23 naming migration verification — 2026-11-17

**Naming, migration and integration checks passed.** The printer now loads
`[load_cell_v23]` and exposes the four `BED_LOAD_CELL_*` commands. Stationary
sampling, two five-tap runs, load-cell homing, re-probing and gate checks completed
without sampling errors. Repeatability was wider than previous settled runs and
is reported below; this is not a claim of improved measurement precision.

## Source and deployment

- [Kalico source 49f5b242](https://github.com/gilrim/kalico/commit/49f5b242f1a258ae5f4c510f91651e84ef6b6c48): renamed module, object, class, commands, tests and references.
- [SimpleAF integration 319bd9a](https://github.com/gilrim/creality/commit/319bd9a4431e782368f7bee318c49dd11b3fe2e7): `--loadcells-v23`, configuration/macros, print-start detection and migration helper.
- The deployed module and machine reference both have SHA-256
  `5af73a1f071ae4eeaafba8ba62376f934c2b40370b80fee1505394ab24a77962`.

The test printer is the existing K1 Max retrofit: x2000 mainboard, V23 leveling
board, inline MAX3232 adapter on `/dev/ttyS9`, and Cartographer initial homing.
This was a targeted module/configuration deployment with a full Klipper service
restart. The base Kalico/SimpleAF installations were not upgraded. The machine
repository and separate overrides repository were synchronized; unrelated chamber
edits were preserved byte for byte. The live print-start condition now recognizes
`load_cell_v23`, matching the contribution's integration.

The old module and bytecode were removed after backup and successful startup.
The loaded object list, command registry, configuration and print-start template
were checked: the new names are active, and the old module/object/commands are
absent. Firmware wire-command names remain unchanged. An AST comparison against
the previously deployed driver confirms identical logic after accounting for the
identifier and diagnostic-string substitutions.

## Configuration migration and software checks

A one-time migration helper (`migrate-v23-config.py`) renamed the old/new config
sections, includes, commands and saved offsets, with backups and conflict
detection; it was tested with fixtures on both the workstation and printer, then
removed from the tree afterward since this fork had no other installations left
to migrate. Historical logs are excluded. The live files were migrated through
synchronized git commits.

| Check | Result |
|---|---|
| Kalico host suite | 82 passed, including 42 V23 cases |
| Machine/upstream suite against the deployable reference | 67 passed |
| Printer Python 3.8 | 30 passed: 25 machine tests and five migration tests |
| Creality suite | 13 passed, including five migration tests |
| Bench tool self-test | Passed |
| Bash syntax for installer and machine post-update script | Passed |
| ShellCheck compared with the pre-rename installer | 211 existing diagnostics before and after; no additions |
| V23 module/test Ruff lint and formatting | Passed |

An existing unsaved `prtouch_v3.z_offset = -0.020` was present before deployment.
It was recorded before the restart and restored through
`BED_LOAD_CELL_Z_OFFSET_APPLY_PROBE` as `load_cell_v23.z_offset = -0.020`.
The G-code Z offset returned to zero. No calibration was saved or discarded;
the adjustment remains pending exactly as it was before this task.

## Printer results

The renamed 60-second diagnostic returned all four channels and 192 force
readings, ranging from -451 to +1105 counts, without a sampling failure.
`G28` passed, followed by the existing nozzle-cleaning macro's 175 °C and 148 °C
wipes. Both accuracy runs used 148 °C; bed and chamber heaters remained off.

| Five-tap run | Range | Standard deviation | Mean contact height |
|---|---|---|---|
| 1 | 38.544 µm | 13.462 µm | 0.207188 mm |
| 2 | 14.096 µm | 5.296 µm | 0.185526 mm |

All ten taps passed the existing fit checks without missing samples. The first
run's spread and the changing mean indicate that repeatability remains sensitive
to the test conditions; this run did not isolate the cause. The rename changes
neither the sampling algorithm nor the acceptance limits. No precision limit was
relaxed to obtain these results.

Load-cell homing accepted contact at 0.171583 mm (299.2 counts/µm). Re-probing
measured -0.001258 mm from the new zero (319.3 counts/µm), passing the ±0.010 mm
check. The touch gate accepted the successful home; `G28 X` invalidated it and the
gate then refused as intended. The known Moonraker HTTP error-delivery issue
remains: G-code history confirms the refusal despite the client connection closing.

Final state: standby, parked at Z10, all heater targets zero, G-code Z offset zero,
and the pre-existing -0.020 mm adjustment still pending under the new section.
No `SAVE_CONFIG`, full print, firmware flash or fault injection was performed.
Detailed journals remain in the local maintenance repositories; this public page
contains the summary only.
