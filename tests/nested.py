"""Hyprland aninhado numa tela virtual, totalmente isolado, para provar o Pomarchy
sem tocar no desktop nem nos dados de quem está usando a máquina.

Isolamento (trocar só o HOME não basta: o XDG_DATA_HOME da sessão vaza, e um
teste que esvazia a Lixeira esvaziaria a de verdade):
- HOME e TODAS as pastas XDG (config, data, state, cache, runtime) ficam
  dentro de uma pasta temporária; nada é link para o HOME real;
- D-Bus próprio da sessão de teste, e XDG_RUNTIME_DIR próprio, então o
  systemd --user, o portal, o gvfs e o chaveiro da sessão real ficam fora de
  alcance (uwsm-app e systemd-run nem conseguem falar com o systemd real);
- comandos com efeito no sistema (abrir app, lixeira, tema, desligar...) são
  dublês que só anotam a chamada em `stub_calls()`;
- ao fechar, confere se alguma pasta sensível do HOME real mudou e acusa.

O compositor abre com o backend Wayland (a janela aninhada só inicializa a
renderização), cria a saída headless POMAR-TEST e desliga a janela aninhada:
foco e teclas dos testes nunca chegam ao desktop real.
"""
import atexit
import json
import os
import pwd
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OMARCHY = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
OUTPUT = "POMAR-TEST"
MODE = "1920x1200@60"
REAL_HOME = Path(pwd.getpwuid(os.getuid()).pw_dir)
REAL_RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
VPOINTER_SRC = REPO / "tests/vpointer"
_VPOINTER = None


def vpointer_available():
    return all(shutil.which(tool) for tool in ("gcc", "wayland-scanner", "pkg-config")) and subprocess.run(
        ["pkg-config", "--exists", "wayland-client"]).returncode == 0


def vpointer_tool():
    """Compila uma vez (por processo de teste) o cursor virtual de tests/vpointer."""
    global _VPOINTER
    if _VPOINTER is None:
        build = Path(tempfile.mkdtemp(prefix="pomar-vpointer-"))
        atexit.register(shutil.rmtree, build, True)
        xml = VPOINTER_SRC / "wlr-virtual-pointer-unstable-v1.xml"
        header = build / "wlr-virtual-pointer-unstable-v1-client-protocol.h"
        code = build / "wlr-virtual-pointer-unstable-v1-protocol.c"
        subprocess.run(["wayland-scanner", "client-header", str(xml), str(header)], check=True)
        subprocess.run(["wayland-scanner", "private-code", str(xml), str(code)], check=True)
        flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "wayland-client"], text=True).split()
        subprocess.run(["gcc", "-O1", "-I", str(build), str(VPOINTER_SRC / "vpointer.c"), str(code),
                        "-o", str(build / "vpointer"), *flags], check=True)
        _VPOINTER = build / "vpointer"
    return _VPOINTER

# O que do HOME real teste nenhum pode alterar. Só o que o Pomarchy e o shell de
# teste poderiam tocar: o resto de ~/.config/omarchy e ~/.local/state/omarchy
# muda sozinho com o uso normal (tempo de tela, área de transferência...).
SENSITIVE = (".local/share/Trash/files", ".local/share/Trash/info", ".local/share/applications",
             ".local/share/icons/hicolor", ".local/share/pomar", ".local/bin", ".config/omarchy/shell.json",
             ".config/omarchy/themes", ".config/omarchy/plugins", ".config/omarchy/hooks", ".config/hypr",
             ".config/pomar", ".local/state/omarchy/current/theme.name", ".local/state/omarchy/current",
             ".local/state/pomar")

# Comandos que viram dublês dentro da sessão de teste.
STUBBED = ("uwsm-app", "uwsm", "gtk-launch", "gio", "xdg-open", "xdg-settings", "systemctl", "systemd-run",
           "loginctl", "reboot", "poweroff", "shutdown", "hyprshutdown", "pomar", "omarchy", "trash-put",
           "trash-empty", "gtk-update-icon-cache", "update-desktop-database", "nautilus-trash")
STUBBED_PREFIXES = ("omarchy-launch", "omarchy-theme", "omarchy-system", "omarchy-restart", "omarchy-refresh",
                    "omarchy-plugin", "omarchy-bar", "omarchy-remove", "omarchy-install", "omarchy-pkg",
                    "omarchy-update", "omarchy-hook", "omarchy-webapp", "omarchy-toggle", "omarchy-cmd-screen",
                    "omarchy-capture", "omarchy-branding")
