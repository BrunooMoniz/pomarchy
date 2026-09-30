"""O comando pomar: barra no estilo Mac (ida e volta), o bloco do hyprland.lua,
os atalhos para abrir as telas do Pomarchy e o doctor. Mesmo isolamento do
test_install: HOME e XDG temporários, dublês no PATH, HOME real conferido."""
import json
import os
import shutil
import subprocess
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_install import BLOCK, REQUIRE_LINE, SHELL, HYPRLAND_LUA, MAC_CLOCK, IsolatedTestCase, dump_shell  # noqa: E402

# Um shell.json de quem já mexeu na barra: widgets de terceiros no centro, na
# direita e na esquerda, entrada escrita só como texto, opções por widget,
# chaves que o Pomarchy não conhece e o mesmo widget no centro e na direita.
CUSTOM_SHELL = {
    "version": 1,
    "idle": {"screensaver": 90, "lock": 600},
    "bar": {
        "position": "top",
        "transparent": True,
        "centerAnchor": "omarchy.clock",
        "layout": {
            "left": ["omarchy.menu", {"id": "omarchy.spacer", "size": 12}, {"id": "omarchy.workspaces"},
                     {"id": "meu.cpu", "interval": 2}],
            "center": [{"id": "acme.weather", "units": "metric"},
                       {"id": "omarchy.clock", "format": "HH:mm", "formatAlt": "dddd"},
                       {"id": "omarchy.media"}],
            "right": ["omarchy.tray", {"id": "omarchy.media"}, {"id": "acme.vpn", "label": "Casa"},
                      {"id": "omarchy.power"}],
        },
    },
    "plugins": [{"id": "acme.notes"}],
    "extra": {"mantido": ["sim", 1, None]},
}


