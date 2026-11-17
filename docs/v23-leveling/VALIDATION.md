# V23 leveling-board validation record

This record accompanies the [installation guide](INSTALL.md) and
[MAX3232 adapter guide](MAX3232_ADAPTER.md). Hardware results below are historical
observations from the author's K1 Max development notes and public commit messages.
Software checks were rerun after rebasing on November 16 and after the naming
migration on November 17. See the [naming verification](VERIFICATION_2026-11-17.md). The
[targeted printer verification](VERIFICATION_2026-11-16.md) initially exposed
intermittent fresh-sample failures. After the native CRC and bounded-wait fix,
three consecutive 60-second diagnostics and three five-tap runs completed without
sampling errors. Ranges were 21.6, 7.9 and 6.3 µm; the report retains the wider
first run, the homing checks, and the earlier failures.

## Software validation

| Repository | Upstream base | Checked source revision |
|---|---|---|
| Creality | [pellcorp/creality:main at 0ad9fd2][creality-base] | [319bd9a][creality-source] |
| Kalico | [pellcorp/kalico:aug2026 at 08abba83][kalico-base] | [49f5b242][kalico-source] |

Both rebases completed without conflicts. `git range-diff` showed the five
Creality and six Kalico feature commits retained their patches. A subsequent
Creality commit quoted model/probe paths and replaced an indirect return-code
check; it preserves the setup function's convention that return code 1 requests
a Kalico restart. Documentation updates follow the checked source revision.

The later Kalico sampling fix adds an equivalent native CRC, a bounded wait for fresh channel
coverage, and 12 host cases covering CRC equivalence, rolling freshness,
deadline expiry, stopped streams, and overlapping packet timestamps.
The November 17 naming migration passed 67 machine/upstream cases on the
workstation, and 30 cases under the printer's Python 3.8 (25 machine tests and
five configuration migration tests). The migration cases cover saved offsets,
custom macros, conflicting files/sections, idempotence and protocol preservation.

Environment: Python 3.13.5, pytest 8.4.2, Ruff 0.9.3, ConfigUpdater 3.2, and
ShellCheck 0.11.0. Kalico dependencies came from its checked-in
`scripts/klippy-requirements.txt` and `scripts/requirements_dev.txt`; ConfigUpdater
came from Creality's bundled wheel.

| Check | Result |
|---|---|
| Kalico `test/test_*.py` | 82 passed, including all 42 cases in `test_load_cell_v23.py` |
| Ruff lint and format checks on the V23 load-cell module and tests | Passed |
| Creality `unittest` suite | 13 passed, including five naming migration cases |
| `k1/v23_leveling.py selftest` | Passed |
| `bash -n k1/installer.sh` | Passed |
| ShellCheck, Bash mode, compared with upstream `k1/installer.sh` | 211 diagnostics in each; no added diagnostic codes/messages |
| Documentation links and image paths | Checked against both repository trees |

The ShellCheck result is a comparison with the existing installer, not a claim
that the whole installer is warning-free. The Kalico test command covers the
Python host tests. It does not cover the full MCU build matrix or the
`test/klippy/*.test` simulations that require firmware dictionaries.

### Reproducing the software checks

In a Python virtual environment, install the two Kalico requirements files above
and the Creality `packages/ConfigUpdater-3.2-py2.py3-none-any.whl` wheel. From the
Kalico checkout, run:

```sh
python -m pytest -q test/test_*.py
ruff check klippy/extras/load_cell_v23.py test/test_load_cell_v23.py
ruff format --check klippy/extras/load_cell_v23.py test/test_load_cell_v23.py
```

This Pellcorp Kalico branch ships a MIPS `klippy/chelper/c_helper.so` and disables
its automatic rebuild. On a desktop host, first build a native helper from the
same source for testing. The following wrapper builds it with the repository's
compiler settings, runs the host tests, and restores the checked-in binary even
when a test fails:

```python
from pathlib import Path
import shlex
import subprocess
import sys

import klippy.chelper as chelper

srcdir = Path("klippy/chelper").resolve()
helper = srcdir / chelper.DEST_LIB
original = helper.read_bytes()
try:
    sources = chelper.get_abs_files(str(srcdir), chelper.SOURCE_FILES)
    command = (chelper.GCC_CMD + " " + chelper.COMPILE_ARGS) % (
        str(helper), " ".join(sources)
    )
    subprocess.run(shlex.split(command), check=True)
    tests = [str(path) for path in sorted(Path("test").glob("test_*.py"))]
    subprocess.run([sys.executable, "-m", "pytest", "-q", *tests], check=True)
finally:
    helper.write_bytes(original)
```

Run that code with the virtual environment's Python from the Kalico repository
root. The restored MIPS binary must remain unchanged in the contribution.

From the Creality checkout:

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
python k1/v23_leveling.py selftest
bash -n k1/installer.sh
shellcheck --shell=bash k1/installer.sh
```

For the ShellCheck comparison, run the same version and flags against the
upstream base and feature branch, comparing diagnostic code, severity, message,
and count rather than line numbers, which move when code is added.

## Hardware and protocol observations

The test printer was a K1 Max with an x2000 `CR4CU220812S11` mainboard,
Cartographer scan homing, and a K1-MAX-L_V23 leveling board containing a CH32V203
and four CS1237 converters. Initial runs used Kalico `v2026.08.00-45` and SimpleAF
`f8dc056` / `v0.0.1-1390`. Later fixes are identified separately below.

- The board identified as `CTF_V1.0.0.16.20250320`, MCU `ch32v203x8`, 144 MHz,
  230400 baud. Its dictionary contained 73 commands and 28 responses.
- Configuration uses `config_prtouch_pres` for each channel. Force streaming
  uses `start_prtouch_pres`, the board's `resault_prtouch_pres` response, and
  `stop_prtouch_pres`; samples are delta encoded. Protocol and fitting fixtures
  are in the [host tests][kalico-tests] and [bench tool](../../k1/v23_leveling.py).
- The configured acquisition interval is 0.78125 ms, but observed delivery was
  roughly 650-680 samples per second per channel. The module therefore avoids
  timestamping samples with a clock that assumes the configured rate is the
  delivered rate. See the [sample-clock correction][clock-fix].
- The x2000 mainboard's TX idled at about -5.5 V. Direct connection pulled V23 RX
  to about -2.2 V and produced scrambled frames. A CH341 at TTL levels worked;
  the inline MAX3232 adapter subsequently enabled `/dev/ttyS9`. The adapter
  guide contains the circuit, measured voltages, and photos.
- Resetting the V23 entered its IAP bootloader for about 60 seconds; power-on
  started the application directly. The module owns its serial connection
  instead of registering it as a normal Kalico `[mcu]`.
- The board's SYNC trigger did not fire during investigation. The contribution
  uses settled force readings and host-controlled Z steps, not a hardware
  endstop. Force limits are evaluated after a step.

## Hardware validation history

Contact heights below are in the coordinate system before load-cell homing;
they vary with the scan reference, mounting, and temperature. Repeatability
ranges are not absolute accuracy measurements.

| Date / stage | Connection | Recorded outcome |
|---|---|---|
| 2026-10-28, initial probing | CH341 USB-UART | Three contacts at 0.1399, 0.1395, and 0.1394 mm; 0.5 µm span; stiffness 314-320 counts/µm. A home at 0.1312 mm was followed by re-probes at -0.0001 and -0.0035 mm. |
| 2026-11-03, after safety fixes | CH341 USB-UART | Five-tap range 2.7 µm, standard deviation 1.0 µm. Home at 0.1867 mm, 324 counts/µm; re-probe -0.0026 mm. The local print gate accepted the home and refused after `G28 X` cleared it. |
| 2026-11-03, ABS print | CH341 USB-UART | Bed 100 °C; home at 0.2228 mm, 252 counts/µm; gate accepted and printing continued. The chamber was preheated separately because of the USB fault described below. |
| 2026-11-10, initial adapter installation | MAX3232 / ttyS9 | After reassembly, contact shifted to about 0.98 mm and a later tap's residual reached 0.0098 mm. The 0.005 mm fit limit rejected the home, the nozzle retracted, and `last_home_z_result` remained unset. |
| 2026-11-10, after remount and bed leveling | MAX3232 / ttyS9 | Ten-tap range 1.68 µm; another run 5.06 µm. Home at 0.1341 mm, 248 counts/µm, followed by a real print reported to look good. The mechanical issue was closed. |
| 2026-11-11, second adapter build | MAX3232 / ttyS9 | The 2k7/5k6 divider worked without the first build's divider iteration; see the adapter guide, section 4. |
| Sample-clock / re-tare fix | K1 Max, as recorded in the [commit][clock-fix] | Range 2.8 µm, stiffness 247-308 counts/µm, home 0.1304 mm; gate invalidation and offset staging checked. |
| Buffered-batch / lost-ack fix | K1 Max, as recorded in the [commit][batch-fix] | Range 2.1 µm, stiffness 311 counts/µm, home 0.1186 mm, re-probe 0.0002 mm; gate invalidation and offset staging checked. |
| Stall within a drain call | K1 Max, as recorded in the [commit][stall-fix] | Diagnostic returned 16 readings; accuracy range 6.0 µm; home 0.1278 mm; gate invalidation and offset staging checked. |

The last three rows link to the original public commit messages, which record
those hardware runs. The November 3
and November 10 rows summarize the development run log and bed-leveling record;
they are historical observations, not newly executed checks.

## Fault handling and limitations

- In the November 3 USB-disconnection test, the module reported no samples after
  about nine seconds without hanging. Reconnecting the CH341 stalled another MCU
  on the shared USB hub and required a printer power cycle. That run does not
  establish graceful whole-printer recovery from hot-plugging.
- Heavy chamber-heater, extruder, and fan loads also caused USB drops on the test
  printer. The successful November 3 ABS run used separate chamber preheating.
  Neither the module nor the adapter documentation claims to fix that electrical
  problem.
- Cold-boot debug output originally killed the parser worker. Recorded retests
  after the parser fix decoded those messages and restored diagnostic streaming.
- Host tests cover protocol framing, force fitting, backoff relief, stale sample
  rejection, and streaming cleanup after lost acknowledgements or link errors.
  They do not simulate all printer motion/shutdown paths or prove the retract
  will succeed after a motor, MCU, or power failure.
- A local `touch_gate.cfg` macro was used to check `last_home_z_result` on the
  test printer. It is not shipped in either contribution. The reported gate
  checks demonstrate that local integration; they are not a test of a bundled
  SimpleAF gate. The module's status fields are documented in Kalico.
- No rebased-code hardware test, x2600 printer test, grams calibration, hardware
  SYNC-triggered probing, or successful firmware recovery flash is claimed here.

For a future hardware retest, record both Git SHAs, board firmware, serial path,
nozzle/bed temperatures, diagnostic noise, accuracy statistics, fit parameters,
home and re-probe results, status invalidation, and a representative print. Use
the [installation checks](INSTALL.md#7-verify) and keep the results associated
with the code revision actually installed.

[creality-base]: https://github.com/pellcorp/creality/commit/0ad9fd2c6dee32d509049d2c08375ba94e848c60
[creality-source]: https://github.com/gilrim/creality/commit/319bd9a4431e782368f7bee318c49dd11b3fe2e7
[kalico-base]: https://github.com/pellcorp/kalico/commit/08abba8358b260c95b2ef9fe6220e937acf3dc95
[kalico-source]: https://github.com/gilrim/kalico/commit/49f5b242f1a258ae5f4c510f91651e84ef6b6c48
[kalico-tests]: https://github.com/gilrim/kalico/blob/49f5b242f1a258ae5f4c510f91651e84ef6b6c48/test/test_load_cell_v23.py
[clock-fix]: https://github.com/gilrim/kalico/commit/6fc04d29f7296787e307b7bd8cc4a5635084267b
[batch-fix]: https://github.com/gilrim/kalico/commit/fed344bb54506875a66e008d19f66edc6f10aa37
[stall-fix]: https://github.com/gilrim/kalico/commit/c4cf7f7e3af15a45e649016a881cb2ad71a64c8e
