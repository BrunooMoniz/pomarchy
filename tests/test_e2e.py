"""De ponta a ponta no Hyprland aninhado: o shell real do Omarchy carrega os
plugins do Pomarchy sem erro de QML e cada peça responde aos eventos de verdade.

Lento (cada sessão sobe um compositor e um shell). Pule com POMAR_SKIP_E2E=1.
Fotos em out/e2e/ para olhar depois.
"""
import json
import os
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nested  # noqa: E402
from nested import NestedSession  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
SHOTS = REPO / "out" / "e2e"
SKIP = os.environ.get("POMAR_SKIP_E2E") == "1"


def pomar_problems(log):
    bad = []
    for line in log.splitlines():
        low = line.lower()
        if "pomar" not in low:
            continue
        if any(word in low for word in ("warn", "error", "typeerror", "referenceerror", "unavailable",
                                          "is not a type", "failed")):
            bad.append(line)
    return bad


def ipc_json(session, target, method, *args):
    text = session.shell_ipc(target, method, *args)
    try:
        return json.loads(text)
    except ValueError:
        raise AssertionError(f"IPC {target}.{method} respondeu {text!r}")


@unittest.skipIf(SKIP, "POMAR_SKIP_E2E=1")
class PomarActiveTest(unittest.TestCase):
    """Tema Pomarchy ativo, três janelas abertas."""

    @classmethod
    def setUpClass(cls):
        cls.session = NestedSession(theme="pomarchy", settings={"language": "pt", "welcome": {"seen": True}}).start()
        cls.session.start_shell()
        time.sleep(3.5)
        for app in ("foot", "nautilus", "foot"):
            cls.session.spawn([app])
            time.sleep(0.9)
        time.sleep(1.0)

    @classmethod
    def tearDownClass(cls):
        cls.session.close()

    def wait_state(self, target, predicate, timeout=5.0):
        last = None
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            last = ipc_json(self.session, target, "state")
            if predicate(last):
                return last
            time.sleep(0.1)
        self.fail(f"{target}: estado não chegou; último = {last}")

    def test_00_shell_loads_pomar_cleanly(self):
        listing = self.session.shell_ipc("shell", "listPlugins")
        for plugin in ("pomar.core", "pomar.menubar", "pomar.dock", "pomar.launchpad",
                       "pomar.mission", "pomar.switcher", "pomar.settings"):
            self.assertIn(plugin, listing)
        self.assertEqual(pomar_problems(self.session.shell_log()), [])
        lua = [l for l in self.session.hyprland_log().splitlines() if "Lua error" in l]
        self.assertEqual(lua, [])

    def test_10_menubar_shows_active_app(self):
        state = ipc_json(self.session, "pomar-menubar-test", "state")
        self.assertTrue(state["shown"])
        self.assertTrue(state["macMode"])
        self.assertEqual(state["appId"], "foot")

    def test_20_mission_control_opens_and_closes(self):
        self.session.event("mission:open")
        state = self.wait_state("pomar-mission-test", lambda s: s["opened"] and s["progress"] >= 0.999)
        self.assertEqual(state["mode"], "mission")
        self.session.screenshot(SHOTS / "mission.png")
        self.session.event("mission:close")
        self.wait_state("pomar-mission-test", lambda s: not s["opened"])

    def test_21_live_gesture_follows_fingers(self):
        s = self.session
        s.event("mission:begin")
        for _ in range(10):
            s.event("mission:delta:-13")           # 130 px para cima de 260 = metade
        state = self.wait_state("pomar-mission-test", lambda st: st["opened"])
        self.assertAlmostEqual(state["progress"], 0.5, delta=0.02)
        s.screenshot(SHOTS / "mission-half.png")
        s.event("mission:end:0")                   # soltou devagar depois da metade: abre
        self.wait_state("pomar-mission-test", lambda st: st["progress"] >= 0.999)
        s.event("mission:begin")
        s.event("mission:delta:8")                 # para baixo, pouco: volta a abrir
        s.event("mission:end:0")
        self.wait_state("pomar-mission-test", lambda st: st["opened"] and st["progress"] >= 0.999)
        s.event("mission:begin")
        for _ in range(6):
            s.event("mission:delta:30")            # para baixo, rápido: fecha
        s.event("mission:end:0")
        self.wait_state("pomar-mission-test", lambda st: not st["opened"])

    def test_22_gesture_down_opens_app_expose(self):
        s = self.session
        s.event("mission:begin")
        for _ in range(12):
            s.event("mission:delta:25")
        s.event("mission:end:0")
        state = self.wait_state("pomar-mission-test", lambda st: st["opened"] and st["progress"] >= 0.999)
        self.assertEqual(state["mode"], "expose")
        self.assertEqual(state["exposeApp"], "foot")
        s.screenshot(SHOTS / "expose.png")
        s.event("mission:close")
        self.wait_state("pomar-mission-test", lambda st: not st["opened"])

    def test_23_activate_focuses_window(self):
        s = self.session
        active = json.loads(s.control("-j", "activewindow"))
        others = [c for c in s.clients() if c["address"] != active["address"]
                  and c["workspace"]["id"] == active["workspace"]["id"]]
        self.assertTrue(others)
        s.event("mission:open")
        self.wait_state("pomar-mission-test", lambda st: st["progress"] >= 0.999)
        s.shell_ipc("pomar-mission-test", "activate", others[0]["address"])
        self.wait_state("pomar-mission-test", lambda st: not st["opened"])
        self.assertEqual(json.loads(s.control("-j", "activewindow"))["address"], others[0]["address"])

    @unittest.skipUnless(nested.vpointer_available(), "precisa de gcc, wayland-scanner e wayland-client")
    def test_24_close_button_closes_the_window_with_a_real_click(self):
        s = self.session
        before = {c["address"] for c in s.clients()}
        s.spawn(["foot"])
        deadline = time.monotonic() + 5
        extra = None
        while extra is None and time.monotonic() < deadline:
            extra = next((c["address"] for c in s.clients() if c["address"] not in before), None)
            time.sleep(0.1)
        self.assertIsNotNone(extra, "o terminal extra não abriu")
        time.sleep(0.8)
        s.event("mission:open")
        self.wait_state("pomar-mission-test", lambda st: st["opened"] and st["progress"] >= 0.999)
        time.sleep(0.4)
        index = info = None
        for i in range(12):
            candidate = ipc_json(s, "pomar-mission-test", "closeButton", str(i))
            if candidate and candidate["address"] == extra:
                index, info = i, candidate
                break
        self.assertIsNotNone(info, "a miniatura do terminal extra não apareceu")
        layer = next(layer for monitor in json.loads(s.control("-j", "layers")).values()
                     for level in monitor["levels"].values() for layer in level
                     if layer["namespace"] == "pomar-mission")

        def on_screen(point):
            return point["x"] + layer["x"], point["y"] + layer["y"]

        # Como uma pessoa: passa pela miniatura e vai até o X no canto.
        x, y = on_screen(info)
        s.click(x + 80, y + 60, "move")
        time.sleep(0.35)
        info = ipc_json(s, "pomar-mission-test", "closeButton", str(index))
        self.assertTrue(info["hovered"], f"o cursor não chegou na miniatura: {info}")
        s.click(*on_screen(info), "move")
        time.sleep(0.5)
        info = ipc_json(s, "pomar-mission-test", "closeButton", str(index))
        s.screenshot(SHOTS / "mission-close-hover.png")
        self.assertTrue(info["shown"], f"o X some quando o cursor chega nele: {info}")
        s.click(*on_screen(info))
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline and extra in {c["address"] for c in s.clients()}:
            time.sleep(0.1)
        self.assertNotIn(extra, {c["address"] for c in s.clients()}, "o clique no X não fechou a janela")
        s.event("mission:close")
        self.wait_state("pomar-mission-test", lambda st: not st["opened"])

    def test_30_switcher_moves_between_apps(self):
        s = self.session
        before = json.loads(s.control("-j", "activewindow"))
        s.event("switcher:next")
        state = self.wait_state("pomar-switcher-test", lambda st: st["shown"])
        self.assertGreaterEqual(len(state["apps"]), 2)
        s.screenshot(SHOTS / "switcher.png")
        s.event("switcher:commit")
        self.wait_state("pomar-switcher-test", lambda st: not st["opened"])
        time.sleep(0.4)
        after = json.loads(s.control("-j", "activewindow"))
        self.assertNotEqual(before["class"], after["class"])
        self.assertEqual(s.control("submap").strip(), "default")

    def test_31_switcher_cancel_keeps_focus(self):
        s = self.session
        before = json.loads(s.control("-j", "activewindow"))["address"]
        s.event("switcher:next")
        self.wait_state("pomar-switcher-test", lambda st: st["opened"])
        s.event("switcher:cancel")
        self.wait_state("pomar-switcher-test", lambda st: not st["opened"])
        self.assertEqual(json.loads(s.control("-j", "activewindow"))["address"], before)

    def test_40_minimize_key_action_hides_window(self):
        s = self.session
        active = json.loads(s.control("-j", "activewindow"))["address"]
        s.dispatch('hl.dsp.window.move({ workspace = "special:pomar-minimized", follow = false })')
        time.sleep(0.4)
        moved = {c["address"]: c["workspace"]["name"] for c in s.clients()}
        self.assertEqual(moved[active], "special:pomar-minimized")
        s.dispatch(f'hl.dsp.window.move({{ window = "address:{active}", workspace = "2", follow = true }})')

    def test_99_no_qml_problems_after_everything(self):
        self.assertEqual(pomar_problems(self.session.shell_log()), [])