class BarTest(IsolatedTestCase):
    def test_bar_auto_follows_the_theme(self):
        box = self.sandbox(shell_json=CUSTOM_SHELL)
        path = box.path(".config/omarchy/shell.json")
        original = path.read_bytes()
        theme = box.path(".local/state/omarchy/current/theme.name")
        backup = box.path(".local/state/pomar/bar-backup.json")

        theme.write_text("pomarchy\n")
        self.assertOk(box.pomar("bar", "auto"))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"][0], {"id": "pomar.menubar"})
        self.assertTrue(backup.is_file())

        theme.write_text("tokyo-night\n")
        self.assertOk(box.pomar("bar", "auto"))
        self.assertEqual(path.read_bytes(), original, "fora do Pomarchy, a barra do Omarchy exatamente como era")
        self.assertFalse(backup.exists())
        self.assertOk(box.pomar("bar", "auto"))
        self.assertEqual(path.read_bytes(), original)

        # "Manter o Pomarchy em qualquer tema": barra do Mac com o tema da pessoa.
        box.path(".config/pomar").mkdir(parents=True, exist_ok=True)
        box.path(".config/pomar/settings.json").write_text(json.dumps({"alwaysOn": True}))
        self.assertOk(box.pomar("bar", "auto"))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"][0], {"id": "pomar.menubar"})

    def test_mac_bar_keeps_every_widget_and_goes_back_byte_for_byte(self):
        box = self.sandbox(shell_json=CUSTOM_SHELL)
        path = box.path(".config/omarchy/shell.json")
        original = path.read_bytes()

        result = box.pomar("bar", "mac")
        self.assertOk(result)
        self.assertIn("Barra no estilo Mac", result.stdout)
        shell = box.shell_json()
        layout = shell["bar"]["layout"]
        self.assertEqual(layout["left"], [{"id": "pomar.menubar"}, {"id": "omarchy.workspaces"}])
        self.assertEqual(layout["center"], [])
        self.assertEqual(layout["right"], [
            {"id": "omarchy.spacer", "size": 12},
            {"id": "meu.cpu", "interval": 2},
            {"id": "acme.weather", "units": "metric"},
            {"id": "omarchy.media"},
            "omarchy.tray",
            {"id": "acme.vpn", "label": "Casa"},
            {"id": "omarchy.power"},
            {"id": "omarchy.clock", "format": MAC_CLOCK, "formatAlt": "dddd"},
        ], "widgets de terceiros e suas opções ficam; o relógio vai por último; nada repete")
        for key in ("version", "idle", "plugins", "extra"):
            self.assertEqual(shell[key], CUSTOM_SHELL[key], key)
        for key in ("position", "transparent", "centerAnchor"):
            self.assertEqual(shell["bar"][key], CUSTOM_SHELL["bar"][key], key)
        saved = json.loads(box.path(".local/state/pomar/bar-backup.json").read_text())
        self.assertEqual(saved["bar"], CUSTOM_SHELL["bar"])

        mac = path.read_bytes()
        self.assertOk(box.pomar("bar", "mac"))
        self.assertEqual(path.read_bytes(), mac, "rodar de novo não muda nada")
        saved_again = json.loads(box.path(".local/state/pomar/bar-backup.json").read_text())
        self.assertEqual(saved_again["bar"], CUSTOM_SHELL["bar"], "a cópia continua sendo a barra de antes")
        self.assertIn("estilo Mac", box.pomar("bar", "status").stdout)

        restore = box.pomar("bar", "restore")
        self.assertOk(restore)
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse(box.path(".local/state/pomar/bar-backup.json").exists())
        self.assertIn("a original", box.pomar("bar", "status").stdout)
        self.assertIn("não havia nada guardado", box.pomar("bar", "restore").stdout)

    def test_restore_keeps_widgets_added_while_in_mac_mode(self):
        box = self.sandbox()
        self.assertOk(box.pomar("bar", "mac"))
        shell = box.shell_json()
        shell["bar"]["layout"]["right"].insert(0, {"id": "acme.pomodoro", "minutes": 25})
        box.path(".config/omarchy/shell.json").write_text(dump_shell(shell))
        result = box.pomar("bar", "restore")
        self.assertOk(result)
        layout = box.shell_json()["bar"]["layout"]
        self.assertEqual(layout["left"], SHELL["bar"]["layout"]["left"])
        self.assertEqual(layout["center"], SHELL["bar"]["layout"]["center"])
        self.assertEqual(layout["right"], SHELL["bar"]["layout"]["right"] + [{"id": "acme.pomodoro", "minutes": 25}])
        self.assertIn("acme.pomodoro", result.stdout)

    def test_broken_shell_json_is_left_untouched(self):
        box = self.sandbox(shell_json='{"version": 1, "bar": {\n')
        path = box.path(".config/omarchy/shell.json")
        result = box.pomar("bar", "mac")
        self.assertEqual(result.returncode, 1)
        self.assertIn("erro de digitação", result.stdout)
        self.assertEqual(path.read_text(), '{"version": 1, "bar": {\n')
        self.assertFalse(box.path(".local/state/pomar/bar-backup.json").exists())

    def test_shell_is_asked_to_reload_after_a_change(self):
        box = self.sandbox(shell=True)
        self.assertOk(box.pomar("bar", "mac"))
        self.assertIn(["-q", "shell", "reloadConfig"], box.calls("omarchy-shell"))
        box.reset_calls()
        self.assertOk(box.pomar("bar", "mac"))
        self.assertNotIn(["-q", "shell", "reloadConfig"], box.calls("omarchy-shell"), "nada mudou, nada a reler")


