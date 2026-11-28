import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[1]
CONFIG_HELPER_PATH = REPOSITORY_ROOT / "tools" / "config-helper.py"
CONFIG_OVERRIDES_SH = REPOSITORY_ROOT / "tools" / "config-overrides.sh"
SPEC = importlib.util.spec_from_file_location("config_helper", CONFIG_HELPER_PATH)
config_helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(config_helper)

SAVE_CONFIG_BLOCK = (
    "#*# <---------------------- SAVE_CONFIG ---------------------->\n"
    "#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.\n"
    "#*#\n"
    "#*# [bed_mesh default]\n"
    "#*# version = 1\n"
    "#*# points =\n"
    "#*# \t  0.010000, 0.020000\n"
)
PRINTER_CFG = (
    "[printer]\n"
    "kinematics: corexy\n"
    "max_velocity: 800\n"
    "\n"
    "[stepper_x]\n"
    "microsteps: 32\n"
    "\n"
)


class TempDirTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)


class CrlfConfigHelperTest(TempDirTest):
    """A printer.cfg saved by a Windows editor has CRLF line endings."""

    def run_helper(self, config, *args):
        path = self.tmp / "printer.cfg"
        path.write_bytes(config.replace("\n", "\r\n").encode())
        env = dict(os.environ, HOME=str(self.tmp))
        subprocess.run(
            [sys.executable, "-I", str(CONFIG_HELPER_PATH), "--file", path.as_posix(), *args],
            check=True,
            env=env,
        )
        return path.read_bytes().decode()

    def test_crlf_file_keeps_save_config_block_and_is_edited(self):
        result = self.run_helper(
            PRINTER_CFG + SAVE_CONFIG_BLOCK,
            "--replace-section-entry", "printer", "max_velocity", "500",
        )

        self.assertIn("max_velocity: 500", result)
        self.assertNotIn("\r", result)
        # the SAVE_CONFIG block is still there, complete and last
        self.assertTrue(result.endswith(SAVE_CONFIG_BLOCK), result)

    def test_crlf_file_gets_new_section_before_save_config(self):
        result = self.run_helper(
            PRINTER_CFG + SAVE_CONFIG_BLOCK,
            "--add-section", "load_cell_probe",
        )

        self.assertLess(result.index("[load_cell_probe]"), result.index("SAVE_CONFIG"))
        self.assertTrue(result.endswith(SAVE_CONFIG_BLOCK), result)


class AtomicWriteTest(TempDirTest):
    def test_failed_write_leaves_original_untouched(self):
        path = self.tmp / "printer.cfg"
        path.write_text(PRINTER_CFG + SAVE_CONFIG_BLOCK)

        def failing_write(file):
            file.write("[printer]\nhalf a fi")
            raise RuntimeError("disk full")

        with self.assertRaises(RuntimeError):
            config_helper._write_atomically(str(path), failing_write)

        self.assertEqual(path.read_text(), PRINTER_CFG + SAVE_CONFIG_BLOCK)
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()), ["printer.cfg"])

    def test_successful_write_replaces_file_and_leaves_no_temp(self):
        path = self.tmp / "printer.cfg"
        path.write_text("old\n")
        path.chmod(0o640)

        config_helper._write_atomically(str(path), lambda file: file.write("new\n"))

        self.assertEqual(path.read_text(), "new\n")
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()), ["printer.cfg"])
        if os.name == "posix":
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)

    def test_symlink_is_written_through_not_replaced(self):
        if os.name != "posix":
            self.skipTest("symlinks need posix")
        real = self.tmp / "real.cfg"
        real.write_text("old\n")
        link = self.tmp / "printer.cfg"
        link.symlink_to(real)

        config_helper._write_atomically(str(link), lambda file: file.write("new\n"))

        self.assertTrue(link.is_symlink())
        self.assertEqual(real.read_text(), "new\n")


