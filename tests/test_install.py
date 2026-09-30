"""Instalador e desinstalador do Pomarchy, de ponta a ponta, sem tocar no computador
de ninguém.

Cada teste roda num HOME temporário, com TODAS as pastas XDG, o runtime, o
TMPDIR e o D-Bus apontando para dentro dele, e com dublês no começo do PATH
para tudo que tem efeito no sistema (omarchy, omarchy-shell, hyprctl, abrir
app, systemd...). Os dublês anotam cada chamada e simulam o que os testes
precisam: o shell do Omarchy (que só conhece um plugin depois de reler a
pasta e grava o shell.json um instante depois de responder), a troca de tema
e os erros de configuração do Hyprland. Antes de rodar qualquer coisa, o
teste confere o isolamento; depois, confere que o HOME real não mudou.
"""
import json
import os
import pty
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(HERE))
import nested  # noqa: E402  (fingerprint e REAL_HOME: o retrato do HOME real)

BLOCK_BEGIN = "-- >>> pomar >>>"
BLOCK = (
    "-- >>> pomar >>>\n"
    "-- Pomarchy: Mac-style gestures, shortcuts and animations (active only with a Pomarchy theme).\n"
    "do\n"
    '  local home = os.getenv("HOME") or ""\n'
    '  local ok, err = pcall(dofile, home .. "/.local/share/pomar/current/hypr/pomar.lua")\n'
    '  local mark = home .. "/.local/state/pomar/hypr-erro"\n'
    "  if ok then\n"
    "    pcall(os.remove, mark)\n"
    "  else\n"
    '    pcall(function() hl.notification.create({ text = "Pomarchy OS failed to load: " .. tostring(err), timeout = 15000 }) end)\n'
    '    pcall(function() local file = assert(io.open(mark, "w")); file:write(tostring(err), "\\n"); file:close() end)\n'
    "  end\n"
    "end\n"
    "-- <<< pomar <<<\n"
)
REQUIRE_LINE = 'require("default.hypr.omarchy")\n'
ENABLED = ["pomar.core", "pomar.dock", "pomar.launchpad", "pomar.mission", "pomar.settings", "pomar.switcher"]
MAC_CLOCK = "ddd d MMM  HH:mm"

# Estrutura do ~/.config/hypr/hyprland.lua que o Omarchy 4 instala.
HYPRLAND_LUA = """-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
"""

# Parte de gestos do ~/.config/hypr/input.lua do Omarchy 4: vem tudo comentado.
INPUT_LUA = """-- Keep only your personal input overrides here.

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })
"""

# O mesmo, com a pessoa usando 3 dedos para os lados e para cima de verdade.
INPUT_LUA_CONFLICTS = INPUT_LUA + """
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({
  fingers = 3,
  direction = "up",
  action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end,
})
"""

