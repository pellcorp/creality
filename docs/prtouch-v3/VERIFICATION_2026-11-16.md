# V23 verification summary — 2026-11-16

**Deployment completed; hardware acceptance remains open.** The initial two
five-tap attempts aborted on missing fresh samples. A requested rerun later
completed one five-tap measurement, then the following run aborted with the same
error. The sampling fault is intermittent and remains unresolved.

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

The next code change should reduce decoder overhead and use a bounded wait for
fresh coverage from all channels, retaining the post-settle cutoff, stale-batch
rejection, force limits and failure retraction. Merely disabling the freshness
checks would conceal the problem. Moonraker's periodic stalls may contribute
load, but their role was not proven by this investigation.

All temporary instrumentation and the CRC variant were removed. The original
module hash was restored and Klipper restarted with heaters off. No permanent
code change, calibration change or heated contact test followed these diagnostic
experiments. Detailed captures remain local; this public section is a summary.
