import importlib.util
import unittest
from pathlib import Path

from configupdater import ConfigUpdater


REPOSITORY_ROOT = Path(__file__).parents[1]
FRAGMENTS = Path(__file__).parent / "fragments"
CONFIG_HELPER_PATH = REPOSITORY_ROOT / "tools" / "config-helper.py"
SPEC = importlib.util.spec_from_file_location("config_helper", CONFIG_HELPER_PATH)
config_helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(config_helper)


class OverrideCfgTest(unittest.TestCase):
    def test_deleted_entry_does_not_create_missing_section(self):
        updater = ConfigUpdater(
            strict=False,
            allow_no_value=True,
            space_around_delimiters=False,
            delimiters=(":", "="),
        )
        with (FRAGMENTS / "existing-section.cfg").open() as config_file:
            updater.read_file(config_file)

        updated = config_helper.override_cfg(
            updater,
            FRAGMENTS / "delete-entry-from-missing-section.cfg",
        )

        self.assertFalse(updated)
        self.assertFalse(updater.has_section("missing"))
        self.assertEqual(updater["existing"]["value"].value, "unchanged")


class ReplaceSectionValueTest(unittest.TestCase):
    def test_adds_value_to_empty_section_before_save_config(self):
        updater = ConfigUpdater(
            strict=False,
            allow_no_value=True,
            space_around_delimiters=False,
            delimiters=(":", "="),
        )
        updater.read_string(
            "[load_cell_probe]\n"
            "#*# <---------------------- SAVE_CONFIG ---------------------->\n"
            "#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.\n"
        )
        config_helper._normalise_save_config(updater)

        updated = config_helper.replace_section_value(
            updater, "load_cell_probe", "z_offset", "0.0"
        )

        self.assertTrue(updated)
        self.assertEqual(updater["load_cell_probe"]["z_offset"].value.strip(), "0.0")
        self.assertLess(
            str(updater).index("z_offset: 0.0"),
            str(updater).index("SAVE_CONFIG"),
        )


if __name__ == "__main__":
    unittest.main()