# Estrutura do shell.json padrão do Omarchy 4 (o travessão escapado é como o
# arquivo do Omarchy vem).
SHELL = {
    "version": 1,
    "idle": {"screensaver": 150, "lock": 300},
    "bar": {
        "position": "top",
        "transparent": False,
        "centerAnchor": "omarchy.clock",
        "layout": {
            "left": [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces"}],
            "center": [
                {"id": "omarchy.indicators"},
                {"id": "omarchy.clock", "format": "dddd HH:mm", "formatAlt": "d MMMM 'W'ww yyyy",
                 "verticalFormat": "HH\n—\nmm"},
                {"id": "omarchy.keyboard-layout"},
                {"id": "omarchy.weather"},
                {"id": "omarchy.system-update"},
            ],
            "right": [
                {"id": "omarchy.tray"}, {"id": "omarchy.agents"}, {"id": "omarchy.bluetooth"},
                {"id": "omarchy.network"}, {"id": "omarchy.audio"}, {"id": "omarchy.monitor"},
                {"id": "omarchy.power"},
            ],
        },
    },
    "plugins": [],
}


def dump_shell(value):
    return json.dumps(value, indent=2) + "\n"


# Nomes que viram dublês. Os do fim nunca deveriam ser chamados pelo Pomarchy: o
# dublê deles falha, e os testes conferem que ninguém os chamou.
STUBS_OK = ("omarchy", "omarchy-shell", "omarchy-theme-set", "omarchy-plugin-enable", "omarchy-plugin-disable",
            "omarchy-plugin-validate", "omarchy-restart-shell", "hyprctl", "notify-send", "gtk-update-icon-cache",
            "update-desktop-database")
STUBS_FORBIDDEN = ("qs", "quickshell", "gtk-launch", "uwsm-app", "uwsm", "gio", "xdg-open", "xdg-settings",
                   "xdg-mime", "xdg-desktop-menu", "xdg-icon-resource", "systemctl", "systemd-run", "loginctl",
                   "reboot", "poweroff", "shutdown", "trash-put", "trash-empty", "Hyprland", "hyprland")
STUB_NAMES = STUBS_OK + STUBS_FORBIDDEN

STUB = r'''#!/usr/bin/env python3
"""Dublê para os testes do instalador do Pomarchy. Anota a chamada e simula só o
necessário. Nunca chama o comando de verdade; a única exceção é só de leitura:
`omarchy plugin validate` usa o validador do Omarchy, que apenas lê a pasta."""
import json
import os
import pwd
import re
import subprocess
import sys
import time
from pathlib import Path

NAME = Path(sys.argv[0]).name
ARGS = sys.argv[1:]
HOME = Path(os.environ["HOME"])
ROOT = os.environ.get("POMAR_TEST_ROOT", "")
REAL_HOME = Path(pwd.getpwuid(os.getuid()).pw_dir)
if not ROOT or not str(HOME).startswith(ROOT) or HOME.resolve() == REAL_HOME.resolve():
    sys.stderr.write(f"dublê {NAME}: HOME fora do teste ({HOME}); recusando\n")
    sys.exit(97)
STATE = Path(os.environ["POMAR_STUB_STATE"])
LOG = Path(os.environ["POMAR_TEST_LOG"])
SHELL_UP = os.environ.get("POMAR_STUB_SHELL") == "1"
HYPR_UP = os.environ.get("POMAR_STUB_HYPR") == "1"
OMARCHY_PATH = Path(os.environ["OMARCHY_PATH"])
USER_SHELL = HOME / ".config/omarchy/shell.json"
THEME_NAME = HOME / ".local/state/omarchy/current/theme.name"
HYPR_LUA = HOME / ".config/hypr/hyprland.lua"
PLUGINS = HOME / ".config/omarchy/plugins"
VALIDATOR = Path("/usr/share/omarchy/bin/omarchy-plugin-validate")
FORBIDDEN = set(os.environ.get("POMAR_STUB_FORBIDDEN", "").split())

with LOG.open("a") as handle:
    handle.write(json.dumps({"cmd": NAME, "args": ARGS}) + "\n")


def done(text=None, code=0, err=None):
    if text is not None:
        print(text)
    if err:
        sys.stderr.write(err + "\n")
    sys.exit(code)


def entry_id(entry):
    return str(entry.get("id") or "") if isinstance(entry, dict) else str(entry)


# ------------------------------------------------------------ Hyprland
def compute_errors():
    text = HYPR_LUA.read_text() if HYPR_LUA.exists() else ""
    block = ">>> pomar >>>" in text
    theme = THEME_NAME.read_text().strip() if THEME_NAME.exists() else ""
    errors = []
    if os.environ.get("POMAR_STUB_USER_ERROR"):
        errors.append(os.environ["POMAR_STUB_USER_ERROR"])
    mark = os.environ.get("POMAR_STUB_USER_ERROR_MARK")
    if mark:  # erro da pessoa numa linha que o bloco do Pomarchy empurra para baixo
        for number, line in enumerate(text.splitlines(), 1):
            if mark in line:
                errors.append(f"{HYPR_LUA}:{number}: erro antigo da pessoa")
    if os.environ.get("POMAR_STUB_LATE_ERROR") and (STATE / "recarregou").exists():
        errors.append(os.environ["POMAR_STUB_LATE_ERROR"])  # erro novo da pessoa, sem ligação com o bloco
    if block and os.environ.get("POMAR_STUB_BLOCK_ERROR") == "1":
        errors.append("hyprland.lua:12: erro simulado no bloco do Pomarchy")
    if block and theme.startswith("pomar") and os.environ.get("POMAR_STUB_THEME_ERROR") == "1":
        errors.append("pomar.lua: opção simulada que o Hyprland recusa")
    return errors


def load_block():
    """O que o bloco do Pomarchy faz a cada recarga: se o pomar.lua não carrega,
    avisa e grava o erro em ~/.local/state/pomar/hypr-erro; se carrega, apaga."""
    text = HYPR_LUA.read_text() if HYPR_LUA.exists() else ""
    if ">>> pomar >>>" not in text:
        return
    mark = HOME / ".local/state/pomar/hypr-erro"
    if os.environ.get("POMAR_STUB_LOAD_ERROR") == "1":
        if mark.parent.is_dir():
            mark.write_text("pomar.lua:42: erro simulado ao carregar\n")
    elif mark.exists():
        mark.unlink()


def move_window(lua):
    match = re.search(r'hl\.dsp\.window\.move\(\{ window = "address:(0x[0-9a-fA-F]+)", '
                      r'workspace = "([^"]+)", follow = false \}\)', lua)
    if not match:
        return
    path = STATE / "clients.json"
    clients = json.loads(path.read_text()) if path.exists() else []
    for client in clients:
        if client.get("address") == match.group(1):
            client["workspace"] = {"id": int(match.group(2)), "name": match.group(2)}
    path.write_text(json.dumps(clients))


def hyprctl():
    if not HYPR_UP:
        done(err="HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)", code=1)
    args = [a for a in ARGS if a != "-j"]
    command = args[0] if args else ""
    saved = STATE / "configerrors.json"
    if command == "version":
        done("Hyprland 0.56.2 (dublê)")
    if command == "reload":
        (STATE / "recarregou").touch()
        saved.write_text(json.dumps(compute_errors()))
        load_block()
        done("ok")
    if command == "configerrors":
        errors = json.loads(saved.read_text()) if saved.exists() else compute_errors()
        done("\n".join(errors) if errors else "\n")
    if command == "clients":
        if os.environ.get("POMAR_STUB_CLIENTS_TRUNCATED") == "1":
            done('[{"address": "0x1a2b", "work')  # resposta cortada no meio, com saída 0
        if os.environ.get("POMAR_STUB_CLIENTS_FAIL") == "1":
            done(err="Couldn't connect to the Hyprland socket", code=4)
        path = STATE / "clients.json"
        done(path.read_text() if path.exists() else "[]")
    if command == "activeworkspace":
        path = STATE / "activeworkspace.json"
        done(path.read_text() if path.exists() else '{"id": 1, "name": "1"}')
    if command == "dispatch" and len(args) > 1:
        if os.environ.get("POMAR_STUB_DISPATCH_ERROR") == "1" and "window.move" in args[1]:
            done("error: janela não encontrada")  # sai com 0, como o hyprctl de verdade
        move_window(args[1])
    done("ok")


# ------------------------------------------------------ shell do Omarchy
def shell_memory():
    """A configuração que o shell tem na memória. Como o FileView do shell,
    relê o arquivo quando alguém mais o gravou; senão, fica com a sua."""
    memory, stamp = STATE / "shell-memory.json", STATE / "shell-memory.stamp"
    disk = str(USER_SHELL.stat().st_mtime_ns) if USER_SHELL.exists() else "sem-arquivo"
    if memory.exists() and stamp.exists() and stamp.read_text() == disk:
        return json.loads(memory.read_text())
    if USER_SHELL.exists() and USER_SHELL.read_text().strip():
        return json.loads(USER_SHELL.read_text())
    return json.loads((OMARCHY_PATH / "config/omarchy/shell.json").read_text())


WRITER = """
import fcntl, os, pathlib, sys, time
pending, target, stamp, delay, sequence = sys.argv[1:6]
time.sleep(float(delay))
state = pathlib.Path(stamp).parent
with open(state / "writer.lock", "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)  # um gravador por vez, na ordem, como o shell
    applied = state / "applied-sequence"
    last = int(applied.read_text()) if applied.exists() else 0
    if int(sequence) > last:
        target = pathlib.Path(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(".shell.json.dublê")
        temporary.write_text(pathlib.Path(pending).read_text())
        os.replace(temporary, target)
        pathlib.Path(stamp).write_text(str(target.stat().st_mtime_ns))
        applied.write_text(sequence)
    os.unlink(pending)
"""


def persist(config):
    """Como o shell: memória na hora; disco (JSON.stringify com 2 espaços) um
    instante depois, se POMAR_STUB_SHELL_WRITE_DELAY pedir."""
    config["version"] = 1
    (STATE / "shell-memory.json").write_text(json.dumps(config))
    sequence = str(time.time_ns())
    pending = STATE / f"pending-{sequence}.json"
    pending.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
    delay = os.environ.get("POMAR_STUB_SHELL_WRITE_DELAY", "0")
    command = [sys.executable, "-c", WRITER, str(pending), str(USER_SHELL), str(STATE / "shell-memory.stamp"), delay,
               sequence]
    if float(delay) > 0:
        subprocess.Popen(command, start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.run(command, check=True)


def known():
    path = STATE / "known.json"
    return json.loads(path.read_text()) if path.exists() else {}


def rescan():
    found = {}
    if PLUGINS.is_dir():
        for folder in sorted(PLUGINS.iterdir()):
            manifest = folder / "manifest.json"
            if not folder.name.startswith(".") and manifest.is_file():
                info = json.loads(manifest.read_text())
                found[info["id"]] = info
    (STATE / "known.json").write_text(json.dumps(found))


def in_layout(config, wid):
    layout = (config.get("bar") or {}).get("layout") or {}
    return any(entry_id(e) == wid for section in ("left", "center", "right") for e in layout.get(section) or [])


def enable(wid):
    info = known().get(wid)
    if info is None:
        return "unknown"
    config = shell_memory()
    plugins = config.setdefault("plugins", [])
    if "bar-widget" in info.get("kinds", []):
        if not in_layout(config, wid):
            section = (info.get("barWidget") or {}).get("defaultSection", "center")
            config.setdefault("bar", {}).setdefault("layout", {}).setdefault(section, []).append({"id": wid})
    elif not any(entry_id(e) == wid for e in plugins):
        plugins.append({"id": wid})
    persist(config)
    return "ok"


def disable(wid):
    config = shell_memory()
    config["plugins"] = [e for e in config.get("plugins") or [] if entry_id(e) != wid]
    layout = (config.get("bar") or {}).get("layout") or {}
    for section in ("left", "center", "right"):
        if isinstance(layout.get(section), list):
            layout[section] = [e for e in layout[section] if entry_id(e) != wid]
    persist(config)
    return "ok"


def list_plugins():
    config = shell_memory()
    out = []
    for wid, info in known().items():
        kinds = info.get("kinds", [])
        enabled = in_layout(config, wid) if "bar-widget" in kinds else any(
            entry_id(e) == wid for e in config.get("plugins") or [])
        out.append({"id": wid, "name": info.get("name", wid), "kinds": kinds, "enabled": enabled, "firstParty": False})
    return json.dumps(out)


def omarchy_shell():
    args = list(ARGS)
    quiet = bool(args) and args[0] == "-q"
    if quiet:
        args = args[1:]
    if not SHELL_UP:
        done(code=0) if quiet else done(err="omarchy-shell is not running", code=1)
    if len(args) < 2 or args[0] != "shell":
        done("ok")
    method, rest = args[1], args[2:]
    if method == "ping":
        done("ok")
    if method == "rescanPlugins":
        rescan()
        done()
    if method == "reloadConfig":
        # O shell relê o arquivo (FileView). Com clobber-left > 0, faz o
        # contrário: grava por cima o que tinha na memória, como um shell que
        # ainda não viu a mudança.
        left_file, memory = STATE / "clobber-left", STATE / "shell-memory.json"
        left = int(left_file.read_text()) if left_file.exists() else 0
        if left > 0 and memory.exists():
            left_file.write_text(str(left - 1))
            USER_SHELL.write_text(json.dumps(json.loads(memory.read_text()), indent=2, ensure_ascii=False) + "\n")
        elif USER_SHELL.exists() and USER_SHELL.read_text().strip():
            memory.write_text(json.dumps(json.loads(USER_SHELL.read_text())))
        if USER_SHELL.exists():
            (STATE / "shell-memory.stamp").write_text(str(USER_SHELL.stat().st_mtime_ns))
        done("ok")
    if method == "enablePlugin":
        done(enable(rest[0]))
    if method == "setPluginEnabled":
        done(enable(rest[0]) if rest[1] == "true" else disable(rest[0]))
    if method == "listPlugins":
        done(list_plugins())
    if method == "summon":
        done("ok" if rest and rest[0] in known() else "unknown")
    done("ok")


# ---------------------------------------------------------------- tema
def theme_set(name):
    slug = name.lower().replace(" ", "-")
    if os.environ.get("POMAR_STUB_THEME_FAIL") == "1":
        done(f"Theme '{slug}' could not be applied", code=1)
    if not ((OMARCHY_PATH / "themes" / slug).is_dir() or (HOME / ".config/omarchy/themes" / slug).is_dir()):
        done(f"Theme '{slug}' does not exist", code=1)
    THEME_NAME.parent.mkdir(parents=True, exist_ok=True)
    THEME_NAME.write_text(slug + "\n")
    if HYPR_UP:  # o omarchy-theme-set de verdade roda omarchy-restart-hyprctl
        subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, check=False)
    hooks = HOME / ".config/omarchy/hooks/theme-set.d"  # e depois os ganchos (omarchy-hook)
    if hooks.is_dir():
        for hook in sorted(hooks.iterdir()):
            if hook.is_file() and not hook.name.endswith(".sample"):
                subprocess.run(["bash", str(hook), slug], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    done()


def omarchy():
    group, verb = (ARGS + ["", ""])[:2]
    rest = ARGS[2:]
    if group == "plugin" and verb == "validate":
        if VALIDATOR.is_file():
            sys.exit(subprocess.run(["bash", str(VALIDATOR), *rest]).returncode)
        done()
    if group == "plugin" and verb in ("enable", "disable", "list"):
        if not SHELL_UP:
            done(err=f"omarchy-plugin-{verb}: omarchy-shell is not running", code=1)
        if verb == "list":
            done(list_plugins())
        result = enable(rest[0]) if verb == "enable" else disable(rest[0])
        if result != "ok":
            done(err=f"omarchy-plugin-{verb}: plugin '{rest[0]}' is not known; run: omarchy-shell shell rescanPlugins",
                 code=1)
        done(("Enabled " if verb == "enable" else "Disabled ") + rest[0])
    if group == "theme" and verb == "set":
        theme_set(" ".join(rest))
    if group == "restart" and verb == "shell" and os.environ.get("POMAR_STUB_RESTART_FAIL") == "1":
        done(err="Refusing to restart Omarchy shell while the session is locked.", code=1)
    done()


if NAME in FORBIDDEN:
    done(err=f"dublê {NAME}: o Pomarchy não deveria chamar isto", code=96)
if NAME == "hyprctl":
    hyprctl()
if NAME == "omarchy-shell":
    omarchy_shell()
if NAME == "omarchy":
    omarchy()
if NAME == "omarchy-theme-set":
    theme_set(" ".join(ARGS))
done()
'''


def tree_snapshot(root, ignore=()):
    """Tudo o que existe debaixo de root: links (destino), arquivos (conteúdo)."""
    shot = {}
    for folder, dirs, files in os.walk(root):
        for name in dirs + files:
            path = Path(folder, name)
            rel = path.relative_to(root).as_posix()
            if any(rel == item or rel.startswith(item + "/") for item in ignore):
                continue
            if path.is_symlink():
                shot[rel] = ("link", os.readlink(path))
            elif path.is_dir():
                shot[rel] = ("dir",)
            else:
                shot[rel] = ("file", path.read_bytes())
    return shot


_SOURCE = None


def source_copy():
    """Uma cópia do repositório (sem .git), feita uma vez, para os testes
    instalarem dela. Some sozinha quando o Python termina."""
    global _SOURCE
    if _SOURCE is None:
        _SOURCE = tempfile.TemporaryDirectory(prefix="pomar-fonte-")
        shutil.copytree(REPO, Path(_SOURCE.name) / "pomar", symlinks=True,
                        ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc", "out", ".stage"))
    return Path(_SOURCE.name) / "pomar"


class Sandbox:
    """HOME de teste com o Omarchy 4 de mentira em volta. As mensagens saem em
    português (POMAR_LANG=pt), que é o que a maioria dos testes confere; com
    lang=None, o Pomarchy escolhe sozinho (o LANG daqui é C.UTF-8: inglês)."""

    def __init__(self, *, shell=False, hypr=False, shell_json=SHELL, input_lua=INPUT_LUA, hypr_lua=HYPRLAND_LUA,
                 lang="pt", **stub_env):
        self._temporary = tempfile.TemporaryDirectory(prefix="pomar-instalador-")
        self.root = Path(self._temporary.name).resolve()
        self.home = self.root / "home"
        self.stubs = self.root / "stubs"
        self.state = self.root / "stub-state"
        self.omarchy = self.root / "omarchy"
        self.log = self.root / "chamadas.jsonl"
        self.src = source_copy()
        self.shell_up, self.hypr_up, self.lang, self.stub_env = shell, hypr, lang, stub_env
        for folder in (self.home, self.stubs, self.state, self.root / "tmp", self.root / "run",
                       self.root / "sistema/etc"):
            folder.mkdir(parents=True)
        (self.root / "run").chmod(0o700)
        self.log.touch()

        (self.omarchy / "shell").mkdir(parents=True)
        (self.omarchy / "shell/shell.qml").write_text("// dublê do shell do Omarchy 4\n")
        (self.omarchy / "config/omarchy").mkdir(parents=True)
        (self.omarchy / "config/omarchy/shell.json").write_text(dump_shell(SHELL))
        (self.omarchy / "themes/tokyo-night").mkdir(parents=True)
        (self.omarchy / "themes/tokyo-night/colors.toml").write_text('accent = "#7aa2f7"\n')
        (self.omarchy / "version").write_text("4.0.0\n")

        hypr = self.home / ".config/hypr"
        hypr.mkdir(parents=True)
        (hypr / "hyprland.lua").write_text(hypr_lua)
        (hypr / "input.lua").write_text(input_lua)
        (self.home / ".config/omarchy/themes").mkdir(parents=True)
        if shell_json is not None:
            text = shell_json if isinstance(shell_json, str) else dump_shell(shell_json)
            (self.home / ".config/omarchy/shell.json").write_text(text)
        (self.home / ".local/state/omarchy/current").mkdir(parents=True)
        (self.home / ".local/state/omarchy/current/theme.name").write_text("tokyo-night\n")

        stub = self.stubs / "_dublê.py"
        stub.write_text(STUB)
        stub.chmod(0o755)
        for name in STUB_NAMES:
            (self.stubs / name).symlink_to(stub.name)
        if stub_env.get("POMAR_STUB_USER_ERROR"):  # o erro que a sessão já mostrava no login
            (self.state / "configerrors.json").write_text(json.dumps([stub_env["POMAR_STUB_USER_ERROR"]]))

    def close(self):
        self.wait_shell_writes()
        self._temporary.cleanup()

    # --------------------------------------------------------- ambiente
    def env(self, **extra):
        home = str(self.home)
        env = {
            "HOME": home,
            "USER": "pomar-teste",
            "LOGNAME": "pomar-teste",
            "PATH": f"{self.stubs}:/usr/bin:/bin",
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "TERM": "dumb",
            "NO_COLOR": "1",
            "TMPDIR": str(self.root / "tmp"),
            "XDG_CONFIG_HOME": f"{home}/.config",
            "XDG_DATA_HOME": f"{home}/.local/share",
            "XDG_STATE_HOME": f"{home}/.local/state",
            "XDG_CACHE_HOME": f"{home}/.cache",
            "XDG_RUNTIME_DIR": str(self.root / "run"),
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent",
            "OMARCHY_PATH": str(self.omarchy),
            "POMAR_TEST_ROOT": str(self.root),
            "POMAR_TEST_LOG": str(self.log),
            "POMAR_STUB_STATE": str(self.state),
            "POMAR_STUB_FORBIDDEN": " ".join(STUBS_FORBIDDEN),
            "POMAR_HYPR_SETTLE": "0",
            "POMAR_SHELL_SETTLE": "0",
            "POMAR_SYSTEM_ROOT": str(self.root / "sistema"),
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        if self.shell_up:
            env["POMAR_STUB_SHELL"] = "1"
        if self.hypr_up:
            env["POMAR_STUB_HYPR"] = "1"
            env["HYPRLAND_INSTANCE_SIGNATURE"] = "pomar-teste"
        if self.lang is not None:
            env["POMAR_LANG"] = self.lang
        env.update(self.stub_env)
        env.update(extra)
        self.check_isolation(env)
        return env

    def check_isolation(self, env):
        """Recusa rodar se algo apontar para fora do teste."""
        home = Path(env["HOME"]).resolve()
        real = nested.REAL_HOME.resolve()
        assert home != real and str(home).startswith(str(self.root)), f"HOME fora do teste: {home}"
        for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR",
                    "TMPDIR"):
            assert env[key].startswith(str(self.root)), f"{key} fora do teste: {env[key]}"
        assert "HYPRLAND_INSTANCE_SIGNATURE" not in env or env["HYPRLAND_INSTANCE_SIGNATURE"] == "pomar-teste"
        assert "WAYLAND_DISPLAY" not in env and "DISPLAY" not in env
        path = env["PATH"].split(":")
        assert path[0] == str(self.stubs), "o PATH precisa começar pelos dublês"
        assert not any("omarchy" in part for part in path[1:]), "o PATH não pode ter os comandos do Omarchy"
        for name in STUB_NAMES:
            found = shutil.which(name, path=env["PATH"])
            assert found is None or found.startswith(str(self.stubs)), f"{name} não é dublê: {found}"

    def run(self, *argv, env=None, input=None, timeout=180):
        result = subprocess.run([str(a) for a in argv], env=env or self.env(), cwd=str(self.root), input=input,
                                capture_output=True, text=True, timeout=timeout, start_new_session=True)
        self.wait_shell_writes()
        return result

    def install(self, *args, **extra):
        return self.run("bash", self.src / "install.sh", *args, env=self.env(**extra))

    def uninstall(self, *args, **extra):
        return self.run("bash", self.home / ".local/share/pomar/current/uninstall.sh", *args, env=self.env(**extra))

    def pomar(self, *args, **extra):
        return self.run("bash", self.src / "bin/pomar", *args, env=self.env(**extra))

    def kit(self, *args):
        return self.run("bash", "-c", 'source "$1"; shift; pomar_py "$@"', "kit", self.src / "bin/pomar", *args)

    def wait_shell_writes(self, timeout=15):
        deadline = time.monotonic() + timeout
        while any(self.state.glob("pending-*.json")):
            if time.monotonic() > deadline:
                raise AssertionError("o dublê do shell não terminou de gravar")
            time.sleep(0.05)

    # --------------------------------------------------------- consultas
    def calls(self, cmd=None):
        lines = [json.loads(line) for line in self.log.read_text().splitlines() if line.strip()]
        return [c["args"] for c in lines if cmd is None or c["cmd"] == cmd]

    def reset_calls(self):
        self.log.write_text("")

    def path(self, rel):
        return self.home / rel

    def shell_json(self):
        return json.loads(self.path(".config/omarchy/shell.json").read_text())

    def theme(self):
        return self.path(".local/state/omarchy/current/theme.name").read_text().strip()

    def plugin_ids(self):
        return sorted(p.parent.name for p in self.src.glob("*/manifest.json"))

    def backups(self):
        folder = self.path(".local/state/pomar/backup")
        return sorted(folder.iterdir()) if folder.is_dir() else []


class IsolatedTestCase(unittest.TestCase):
    """Todo teste daqui: nada no HOME real pode mudar."""

    def setUp(self):
        self.real_before = nested.fingerprint()

    def tearDown(self):
        after = nested.fingerprint()
        changed = sorted(rel for rel in set(self.real_before) | set(after) if self.real_before.get(rel) != after.get(rel))
        details = []
        for rel in changed:
            old, new = self.real_before.get(rel), after.get(rel)
            if old and new:
                names = sorted(n for n in set(old[1]) | set(new[1]) if old[1].get(n) != new[1].get(n))
                details.append(f"{rel}: {', '.join(names) or 'a própria pasta'}")
            else:
                details.append(f"{rel}: {'surgiu' if new else 'sumiu'}")
        self.assertEqual(changed, [], "o HOME real mudou durante o teste: " + "; ".join(details))

    def sandbox(self, **options):
        box = Sandbox(**options)
        self.addCleanup(box.close)
        return box

    def assertOk(self, result):
        self.assertEqual(result.returncode, 0, f"saída:\n{result.stdout}\nerros:\n{result.stderr}")

    def assertNoForbiddenCalls(self, box):
        for name in STUBS_FORBIDDEN:
            self.assertEqual(box.calls(name), [], f"{name} não deveria ser chamado")


class ConsentTest(IsolatedTestCase):
    """Nada muda antes de a pessoa dizer sim (o marketplace do Omarchy exige)."""

    def test_without_yes_and_without_a_terminal_nothing_changes(self):
        box = self.sandbox()
        before = tree_snapshot(box.home)
        result = box.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn("install.sh --yes", result.stderr)
        self.assertEqual(tree_snapshot(box.home), before)


class InstallTest(IsolatedTestCase):
    def test_full_install_puts_every_piece_in_place(self):
        box = self.sandbox()
        original_lua = box.path(".config/hypr/hyprland.lua").read_bytes()
        original_shell = box.path(".config/omarchy/shell.json").read_bytes()
        result = box.install("--yes")
        self.assertOk(result)
        for number in range(1, 12):
            self.assertIn(f"{number}. ", result.stdout)
        self.assertIn("Pronto! O Pomarchy está instalado.", result.stdout)
        self.assertIn(".local/share/pomar/current/uninstall.sh", result.stdout)

        current = box.path(".local/share/pomar/current")
        self.assertTrue(current.is_symlink())
        self.assertTrue(os.readlink(current).startswith("releases/"))
        for rel in ("hypr/pomar.lua", "hypr/json.lua", "bin/pomar", "install.sh", "uninstall.sh", "VERSION",
                    "plugins/pomar.dock/shared/Tokens.js", "applications/pomar-launchpad.desktop",
                    "icons/pomar-settings.svg", "themes/pomarchy/colors.toml"):
            self.assertTrue((current / rel).is_file(), rel)
        self.assertTrue(os.access(current / "bin/pomar", os.X_OK))

        for theme in ("pomarchy", "pomarchy-escuro"):
            link = box.path(f".config/omarchy/themes/{theme}")
            self.assertEqual(os.readlink(link), f"{current}/themes/{theme}")
        for plugin in box.plugin_ids():
            link = box.path(f".config/omarchy/plugins/{plugin}")
            self.assertEqual(os.readlink(link), f"{current}/plugins/{plugin}")
        self.assertEqual(os.readlink(box.path(".local/bin/pomar")), f"{current}/bin/pomar")

        lua = box.path(".config/hypr/hyprland.lua").read_text()
        self.assertEqual(lua.count(BLOCK_BEGIN), 1)
        self.assertIn(REQUIRE_LINE + BLOCK, lua)
        self.assertEqual(lua.replace(BLOCK, "").encode(), original_lua)

        self.assertEqual(json.loads(box.path(".config/pomar/settings.json").read_text()),
                         {"version": 1, "language": "auto"},
                         "os gestos comentados do modelo do Omarchy não são conflito")

        for name, verb in (("pomar-launchpad", "open launchpad"), ("pomar-mission-control", "open mission"),
                           ("pomar-settings", "open settings")):
            desktop = box.path(f".local/share/applications/{name}.desktop").read_text()
            self.assertIn(f'Exec="{current}/bin/pomar" {verb}\n', desktop)
            self.assertIn("Name[en]=", desktop)
            self.assertIn(f"Icon={name}\n", desktop)
            self.assertNotIn("@POMAR_BIN@", desktop)
            icon = box.path(f".local/share/icons/hicolor/scalable/apps/{name}.svg")
            self.assertEqual(icon.read_bytes(), (box.src / f"icons/{name}.svg").read_bytes())
            if shutil.which("desktop-file-validate"):
                check = subprocess.run(["desktop-file-validate", str(box.path(
                    f".local/share/applications/{name}.desktop"))], capture_output=True, text=True)
                self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

        shell = box.shell_json()
        self.assertEqual(shell["idle"], SHELL["idle"])
        self.assertEqual(sorted(e["id"] for e in shell["plugins"]), ENABLED)
        layout = shell["bar"]["layout"]
        self.assertEqual(layout["left"], [{"id": "pomar.menubar"}, {"id": "omarchy.workspaces"}])
        self.assertEqual(layout["center"], [])
        self.assertEqual(layout["right"][-1]["format"], MAC_CLOCK)

        self.assertEqual(box.theme(), "pomarchy")
        self.assertEqual(box.path(".local/state/pomar/previous-theme").read_text().strip(), "tokyo-night")
        self.assertEqual(box.calls("omarchy").count(["theme", "set", "pomarchy"]), 1)
        self.assertEqual([c for c in box.calls("omarchy") if c[:2] == ["plugin", "enable"]], [],
                         "sem shell rodando, as peças são ligadas direto no shell.json")
        self.assertEqual(box.calls("hyprctl"), [], "sem Hyprland rodando, nada de hyprctl")
        validated = [c[2] for c in box.calls("omarchy") if c[:2] == ["plugin", "validate"]]
        self.assertEqual(sorted(Path(v).name for v in validated), box.plugin_ids())
        for folder in validated:
            self.assertIn("/.local/share/pomar/releases/", folder, "valida a pasta de verdade, não o link")
        self.assertNoForbiddenCalls(box)

        backups = box.backups()
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "hypr/hyprland.lua").read_bytes(), original_lua)
        self.assertEqual((backups[0] / "omarchy/shell.json").read_bytes(), original_shell)

    def test_running_twice_changes_nothing(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        ignore = (".local/state/pomar/install.log", ".local/state/pomar/.trava")
        first = tree_snapshot(box.home, ignore)
        box.reset_calls()
        second_run = box.install("--yes")
        self.assertOk(second_run)
        self.assertEqual(first, tree_snapshot(box.home, ignore), "a segunda vez mudou algo")
        self.assertEqual(len(list(box.path(".local/share/pomar/releases").iterdir())), 1)
        self.assertEqual(len(box.backups()), 1, "a segunda vez não tem o que guardar")
        self.assertNotIn(["theme", "set", "pomarchy"], box.calls("omarchy"), "o tema já estava ativo")
        self.assertIn("Já estava ligado", second_run.stdout)

    def test_three_finger_gestures_already_in_use_move_pomar_to_four(self):
        box = self.sandbox(input_lua=INPUT_LUA_CONFLICTS)
        result = box.install("--yes")
        self.assertOk(result)
        settings = json.loads(box.path(".config/pomar/settings.json").read_text())
        self.assertEqual(settings, {"version": 1, "language": "auto",
                                    "gestures": {"spacesFingers": 4, "missionFingers": 4}})
        self.assertIn("Você já usa 3 dedos para os lados em outro gesto; o Pomarchy vai usar 4 para trocar de mesa",
                      result.stdout)
        self.assertIn("o Pomarchy vai usar 4 para o Mission Control", result.stdout)
        self.assertIn("Trocar de mesa: 4 dedos", result.stdout)

    def test_existing_settings_are_kept(self):
        box = self.sandbox(input_lua=INPUT_LUA_CONFLICTS)
        settings = box.path(".config/pomar/settings.json")
        settings.parent.mkdir(parents=True)
        settings.write_text('{"dock": {"iconSize": 60}}\n')
        result = box.install("--yes")
        self.assertOk(result)
        self.assertEqual(settings.read_text(), '{"dock": {"iconSize": 60}}\n')
        self.assertIn("Ajustes mantidos", result.stdout)
        self.assertIn("mude em Ajustes do Pomarchy > Gestos", result.stdout)

    def test_real_folders_with_pomar_names_go_to_backup(self):
        box = self.sandbox()
        theme = box.path(".config/omarchy/themes/pomarchy")
        theme.mkdir()
        (theme / "colors.toml").write_text("meu tema\n")
        plugin = box.path(".config/omarchy/plugins/pomar.dock")
        plugin.mkdir(parents=True)
        (plugin / "Dock.qml").write_text("// meu dock\n")
        result = box.install("--yes")
        self.assertOk(result)
        self.assertTrue(theme.is_symlink())
        self.assertTrue(plugin.is_symlink())
        backup = box.backups()[0]
        self.assertEqual((backup / "themes/pomarchy/colors.toml").read_text(), "meu tema\n")
        self.assertEqual((backup / "plugins/pomar.dock/Dock.qml").read_text(), "// meu dock\n")
        self.assertIn("foi guardado em", result.stdout)

    def test_no_apply_and_no_bar_leave_theme_and_bar_alone(self):
        box = self.sandbox()
        result = box.install("--yes", "--no-apply", "--no-bar")
        self.assertOk(result)
        self.assertEqual(box.theme(), "tokyo-night")
        self.assertFalse(box.path(".local/state/pomar/previous-theme").exists())
        self.assertNotIn("theme", [c[0] for c in box.calls("omarchy")])
        shell = box.shell_json()
        self.assertEqual(shell["bar"], SHELL["bar"])
        self.assertEqual(sorted(e["id"] for e in shell["plugins"]), ENABLED)
        self.assertFalse(box.path(".local/state/pomar/bar-backup.json").exists())
        self.assertIn("omarchy theme set pomarchy", result.stdout)
        self.assertNotIn("10. ", result.stdout)

    def test_no_bar_alone_still_applies_theme(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes", "--no-bar"))
        self.assertEqual(box.theme(), "pomarchy")
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"])

    def test_dark_option_applies_the_dark_theme(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes", "--dark"))
        self.assertEqual(box.theme(), "pomarchy-escuro")

    def test_hyprland_error_after_the_block_rolls_it_back(self):
        box = self.sandbox(hypr=True, POMAR_STUB_BLOCK_ERROR="1")
        original = box.path(".config/hypr/hyprland.lua").read_bytes()
        result = box.install("--yes")
        self.assertOk(result)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_bytes(), original)
        self.assertGreaterEqual(box.calls("hyprctl").count(["reload"]), 2)
        self.assertIn(["configerrors"], box.calls("hyprctl"))
        self.assertIn("Tirei o bloco do Pomarchy", result.stdout)
        self.assertIn("gestos e atalhos do Pomarchy ficaram desligados", result.stdout)
        self.assertTrue(box.path(".config/omarchy/plugins/pomar.dock").is_symlink(), "o resto continua")
        self.assertEqual(box.theme(), "pomarchy")

    def test_hyprland_error_once_the_theme_is_active_rolls_the_block_back(self):
        box = self.sandbox(hypr=True, POMAR_STUB_THEME_ERROR="1")
        original = box.path(".config/hypr/hyprland.lua").read_bytes()
        result = box.install("--yes")
        self.assertOk(result)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_bytes(), original)
        self.assertIn("Tirei o bloco do Pomarchy", result.stdout)
        self.assertEqual(box.theme(), "pomarchy")

    def test_errors_the_person_already_had_are_not_blamed_on_pomar(self):
        box = self.sandbox(hypr=True, POMAR_STUB_USER_ERROR="input.lua:3: erro antigo da pessoa")
        result = box.install("--yes")
        self.assertOk(result)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_text().count(BLOCK_BEGIN), 1)
        self.assertNotIn("Tirei o bloco", result.stdout)
        self.assertIn("Hyprland recarregado, sem erros", result.stdout)

    def test_running_shell_is_asked_and_its_late_writes_do_not_undo_the_bar(self):
        # O dublê do shell grava o shell.json 0,3 s depois de responder, como o
        # de verdade faz de forma assíncrona: o instalador precisa esperar.
        box = self.sandbox(shell=True, hypr=True, POMAR_STUB_SHELL_WRITE_DELAY="0.3")
        result = box.install("--yes")
        self.assertOk(result)
        omarchy_calls = box.calls("omarchy")
        enables = [c[2] for c in omarchy_calls if c[:2] == ["plugin", "enable"]]
        self.assertEqual(sorted(enables), ENABLED)
        self.assertNotIn("não ligou na hora", result.stdout, "o shell ligou as peças, sem cair no plano B")
        shell_calls = box.calls("omarchy-shell")
        self.assertIn(["shell", "rescanPlugins"], shell_calls)
        self.assertNotIn(["restart", "shell"], omarchy_calls, "na primeira instalação basta o rescan")
        shell = box.shell_json()
        self.assertEqual(sorted(e["id"] for e in shell["plugins"]), ENABLED)
        self.assertEqual(shell["bar"]["layout"]["left"], [{"id": "pomar.menubar"}, {"id": "omarchy.workspaces"}],
                         "a barra no estilo Mac sobreviveu às gravações atrasadas do shell")
        self.assertEqual(shell["bar"]["layout"]["right"][-1]["format"], MAC_CLOCK)
        self.assertIn(["-q", "shell", "reloadConfig"], shell_calls)
        self.assertNoForbiddenCalls(box)

        uninstall = box.uninstall()
        self.assertOk(uninstall)
        disables = [c[2] for c in box.calls("omarchy") if c[:2] == ["plugin", "disable"]]
        self.assertEqual(sorted(disables), ENABLED)
        self.assertEqual(box.shell_json(), SHELL, "depois de desinstalar, o shell.json diz o mesmo que antes")

    def test_old_omarchy_stops_before_touching_anything(self):
        # O /usr/bin desta máquina tem um omarchy de verdade, então "sem omarchy"
        # não dá para simular com segurança; um Omarchy antigo, sim.
        box = self.sandbox()
        (box.omarchy / "shell/shell.qml").unlink()
        before = tree_snapshot(box.home)
        result = box.install("--yes")
        self.assertEqual(result.returncode, 1)
        self.assertIn("O Pomarchy precisa do Omarchy 4", result.stderr)
        self.assertIn("Nada foi mudado", result.stderr)
        self.assertEqual(before, tree_snapshot(box.home))

    def test_old_hyprland_config_stops_before_touching_anything(self):
        box = self.sandbox()
        lua = box.path(".config/hypr/hyprland.lua")
        lua.rename(lua.with_suffix(".conf"))
        before = tree_snapshot(box.home)
        result = box.install("--yes")
        self.assertEqual(result.returncode, 1)
        self.assertIn("hyprland.conf", result.stderr)
        self.assertEqual(before, tree_snapshot(box.home))

    def test_portuguese_system_gets_portuguese_settings(self):
        box = self.sandbox()
        (box.root / "sistema/etc/vconsole.conf").write_text("KEYMAP=br-abnt2\n")
        result = box.install("--yes", "--no-apply", "--no-bar")
        self.assertOk(result)
        self.assertEqual(json.loads(box.path(".config/pomar/settings.json").read_text())["language"], "pt")
        self.assertIn("Idioma: português", result.stdout)

        by_lang = self.sandbox()
        self.assertOk(by_lang.install("--yes", "--no-apply", "--no-bar", LANG="pt_BR.UTF-8"))
        self.assertEqual(json.loads(by_lang.path(".config/pomar/settings.json").read_text())["language"], "pt")

        by_hypr = self.sandbox(input_lua=INPUT_LUA + 'hl.config({ input = { kb_layout = "us,br" } })\n')
        self.assertOk(by_hypr.install("--yes", "--no-apply", "--no-bar"))
        self.assertEqual(json.loads(by_hypr.path(".config/pomar/settings.json").read_text())["language"], "pt")

    def test_missing_shell_json_is_created_and_later_removed(self):
        box = self.sandbox(shell_json=None)
        self.assertOk(box.install("--yes"))
        shell = box.shell_json()
        self.assertEqual(shell["bar"]["layout"]["left"], [{"id": "pomar.menubar"}, {"id": "omarchy.workspaces"}])
        self.assertEqual(sorted(e["id"] for e in shell["plugins"]), ENABLED)
        self.assertOk(box.uninstall())
        self.assertFalse(box.path(".config/omarchy/shell.json").exists(),
                         "o Pomarchy criou o arquivo; ao sair, o Omarchy volta a usar o padrão dele")

    def test_linked_hyprland_lua_from_dotfiles_stays_a_link(self):
        box = self.sandbox()
        real = box.path("dotfiles/hypr/hyprland.lua")
        real.parent.mkdir(parents=True)
        lua = box.path(".config/hypr/hyprland.lua")
        real.write_bytes(lua.read_bytes())
        lua.unlink()
        lua.symlink_to(real)
        original = real.read_bytes()
        self.assertOk(box.install("--yes"))
        self.assertTrue(lua.is_symlink())
        self.assertEqual(real.read_text().count(BLOCK_BEGIN), 1)
        self.assertOk(box.uninstall())
        self.assertTrue(lua.is_symlink())
        self.assertEqual(real.read_bytes(), original)

    def test_curl_pipe_clones_the_repository_and_installs_from_it(self):
        box = self.sandbox()
        repo = box.root / "repo"
        shutil.copytree(box.src, repo, symlinks=True)
        env = box.env()
        git = ["git", "-c", "user.name=Pomarchy", "-c", "user.email=pomar@teste", "-c", "init.defaultBranch=main"]
        for command in (["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "Pomarchy de teste"]):
            subprocess.run(git + command, cwd=repo, env=env, check=True, capture_output=True)
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=repo, env=env, check=True,
                             capture_output=True, text=True).stdout.strip()
        script = (box.src / "install.sh").read_text()
        env = box.env(POMAR_REPO=f"file://{repo}")
        for attempt in range(2):
            result = box.run("bash", "-s", "--", "--yes", env=env, input=script)
            self.assertOk(result)
            self.assertIn("Baixando o Pomarchy", result.stdout)
            self.assertEqual(os.readlink(box.path(".local/share/pomar/current")), f"releases/{sha}")
            self.assertTrue((box.path(".local/share/pomar/src") / ".git").is_dir())
        self.assertEqual(sorted(p.name for p in box.path(".local/share/pomar/releases").iterdir()), [sha])
        self.assertEqual(box.theme(), "pomarchy")


class PromptTest(IsolatedTestCase):
    """Num terminal de verdade (PTY), sem --yes, o instalador pergunta uma vez."""

    def run_in_terminal(self, box, answer, prompt=b"[S/n]", **extra):
        env = box.env(**extra)
        script = str(box.src / "install.sh")
        pid, fd = pty.fork()
        if pid == 0:  # processo filho: vira o instalador, com o PTY como terminal
            try:
                os.chdir(box.root)
                os.execve("/bin/bash", ["bash", script], env)
            finally:
                os._exit(127)
        output, answered = b"", False
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 1)
            if not ready:
                continue
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
            if not answered and prompt in output:
                os.write(fd, answer)
                answered = True
        _, status = os.waitpid(pid, 0)
        os.close(fd)
        box.wait_shell_writes()
        text = output.decode("utf-8", "replace")
        self.assertTrue(answered, f"não perguntou nada:\n{text}")
        self.assertEqual(os.waitstatus_to_exitcode(status), 0, text)
        return text

    def test_answering_no_changes_nothing(self):
        # Pergunta antes de mudar qualquer coisa, dizendo o que vai mudar.
        box = self.sandbox()
        before = tree_snapshot(box.home)
        text = self.run_in_terminal(box, b"n\n")
        self.assertEqual(text.count("[S/n]"), 1)
        self.assertIn("hyprland.lua", text)
        self.assertIn("Nada foi mudado.", text)
        self.assertEqual(tree_snapshot(box.home), before)

    def test_ctrl_d_is_not_yes(self):
        box = self.sandbox()
        before = tree_snapshot(box.home)
        text = self.run_in_terminal(box, b"\x04")
        self.assertIn("Nada foi mudado.", text)
        self.assertEqual(tree_snapshot(box.home), before)

    def test_english_prompt_says_y_n_and_no_changes_nothing(self):
        box = self.sandbox(lang=None)
        before = tree_snapshot(box.home)
        text = self.run_in_terminal(box, b"n\n", prompt=b"[Y/n]")
        self.assertEqual(text.count("Install? [Y/n]"), 1)
        self.assertNotIn("[S/n]", text)
        self.assertIn("Pomarchy will:", text)
        self.assertIn("Nothing was changed.", text)
        self.assertEqual(tree_snapshot(box.home), before)

    def test_pressing_enter_installs_and_applies_with_one_question(self):
        box = self.sandbox()
        text = self.run_in_terminal(box, b"\n")
        self.assertEqual(text.count("[S/n]"), 1, "uma pergunta só")
        self.assertEqual(box.theme(), "pomarchy")
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"], [{"id": "pomar.menubar"}, {"id": "omarchy.workspaces"}])


