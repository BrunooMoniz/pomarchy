"""Contratos que atravessam linguagens: os padrões de ajustes do QML
(shared/Defaults.js) e do Hyprland (hypr/pomar.lua) são os mesmos, e o
arranjo do Mission Control não sobrepõe janelas nem sai da área."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
NODE = shutil.which("node")
LUA = shutil.which("lua5.4") or shutil.which("lua")


def js_library(path):
    return Path(path).read_text().replace(".pragma library", "", 1)


def run_node(script):
    out = subprocess.run([NODE, "-e", script], capture_output=True, text=True, timeout=20)
    if out.returncode != 0:
        raise AssertionError(out.stderr)
    return json.loads(out.stdout)


def normalize(value):
    """Lua não distingue lista vazia de objeto vazio."""
    if isinstance(value, dict):
        return {k: normalize(v) for k, v in value.items()} if value else []
    if isinstance(value, list):
        return [normalize(v) for v in value]
    return value


@unittest.skipIf(NODE is None or LUA is None, "node e lua são necessários")
class DefaultsContractTest(unittest.TestCase):
    def test_qml_and_lua_defaults_match(self):
        js = run_node(js_library(REPO / "shared/Defaults.js") + "\nconsole.log(JSON.stringify(DEFAULTS))")
        with tempfile.TemporaryDirectory() as home:
            out = subprocess.run([LUA, str(REPO / "tests/lua/run.lua"), str(REPO), "defaults"],
                                 env={**os.environ, "HOME": home}, capture_output=True, text=True, timeout=20)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(normalize(js), normalize(json.loads(out.stdout)))

    def test_merge_ignores_wrong_types(self):
        result = run_node(js_library(REPO / "shared/Defaults.js") + """
console.log(JSON.stringify(merged({ dock: { iconSize: "grande", autohide: true, favorites: "x" }, extra: 1 })))""")
        self.assertEqual(result["dock"]["iconSize"], 54)
        self.assertTrue(result["dock"]["autohide"])
        self.assertEqual(result["dock"]["favorites"], [])
        self.assertEqual(result["extra"], 1)


@unittest.skipIf(NODE is None, "node é necessário")
class ExposeLayoutTest(unittest.TestCase):
    def layout(self, windows, area, gap=36):
        lib = js_library(REPO / "pomar.mission/ExposeLayout.js")
        return run_node(lib + f"\nconsole.log(JSON.stringify(layout({json.dumps(windows)}, {json.dumps(area)}, {{ gap: {gap}, maxScale: 0.88 }})))")

    def check(self, windows, area, gap=36):
        rects = self.layout(windows, area, gap)
        self.assertEqual(len(rects), len(windows))
        for i, r in enumerate(rects):
            self.assertGreaterEqual(r["x"], area["x"] - 0.5)
            self.assertGreaterEqual(r["y"], area["y"] - 0.5)
            self.assertLessEqual(r["x"] + r["w"], area["x"] + area["w"] + 0.5)
            self.assertLessEqual(r["y"] + r["h"], area["y"] + area["h"] + 0.5)
            ratio_in = windows[i]["w"] / windows[i]["h"]
            self.assertAlmostEqual(r["w"] / r["h"], ratio_in, places=3)
            self.assertLessEqual(r["w"], windows[i]["w"] * 0.88 + 0.5)
            for j, q in enumerate(rects):
                if j <= i:
                    continue
                overlap_x = min(r["x"] + r["w"], q["x"] + q["w"]) - max(r["x"], q["x"])
                overlap_y = min(r["y"] + r["h"], q["y"] + q["h"]) - max(r["y"], q["y"])
                self.assertFalse(overlap_x > 0.5 and overlap_y > 0.5, f"janelas {i} e {j} se sobrepõem")
        return rects

    def test_empty(self):
        self.assertEqual(self.layout([], {"x": 0, "y": 0, "w": 100, "h": 100}), [])

    def test_single_window_is_centered_and_smaller(self):
        area = {"x": 56, "y": 200, "w": 1808, "h": 900}
        r = self.check([{"x": 10, "y": 40, "w": 1900, "h": 1150}], area)[0]
        self.assertAlmostEqual(r["x"] + r["w"] / 2, area["x"] + area["w"] / 2, delta=1)
        self.assertAlmostEqual(r["y"] + r["h"] / 2, area["y"] + area["h"] / 2, delta=1)

    def test_tiled_desktop(self):
        windows = [{"x": 10, "y": 40, "w": 940, "h": 1150}, {"x": 965, "y": 40, "w": 945, "h": 570},
                   {"x": 965, "y": 620, "w": 470, "h": 570}, {"x": 1440, "y": 620, "w": 470, "h": 570}]
        rects = self.check(windows, {"x": 56, "y": 200, "w": 1808, "h": 900})
        # Quem estava à esquerda continua à esquerda da janela que estava à direita.
        self.assertLess(rects[0]["x"], rects[3]["x"])

    def test_many_windows(self):
        windows = [{"x": (i % 5) * 380, "y": (i // 5) * 300, "w": 800 + (i * 37) % 400, "h": 500 + (i * 53) % 300}
                   for i in range(14)]
        self.check(windows, {"x": 40, "y": 160, "w": 1840, "h": 980})

    def test_neighbor_navigation(self):
        lib = js_library(REPO / "pomar.mission/ExposeLayout.js")
        rects = [{"x": 0, "y": 0, "w": 100, "h": 100}, {"x": 200, "y": 0, "w": 100, "h": 100},
                 {"x": 0, "y": 200, "w": 100, "h": 100}]
        got = run_node(lib + f"\nvar r={json.dumps(rects)};console.log(JSON.stringify([neighbor(r,0,'right'),neighbor(r,0,'down'),neighbor(r,1,'left'),neighbor(r,2,'up'),neighbor(r,0,'left')]))")
        self.assertEqual(got, [1, 2, 0, 0, 0])


if __name__ == "__main__":
    unittest.main()