class HyprBlockTest(IsolatedTestCase):
    """Pôr e tirar o bloco são o inverso exato um do outro, em qualquer arquivo."""

    CASES = {
        "padrão do Omarchy": HYPRLAND_LUA,
        "sem a linha do Omarchy": "-- meu config\nhl.config({ general = { gaps_in = 2 } })\n",
        "sem quebra no fim": "-- meu config\nhl.config({})",
        "require como última linha sem quebra": "dofile('x')\n" + REQUIRE_LINE.rstrip("\n"),
        "vazio": "",
        "com CRLF": "-- windows\r\n" + REQUIRE_LINE.replace("\n", "\r\n") + "-- fim\r\n",
    }

    def test_add_then_remove_gives_the_same_bytes(self):
        box = self.sandbox()
        path = box.path(".config/hypr/teste.lua")
        for name, text in self.CASES.items():
            with self.subTest(name):
                path.write_bytes(text.encode())
                self.assertIn("status\tchanged", box.kit("hypr-add", path).stdout)
                added = path.read_text()
                self.assertEqual(added.count("-- >>> pomar >>>"), 1)
                self.assertIn("status\tok", box.kit("hypr-check", path).stdout)
                self.assertIn("status\tunchanged", box.kit("hypr-add", path).stdout)
                self.assertIn("status\tchanged", box.kit("hypr-remove", path).stdout)
                self.assertEqual(path.read_bytes(), text.encode())

    def test_block_goes_right_after_the_omarchy_defaults(self):
        box = self.sandbox()
        path = box.path(".config/hypr/hyprland.lua")
        box.kit("hypr-add", path)
        self.assertIn(REQUIRE_LINE + BLOCK + "\n-- Put your personal overrides", path.read_text())

    def test_an_old_block_is_replaced_by_one_new_block(self):
        box = self.sandbox()
        path = box.path(".config/hypr/hyprland.lua")
        old = "-- >>> pomar >>>\n-- versão antiga\ndofile('velho.lua')\n-- <<< pomar <<<\n"
        path.write_text(HYPRLAND_LUA + old)
        box.kit("hypr-add", path)
        text = path.read_text()
        self.assertEqual(text.count("-- >>> pomar >>>"), 1)
        self.assertNotIn("velho.lua", text)
        self.assertIn(REQUIRE_LINE + BLOCK, text)
        box.kit("hypr-remove", path)
        self.assertEqual(path.read_text(), HYPRLAND_LUA)

    def test_half_a_block_is_explained_and_left_alone(self):
        box = self.sandbox()
        path = box.path(".config/hypr/hyprland.lua")
        path.write_text(HYPRLAND_LUA + "-- >>> pomar >>>\n")
        result = box.kit("hypr-add", path)
        self.assertEqual(result.returncode, 1)
        self.assertIn("pela metade", result.stdout)
        self.assertEqual(path.read_text(), HYPRLAND_LUA + "-- >>> pomar >>>\n")


class CommandTest(IsolatedTestCase):
    def pomar_theme(self, box):
        box.path(".local/state/omarchy/current/theme.name").write_text("pomar\n")
        (box.state / "known.json").write_text(json.dumps({"pomar.settings": {"id": "pomar.settings", "kinds": ["panel"]}}))

    def test_open_sends_the_right_event_to_hyprland(self):
        box = self.sandbox(hypr=True, shell=True)
        self.pomar_theme(box)
        for args, event in ((("open", "launchpad"), "launchpad:toggle"), (("open", "mission"), "mission:toggle"),
                            (("open", "expose"), "mission:expose"), (("open", "switcher"), "switcher:next"),
                            (("dock", "autohide"), "dock:autohide-toggle")):
            with self.subTest(event):
                box.reset_calls()
                self.assertOk(box.pomar(*args))
                self.assertEqual(box.calls("hyprctl"), [["dispatch", f'hl.dsp.event("pomar>>{event}")']])
        self.assertEqual(box.calls("notify-send"), [])

    def test_open_settings_and_welcome_summon_the_panel(self):
        box = self.sandbox(hypr=True, shell=True)
        self.pomar_theme(box)
        for args, payload in ((("open", "settings"), "{}"), (("open", "settings", "dock"), '{"page":"dock"}'),
                              (("open", "welcome"), '{"page":"welcome"}')):
            with self.subTest(payload):
                box.reset_calls()
                self.assertOk(box.pomar(*args))
                self.assertEqual(box.calls("omarchy-shell"), [["shell", "summon", "pomar.settings", payload]])
        bad = box.pomar("open", "settings", 'x"; rm -rf ~')
        self.assertEqual(bad.returncode, 1)
        self.assertIn("Página inválida", bad.stderr)

    def test_open_with_another_theme_explains_why_nothing_shows(self):
        box = self.sandbox(hypr=True)
        self.assertOk(box.pomar("open", "launchpad"))
        self.assertEqual(len(box.calls("notify-send")), 1, "aberto sem terminal, avisa por notificação")

    def test_help_version_and_unknown_command(self):
        box = self.sandbox()
        help_text = box.pomar("help").stdout
        for command in ("open launchpad", "open settings", "dock autohide", "bar mac", "bar restore", "doctor"):
            self.assertIn(command, help_text)
        version = (box.src / "VERSION").read_text().strip()
        self.assertIn(f"Pomarchy {version}", box.pomar("version").stdout)
        unknown = box.pomar("voar")
        self.assertEqual(unknown.returncode, 2)
        self.assertIn("Comando desconhecido", unknown.stderr)