# Letras que só o português usa: nenhuma pode sobrar numa saída em inglês.
PORTUGUESE = re.compile("[ãõçáéíóúâêôàÃÕÇÁÉÍÓÚÂÊÔÀ]")


class LanguageTest(IsolatedTestCase):
    """Inglês por padrão; português com --lang pt, POMAR_LANG=pt, "language": "pt"
    nos ajustes ou o sistema em português. Vale a primeira regra que decide."""

    # (ambiente, ajustes, opções, idioma). O ambiente base tem LANG e LC_ALL C.UTF-8.
    CASES = (
        ({}, None, (), "en"),
        ({"POMAR_LANG": "pt"}, None, (), "pt"),
        ({"POMAR_LANG": "EN", "LANG": "pt_BR.UTF-8"}, None, (), "en"),
        ({"POMAR_LANG": "fr"}, None, (), "en"),
        ({}, '{\n  "version": 1,\n  "language": "pt"\n}\n', (), "pt"),
        ({"LANG": "pt_BR.UTF-8"}, '{"language":"en"}', (), "en"),
        ({"LANG": "pt_BR.UTF-8"}, '{"language": "auto"}', (), "pt"),
        ({}, "{ não é json", (), "en"),
        ({"LANGUAGE": "pt_BR:en"}, None, (), "pt"),
        ({"LC_MESSAGES": "pt_PT.UTF-8"}, None, (), "pt"),
        ({"LC_ALL": "pt_BR.UTF-8"}, None, (), "pt"),
        ({"POMAR_LANG": "en"}, '{"language": "en"}', ("--lang", "pt"), "pt"),
        ({"POMAR_LANG": "pt"}, None, ("--lang=EN",), "en"),
    )

    def test_every_entry_point_picks_the_same_language(self):
        # O install.sh lido da entrada padrão e uma cópia solta do uninstall.sh
        # não têm o bin/pomar ao lado: usam a cópia da regra, que decide igual.
        box = self.sandbox(lang=None)
        stray = box.root / "solto/uninstall.sh"
        stray.parent.mkdir()
        shutil.copy(box.src / "uninstall.sh", stray)
        script = (box.src / "install.sh").read_text()
        settings = box.path(".config/pomar/settings.json")
        settings.parent.mkdir(parents=True)
        entry_points = {
            "pomar": lambda env, args: box.run("bash", box.src / "bin/pomar", *args, "help", env=env),
            "install.sh": lambda env, args: box.run("bash", box.src / "install.sh", *args, "--help", env=env),
            "uninstall.sh": lambda env, args: box.run("bash", box.src / "uninstall.sh", *args, "--help", env=env),
            "install.sh sozinho": lambda env, args: box.run("bash", "-s", "--", *args, "--help", env=env, input=script),
            "uninstall.sh solto": lambda env, args: box.run("bash", stray, *args, "--help", env=env),
        }
        for extra, text, args, expected in self.CASES:
            if text is None:
                settings.unlink(missing_ok=True)
            else:
                settings.write_text(text)
            for name, run in entry_points.items():
                with self.subTest(env=extra, settings=text, args=args, entry=name):
                    result = run(box.env(**extra), args)
                    self.assertOk(result)
                    wanted, other = ("Uso:", "Usage:") if expected == "pt" else ("Usage:", "Uso:")
                    self.assertIn(wanted, result.stdout)
                    self.assertNotIn(other, result.stdout)

        settings.unlink(missing_ok=True)
        missing = box.run("bash", stray)
        self.assertEqual(missing.returncode, 1)
        self.assertIn("Couldn't find the Pomarchy files", missing.stderr)
        missing = box.run("bash", stray, env=box.env(POMAR_LANG="pt"))
        self.assertIn("Não achei os arquivos do Pomarchy (bin/pomar); não há o que desinstalar.", missing.stderr)

    def assertEnglish(self, text):
        leftover = [line for line in text.splitlines() if PORTUGUESE.search(line)]
        self.assertEqual(leftover, [], "sobrou português")

    def test_plain_install_and_uninstall_speak_english(self):
        box = self.sandbox(lang=None)
        result = box.install("--yes")
        self.assertOk(result)
        self.assertIn("1. Checking this computer", result.stdout)
        self.assertIn("Done! Pomarchy is installed.", result.stdout)
        self.assertIn("Switch desktops: swipe sideways with 3 fingers", result.stdout)
        self.assertEnglish(result.stdout + result.stderr)
        doctor = box.run("bash", box.path(".local/bin/pomar"), "doctor")
        self.assertOk(doctor)
        self.assertIn("All good.", doctor.stdout)
        self.assertIn("Current theme: Pomarchy", doctor.stdout)
        self.assertIn("Mac-style menu bar", doctor.stdout)
        self.assertEnglish(doctor.stdout)
        uninstall = box.uninstall()
        self.assertOk(uninstall)
        self.assertIn("Done: Pomarchy has been uninstalled.", uninstall.stdout)
        self.assertEnglish(uninstall.stdout + uninstall.stderr)

    def test_doctor_explains_problems_in_english(self):
        box = self.sandbox(lang=None)
        self.assertOk(box.install("--yes"))
        box.path(".config/omarchy/plugins/pomar.dock").unlink()
        doctor = box.run("bash", box.path(".local/bin/pomar"), "doctor")
        self.assertEqual(doctor.returncode, 1)
        self.assertIn("Plugins missing in", doctor.stdout)
        self.assertIn("How to fix: run the installer again.", doctor.stdout)
        self.assertEnglish(doctor.stdout)

    def test_lang_pt_settings_pt_and_a_portuguese_system_give_portuguese(self):
        for how, extra, settings, args in (("--lang pt", {}, None, ("--lang", "pt")),
                                           ("ajustes", {}, '{"version": 1, "language": "pt"}\n', ()),
                                           ("LANG", {"LANG": "pt_BR.UTF-8"}, None, ())):
            with self.subTest(how):
                box = self.sandbox(lang=None)
                if settings is not None:
                    box.path(".config/pomar").mkdir(parents=True)
                    box.path(".config/pomar/settings.json").write_text(settings)
                result = box.install("--yes", *args, **extra)
                self.assertOk(result)
                self.assertIn("1. Conferindo o computador", result.stdout)
                self.assertIn("Pronto! O Pomarchy está instalado.", result.stdout)
                doctor = box.run("bash", box.path(".local/bin/pomar"), *args, "doctor", env=box.env(**extra))
                self.assertIn("Tudo certo.", doctor.stdout)
                uninstall = box.uninstall(*args, **extra)
                self.assertOk(uninstall)
                self.assertIn("Pronto: o Pomarchy foi desinstalado.", uninstall.stdout)
        box = self.sandbox()  # POMAR_LANG=pt, mas o --lang en vale mais
        english = box.install("--yes", "--lang", "en")
        self.assertIn("Done! Pomarchy is installed.", english.stdout)

    def test_an_unknown_language_stops_before_anything(self):
        box = self.sandbox(lang=None)
        before = tree_snapshot(box.home)
        for name, result in (("install.sh", box.install("--yes", "--lang", "fr")),
                             ("uninstall.sh", box.run("bash", box.src / "uninstall.sh", "--lang")),
                             ("pomar", box.pomar("--lang", "xx", "doctor"))):
            with self.subTest(name):
                self.assertEqual(result.returncode, 2)
                self.assertIn("Unknown language", result.stderr)
                self.assertIn("Usage:", result.stderr)
        result = box.install("--yes", "--lang=de", POMAR_LANG="pt")
        self.assertEqual(result.returncode, 2)
        self.assertIn('Idioma desconhecido: "de" (use en ou pt)', result.stderr)
        # Como antes: vale a primeira opção que encerra.
        self.assertEqual(box.install("--help", "--nao-existe").returncode, 0)
        self.assertEqual(box.install("--nao-existe", "--help").returncode, 2)
        self.assertEqual(tree_snapshot(box.home), before)


