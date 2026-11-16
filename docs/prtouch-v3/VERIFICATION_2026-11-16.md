# V23 verification summary — 2026-11-16

**Deployment completed; hardware acceptance remains open.** Both five-tap
accuracy attempts stopped because fresh board samples were unavailable within
the required 0.15-second window. No repeatability result or new load-cell Z home
was accepted.

The test printer was a K1 Max with an x2000 mainboard, K1-MAX-L_V23 board,
MAX3232 adapter on `/dev/ttyS9`, and Cartographer scan homing. The installed
PRTouch module matched [Kalico `86d61945`](https://github.com/gilrim/kalico/commit/86d619459d5bbfac92c4f3bff1695ea2df062169)
byte for byte. The targeted deployment synchronized the machine integration and
reloaded it; it did not upgrade the complete base Kalico/SimpleAF installations.

| Check | Result |
|---|---|
| Workstation tests against the deployable module | 53 passed, including 30 upstream PRTouch tests; Ruff passed |
| Machine tests on the printer's Python 3.8 | 23 passed |
| V23 diagnostics | Both runs returned all four channels and 16 readings |
| Initial scan homing | Passed |
| Nozzle cleaning | Existing macro completed wipes at 175 °C and 148 °C |
| Five-tap repeatability | Initial attempt and one controlled retry both aborted on missing fresh samples |
| Failure handling | Retracted to the 1 mm start height; no load-cell home or accuracy result accepted |
| Missing-home guard | Klipper refused as intended; Moonraker separately failed to deliver the HTTP error response |
| Offset staging | Passed; temporary value discarded with a restart, without saving calibration |
| Final state | Parked before restart, Klipper ready, heater targets off, no pending configuration |

Probing used a 148 °C nozzle with the bed and chamber heaters off. Safety limits
were unchanged. Existing chamber-macro edits and calibration were preserved.
Load-cell homing, re-probing near the new zero, successful-home gate/invalidation
checks, and a full print were deferred after the repeated sampling failure.

Moonraker also reported multi-second event-loop stalls. Host timing is a lead to
investigate, not a confirmed cause. Distinguish serial delivery gaps from delayed
worker drains before repeating acceptance, keeping the freshness and force/fit
checks intact. Detailed diagnostic captures remain in local maintenance records.
