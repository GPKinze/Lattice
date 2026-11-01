import json
import posixpath
import re
from pathlib import Path
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.manifest = tomllib.loads((ROOT / "plugin.toml").read_text())

    def test_current_production_manifest_identity_and_entries(self):
        self.assertEqual(self.manifest["id"], "gpkinze/lattice")
        self.assertEqual(self.manifest["plugin_api"], 43)
        self.assertEqual(len(self.manifest["service"]), 1)
        self.assertEqual(self.manifest["service"][0]["entry"], "service.luau")
        self.assertNotIn("panel", self.manifest)
        self.assertEqual(len(self.manifest["widget"]), 1)
        self.assertEqual(self.manifest["widget"][0]["entry"], "bar.luau")
        self.assertFalse(any(key in self.manifest for key in ["layer", "launcher_provider"]))
        production_luau = [
            "service.luau",
            "bar.luau",
            "lib/state.luau",
            "lib/inline_model.luau",
            "lib/inline_ui.luau",
            "lib/interaction.luau",
            "lib/bar_model.luau",
            "lib/presentation.luau",
        ]
        for entry in production_luau:
            source = (ROOT / entry).read_text()
            for module in re.findall(r'require\(\s*["\']([^"\']+)["\']\s*\)', source):
                resolved = posixpath.normpath(
                    posixpath.join(posixpath.dirname(entry), module)
                )
                self.assertFalse(
                    resolved == "prototype" or resolved.startswith("prototype/"),
                    f"{entry} imports retired prototype module {module}",
                )
                self.assertNotIn(
                    resolved,
                    {"preview", "preview.luau"},
                    f"{entry} imports retired preview module {module}",
                )

    def test_outer_gesture_defaults_remain_disabled(self):
        widget = self.manifest["widget"][0]
        self.assertFalse(widget["hover_highlight"])
        self.assertEqual(set(widget["actions"]), {"left", "right", "middle", "back", "forward",
            "scroll_up", "scroll_down", "scroll_left", "scroll_right"})
        self.assertTrue(all(value == "none" for value in widget["actions"].values()))

    def test_settings_are_presentation_only_and_translated(self):
        settings = self.manifest["widget"][0]["setting"]
        self.assertEqual({setting["key"] for setting in settings}, {"capsule_padding", "workspace_spacing",
            "icon_size", "max_icons", "group_icons", "density"})
        translations = json.loads((ROOT / "translations/en.json").read_text())
        for setting in settings:
            self.assertIn(setting["label_key"], translations)
            for option in setting.get("options", []):
                self.assertIn(option["label_key"], translations)

    def test_required_defaults_and_bounded_icon_settings(self):
        settings = {setting["key"]:setting for setting in self.manifest["widget"][0]["setting"]}
        self.assertEqual(settings["max_icons"]["default"], 4)
        self.assertEqual(settings["max_icons"]["max"], 8)
        self.assertEqual(settings["icon_size"]["default"], 16)
        self.assertEqual(settings["density"]["default"], "compact")
        self.assertTrue(settings["group_icons"]["default"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
