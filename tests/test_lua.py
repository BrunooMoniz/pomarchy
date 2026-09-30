"""hypr/pomar.lua fora do Hyprland: com um dublê da API Lua, confere o que o
Pomarchy registra (gestos, atalhos, submapa, regras) em cada situação."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LUA = shutil.which("lua5.4") or shutil.which("lua")


def run_lua(home, scenario="load"):
    out = subprocess.run([LUA, str(REPO / "tests/lua/run.lua"), str(REPO), scenario],
                         env={**os.environ, "HOME": str(home)}, capture_output=True, text=True, timeout=20)
    if out.returncode != 0:
        raise AssertionError(out.stderr)
    return json.loads(out.stdout)


@unittest.skipIf(LUA is None, "lua não instalado")
class PomarLuaTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        (self.home / ".local/state/omarchy/current").mkdir(parents=True)
        (self.home / ".config/pomar").mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def theme(self, name):
        (self.home / ".local/state/omarchy/current/theme.name").write_text(name + "\n")

    def settings(self, data):
        (self.home / ".config/pomar/settings.json").write_text(json.dumps(data))

    def load(self):
        return run_lua(self.home)

    def test_other_theme_registers_nothing(self):
        self.theme("outro-tema")
        result = self.load()
        self.assertFalse(result["active"])
        calls = result["calls"]
        self.assertEqual(calls["gestures"], [])
        self.assertEqual(calls["binds"], [])
        self.assertEqual(calls["layer_rules"], [])

    def test_always_on_works_with_any_theme(self):
        self.theme("tokyo-night")
        self.settings({"alwaysOn": True})
        self.assertTrue(self.load()["active"])

    def test_pomar_theme_registers_mac_gestures(self):
        self.theme("pomarchy")
        calls = self.load()["calls"]
        gestures = {(g["fingers"], g["direction"]): g["action"] for g in calls["gestures"]}
        self.assertEqual(gestures[(3, "horizontal")], "workspace")
        self.assertIsInstance(gestures[(3, "vertical")], dict)      # Mission Control ao vivo
        self.assertIsInstance(gestures[(4, "pinch")], dict)          # Launchpad ao vivo

    def test_finger_counts_come_from_settings(self):
        self.theme("pomarchy-escuro")
        self.settings({"gestures": {"spacesFingers": 4, "missionFingers": 4}})
        pairs = {(g["fingers"], g["direction"]) for g in self.load()["calls"]["gestures"]}
        self.assertIn((4, "horizontal"), pairs)
        self.assertIn((4, "vertical"), pairs)
        self.assertNotIn((3, "horizontal"), pairs)

    def test_invalid_finger_count_falls_back(self):
        self.theme("pomarchy")
        self.settings({"gestures": {"spacesFingers": 9, "missionFingers": "quatro"}})
        pairs = {(g["fingers"], g["direction"]) for g in self.load()["calls"]["gestures"]}
        self.assertIn((3, "horizontal"), pairs)
        self.assertIn((3, "vertical"), pairs)

    def test_gestures_off(self):
        self.theme("pomarchy")
        self.settings({"gestures": {"enabled": False}})
        self.assertEqual(self.load()["calls"]["gestures"], [])

    def test_broken_settings_file_uses_defaults(self):
        self.theme("pomarchy")
        (self.home / ".config/pomar/settings.json").write_text("{ isto não é json ")
        result = self.load()
        self.assertTrue(result["active"])
        self.assertTrue(result["calls"]["gestures"])

    def test_keys_and_switcher_submap(self):
        self.theme("pomarchy")
        calls = self.load()["calls"]
        global_binds = {b["keys"]: b for b in calls["binds"] if b.get("submap") is None}
        for keys in ("ALT + TAB", "ALT + SHIFT + TAB", "SUPER + CTRL + UP", "SUPER + CTRL + DOWN",
                     "SUPER + ALT + SPACE", "SUPER + M", "SUPER + ALT + D"):
            self.assertIn(keys, global_binds, keys)
        # Os que já existem no Omarchy são trocados, não duplicados.
        for keys in ("ALT + TAB", "ALT + SHIFT + TAB", "SUPER + ALT + SPACE"):
            self.assertIn(keys, calls["unbinds"])
        # O melhor do Omarchy fica: SUPER+TAB continua sendo "próxima mesa".
        for keys in ("SUPER + TAB", "SUPER + SHIFT + TAB", "SUPER + SPACE", "SUPER + K"):
            self.assertNotIn(keys, calls["unbinds"])
            self.assertNotIn(keys, global_binds)
        self.assertIn("pomar-switcher", calls["submaps"])
        sub = [b for b in calls["binds"] if b.get("submap") == "pomar-switcher"]
        releases = [b for b in sub if isinstance(b["opts"], dict) and b["opts"].get("release")]
        self.assertTrue(any(b["keys"] == "ALT + Alt_L" for b in releases))
        # Sempre há saída do submapa sem soltar o SUPER.
        self.assertTrue(any(b["keys"] == "ESCAPE" for b in sub))
        self.assertFalse(any(b["keys"] == "catchall" for b in sub))

    def test_keys_can_be_disabled(self):
        self.theme("pomarchy")
        self.settings({"keys": {"cmdTab": False, "missionControl": False, "launchpad": False,
                                "minimize": False, "dockToggle": False}})
        calls = self.load()["calls"]
        self.assertEqual(calls["binds"], [])
        self.assertEqual(calls["unbinds"], [])

    def test_blur_rules_cover_pomar_surfaces(self):
        self.theme("pomarchy")
        rules = self.load()["calls"]["layer_rules"]
        namespaces = " ".join(r["match"]["namespace"] for r in rules)
        for name in ("dock", "menu", "switcher", "settings", "launchpad", "mission"):
            self.assertIn(name, namespaces)

    def test_other_theme_gives_minimized_windows_back(self):
        # Sem o Pomarchy não há Dock para devolver a janela minimizada.
        self.theme("tokyo-night")
        self.assertEqual(run_lua(self.home, "release"),
                         [{"move": "address:0xaaa", "to": "3"}])

    def test_minimize_tells_the_dock_before_hiding_the_window(self):
        self.theme("pomarchy")
        self.assertEqual(run_lua(self.home, "minimize"), [
            {"event": "pomar>>dock:minimizing:0xccc,10,40,800,600"},
            {"move": "address:0xccc", "to": "special:pomar-minimized"},
            {"event": "pomar>>dock:minimized:0xccc"},
        ])

    def gap_configs(self, scenario):
        calls = run_lua(self.home, scenario)["calls"]
        return [c["general"] for c in calls["configs"]
                if isinstance(c.get("general"), dict) and isinstance(c["general"].get("gaps_in"), dict)]

    def test_title_gap_grows_only_the_top_side(self):
        # A config da pessoa (6 e 12) carrega depois do Pomarchy: só o lado de
        # cima cresce até caber os botões das janelas (28 px).
        self.theme("pomarchy")
        self.assertEqual(self.gap_configs("usergaps"), [{
            "gaps_in": {"top": 22, "right": 6, "bottom": 6, "left": 6},
            "gaps_out": {"top": 28, "right": 12, "bottom": 12, "left": 12},
        }])

    def test_title_gap_is_left_alone_when_there_is_room(self):
        self.theme("pomarchy")
        self.assertEqual(self.gap_configs("roomy"), [])

    def test_title_gap_off_without_window_controls(self):
        self.theme("pomarchy")
        self.settings({"windowControls": {"enabled": False}})
        self.assertEqual(self.gap_configs("usergaps"), [])

    def test_live_gesture_events(self):
        self.theme("pomarchy")
        self.assertEqual(run_lua(self.home, "gesture:mission"),
                         ["pomar>>mission:begin", "pomar>>mission:delta:-12.35",
                          "pomar>>mission:end:0", "pomar>>mission:end:1"])
        self.assertEqual(run_lua(self.home, "gesture:launchpad"),
                         ["pomar>>launchpad:begin", "pomar>>launchpad:scale:0.8123",
                          "pomar>>launchpad:end:0", "pomar>>launchpad:end:1"])


@unittest.skipIf(LUA is None, "lua não instalado")
class JsonLuaTest(unittest.TestCase):
    def decode(self, text):
        return run_lua(Path(tempfile.gettempdir()), "json:" + text)

    def test_objects_arrays_and_scalars(self):
        result = self.decode('{"a": [1, 2.5, -3e2], "b": {"c": true, "d": false}, "e": "x\\"y", "f": null}')
        self.assertTrue(result["ok"])
        self.assertEqual(result["value"]["a"], [1, 2.5, -300.0])
        self.assertEqual(result["value"]["b"], {"c": True, "d": False})
        self.assertEqual(result["value"]["e"], 'x"y')
        self.assertNotIn("f", result["value"])

    def test_unicode_escape(self):
        self.assertEqual(self.decode('{"n": "Ma\\u00e7\\u00e3"}')["value"]["n"], "Maçã")

    def test_garbage_is_rejected(self):
        for text in ("{", '{"a": }', "[1, 2", '{"a": 1} lixo', "tru"):
            self.assertFalse(self.decode(text)["ok"], text)


if __name__ == "__main__":
    unittest.main()
