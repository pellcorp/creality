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
    @staticmethod
    def updater(config):
        updater = ConfigUpdater(
            strict=False,
            allow_no_value=True,
            space_around_delimiters=False,
            delimiters=(":", "="),
        )
        updater.read_string(config)
        return updater

    def assert_z_offset_follows_section(self, updater):
        rendered = str(updater)
        self.assertIn("[load_cell_probe]\nz_offset: 0.0\n", rendered)
        self.assertNotIn("[load_cell_probe]\n\nz_offset: 0.0\n", rendered)

    def test_adds_value_to_new_section_at_end_of_file(self):
        updater = self.updater("[printer]\nkinematics: corexy\n")
        config_helper.add_section(updater, "load_cell_probe")

        updated = config_helper.replace_section_value(
            updater, "load_cell_probe", "z_offset", "0.0"
        )

        self.assertTrue(updated)
        self.assert_z_offset_follows_section(updater)
        self.assertTrue(str(updater).endswith("[load_cell_probe]\nz_offset: 0.0\n\n"))

    def test_adds_value_to_new_section_before_save_config(self):
        updater = self.updater(
            "[printer]\n"
            "kinematics: corexy\n"
            "\n"
            "#*# <---------------------- SAVE_CONFIG ---------------------->\n"
            "#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.\n"
        )
        config_helper._normalise_save_config(updater)
        config_helper.add_section(updater, "load_cell_probe")

        updated = config_helper.replace_section_value(
            updater, "load_cell_probe", "z_offset", "0.0"
        )

        self.assertTrue(updated)
        self.assert_z_offset_follows_section(updater)
        self.assertLess(
            str(updater).index("z_offset: 0.0"),
            str(updater).index("SAVE_CONFIG"),
        )

    def test_adds_value_to_existing_section_at_end_of_file(self):
        for trailing_space in ("", "\n"):
            with self.subTest(trailing_space=bool(trailing_space)):
                updater = self.updater(f"[load_cell_probe]\n{trailing_space}")

                updated = config_helper.replace_section_value(
                    updater, "load_cell_probe", "z_offset", "0.0"
                )

                self.assertTrue(updated)
                self.assert_z_offset_follows_section(updater)

    def test_adds_value_to_existing_section_before_save_config(self):
        for section_space in ("", "\n"):
            with self.subTest(section_space=bool(section_space)):
                updater = self.updater(
                    "[load_cell_probe]\n"
                    f"{section_space}"
                    "#*# <---------------------- SAVE_CONFIG ---------------------->\n"
                    "#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.\n"
                )
                config_helper._normalise_save_config(updater)

                updated = config_helper.replace_section_value(
                    updater, "load_cell_probe", "z_offset", "0.0"
                )

                self.assertTrue(updated)
                self.assert_z_offset_follows_section(updater)
                self.assertLess(
                    str(updater).index("z_offset: 0.0"),
                    str(updater).index("SAVE_CONFIG"),
                )

    def test_adds_value_after_existing_options_and_before_trailing_space(self):
        updater = self.updater("[load_cell_probe]\nfoo: bar\n\n")

        updated = config_helper.replace_section_value(
            updater, "load_cell_probe", "z_offset", "0.0"
        )

        self.assertTrue(updated)
        self.assertEqual(
            str(updater),
            "[load_cell_probe]\nfoo: bar\nz_offset: 0.0\n\n",
        )

    def test_replaces_existing_value_without_moving_it(self):
        updater = self.updater(
            "[load_cell_probe]\nz_offset: 1.5\nreference_tare_counts: -100101\n\n"
        )

        updated = config_helper.replace_section_value(
            updater, "load_cell_probe", "z_offset", "0.0"
        )

        self.assertTrue(updated)
        self.assertEqual(
            str(updater),
            "[load_cell_probe]\nz_offset: 0.0\nreference_tare_counts: -100101\n\n",
        )

    def test_handles_trailing_space_with_incorrect_container(self):
        updater = self.updater("[load_cell_probe]\n\n")
        section = updater["load_cell_probe"]
        # Reproduce the ownership mismatch reported by ConfigUpdater in the
        # installer traceback while keeping the block in the section structure.
        section.last_block._container = updater

        updated = config_helper.replace_section_value(
            updater, "load_cell_probe", "z_offset", "0.0"
        )

        self.assertTrue(updated)
        self.assert_z_offset_follows_section(updater)


if __name__ == "__main__":
    unittest.main()
