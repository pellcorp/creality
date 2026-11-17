# V23 verification summary — 2026-11-16

**Sampling fix deployed and retested.** Three one-minute diagnostics and all
15 repeatability taps completed without sampling errors. Load-cell homing,
re-probing (+2.611 µm), and touch-gate invalidation/refusal passed. Five-tap ranges
were 21.575, 7.913 and 6.291 µm; the first run remains a repeatability limitation.
See [sampling fix and retest](#sampling-fix-and-retest) for the current result.

## Initial deployment

The initial two five-tap attempts aborted on missing fresh samples. A requested
rerun later completed one five-tap measurement, then the following run aborted
with the same error. These failures motivated the sampling fix and retest below.

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
| Final state | Parked at Z10 after the rerun, Klipper ready, heater targets off, no pending configuration |

Probing used a 148 °C nozzle with the bed and chamber heaters off. Safety limits
were unchanged. Existing chamber-macro edits and calibration were preserved.
Load-cell homing, re-probing near the new zero, successful-home gate/invalidation
checks, and a full print were deferred after the repeated sampling failure.

Moonraker also reported multi-second event-loop stalls. Host timing is a lead to
investigate, not a confirmed cause. Distinguish serial delivery gaps from delayed
worker drains before repeating acceptance, keeping the freshness and force/fit
checks intact. Detailed diagnostic captures remain in local maintenance records.

## Repeatability rerun

After repeating scan homing and the 175/148 °C cleaning cycle, two consecutive
five-tap runs were attempted at 148 °C with unchanged code and safety limits:

| Run | Result | Range | Standard deviation | Mean contact height |
|---|---|---|---|---|
| 1 | Completed five taps | 7.413 µm | 2.984 µm | 0.113036 mm |
| 2 | Aborted on missing fresh samples in the 0.15 s window | Unavailable | Unavailable | Unavailable |

The failed run retracted to its start height and cleared the accuracy result.
Heaters were turned off and the nozzle parked at Z10. No calibration or load-cell
home was saved. One completed run does not resolve the intermittent failure.

## Sampling investigation

Stationary tests reproduced the failure without heating or motion. The traces
show two ways the current measurement can end without fresh coverage:

- With the original driver, read/processing cycles exceeded the 200 ms freshness
  limit. Two consecutive cycles received 4,095 bytes each, but their samples were
  discarded as potentially stale. At the failed query, all four channels had zero
  fresh samples and their newest accepted values were about 0.6 seconds old.
- A temporary equivalent native CRC reduced decoder CPU time by about 55%, but
  one stationary test still failed: channel 0's newest accepted sample was 191 ms
  old while the other three channels had 145, 64 and 115 fresh samples. Read cycles
  were normal, around 60–68 ms. The fixed 150 ms measurement window does not always
  contain fresh data from every channel. The trace did not establish whether the
  missing channel's next packet was late on the wire or pending publication.

Profiling five seconds of captured traffic found the Python CRC loop consumed
about half of decoder CPU time. The equivalent native CRC matched 1,000 test
inputs and every captured frame, reducing total decoder CPU time from about
1.8 seconds to 0.8 seconds. Across its stationary comparisons, four 60-second runs
completed and one failed. This is a promising optimization, not a complete fix.
The five-second packet capture contained 1,781 valid frames; skipped bytes were
only incomplete frames at the capture boundaries.

These findings motivated the sampling fix described below: reduce decoder
overhead and use a bounded wait for fresh coverage from all channels, retaining
the post-settle cutoff, stale-batch rejection, force limits and failure
retraction. Merely disabling the freshness checks would conceal the problem. Moonraker's periodic stalls may contribute
load, but their role was not proven by this investigation.

All temporary instrumentation and the CRC variant were removed. The original
module hash was restored and Klipper restarted with heaters off. At the end of
this investigation, no permanent code change, calibration change or heated
contact test had followed these diagnostic experiments; the subsequent
implementation and retest are recorded below. Detailed captures remain local; this public section is a summary.

## Sampling fix and retest

The deployed module now uses an equivalent native CRC and waits for fresh
coverage from every configured channel. After settling, the first check follows
one 150 ms sample window; missing coverage is retried every 20 ms, with a default
500 ms deadline measured from the end of settling. Every accepted reading still
needs at least five samples per channel, timestamped after settling and within
the rolling 150 ms window. Waiting does not move the nozzle or widen that window.
A timeout reports each channel's sample count and newest accepted sample age.

History scans now stop after accounting for the maximum possible overlap between
packet timestamp ranges, reducing time spent holding the sample lock. The 200 ms
stale-batch rejection, force/fit/travel limits, and failure retraction are unchanged.
`sample_timeout` defaults to `max(0.5, sample_time + 0.35)` and must exceed
`sample_time`; this printer uses the defaults without a configuration change.

Source: [Kalico 27d3e7e](https://github.com/gilrim/kalico/commit/27d3e7e90dec8a253392869c7ef03c4c4cd905ea).
Installed module SHA-256:
`1f0b8d04006e29258c0f1646783066243127ad9df21758449d6ec0be4e9ecc8d`.
The original module/configuration were backed up before a full Klipper service
restart. The base Kalico/SimpleAF installations and chamber configuration remain
as described above.

Software checks passed: 82 Kalico host cases (42 PRTouch), 66 workstation
machine/upstream cases, 24 machine cases on the printer's Python 3.8, and Ruff
lint/format checks. Added regressions cover independent CRC equivalence,
corrupted-frame rejection, delayed-channel recovery, post-settle and rolling
freshness cutoffs, deadline overrun, stopped streams, overlapping timestamps,
and timeout configuration bounds.

Three stationary `PRTOUCH_DIAGNOSTIC TIME=60` runs completed consecutively:
192, 192 and 191 force readings, with ranges of -222 to +648, -398 to +704,
and -456 to +385 counts. No sampling errors occurred. The first preflight after
service restart stopped while Klipper was still starting; no diagnostic command
was issued until it reported ready.

After `G28`, the existing nozzle macro completed its 175 °C wipe and second wipe
at 148 °C. Three consecutive five-tap runs then completed at 148 °C, with the bed
and chamber heaters off. All 15 taps passed the existing fit checks, with no
fresh-sample aborts:

| Run | Range | Standard deviation | Mean contact height |
|---|---|---|---|
| 1 | 21.575 µm | 7.581 µm | 0.143960 mm |
| 2 | 7.913 µm | 2.839 µm | 0.121740 mm |
| 3 | 6.291 µm | 2.377 µm | 0.120863 mm |

The first run was wider than the earlier 7.413 µm result, and its mean was about
22 µm higher than the second run. The final two means differed by 0.878 µm.
This is compatible with settling after cleaning/heating, but this test did not
isolate the cause. The sampling fix passed this retest; it does not establish
2 µm repeatability or guarantee that no future sampling fault can occur.

`_LOAD_CELL_HOME_Z` accepted contact at 0.120389 mm with stiffness
317.4 counts/µm. A subsequent independent probe measured +0.002611 mm from the
new zero (301.6 counts/µm), within the 0.010 mm re-probe check. The local touch
gate accepted the successful home, `G28 X` cleared `last_home_z_result`, and the
gate then refused with `no successful load cell home available`. Moonraker's
previously observed HTTP error-delivery failure remains: the client connection
closed, while the G-code history confirmed the expected refusal.

Final state: parked at Z10, standby, all heater targets zero, zero G-code Z
offset, no pending configuration, and no accepted load-cell home after the
invalidation test. No `SAVE_CONFIG`, full print, firmware flash, or cable-fault
injection was performed. Offset staging had passed during the initial deployment
above and was not repeated for this sampling-only change. Detailed journals
remain in the local maintenance repositories; GitHub contains this summary only.
