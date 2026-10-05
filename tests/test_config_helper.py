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


if __name__ == "__main__":
    unittest.main()
