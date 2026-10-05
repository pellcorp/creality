# Simple AF is for:

- K1, K1C, K1 Max and K1SE
- Ender 3 V3 KE
- Ender 5 Max
- CR10SE
- Ender 3 V3
- Ender 3 V3 SE (retail Nebula Pad)
- Ender 3 V1, V1 Pro, Neo, V2 and V2 Neo (retail Nebula Pad)
- Any cartesian or corexy printer with a RPi, OrangePi or the like SBC!

An alternative environment for your printer which requires a separate probe

## Running Tests

The Python tests use the standard library's `unittest` framework. From the repository root, create a virtual environment and install the bundled ConfigUpdater dependency:

```bash
python3 -m venv .venv
.venv/bin/pip install packages/ConfigUpdater-3.2-py2.py3-none-any.whl
```

Run the tests with:

```bash
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
```

## Related Projects

The following projects also owned and developed by me (usually from an upstream fork) that are also used by this project:

- https://github.com/pellcorp/creality-wiki
- https://github.com/pellcorp/grumpyscreen
- https://github.com/pellcorp/klipper
- https://github.com/pellcorp/klipper-rpi
- https://github.com/pellcorp/k1-klipper-firmware
- https://github.com/pellcorp/kalico
- https://github.com/pellcorp/kalico-rpi
- https://github.com/pellcorp/k1-kalico-firmware
- https://github.com/pellcorp/k1-ustreamer
- https://github.com/pellcorp/k1-bash
- https://github.com/pellcorp/k1-sftp-server
- https://github.com/pellcorp/k1-nginx
- https://github.com/pellcorp/creality-firmware