KEEP_REAL = ("omarchy-shell",)


def fingerprint():
    """Retrato barato das pastas sensíveis do HOME real (nomes e mtimes)."""
    shot = {}
    for rel in SENSITIVE:
        path = REAL_HOME / rel
        try:
            info = path.lstat()
        except FileNotFoundError:
            shot[rel] = None
            continue
        entries = {}
        if stat.S_ISDIR(info.st_mode):
            try:
                for child in os.scandir(path):
                    try:
                        entries[child.name] = child.stat(follow_symlinks=False).st_mtime_ns
                    except FileNotFoundError:
                        pass
            except PermissionError:
                pass
        shot[rel] = (info.st_mtime_ns, entries)
    return shot


def describe_change(rel, before, after):
    """O que mudou numa pasta do retrato, com nomes, para o alerta dizer o quê."""
    if before is None or after is None:
        return f"{rel} ({'apareceu' if before is None else 'sumiu'})"
    old, new = before[1], after[1]
    parts = [f"+{name}" for name in sorted(set(new) - set(old))]
    parts += [f"-{name}" for name in sorted(set(old) - set(new))]
    parts += [f"~{name}" for name in sorted(set(old) & set(new)) if old[name] != new[name]]
    return f"{rel} ({', '.join(parts) if parts else 'só a data da pasta: algo entrou e saiu'})"


def base_config(home: Path, extra: str = "", mode: str = MODE) -> str:
    """Config Lua do compositor de teste: visual e janelas do Omarchy, sem
    autostart (nada de shell, idle ou serviços subindo sozinhos)."""
    return f"""
package.path = "{home}/.local/state/?.lua;{home}/.config/?.lua;{OMARCHY}/?.lua;" .. package.path
require("default.hypr.helpers")
require("default.hypr.envs")
require("default.hypr.looknfeel")
require("default.hypr.input")
require("default.hypr.windows")
local require_optional = require("default.hypr.require_optional")
require_optional.module("omarchy.current.theme.hyprland")
hl.monitor({{ output = "", mode = "{mode}", position = "auto", scale = 1 }})
hl.config({{ misc = {{ disable_hyprland_logo = true, disable_splash_rendering = true }} }})
{extra}
"""


class IsolationError(AssertionError):
    pass