class UninstallTest(IsolatedTestCase):
    def test_uninstall_gives_back_the_exact_files(self):
        box = self.sandbox()
        original_lua = box.path(".config/hypr/hyprland.lua").read_bytes()
        original_shell = box.path(".config/omarchy/shell.json").read_bytes()
        self.assertOk(box.install("--yes"))
        result = box.uninstall()
        self.assertOk(result)
        self.assertIn("Pronto: o Pomarchy foi desinstalado.", result.stdout)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_bytes(), original_lua)
        self.assertEqual(box.path(".config/omarchy/shell.json").read_bytes(), original_shell)
        self.assertEqual(box.theme(), "tokyo-night")
        for folder in (".config/omarchy/themes", ".config/omarchy/plugins"):
            self.assertEqual(list(box.path(folder).iterdir()), [], folder)
        self.assertFalse(box.path(".local/bin/pomar").exists())
        self.assertFalse(box.path(".local/bin/pomar").is_symlink())
        self.assertEqual(list(box.path(".local/share/applications").glob("pomar-*")), [])
        self.assertEqual(list(box.path(".local/share/icons/hicolor/scalable/apps").glob("pomar-*")), [])
        self.assertTrue(box.path(".config/pomar/settings.json").is_file(), "os ajustes ficam")
        self.assertTrue(box.path(".local/share/pomar/current/uninstall.sh").is_file(), "as versões ficam")
        for gone in ("previous-theme", "bar-backup.json"):
            self.assertFalse(box.path(f".local/state/pomar/{gone}").exists(), gone)
        self.assertNoForbiddenCalls(box)

        again = box.uninstall()
        self.assertOk(again)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_bytes(), original_lua)
        self.assertEqual(box.path(".config/omarchy/shell.json").read_bytes(), original_shell)

    def test_uninstall_only_removes_what_is_pomars(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        mine = box.path(".config/omarchy/themes/meu-tema")
        mine.mkdir()
        other = box.path(".config/omarchy/plugins/meu.relogio")
        other.symlink_to(box.root / "fora-do-pomar")
        desktop = box.path(".local/share/applications/pomar-notas.desktop")
        desktop.write_text("[Desktop Entry]\nType=Application\nName=Notas\nExec=notas\n")
        self.assertOk(box.uninstall())
        self.assertTrue(mine.is_dir())
        self.assertTrue(other.is_symlink())
        self.assertTrue(desktop.is_file(), "um .desktop sem a marca X-Pomar não é do Pomarchy")

    def test_purge_removes_pomar_files_but_keeps_backups(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        result = box.uninstall("--purge")
        self.assertOk(result)
        self.assertFalse(box.path(".config/pomar").exists())
        self.assertFalse(box.path(".local/share/pomar").exists())
        state = box.path(".local/state/pomar")
        self.assertEqual(sorted(p.name for p in state.iterdir()), ["backup"])
        self.assertTrue(any(state.glob("backup/*/hypr/hyprland.lua")))
        self.assertIn("Cópias de segurança", result.stdout)

    def test_uninstall_goes_back_to_the_default_theme_when_the_previous_is_unknown(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        box.path(".local/state/pomar/previous-theme").unlink()
        self.assertOk(box.uninstall())
        self.assertEqual(box.theme(), "tokyo-night")


class ReviewFixesTest(IsolatedTestCase):
    """Achados da revisão cruzada (Codex): cada teste falhava antes da correção."""

    def test_c7_block_never_lands_inside_a_split_require(self):
        split = HYPRLAND_LUA.replace(REQUIRE_LINE, 'require("default.hypr.omarchy"\n)\n')
        box = self.sandbox(hypr_lua=split)
        self.assertOk(box.install("--yes"))
        text = box.path(".config/hypr/hyprland.lua").read_text()
        self.assertIn('require("default.hypr.omarchy"\n)\n', text, "o bloco não entra no meio da expressão")
        self.assertEqual(text.count("-- >>> pomar >>>"), 1)
        if shutil.which("luac"):
            check = subprocess.run(["luac", "-p", "-"], input=text, capture_output=True, text=True)
            self.assertEqual(check.returncode, 0, check.stderr)

    @unittest.skipUnless(shutil.which("luac"), "precisa do luac")
    def test_c7_a_hyprland_lua_that_would_not_parse_is_left_alone(self):
        broken = HYPRLAND_LUA + "hl.config({ general = { gaps_in = 2 }\n"
        box = self.sandbox(hypr_lua=broken)
        result = box.install("--yes")
        self.assertOk(result)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_text(), broken, "não grava o que não passa no luac")
        self.assertIn("erro de Lua", result.stdout)
        self.assertTrue(box.path(".config/omarchy/plugins/pomar.dock").is_symlink(), "o resto continua")

    def test_r1_uninstall_brings_minimized_windows_back_first(self):
        box = self.sandbox(hypr=True)
        self.assertOk(box.install("--yes"))
        clients = [
            {"address": "0x1a2b", "class": "foot", "workspace": {"id": -98, "name": "special:pomar-minimized"}},
            {"address": "0x3c4d", "class": "firefox", "workspace": {"id": -98, "name": "special:pomar-minimized"}},
            {"address": "0x5e6f", "class": "nautilus", "workspace": {"id": 3, "name": "3"}},
        ]
        (box.state / "clients.json").write_text(json.dumps(clients))
        (box.state / "activeworkspace.json").write_text('{"id": 2, "name": "2"}')
        box.reset_calls()
        self.assertOk(box.uninstall())
        moves = [c for c in box.calls("hyprctl") if c[:1] == ["dispatch"]]
        self.assertEqual(moves, [
            ["dispatch", 'hl.dsp.window.move({ window = "address:0x1a2b", workspace = "2", follow = false })'],
            ["dispatch", 'hl.dsp.window.move({ window = "address:0x3c4d", workspace = "2", follow = false })'],
        ])
        after = json.loads((box.state / "clients.json").read_text())
        self.assertEqual([c["workspace"]["name"] for c in after], ["2", "2", "3"])
        log = [json.loads(line) for line in box.log.read_text().splitlines()]
        first_move = next(i for i, c in enumerate(log) if c["cmd"] == "hyprctl" and c["args"][:1] == ["dispatch"])
        first_theme = next(i for i, c in enumerate(log) if c["cmd"] == "omarchy" and c["args"][:2] == ["theme", "set"])
        self.assertLess(first_move, first_theme, "as janelas voltam antes de desligar qualquer coisa")

    def test_c3_what_was_moved_aside_comes_back_on_uninstall(self):
        box = self.sandbox()
        theme = box.path(".config/omarchy/themes/pomarchy")
        theme.mkdir()
        (theme / "colors.toml").write_text("meu tema\n")
        plugin = box.path(".config/omarchy/plugins/pomar.dock")
        plugin.mkdir(parents=True)
        (plugin / "Dock.qml").write_text("// meu dock\n")
        desktop = box.path(".local/share/applications/pomar-launchpad.desktop")
        desktop.parent.mkdir(parents=True)
        desktop.write_text("[Desktop Entry]\nType=Application\nName=Meu Launchpad\nExec=meu\n")
        command = box.path(".local/bin/pomar")
        command.parent.mkdir(parents=True)
        command.write_text("#!/bin/sh\necho meu pomar\n")
        self.assertOk(box.install("--yes"))
        self.assertTrue(theme.is_symlink())
        result = box.uninstall()
        self.assertOk(result)
        self.assertEqual((theme / "colors.toml").read_text(), "meu tema\n")
        self.assertFalse(theme.is_symlink())
        self.assertEqual((plugin / "Dock.qml").read_text(), "// meu dock\n")
        self.assertIn("Name=Meu Launchpad", desktop.read_text())
        self.assertEqual(command.read_text(), "#!/bin/sh\necho meu pomar\n")
        self.assertIn("voltou para o lugar", result.stdout)

    def test_c8_uninstall_stops_before_removing_themes_when_no_theme_applies(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        result = box.uninstall(POMAR_STUB_THEME_FAIL="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("parei antes de tirar", result.stderr)
        self.assertTrue(box.path(".config/omarchy/themes/pomarchy").is_symlink(), "o tema em uso continua existindo")
        self.assertTrue(box.path(".local/state/pomar/previous-theme").is_file(), "o tema de antes não é esquecido")
        self.assertTrue(box.path(".config/omarchy/plugins/pomar.dock").is_symlink())
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_text().count("-- >>> pomar >>>"), 1)
        self.assertOk(box.uninstall())
        self.assertEqual(box.theme(), "tokyo-night")
        self.assertFalse(box.path(".local/state/pomar/previous-theme").exists())

    def test_c4_uninstall_rewrites_the_bar_when_the_shell_puts_the_old_one_back(self):
        box = self.sandbox(shell=True)
        self.assertOk(box.install("--yes"))
        (box.state / "clobber-left").write_text("1")
        self.assertOk(box.uninstall())
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"])
        self.assertFalse(box.path(".local/state/pomar/bar-backup.json").exists())

    def test_c4_uninstall_stops_when_the_bar_never_sticks(self):
        box = self.sandbox(shell=True)
        self.assertOk(box.install("--yes"))
        (box.state / "clobber-left").write_text("99")
        result = box.uninstall("--purge")
        self.assertEqual(result.returncode, 1, "sem a barra de volta, o desinstalador para")
        self.assertTrue(box.path(".local/state/pomar/bar-backup.json").is_file(), "a barra original não se perde")
        self.assertTrue(os.path.lexists(box.path(".local/bin/pomar")), "o pomar bar restore continua à mão")
        (box.state / "clobber-left").write_text("0")
        self.assertOk(box.uninstall("--purge"))
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"])

    def test_c5_empty_shell_json_comes_back_empty_with_a_running_shell(self):
        # O shell enche o arquivo vazio ao ligar as peças e grava por cima uma
        # vez na volta: mesmo assim, termina vazio como era.
        box = self.sandbox(shell=True, shell_json="")
        self.assertOk(box.install("--yes"))
        (box.state / "clobber-left").write_text("1")
        self.assertOk(box.uninstall())
        self.assertEqual(box.path(".config/omarchy/shell.json").read_bytes(), b"")
        self.assertFalse(box.path(".local/state/pomar/shell-json-criado").exists())

    def test_r1_uninstall_stops_when_a_minimized_window_does_not_come_back(self):
        box = self.sandbox(hypr=True, POMAR_STUB_DISPATCH_ERROR="1")
        self.assertOk(box.install("--yes"))
        clients = [{"address": "0x1a2b", "class": "foot", "workspace": {"id": -98, "name": "special:pomar-minimized"}}]
        (box.state / "clients.json").write_text(json.dumps(clients))
        result = box.uninstall()
        self.assertEqual(result.returncode, 1)
        self.assertIn("não voltaram para a mesa", result.stderr)
        self.assertEqual(box.theme(), "pomarchy", "parou antes de trocar o tema")
        self.assertTrue(box.path(".config/omarchy/plugins/pomar.dock").is_symlink(), "nada foi desligado")

    def test_13_pomar_lua_that_fails_is_blamed_even_with_another_new_error(self):
        box = self.sandbox(hypr=True, POMAR_STUB_LOAD_ERROR="1", POMAR_STUB_LATE_ERROR="monitors.lua:3: erro novo da pessoa")
        original = box.path(".config/hypr/hyprland.lua").read_bytes()
        result = box.install("--yes")
        self.assertOk(result)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_bytes(), original, "o bloco que não carrega sai")
        self.assertIn("Tirei o bloco do Pomarchy", result.stdout)

    def test_uninstall_takes_pomarchy_out_of_a_saved_bar_that_had_it(self):
        shell = json.loads(json.dumps(SHELL))
        shell["bar"]["layout"]["left"] = [{"id": "pomar.menubar"}] + shell["bar"]["layout"]["left"]
        box = self.sandbox(shell_json=shell)
        self.assertOk(box.install("--yes"))
        self.assertOk(box.uninstall())
        ids = [e["id"] for name in ("left", "center", "right") for e in box.shell_json()["bar"]["layout"][name]]
        self.assertNotIn("pomar.menubar", ids)

    def test_theme_hook_gives_the_omarchy_bar_back_outside_pomarchy(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        hook = box.path(".config/omarchy/hooks/theme-set.d/50-pomarchy")
        self.assertTrue(hook.is_symlink())
        self.assertEqual(os.readlink(hook), str(box.path(".local/share/pomar/current/hooks/theme-set")))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"][0], {"id": "pomar.menubar"})
        theme = box.path(".local/state/omarchy/current/theme.name")

        theme.write_text("tokyo-night\n")  # o omarchy-theme-set grava o nome e chama o gancho
        self.assertOk(box.run("bash", hook, "tokyo-night", env=box.env()))
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"], "fora do Pomarchy, a barra do Omarchy")

        theme.write_text("pomarchy\n")
        self.assertOk(box.run("bash", hook, "pomarchy", env=box.env()))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"][0], {"id": "pomar.menubar"})

        self.assertOk(box.uninstall())
        self.assertFalse(os.path.lexists(hook), "o gancho sai junto")
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"])

    def test_install_without_theme_on_another_theme_keeps_the_omarchy_bar(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes", "--no-apply"))
        self.assertEqual(box.theme(), "tokyo-night")
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"], "o tema não é Pomarchy: a barra fica a do Omarchy")
        self.assertFalse(box.path(".local/state/pomar/bar-backup.json").exists())

    def test_r1_uninstall_stops_when_hyprland_does_not_list_the_windows(self):
        box = self.sandbox(hypr=True)
        self.assertOk(box.install("--yes"))
        result = box.uninstall(POMAR_STUB_CLIENTS_FAIL="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("pelas janelas minimizadas", result.stderr)
        self.assertEqual(box.theme(), "pomarchy", "parou antes de trocar o tema")

    def test_restored_bar_backup_is_kept_in_the_backup_folder(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        self.assertOk(box.uninstall())
        self.assertFalse(box.path(".local/state/pomar/bar-backup.json").exists())
        kept = list(box.path(".local/state/pomar/backup").glob("barra-*.json"))
        self.assertEqual(len(kept), 1, "a barra original fica guardada, não é apagada")
        self.assertEqual(json.loads(kept[0].read_text())["bar"], SHELL["bar"])

    def test_no_bar_holds_when_the_theme_changes(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes", "--no-bar"))  # o tema é aplicado e o gancho roda
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"], "--no-bar: a barra do Omarchy fica")
        self.assertOk(box.run("omarchy", "theme", "set", "pomarchy"))
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"], "nem numa troca de tema depois")

    def test_bar_restore_is_a_lasting_choice_and_bar_mac_undoes_it(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        self.assertOk(box.pomar("bar", "restore"))
        self.assertOk(box.run("omarchy", "theme", "set", "pomarchy"))
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"], "o gancho não desfaz o pomar bar restore")
        self.assertOk(box.pomar("bar", "mac"))
        self.assertOk(box.run("omarchy", "theme", "set", "tokyo-night"))
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"], "fora do Pomarchy, a barra do Omarchy")
        self.assertOk(box.run("omarchy", "theme", "set", "pomarchy"))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"][0], {"id": "pomar.menubar"})

    def test_updating_from_the_installed_copy_asks_before_downloading(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        installed = box.path(".local/share/pomar/current/install.sh")
        before = tree_snapshot(box.home)
        result = box.run("bash", installed, env=box.env(POMAR_REPO="file:///nao/existe"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("antes de baixar", result.stderr)
        self.assertEqual(tree_snapshot(box.home), before, "nada baixado nem movido sem o sim")

    def test_uninstall_stops_on_a_cut_off_window_list(self):
        box = self.sandbox(hypr=True)
        self.assertOk(box.install("--yes"))
        result = box.uninstall(POMAR_STUB_CLIENTS_TRUNCATED="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(box.theme(), "pomarchy", "parou antes de trocar o tema")

    def test_the_bar_choice_never_touches_the_settings_file(self):
        box = self.sandbox()
        settings = box.path(".config/pomar/settings.json")
        settings.parent.mkdir(parents=True)
        settings.write_text('{"dock": {"favorites": ["foot"],}}\n')  # vírgula a mais, feita à mão
        before = settings.read_bytes()
        self.assertOk(box.install("--yes", "--no-bar"))
        self.assertOk(box.pomar("bar", "restore"))
        self.assertOk(box.pomar("bar", "mac"))
        self.assertEqual(settings.read_bytes(), before, "os ajustes da pessoa ficam como estão")

    def test_turning_off_the_system_menu_keeps_the_mac_bar(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        settings = box.path(".config/pomar/settings.json")
        data = json.loads(settings.read_text())
        data["menubar"] = {"enabled": False}  # Ajustes > Barra > Menu do sistema desligado
        settings.write_text(json.dumps(data))
        self.assertOk(box.run("omarchy", "theme", "set", "pomarchy"))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"][0], {"id": "pomar.menubar"})

    def test_an_update_keeps_the_omarchy_bar_that_was_chosen(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        self.assertOk(box.pomar("bar", "restore"))
        self.assertOk(box.install("--yes"))
        self.assertEqual(box.shell_json()["bar"], SHELL["bar"], "a atualização respeita a barra escolhida")

    def test_c5_empty_shell_json_comes_back_empty(self):
        box = self.sandbox(shell_json="")
        self.assertOk(box.install("--yes"))
        self.assertEqual(box.shell_json()["bar"]["layout"]["left"][0], {"id": "pomar.menubar"})
        self.assertOk(box.uninstall())
        path = box.path(".config/omarchy/shell.json")
        self.assertTrue(path.is_file(), "vazio não é o mesmo que não existir")
        self.assertEqual(path.read_bytes(), b"")

    def test_c5_linked_shell_json_is_never_deleted(self):
        box = self.sandbox(shell_json=None)
        target = box.path("dotfiles/omarchy/shell.json")
        target.parent.mkdir(parents=True)
        link = box.path(".config/omarchy/shell.json")
        link.symlink_to(target)
        self.assertOk(box.install("--yes"))
        self.assertTrue(link.is_symlink())
        self.assertOk(box.uninstall())
        self.assertTrue(link.is_symlink(), "o link dos dotfiles continua")
        self.assertEqual(os.readlink(link), str(target))
        self.assertEqual(json.loads(target.read_text()), SHELL)

    def test_c6_uninstall_keeps_pomar_named_entries_that_are_not_pomarchy(self):
        shell = json.loads(json.dumps(SHELL))
        shell["plugins"] = [{"id": "pomar.meu-widget"}]
        shell["bar"]["layout"]["right"].append({"id": "pomar.relogio-mundial", "zona": "Lisboa"})
        box = self.sandbox(shell_json=shell)
        original = box.path(".config/omarchy/shell.json").read_bytes()
        self.assertOk(box.install("--yes"))
        self.assertOk(box.uninstall())
        self.assertEqual(box.path(".config/omarchy/shell.json").read_bytes(), original)

    def test_c1_bootstrap_moves_the_old_copy_to_backup(self):
        box = self.sandbox()
        repo = box.root / "repo"
        shutil.copytree(box.src, repo, symlinks=True)
        env = box.env()
        git = ["git", "-c", "user.name=Pomarchy", "-c", "user.email=pomar@teste", "-c", "init.defaultBranch=main"]
        for command in (["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "Pomarchy de teste"]):
            subprocess.run(git + command, cwd=repo, env=env, check=True, capture_output=True)
        script = (box.src / "install.sh").read_text()
        env = box.env(POMAR_REPO=f"file://{repo}")
        self.assertOk(box.run("bash", "-s", "--", "--yes", env=env, input=script))
        first = subprocess.run(["git", "rev-parse", "HEAD"], cwd=box.path(".local/share/pomar/src"), env=env,
                               capture_output=True, text=True, check=True).stdout
        self.assertOk(box.run("bash", "-s", "--", "--yes", env=env, input=script))
        kept = [p for p in box.backups() if p.name.endswith("-src")]
        self.assertEqual(len(kept), 1, "mesmo limpa, a cópia anterior vai para o backup, nunca para o lixo")
        moved = subprocess.run(["git", "rev-parse", "HEAD"], cwd=kept[0], env=env, capture_output=True, text=True,
                               check=True).stdout
        self.assertEqual(moved, first)

    def test_r3_an_old_error_that_only_moved_lines_is_not_blamed_on_pomarchy(self):
        lua = HYPRLAND_LUA + 'hl.config({ misc = { nao_existe = true } }) -- erro-da-pessoa\n'
        box = self.sandbox(hypr=True, hypr_lua=lua, POMAR_STUB_USER_ERROR_MARK="erro-da-pessoa")
        result = box.install("--yes")
        self.assertOk(result)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_text().count("-- >>> pomar >>>"), 1)
        self.assertNotIn("Tirei o bloco", result.stdout)

    def test_13_block_warns_and_installer_rolls_back_when_pomar_lua_fails_to_load(self):
        box = self.sandbox(hypr=True, POMAR_STUB_LOAD_ERROR="1")
        original = box.path(".config/hypr/hyprland.lua").read_bytes()
        result = box.install("--yes")
        self.assertOk(result)
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_bytes(), original)
        self.assertIn("pomar.lua:42: erro simulado ao carregar", result.stdout)
        self.assertIn("Tirei o bloco do Pomarchy", result.stdout)
        doctor = box.run("bash", box.path(".local/bin/pomar"), "doctor")
        self.assertEqual(doctor.returncode, 1)
        self.assertIn("falta o bloco do Pomarchy", doctor.stdout)
        self.assertIn("rode o instalador de novo", doctor.stdout)

    def test_13_block_text_catches_load_errors_and_notifies(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes", "--no-apply", "--no-bar"))
        text = box.path(".config/hypr/hyprland.lua").read_text()
        block = text[text.index("-- >>> pomar >>>"):text.index("-- <<< pomar <<<")]
        self.assertIn("local ok, err = pcall(dofile,", block)
        self.assertIn('hl.notification.create({ text = "Pomarchy OS failed to load: " .. tostring(err), timeout = 15000 })',
                      block)
        if shutil.which("luac"):
            check = subprocess.run(["luac", "-p", "-"], input=text, capture_output=True, text=True)
            self.assertEqual(check.returncode, 0, check.stderr)

    def test_12_purge_never_deletes_inside_backup(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes"))
        backup = box.path(".local/state/pomar/backup")
        (backup / "minha-anotacao.txt").write_text("importante\n")
        (backup / "pasta-minha").mkdir()
        (backup / "pasta-minha/foto.txt").write_text("foto\n")
        before = tree_snapshot(backup)
        self.assertOk(box.uninstall("--purge"))
        after = tree_snapshot(backup)
        for rel, value in before.items():
            self.assertEqual(after.get(rel), value, rel)


OLD_VERSION = "d8ff529"  # a primeira versão instalada de verdade (30/09/2026)


def has_commit(commit):
    return shutil.which("git") is not None and subprocess.run(
        ["git", "-C", str(REPO), "cat-file", "-e", f"{commit}^{{commit}}"], capture_output=True).returncode == 0


@unittest.skipUnless(has_commit(OLD_VERSION), f"precisa do histórico do git com {OLD_VERSION}")
class UpgradeTest(IsolatedTestCase):
    """Atualizar por cima da versão antiga, instalada de verdade num HOME de teste."""

    def old_source(self, box):
        folder = box.root / "versao-antiga"
        folder.mkdir()
        archive = subprocess.run(["git", "-C", str(REPO), "archive", OLD_VERSION], capture_output=True, check=True)
        subprocess.run(["tar", "-x", "-C", str(folder)], input=archive.stdout, check=True)
        return folder

    def test_upgrade_from_the_old_layout_and_then_uninstall(self):
        shell = json.loads(json.dumps(SHELL))
        shell["bar"]["layout"]["left"] = [{"id": "meu.menu"}, {"id": "omarchy.workspaces"}]
        box = self.sandbox(shell_json=shell)
        manifest = box.path(".config/omarchy/plugins/meu.menu/manifest.json")
        manifest.parent.mkdir(parents=True)
        manifest.write_text(json.dumps({"schemaVersion": 1, "id": "meu.menu", "name": "Meu menu",
                                        "version": "1.0.0", "kinds": ["menu", "bar-widget"],
                                        "entryPoints": {"menu": "Menu.qml", "barWidget": "Widget.qml"}}))
        original_lua = box.path(".config/hypr/hyprland.lua").read_bytes()
        original_shell = box.path(".config/omarchy/shell.json").read_bytes()

        old = box.run("bash", self.old_source(box) / "install.sh", "--yes")
        self.assertOk(old)
        self.assertEqual(box.theme(), "pomar", "a versão antiga ainda chamava o tema de pomar")
        self.assertIn("-- Pomar: gestos", box.path(".config/hypr/hyprland.lua").read_text())

        result = box.install("--yes")
        self.assertOk(result)
        lua = box.path(".config/hypr/hyprland.lua").read_text()
        self.assertEqual(lua.count("-- >>> pomar >>>"), 1)
        self.assertIn(REQUIRE_LINE + BLOCK, lua, "o bloco antigo virou o bloco novo, no mesmo lugar")
        self.assertEqual(box.theme(), "pomarchy")
        self.assertTrue(box.path(".config/omarchy/themes/pomarchy").is_symlink())
        self.assertFalse(os.path.lexists(box.path(".config/omarchy/themes/pomar")), "o link do nome antigo sai")
        self.assertEqual(box.path(".local/state/pomar/previous-theme").read_text().strip(), "tokyo-night")
        current = box.shell_json()
        self.assertEqual(current["bar"]["layout"]["left"], [{"id": "pomar.menubar"}, {"id": "omarchy.workspaces"}],
                         "as mesas que a versão antiga tirou voltam para a barra")
        self.assertIn({"id": "meu.menu"}, current["plugins"],
                      "o menu clonado que a versão antiga tirou da barra volta a ficar ligado")
        self.assertEqual(sorted(e["id"] for e in current["plugins"] if e["id"].startswith("pomar.")), ENABLED)

        self.assertOk(box.uninstall())
        self.assertEqual(box.path(".config/hypr/hyprland.lua").read_bytes(), original_lua)
        self.assertEqual(box.path(".config/omarchy/shell.json").read_bytes(), original_shell)
        self.assertEqual(box.theme(), "tokyo-night")

    def test_update_restarts_a_running_shell(self):
        # Com o shell aberto, as peças antigas continuam na memória dele: mesmo
        # id e versão, o rescanPlugins não troca o código.
        box = self.sandbox(shell=True, hypr=True)
        self.assertOk(box.run("bash", self.old_source(box) / "install.sh", "--yes"))
        box.reset_calls()
        result = box.install("--yes")
        self.assertOk(result)
        calls = box.calls("omarchy")
        self.assertIn(["restart", "shell"], calls)
        first_enable = next(i for i, c in enumerate(calls) if c[:2] == ["plugin", "enable"])
        self.assertLess(calls.index(["restart", "shell"]), first_enable, "o shell novo é que liga as peças")
        self.assertNotIn("próximo login", result.stdout)
        self.assertEqual(sorted(c[2] for c in calls if c[:2] == ["plugin", "enable"]), ENABLED)

    def test_update_that_does_not_touch_the_plugins_keeps_the_shell_running(self):
        box = self.sandbox(shell=True, hypr=True)
        self.assertOk(box.install("--yes"))
        changed = box.root / "fonte-nova"
        shutil.copytree(box.src, changed, symlinks=True)
        with open(changed / "install.sh", "a", encoding="utf-8") as script:
            script.write("# só o instalador mudou\n")
        time.sleep(1.1)  # sem git, o nome da versão tem a hora com segundos
        box.reset_calls()
        result = box.run("bash", changed / "install.sh", "--yes", env=box.env())
        self.assertOk(result)
        self.assertNotIn(["restart", "shell"], box.calls("omarchy"), "peças iguais: o shell não pisca à toa")
        self.assertIn(["shell", "rescanPlugins"], box.calls("omarchy-shell"))

    def test_update_without_theme_says_the_pomarchy_theme_is_still_on(self):
        box = self.sandbox()
        self.assertOk(box.install("--yes", "--dark"))
        result = box.install("--yes", "--no-apply")
        self.assertOk(result)
        self.assertIn("Tema Pomarchy Escuro, com Dock", result.stdout)
        self.assertNotIn("ainda não aparece", result.stdout)

    def test_update_interrupted_after_the_switch_still_restarts_the_shell_next_time(self):
        box = self.sandbox(shell=True, hypr=True)
        self.assertOk(box.run("bash", self.old_source(box) / "install.sh", "--yes"))
        local_bin = box.path(".local/bin")
        local_bin.chmod(0o555)  # o passo 8 (comando pomarchy) falha depois de trocar a versão em uso
        try:
            result = box.install("--yes")
        finally:
            local_bin.chmod(0o755)
        self.assertNotEqual(result.returncode, 0, result.stdout[-600:])
        self.assertTrue(box.path(".local/state/pomar/reiniciar-shell").exists())
        box.reset_calls()
        self.assertOk(box.install("--yes"))
        self.assertIn(["restart", "shell"], box.calls("omarchy"), "a versão já estava trocada: reinicia mesmo assim")
        self.assertFalse(box.path(".local/state/pomar/reiniciar-shell").exists())

    def test_update_with_a_locked_screen_leaves_the_restart_for_later(self):
        box = self.sandbox(shell=True, hypr=True, POMAR_STUB_RESTART_FAIL="1")
        self.assertOk(box.run("bash", self.old_source(box) / "install.sh", "--yes"))
        box.reset_calls()
        result = box.install("--yes")
        self.assertOk(result)
        self.assertIn(["restart", "shell"], box.calls("omarchy"))
        self.assertIn(["shell", "rescanPlugins"], box.calls("omarchy-shell"))
        self.assertIn("omarchy restart shell", result.stdout)
        # Depois de desbloquear: a mesma versão, instalada de novo, reinicia o shell.
        box.reset_calls()
        again = box.install("--yes", POMAR_STUB_RESTART_FAIL="0")
        self.assertOk(again)
        self.assertIn(["restart", "shell"], box.calls("omarchy"))
        self.assertFalse(box.path(".local/state/pomar/reiniciar-shell").exists())

    def test_upgrade_keeps_the_dark_variant(self):
        box = self.sandbox(shell_json=json.loads(json.dumps(SHELL)))
        self.assertOk(box.run("bash", self.old_source(box) / "install.sh", "--yes"))
        # Depois de instalar, a pessoa escolheu o escuro (nome antigo do tema).
        box.path(".local/state/omarchy/current/theme.name").write_text("pomar-escuro\n")
        self.assertOk(box.install("--yes"))
        self.assertEqual(box.theme(), "pomarchy-escuro", "quem usava o escuro continua no escuro")
        self.assertOk(box.install("--yes"))
        self.assertEqual(box.theme(), "pomarchy-escuro")


if __name__ == "__main__":
    unittest.main()