@unittest.skipUnless(shutil.which("sh"), "needs a posix sh")
class SaveConfigSnapshotTest(TempDirTest):
    """The loop in config-overrides.sh that copies the SAVE_CONFIG block of printer.cfg."""

    @staticmethod
    def snapshot_loop():
        script = CONFIG_OVERRIDES_SH.read_text()
        match = re.search(r"^( *)saves=false\n.*?done < \"\$updated_file\"\n", script, re.S | re.M)
        assert match, "snapshot loop not found in config-overrides.sh"
        return match.group(0)

    def snapshot(self, config):
        overrides = self.tmp / "pellcorp-overrides"
        overrides.mkdir()
        updated = self.tmp / "printer.cfg"
        updated.write_bytes(config.encode())
        script = f"STAGING='{overrides.as_posix()}'\nupdated_file='{updated.as_posix()}'\n" + self.snapshot_loop()
        subprocess.run(["sh", "-c", script], check=True, stdout=subprocess.DEVNULL)
        saved = overrides / "printer.cfg.save_config"
        return saved.read_bytes().decode() if saved.exists() else None

    def test_lf_file_snapshot(self):
        self.assertEqual(self.snapshot(PRINTER_CFG + SAVE_CONFIG_BLOCK), "\n" + SAVE_CONFIG_BLOCK)

    def test_crlf_file_snapshot_is_found_and_has_lf_endings(self):
        crlf = (PRINTER_CFG + SAVE_CONFIG_BLOCK).replace("\n", "\r\n")
        self.assertEqual(self.snapshot(crlf), "\n" + SAVE_CONFIG_BLOCK)

    def test_file_without_save_config_makes_no_snapshot(self):
        self.assertIsNone(self.snapshot(PRINTER_CFG))


@unittest.skipUnless(os.name == "posix" and shutil.which("sh"), "runs the real script under a posix sh")
class OverridesStagingTest(TempDirTest):
    """tools/config-overrides.sh regenerates ~/pellcorp-overrides via a staging directory."""

    def setUp(self):
        super().setUp()
        home = self.home = self.tmp / "home"
        for directory in ("pellcorp/tools", "pellcorp-backups", "printer_data/config", "pellcorp-overrides", "bin"):
            (home / directory).mkdir(parents=True)
        tools = REPOSITORY_ROOT / "tools"
        shutil.copy(tools / "config-overrides.py", home / "pellcorp/tools")
        (home / "pellcorp/tools/config-overrides.py").chmod(0o755)
        shutil.copy(CONFIG_OVERRIDES_SH, home / "pellcorp/tools")
        # the script runs config-overrides.py through its python3 shebang: point that at this interpreter
        python3 = home / "bin/python3"
        python3.write_text(f'#!/bin/sh\nexec "{sys.executable}" "$@"\n')
        python3.chmod(0o755)
        (home / "pellcorp.done").write_text("probe\nprobe\n")
        (home / "pellcorp-backups/printer.cfg").write_text(PRINTER_CFG)
        (home / "printer_data/config/printer.cfg").write_text(PRINTER_CFG.replace("max_velocity: 800", "max_velocity: 500"))
        # what the previous run produced
        (home / "pellcorp-overrides/stale.cfg").write_text("[old]\nkey: 1\n")
        (home / "pellcorp-overrides/config.info").write_text("printer=k1\n")

    def run_script(self):
        env = dict(os.environ, HOME=str(self.home), PATH=f"{self.home / 'bin'}:{os.environ['PATH']}")
        return subprocess.run(
            ["sh", str(self.home / "pellcorp/tools/config-overrides.sh")],
            env=env, capture_output=True, text=True,
        )

    def overrides(self):
        return sorted(p.name for p in (self.home / "pellcorp-overrides").iterdir())

    def leftovers(self):
        return sorted(p.name for p in self.home.iterdir() if "staging" in p.name)

    def test_success_replaces_generated_files_and_keeps_the_others(self):
        (self.home / "printer_data/config/my macros.cfg").write_text("[gcode_macro MINE]\ngcode: M117 hi\n")

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.overrides(), ["config.info", "my macros.cfg", "printer.cfg"])
        self.assertIn("max_velocity: 500", (self.home / "pellcorp-overrides/printer.cfg").read_text())
        self.assertEqual(self.leftovers(), [])

    def test_failure_keeps_the_previous_overrides(self):
        (self.home / "pellcorp-backups/bad.cfg").write_text("[ok]\nkey: 1\n")
        (self.home / "printer_data/config/bad.cfg").write_text("this has no section header\n")

        result = self.run_script()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.overrides(), ["config.info", "stale.cfg"])
        self.assertEqual((self.home / "pellcorp-overrides/stale.cfg").read_text(), "[old]\nkey: 1\n")
        self.assertEqual(self.leftovers(), [])


if __name__ == "__main__":
    unittest.main()