class NestedSession:
    def __init__(self, theme="pomarchy", settings=None, extra_lua="", load_pomar=True, mode=MODE):
        self.temporary = tempfile.TemporaryDirectory(prefix="pomar-nested-")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        # Caminho curto de propósito: socket Unix tem limite de 108 caracteres e
        # o do Hyprland leva a assinatura da instância (uns 60).
        self.runtime_temporary = tempfile.TemporaryDirectory(prefix="pr-", dir="/tmp")
        self.runtime = Path(self.runtime_temporary.name)
        self.stubs = self.root / "stubs"
        self.stub_log = self.root / "stub-calls.log"
        self.process = None
        self.bus = None
        self.log = None
        self.env = {}
        self.children = []
        self.handles = []
        self.theme = theme
        self.settings = settings
        self.extra_lua = extra_lua
        self.load_pomar = load_pomar
        self.mode = mode
        self.before = None

    # ------------------------------------------------------------ ambiente
    def base_env(self):
        """Ambiente isolado comum ao compositor, aos apps e às ferramentas."""
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(("XDG_", "DBUS_", "WAYLAND_", "HYPRLAND_", "DISPLAY", "SWAYSOCK",
                                    "SYSTEMD_", "INVOCATION_ID", "JOURNAL_STREAM", "MANAGERPID"))}
        env.update({
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "XDG_DATA_DIRS": "/usr/local/share:/usr/share",
            "XDG_CONFIG_DIRS": "/etc/xdg",
            "XDG_CURRENT_DESKTOP": "Hyprland",
            "XDG_SESSION_TYPE": "wayland",
            "DBUS_SESSION_BUS_ADDRESS": f"unix:path={self.runtime}/bus",
            "POMAR_STUB_LOG": str(self.stub_log),
            "OMARCHY_PATH": str(OMARCHY),
        })
        return env

    def make_stubs(self):
        self.stubs.mkdir()
        script = '#!/bin/bash\nprintf "%s\\t%s\\n" "$(basename "$0")" "$*" >> "$POMAR_STUB_LOG"\nexit 0\n'
        names = set(STUBBED)
        for directory in os.environ.get("PATH", "").split(os.pathsep):
            try:
                for entry in os.scandir(directory):
                    if entry.name.startswith(STUBBED_PREFIXES) and entry.name not in KEEP_REAL:
                        names.add(entry.name)
            except (FileNotFoundError, NotADirectoryError, PermissionError):
                pass
        for name in names:
            path = self.stubs / name
            path.write_text(script)
            path.chmod(0o755)

    def stub_calls(self):
        if not self.stub_log.exists():
            return []
        return [tuple(line.split("\t", 1)) for line in self.stub_log.read_text().splitlines() if line]

    # ------------------------------------------------------------ preparo
    def prepare_home(self):
        """HOME de teste com o tema aplicado de verdade (omarchy-theme-set em
        modo headless, escrevendo só neste HOME) e o Pomarchy montado."""
        self.runtime.chmod(0o700)
        omarchy_config = self.home / ".config/omarchy"
        (omarchy_config / "themes").mkdir(parents=True)
        (self.home / ".local/state/omarchy/current").mkdir(parents=True)
        (self.home / ".config/hypr").mkdir(parents=True)
        for theme in (REPO / "themes").iterdir():
            (omarchy_config / "themes" / theme.name).symlink_to(theme)
        env = {**self.base_env(), "OMARCHY_THEME_HEADLESS": "1",
               "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent/pomar-test-bus"}
        subprocess.run(["omarchy-theme-set", self.theme], env=env, check=True, timeout=90,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        config = self.home / ".config/pomar"
        config.mkdir(parents=True)
        if self.settings is not None:
            (config / "settings.json").write_text(json.dumps(self.settings, indent=2) + "\n")
        share = self.home / ".local/share"
        share.mkdir(parents=True, exist_ok=True)
        # Cópias, nunca links: escrever aqui não pode atravessar para o HOME real.
        for name in ("icons", "applications"):
            source = REAL_HOME / ".local/share" / name
            if source.is_dir():
                shutil.copytree(source, share / name, symlinks=False, ignore_dangling_symlinks=True)
        # Os ícones do próprio Pomarchy vêm do repositório, não da instalação da
        # máquina (que pode ser de uma versão anterior).
        apps_icons = share / "icons/hicolor/scalable/apps"
        apps_icons.mkdir(parents=True, exist_ok=True)
        for icon in (REPO / "icons").glob("*.svg"):
            shutil.copy2(icon, apps_icons / icon.name)
        (share / "Trash/files").mkdir(parents=True)
        (share / "Trash/info").mkdir(parents=True)
        sys.path.insert(0, str(REPO / "tools"))
        from stage import stage
        self.release = stage(share / "pomar/current")
        plugins = omarchy_config / "plugins"
        plugins.mkdir()
        for plugin in (self.release / "plugins").iterdir():
            (plugins / plugin.name).symlink_to(plugin)
        (omarchy_config / "shell.json").write_text(json.dumps(self.shell_config(), indent=2) + "\n")
        self.make_stubs()

    def shell_config(self):
        """shell.json de teste: barra no estilo Mac e os plugins do Pomarchy ligados.
        Serviços que falam com o sistema de verdade ficam desligados."""
        return {
            "version": 1,
            "bar": {"position": "top", "layout": {
                "left": [{"id": "pomar.menubar"}],
                "center": [],
                "right": [{"id": "omarchy.audio"}, {"id": "omarchy.network"}, {"id": "omarchy.power"},
                          {"id": "omarchy.clock", "format": "ddd d MMM  HH:mm"}]}},
            "plugins": [{"id": p} for p in ("pomar.core", "pomar.dock", "pomar.launchpad", "pomar.mission",
                                              "pomar.switcher", "pomar.settings")],
            "disabledPlugins": ["omarchy.idle", "omarchy.lock", "omarchy.polkit", "omarchy.battery",
                                "omarchy.nightlight", "omarchy.notifications"],
        }

    def start_shell(self, log=None):
        """Sobe o shell do Omarchy de verdade dentro do compositor de teste, no
        D-Bus da sessão de teste."""
        log = log or (self.root / "shell.log")
        self.shell_log_path = Path(log)
        return self.spawn(["quickshell", "--no-color", "-n", "-p", str(OMARCHY / "shell")], log=log,
                          POMAR_TEST="1")

    def shell_log(self):
        path = getattr(self, "shell_log_path", None)
        return path.read_text(errors="replace") if path and path.exists() else ""

    def shell_ipc(self, *args):
        """IPC para o shell de teste (o qs acha a instância pelo WAYLAND_DISPLAY)."""
        return subprocess.run(["qs", "ipc", "-n", "-p", str(OMARCHY / "shell"), "call", "--", *args],
                              env=self.client_env(), capture_output=True, text=True, timeout=10).stdout.strip()

    def config_text(self):
        extra = self.extra_lua
        if self.load_pomar:
            extra += f'\nlocal ok, err = pcall(dofile, "{self.release}/hypr/pomar.lua")\nif not ok then hl.notification.create({{ text = "POMAR_LUA_ERROR " .. tostring(err), timeout = 60000 }}) end\n'
        return base_config(self.home, extra, self.mode)

    # ------------------------------------------------------------ ciclo
    def start(self):
        self.before = fingerprint()
        try:
            self.prepare_home()
            base = self.base_env()
            self.bus = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--nopidfile",
                                         f"--address=unix:path={self.runtime}/bus"], env=base,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            deadline = time.monotonic() + 5
            while not (self.runtime / "bus").exists():
                if time.monotonic() > deadline or self.bus.poll() is not None:
                    raise RuntimeError("D-Bus de teste não subiu")
                time.sleep(.02)
            # Claro/escuro dos apps GTK (Arquivos etc.), como o omarchy-theme-set
            # faz fora do modo headless. Escreve só no dconf do HOME de teste.
            subprocess.run(["omarchy-theme-set-gnome"], env=base, timeout=30,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            config = self.root / "hyprland.lua"
            config.write_text(self.config_text())
            parent = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
            parent_socket = parent if parent.startswith("/") else str(REAL_RUNTIME / parent)
            env = {**base, "WAYLAND_DISPLAY": parent_socket, "AQ_DRM_DEVICES": "/dev/null",
                   "HYPRLAND_NO_SD_VARS": "1", "HYPRLAND_NO_SD_TARGET": "1", "HYPRLAND_NO_SD_NOTIFY": "1"}
            self.log = (self.root / "hyprland.log").open("w")
            self.process = subprocess.Popen(["Hyprland", "--config", str(config)], env=env,
                                            stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if self.process.poll() is not None:
                    raise RuntimeError("Hyprland de teste não iniciou: " + self.hyprland_log()[-2000:])
                listing = subprocess.run(["hyprctl", "-j", "instances"], env=base, capture_output=True,
                                         text=True, timeout=5).stdout
                try:
                    instances = json.loads(listing)
                except ValueError:
                    instances = []   # sem instâncias o hyprctl imprime só "]"
                instance = next((i for i in instances if i["pid"] == self.process.pid), None)
                if instance:
                    self.env = {"WAYLAND_DISPLAY": instance["wl_socket"],
                                "HYPRLAND_INSTANCE_SIGNATURE": instance["instance"]}
                    break
                time.sleep(.05)
            else:
                raise RuntimeError("Hyprland de teste não ficou disponível.")
            # O portal (que diz aos apps GTK 4 se o tema é claro ou escuro) sobe sob
            # demanda no D-Bus de teste; precisa saber qual tela usar. Sem --systemd:
            # só o D-Bus de teste muda, o systemd da sessão real nem é tocado.
            subprocess.run(["dbus-update-activation-environment", f"WAYLAND_DISPLAY={self.env['WAYLAND_DISPLAY']}",
                            f"HYPRLAND_INSTANCE_SIGNATURE={self.env['HYPRLAND_INSTANCE_SIGNATURE']}"],
                           env=base, timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.control("output", "create", "headless", OUTPUT)
            self.control("eval", f'hl.monitor({{output="{OUTPUT}",mode="{self.mode}",position="0x0",scale=1}})')
            for monitor in json.loads(self.control("-j", "monitors")):
                if monitor["name"] != OUTPUT:
                    self.control("eval", 'hl.monitor({output=' + json.dumps(monitor["name"]) + ',disabled=true})')
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                active = json.loads(self.control("-j", "monitors"))
                if len(active) == 1 and active[0]["name"] == OUTPUT:
                    # Some com o aviso "started without start-hyprland" das fotos.
                    self.control("dismissnotify")
                    return self
                time.sleep(.05)
            raise RuntimeError("Hyprland de teste não isolou a tela virtual.")
        except Exception:
            self.close(check=False)
            raise

    def close(self, check=True):
        for child in reversed(self.children):
            self._stop(child)
        self.children = []
        for handle in self.handles:
            handle.close()
        self.handles = []
        if self.process is not None:
            self._stop(self.process)
            self.process = None
        if self.bus is not None:
            self._stop(self.bus)
            self.bus = None
        if self.log is not None:
            self.log.close()
            self.log = None
        self.temporary.cleanup()
        self.runtime_temporary.cleanup()
        if check and self.before is not None:
            after = fingerprint()
            changed = [describe_change(rel, self.before.get(rel), after.get(rel))
                       for rel in SENSITIVE if self.before.get(rel) != after.get(rel)]
            self.before = None
            if changed:
                raise IsolationError("ALERTA: pastas do HOME real mudaram durante o teste: " + "; ".join(changed)
                                     + ". Se não foi você usando a máquina, o isolamento vazou.")

    @staticmethod
    def _stop(process):
        if process.poll() is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)

    def __enter__(self):
        return self.start()

    def __exit__(self, *exc):
        self.close(check=exc[0] is None)

    # ------------------------------------------------------------ uso
    def client_env(self, **extra):
        env = {**self.base_env(), **self.env, "QT_QPA_PLATFORM": "wayland",
               "PATH": str(self.stubs) + os.pathsep + os.environ.get("PATH", "")}
        env.update({k: str(v) for k, v in extra.items()})
        return env

    def control(self, *args):
        return subprocess.check_output(["hyprctl", "-i", self.env["HYPRLAND_INSTANCE_SIGNATURE"], *args],
                                       env=self.base_env(), text=True, timeout=5)

    def dispatch(self, lua):
        return self.control("dispatch", lua).strip()

    def event(self, message):
        return self.dispatch(f'hl.dsp.event("pomar>>{message}")')

    def spawn(self, args, log=None, **env):
        """Abre um processo dentro da sessão de teste. O primeiro argumento é
        resolvido no PATH real antes dos dublês (para abrir o foot de verdade)."""
        out = open(log, "w") if log else subprocess.DEVNULL
        if log:
            self.handles.append(out)
        program = shutil.which(args[0]) or args[0]
        process = subprocess.Popen([program, *args[1:]], env=self.client_env(**env), stdout=out,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        self.children.append(process)
        return process

    def screenshot(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["grim", "-o", OUTPUT, str(path)], env=self.client_env(), check=True, timeout=10)
        return Path(path)

    def cursor(self, x, y):
        """Move o ponteiro do compositor de teste (hover de verdade nas superfícies)."""
        return self.dispatch(f"hl.dsp.cursor.move({{ x = {int(x)}, y = {int(y)} }})")

    def click(self, x, y, button="left"):
        """Clique de verdade (cursor virtual) no compositor de teste; button="move"
        só leva o cursor até o ponto. Só fala com o socket da sessão de teste."""
        env = self.client_env()
        socket = Path(env["WAYLAND_DISPLAY"])
        if not socket.is_absolute():
            socket = Path(env["XDG_RUNTIME_DIR"]) / socket
        if (not socket.resolve().is_relative_to(self.runtime.resolve())
                or socket.resolve().is_relative_to(REAL_RUNTIME.resolve()) or not socket.exists()):
            raise IsolationError(f"o cursor virtual iria para {socket}, fora da sessão de teste")
        width, height = (int(v) for v in MODE.split("@")[0].split("x"))
        subprocess.run([str(vpointer_tool()), str(int(x)), str(int(y)), str(width), str(height), button],
                       env=env, check=True, timeout=10)

    def keys(self, *args):
        """Teclas virtuais no compositor de teste (wtype), ex.: keys("-M", "logo", "-k", "Tab")."""
        subprocess.run(["wtype", *args], env=self.client_env(), check=True, timeout=10)

    def clients(self):
        return json.loads(self.control("-j", "clients"))

    def config_errors(self):
        return self.control("configerrors").strip()

    def hyprland_log(self):
        path = self.root / "hyprland.log"
        return path.read_text(errors="replace") if path.exists() else ""

    def wait_for(self, predicate, timeout=8.0, interval=0.1, message="condição"):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            time.sleep(interval)
        raise AssertionError(f"tempo esgotado esperando {message}")