@unittest.skipIf(SKIP, "POMAR_SKIP_E2E=1")
@unittest.skipUnless(nested.vpointer_available(), "precisa de gcc, wayland-scanner e wayland-client")
class WindowControlsTest(unittest.TestCase):
    """Botões de fechar, minimizar e zoom no alto das janelas, com cliques de verdade."""

    @classmethod
    def setUpClass(cls):
        cls.session = NestedSession(theme="pomarchy", settings={"language": "pt", "welcome": {"seen": True}}).start()
        cls.session.start_shell()
        time.sleep(3.5)
        for _ in range(3):
            cls.session.spawn(["foot"])
            time.sleep(0.9)
        time.sleep(1.2)

    @classmethod
    def tearDownClass(cls):
        cls.session.close()

    def controls(self, timeout=6.0):
        """Os botões à vista e parados: duas leituras seguidas iguais, como quem
        espera a janela terminar de se mexer antes de clicar."""
        deadline = time.monotonic() + timeout
        info = previous = None
        while time.monotonic() < deadline:
            info = ipc_json(self.session, "pomar-dock-test", "windowControls")
            if info["settled"] and info == previous:
                return info
            previous = info if info["settled"] else None
            time.sleep(0.3)
        self.fail(f"os botões não assentaram: {info}")

    def clients(self):
        return {c["address"]: c for c in self.session.clients()}

    def wait_for(self, predicate, what, timeout=4.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.1)
        self.fail(what)

    def test_10_buttons_sit_in_the_gap_above_each_window(self):
        info = self.controls()
        self.assertTrue(info["enabled"])
        clients = self.clients()
        self.assertEqual(len(info["windows"]), 3)
        for w in info["windows"]:
            c = clients[w["address"]]
            x, y = w["close"]
            self.assertTrue(c["at"][0] < x < c["at"][0] + 40, (w, c["at"]))
            self.assertTrue(c["at"][1] - 29 < y < c["at"][1], f"fora do espaço de cima da janela: {w} {c['at']}")
        self.session.screenshot(SHOTS / "window-controls.png")

    def test_20_red_closes_the_window(self):
        target = self.controls()["windows"][-1]
        self.session.click(*target["close"])
        self.wait_for(lambda: target["address"] not in self.clients(), "o vermelho não fechou a janela")

    def test_30_yellow_minimizes_to_the_dock(self):
        target = self.controls()["windows"][0]
        self.session.click(*target["minimize"])
        self.wait_for(lambda: self.clients()[target["address"]]["workspace"]["name"] == "special:pomar-minimized",
                      "o amarelo não mandou a janela para o Dock")

    def test_40_green_zooms_and_green_again_goes_back(self):
        s = self.session
        s.spawn(["foot"])
        time.sleep(1.2)
        info = self.controls()
        self.assertEqual(len(info["windows"]), 2)
        target = info["windows"][0]
        s.click(*target["zoom"])
        self.wait_for(lambda: self.clients()[target["address"]].get("fullscreen") == 1, "o verde não ampliou")
        info = self.controls()
        self.assertEqual([w["address"] for w in info["windows"]], [target["address"]],
                         "com a janela ampliada, só ela mostra os botões")
        s.click(*info["windows"][0]["zoom"])
        self.wait_for(lambda: self.clients()[target["address"]].get("fullscreen") == 0, "o verde não desfez")
        self.assertEqual(len(self.controls()["windows"]), 2)

    def test_50_a_tab_group_gets_one_set_of_buttons_above_the_tabs(self):
        s = self.session
        before = set(self.clients())

        def new_windows():
            return [c for a, c in self.clients().items() if a not in before]

        def active_address():
            return json.loads(s.control("-j", "activewindow")).get("address")

        s.spawn(["foot"])
        self.wait_for(lambda: len(new_windows()) == 1 and active_address() == new_windows()[0]["address"],
                      "o primeiro terminal não abriu com foco")
        s.dispatch("hl.dsp.group.toggle()")
        self.wait_for(lambda: len(new_windows()[0]["grouped"]) == 1, "o grupo não foi criado")
        s.spawn(["foot"])  # abre dentro do grupo, como a segunda aba
        self.wait_for(lambda: len(new_windows()) == 2 and all(len(c["grouped"]) == 2 for c in new_windows()),
                      "o segundo terminal não entrou no grupo")
        members = new_windows()
        options = {name: json.loads(s.control("-j", "getoption", f"group:groupbar:{name}"))
                   for name in ("height", "indicator_height", "indicator_gap", "gaps_out")}
        reserve = sum(option["int"] for option in options.values())
        info = self.controls()
        ours = [w for w in info["windows"] if w["address"] in {c["address"] for c in members}]
        self.assertEqual(len(ours), 1, "um grupo de abas, um conjunto de botões")
        tab = self.clients()[ours[0]["address"]]
        self.assertEqual(ours[0]["close"][1], tab["at"][1] - reserve - 1 - 14, "acima da barra de abas")
        s.screenshot(SHOTS / "window-controls-group.png")
        # Um clique vindo dos botões na posição do grupo não fecha a aba escondida.
        hidden = next(c for c in members if c["address"] != ours[0]["address"])
        gx, gy = ours[0]["origin"]
        s.shell_ipc("pomar-dock-test", "windowAct", "close", hidden["address"], str(gx), str(gy))
        time.sleep(1.0)
        self.assertIn(hidden["address"], self.clients(), "a aba escondida não fecha")
        s.click(*ours[0]["close"])
        self.wait_for(lambda: ours[0]["address"] not in self.clients(), "o vermelho não fechou a aba")
        # Sobrou uma aba só: ainda é grupo, com a barra de abas, e os botões ficam acima dela.
        remaining = next(c for c in members if c["address"] != ours[0]["address"])
        info = self.controls()
        alone = next(w for w in info["windows"] if w["address"] == remaining["address"])
        tab = self.clients()[remaining["address"]]
        self.assertEqual(len(tab["grouped"]), 1)
        self.assertEqual(alone["close"][1], tab["at"][1] - reserve - 1 - 14, "uma aba só também tem a barra")

    def test_60_buttons_under_a_floating_window_let_the_click_through(self):
        s = self.session
        target = min(self.controls()["windows"], key=lambda w: (w["close"][1], w["close"][0]))
        before = set(self.clients())
        s.spawn(["foot"])
        self.wait_for(lambda: len(set(self.clients()) - before) == 1, "o terminal flutuante não abriu")
        floating = (set(self.clients()) - before).pop()
        s.dispatch(f'hl.dsp.window.float({{ action = "enable", window = "address:{floating}" }})')
        s.dispatch(f'hl.dsp.window.resize({{ x = 520, y = 320, window = "address:{floating}" }})')
        x, y = target["close"]
        s.dispatch(f'hl.dsp.window.move({{ x = {x - 60}, y = {y - 20}, window = "address:{floating}" }})')
        time.sleep(1.4)
        # O foco volta para a janela de baixo: só um clique que chega na
        # flutuante (e não nos botões escondidos) passa o foco para ela.
        s.dispatch(f'hl.dsp.focus({{ window = "address:{target["address"]}" }})')
        time.sleep(0.4)
        s.click(x, y)
        time.sleep(0.8)
        self.assertIn(target["address"], self.clients(), "o botão escondido não fechou a janela de baixo")
        self.assertEqual(json.loads(s.control("-j", "activewindow"))["address"], floating,
                         "o clique chegou na janela flutuante")
        s.dispatch(f'hl.dsp.window.close({{ window = "address:{floating}" }})')
        self.wait_for(lambda: floating not in self.clients(), "o terminal flutuante não fechou")

    def test_70_a_button_click_from_the_old_place_does_nothing(self):
        # Trocar janelas de lugar pelo teclado não gera evento: o clique confere
        # a posição numa consulta nova antes de fechar.
        s = self.session
        target = self.controls()["windows"][0]
        gx, gy = target["origin"]
        s.shell_ipc("pomar-dock-test", "windowAct", "close", target["address"], str(gx + 300), str(gy))
        time.sleep(1.0)
        self.assertIn(target["address"], self.clients(), "clique de um lugar antigo não fecha nada")
        s.shell_ipc("pomar-dock-test", "windowAct", "close", target["address"], str(gx), str(gy))
        self.wait_for(lambda: target["address"] not in self.clients(), "no lugar certo, o vermelho fecha")

    def test_99_no_qml_problems(self):
        self.assertEqual(pomar_problems(self.session.shell_log()), [])


@unittest.skipIf(SKIP, "POMAR_SKIP_E2E=1")
class PomarInactiveTest(unittest.TestCase):
    """Outro tema do Omarchy: o Pomarchy não aparece nem responde."""

    def test_other_theme_is_untouched(self):
        with NestedSession(theme="pomarchy", settings={}) as session:
            state = session.home / ".local/state/omarchy/current/theme.name"
            state.write_text("tokyo-night\n")
            session.start_shell()
            time.sleep(3.5)
            session.spawn(["foot"])
            time.sleep(1.2)
            # A barra nunca fica sem menu: vira o logo do Omarchy.
            menubar = ipc_json(session, "pomar-menubar-test", "state")
            self.assertTrue(menubar["shown"])
            self.assertFalse(menubar["macMode"])
            session.event("mission:open")
            session.event("switcher:next")
            time.sleep(0.8)
            self.assertFalse(ipc_json(session, "pomar-mission-test", "state")["opened"])
            self.assertFalse(ipc_json(session, "pomar-switcher-test", "state")["opened"])
            self.assertEqual(pomar_problems(session.shell_log()), [])


if __name__ == "__main__":
    unittest.main()