class DoctorTest(IsolatedTestCase):
    def test_doctor_is_happy_after_install_and_explains_a_problem(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        doctor = box.run("bash", box.path(".local/bin/pomar"), "doctor")
        self.assertOk(doctor)
        self.assertIn("Tudo certo.", doctor.stdout)
        self.assertIn("Barra no estilo Mac", doctor.stdout)
        self.assertIn("Tema atual: Pomarchy", doctor.stdout)

        box.path(".config/omarchy/plugins/pomar.dock").unlink()
        broken = box.run("bash", box.path(".local/bin/pomar"), "doctor")
        self.assertEqual(broken.returncode, 1)
        self.assertIn("Faltam peças", broken.stdout)
        self.assertIn("pomar.dock", broken.stdout)
        self.assertIn("Como corrigir", broken.stdout)

    def test_doctor_reports_hyprland_errors(self):
        box = self.sandbox(hypr=True, POMAR_STUB_USER_ERROR="input.lua:3: erro da pessoa")
        self.assertOk(box.install("--yes"))
        doctor = box.run("bash", box.path(".local/bin/pomar"), "doctor")
        self.assertEqual(doctor.returncode, 1)
        self.assertIn("input.lua:3: erro da pessoa", doctor.stdout)
        self.assertIn("não no Pomarchy", doctor.stdout)


class ReviewFixesKitTest(IsolatedTestCase):
    """Achados da revisão cruzada (Codex) no kit do pomar: cada teste falhava antes."""

    def test_c7_only_a_whole_require_line_is_an_anchor(self):
        box = self.sandbox()
        path = box.path(".config/hypr/hyprland.lua")
        cases = {
            "parêntese na linha de baixo": 'require("default.hypr.omarchy"\n)\n-- fim\n',
            "dentro de uma string longa": 'local s = [[\nrequire("default.hypr.omarchy")\n]]\n',
            "dentro de um comentário longo": '--[[\nrequire("default.hypr.omarchy")\n]]\n',
            "seguido de comentário longo": 'require("default.hypr.omarchy") --[[ nota\n]]\n',
        }
        for name, text in cases.items():
            with self.subTest(name):
                path.write_text(text)
                self.assertIn("status\tchanged", box.kit("hypr-add", path).stdout)
                self.assertEqual(path.read_text(), text + BLOCK, "sem linha inteira de verdade, o bloco vai para o fim")
        path.write_text('local s = [[\nrequire("default.hypr.omarchy")\n]]\n' + REQUIRE_LINE + "-- fim\n")
        box.kit("hypr-add", path)
        self.assertIn("]]\n" + REQUIRE_LINE + BLOCK + "-- fim\n", path.read_text(), "a linha de verdade é a âncora")
        path.write_text('require "default.hypr.omarchy"  -- padrões do Omarchy\n-- fim\n')
        box.kit("hypr-add", path)
        self.assertIn('-- padrões do Omarchy\n' + BLOCK + "-- fim\n", path.read_text(), "require sem parênteses vale")

    @unittest.skipUnless(shutil.which("luac"), "precisa do luac")
    def test_c7_result_that_does_not_parse_is_never_written(self):
        box = self.sandbox()
        path = box.path(".config/hypr/hyprland.lua")
        broken = HYPRLAND_LUA + "hl.config({\n"
        path.write_text(broken)
        result = box.kit("hypr-add", path)
        self.assertEqual(result.returncode, 1)
        self.assertIn("erro de Lua", result.stdout)
        self.assertIn("~/.config/hypr/hyprland.lua", result.stdout)
        self.assertEqual(path.read_text(), broken)

    def test_c2_prune_only_removes_old_pomarchy_versions(self):
        box = self.sandbox()
        releases = box.path(".local/share/pomar/releases")
        now = time.time()

        def folder(name, age, pomar_lua=True):
            path = releases / name
            (path / "hypr").mkdir(parents=True)
            if pomar_lua:
                (path / "hypr/pomar.lua").write_text("-- Pomarchy\n")
            os.utime(path, (now - age, now - age))
            return path

        for name, age in (("aaaaaaa", 900), ("bbbbbbb", 800), ("0.1.0-20260101-000000", 300), ("ccccccc", 200),
                          ("ddddddd-dirty", 100)):
            folder(name, age)
        folder("eeeeeee", 1000, pomar_lua=False)
        photos = releases / "fotos"
        photos.mkdir()
        (photos / "praia.jpg").write_text("foto\n")
        os.utime(photos, (now - 5000, now - 5000))
        box.kit("prune-releases", releases, "ddddddd-dirty", "2")
        self.assertEqual(sorted(p.name for p in releases.iterdir()),
                         ["0.1.0-20260101-000000", "ccccccc", "ddddddd-dirty", "eeeeeee", "fotos"])

    def test_c2_prune_refuses_a_linked_releases_folder(self):
        box = self.sandbox()
        elsewhere = box.root / "outro-disco"
        for name in ("aaaaaaa", "bbbbbbb", "ccccccc", "ddddddd"):
            (elsewhere / name / "hypr").mkdir(parents=True)
            (elsewhere / name / "hypr/pomar.lua").write_text("-- Pomarchy\n")
        releases = box.path(".local/share/pomar/releases")
        releases.parent.mkdir(parents=True)
        releases.symlink_to(elsewhere)
        box.kit("prune-releases", releases, "ddddddd", "0")
        self.assertEqual(sorted(p.name for p in elsewhere.iterdir()), ["aaaaaaa", "bbbbbbb", "ccccccc", "ddddddd"])

    def test_c9_a_bar_without_clock_goes_back_without_clock(self):
        shell = json.loads(json.dumps(SHELL))
        shell["bar"]["layout"]["center"] = [e for e in shell["bar"]["layout"]["center"] if e["id"] != "omarchy.clock"]
        box = self.sandbox(shell_json=shell)
        path = box.path(".config/omarchy/shell.json")
        original = path.read_bytes()
        self.assertOk(box.pomar("bar", "mac"))
        self.assertEqual(box.shell_json()["bar"]["layout"]["right"][-1], {"id": "omarchy.clock", "format": MAC_CLOCK})
        self.assertOk(box.pomar("bar", "restore"))
        self.assertEqual(path.read_bytes(), original, "o relógio que o bar mac pôs sai junto")

    def test_14_cloned_menu_stays_loaded_and_the_file_goes_back_byte_for_byte(self):
        shell = json.loads(json.dumps(SHELL))
        shell["bar"]["layout"]["left"] = [{"id": "meu.menu"}, {"id": "omarchy.workspaces"}]
        box = self.sandbox(shell_json=shell)
        manifest = box.path(".config/omarchy/plugins/meu.menu/manifest.json")
        manifest.parent.mkdir(parents=True)
        manifest.write_text(json.dumps({"schemaVersion": 1, "id": "meu.menu", "name": "Meu menu",
                                        "version": "1.0.0", "kinds": ["menu", "bar-widget"],
                                        "entryPoints": {"menu": "Menu.qml", "barWidget": "Widget.qml"}}))
        path = box.path(".config/omarchy/shell.json")
        original = path.read_bytes()
        self.assertOk(box.pomar("bar", "mac"))
        mac = box.shell_json()
        self.assertIn({"id": "meu.menu"}, mac["plugins"], "o menu clonado continua carregado fora da barra")
        self.assertNotIn({"id": "meu.menu"}, mac["bar"]["layout"]["left"])
        self.assertOk(box.pomar("bar", "restore"))
        self.assertEqual(path.read_bytes(), original)

    def test_c4_restore_is_written_again_when_the_shell_puts_the_old_bar_back(self):
        box = self.sandbox(shell=True)
        path = box.path(".config/omarchy/shell.json")
        original = path.read_bytes()
        self.assertOk(box.pomar("bar", "mac"))
        (box.state / "clobber-left").write_text("1")
        box.reset_calls()
        result = box.pomar("bar", "restore")
        self.assertOk(result)
        self.assertEqual(box.shell_json(), json.loads(original), "o shell reformata o arquivo; o conteúdo é o de antes")
        self.assertFalse(box.path(".local/state/pomar/bar-backup.json").exists())
        self.assertGreaterEqual(box.calls("omarchy-shell").count(["shell", "reloadConfig"]), 2)

    def test_c4_restore_that_never_sticks_keeps_the_backup_and_says_so(self):
        box = self.sandbox(shell=True)
        self.assertOk(box.pomar("bar", "mac"))
        (box.state / "clobber-left").write_text("99")
        result = box.pomar("bar", "restore")
        self.assertEqual(result.returncode, 1, "a barra não voltou: o comando diz que falhou")
        self.assertTrue(box.path(".local/state/pomar/bar-backup.json").is_file(), "a barra original não se perde")
        self.assertIn("continua guardada", result.stdout)
        self.assertEqual(box.calls("omarchy-shell").count(["shell", "reloadConfig"]), 3)


    def test_c4_finish_keeps_the_backup_while_the_mac_bar_is_on_disk(self):
        box = self.sandbox()
        self.assertOk(box.pomar("bar", "mac"))
        result = box.kit("bar-restore-finish")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(box.path(".local/state/pomar/bar-backup.json").is_file(), "só apaga depois de a barra voltar")


class OldBarBackupTest(IsolatedTestCase):
    """Cópia da barra feita por uma versão anterior (regras 1): o `bar mac` de
    hoje devolve uma vez o que as regras novas mantêm, e depois respeita a pessoa."""

    def test_old_backup_brings_workspaces_back_once(self):
        mac_v1 = json.loads(json.dumps(SHELL))
        mac_v1["bar"]["layout"] = {"left": [{"id": "pomar.menubar"}], "center": [],
                                   "right": [{"id": "omarchy.tray"}, {"id": "omarchy.clock", "format": MAC_CLOCK}]}
        box = self.sandbox(shell_json=mac_v1)
        backup = box.path(".local/state/pomar/bar-backup.json")
        backup.parent.mkdir(parents=True)
        backup.write_text(json.dumps({"version": 1, "hadBar": True, "bar": SHELL["bar"]}))
        self.assertOk(box.pomar("bar", "mac"))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"],
                         [{"id": "pomar.menubar"}, {"id": "omarchy.workspaces"}])
        self.assertEqual(json.loads(backup.read_text())["rules"], 2)

        shell = box.shell_json()
        shell["bar"]["layout"]["left"] = [{"id": "pomar.menubar"}]  # a pessoa tirou as mesas
        box.path(".config/omarchy/shell.json").write_text(dump_shell(shell))
        self.assertOk(box.pomar("bar", "mac"))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"], [{"id": "pomar.menubar"}],
                         "com a cópia já nas regras novas, vale o que a pessoa escolheu")


if __name__ == "__main__":
    unittest.main()
