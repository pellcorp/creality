import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("v23_migration", ROOT / "tools/migrate-v23-config.py")
migration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(migration)


class V23MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / "config"
        self.overrides = self.root / "overrides"
        self.backup = self.root / "backups"
        self.config.mkdir()
        self.overrides.mkdir()

    def migrate(self):
        return migration.migrate([self.config, self.overrides], self.backup)

    def test_preserves_values_saved_offsets_macros_and_unrelated_bytes(self):
        config = "[prtouch_v3]\nserial: /dev/ttyS9\nmax_travel: 2.7\n[gcode_macro PRTOUCH_PROBE_ACCURACY]\nrename_existing: _PRTOUCH_PROBE_ACCURACY\ngcode:\n  _PRTOUCH_PROBE_ACCURACY {rawparams}\n"
        (self.config / "prtouch_v3.cfg").write_text(config)
        main = "[include prtouch_v3.cfg]\n[printer]\nmax_velocity: 300\n#*# [prtouch_v3]\n#*# z_offset = -0.037\n#*# [heater_bed]\n#*# pid_kp = 49.148\n"
        (self.config / "printer.cfg").write_text(main)
        (self.overrides / "printer.cfg.save_config").write_text("#*# [prtouch_v3]\n#*# z_offset = -0.037\n")
        (self.overrides / "touch_gate.cfg").write_text("{% set lc = printer['prtouch_v3'] %}\nvariable_prtouch_accept_min: -0.10\n")
        untouched = b"[gcode_macro CUSTOM]\ngcode:\n  M118 untouched\n"
        (self.config / "custom.cfg").write_bytes(untouched)
        self.assertEqual(self.migrate(), 4)
        self.assertFalse((self.config / "prtouch_v3.cfg").exists())
        self.assertIn("max_travel: 2.7", (self.config / "loadcells_v23.cfg").read_text())
        self.assertIn("_BED_LOAD_CELL_PROBE_ACCURACY", (self.config / "loadcells_v23.cfg").read_text())
        actual = (self.config / "printer.cfg").read_text()
        self.assertEqual(actual, main.replace("prtouch_v3.cfg", "loadcells_v23.cfg").replace("prtouch_v3", "load_cell_v23"))
        self.assertIn("z_offset = -0.037", (self.overrides / "printer.cfg.save_config").read_text())
        self.assertIn("printer['load_cell_v23']", (self.overrides / "touch_gate.cfg").read_text())
        self.assertEqual((self.config / "custom.cfg").read_bytes(), untouched)
        backup = self.backup / str((self.config / "prtouch_v3.cfg").resolve()).lstrip("/")
        self.assertEqual(backup.read_text(), config)
        self.assertEqual(self.migrate(), 0)

    def test_conflicting_files_abort_before_any_write(self):
        original = "[include prtouch_v3.cfg]\n"
        (self.config / "printer.cfg").write_text(original)
        (self.overrides / "prtouch_v3.cfg").write_text("[prtouch_v3]\nz_offset: 0.1\n")
        (self.overrides / "loadcells_v23.cfg").write_text("[load_cell_v23]\nz_offset: 0.2\n")
        with self.assertRaisesRegex(ValueError, "different old and new"):
            self.migrate()
        self.assertEqual((self.config / "printer.cfg").read_text(), original)
        self.assertFalse(self.backup.exists())

    def test_mixed_saved_sections_are_not_silently_combined(self):
        for text in ("#*# [prtouch_v3]\n#*# z_offset = 0.1\n#*# [load_cell_v23]\n#*# z_offset = 0.2\n",
                     "[prtouch_v3]\n[load_cell_v23]\n",
                     "[include prtouch_v3.cfg]\n[include loadcells_v23.cfg]\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                migration.renamed(text)

    def test_firmware_protocol_identifiers_remain_unchanged(self):
        protocol = "config_prtouch_pres start_prtouch_pres stop_prtouch_pres ack_prtouch resault_prtouch_pres prtouch_v3_wrapper"
        self.assertEqual(migration.renamed(protocol), protocol)

    def test_history_and_backups_are_not_rewritten(self):
        for name in ("journal.jsonl", "prtouch.log", "printer.cfg.bak"):
            (self.config / name).write_text("PRTOUCH_PROBE [prtouch_v3]")
        self.assertEqual(self.migrate(), 0)


if __name__ == "__main__":
    unittest.main()
