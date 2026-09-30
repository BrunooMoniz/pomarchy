#!/usr/bin/env python3
"""Grava o vídeo de demonstração do Pomarchy OS no Hyprland de teste (isolado).

Os gestos são os mesmos eventos que o trackpad de verdade manda pelo
hypr/pomar.lua (mission:begin/delta/end, launchpad:begin/scale/end), no ritmo
de uma mão; uma ilustração do trackpad no canto mostra os dedos e uma legenda
explica cada passo.

Uso: tools/demo/record_demo.py [saida.mp4]
"""
import base64
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tests"))
from nested import NestedSession, OUTPUT  # noqa: E402

HUD = REPO / "tools/demo/hud"
FPS = 30


class Recorder:
    """grim em laço (PPM) direto para o ffmpeg, com o horário de chegada de cada
    quadro como carimbo de tempo; o ffmpeg regulariza para 30 quadros por segundo."""

    def __init__(self, session, path):
        self.session = session
        self.path = Path(path)
        self.stop_flag = threading.Event()
        self.frames = 0

    def start(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.ffmpeg = subprocess.Popen(
            ["ffmpeg", "-y", "-loglevel", "error", "-f", "image2pipe", "-use_wallclock_as_timestamps", "1",
             "-c:v", "ppm", "-i", "-", "-vf", f"fps={FPS},format=yuv420p", "-c:v", "libx264", "-preset", "medium",
             "-crf", "20", "-movflags", "+faststart", str(self.path)],
            stdin=subprocess.PIPE)
        self.thread = threading.Thread(target=self.loop, daemon=True)
        self.thread.start()
        return self

    def loop(self):
        env = self.session.client_env()
        while not self.stop_flag.is_set():
            shot = subprocess.run(["grim", "-t", "ppm", "-o", OUTPUT, "-"], env=env, capture_output=True)
            if shot.returncode == 0 and shot.stdout:
                self.ffmpeg.stdin.write(shot.stdout)
                self.frames += 1

    def stop(self):
        self.stop_flag.set()
        self.thread.join(timeout=10)
        self.ffmpeg.stdin.close()
        self.ffmpeg.wait(timeout=300)


class Demo:
    def __init__(self, session):
        self.s = session

    # ------------------------------------------------------------ utilidades
    def hud(self, method, *args):
        return subprocess.run(["qs", "ipc", "-n", "-p", str(HUD), "call", "--", "hud", method, *map(str, args)],
                              env=self.s.client_env(), capture_output=True, text=True, timeout=10).stdout.strip()

    def caption(self, title, subtitle=""):
        self.hud("caption", title, subtitle)

    def wait(self, seconds):
        time.sleep(seconds)

    def ev(self, message):
        self.s.event(message)

    def ipc(self, target, method, *args):
        return self.s.shell_ipc(target, method, *map(str, args))

    def dock_state(self):
        return json.loads(self.ipc("pomar-dock-test", "state"))

    def dock_index(self, key):
        for item in self.dock_state()["items"]:
            if item["key"] == key:
                return item["index"]
        return None

    def dock_center(self, key):
        for item in self.dock_state()["items"]:
            if item["key"] == key:
                return item["x"], item["y"]
        return None

    def glide(self, points, seconds):
        """Leva o ponteiro por uma sequência de pontos, suave."""
        steps = max(2, int(seconds * 40))
        path = []
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            for i in range(steps // max(1, len(points) - 1)):
                t = i / max(1, steps // max(1, len(points) - 1))
                path.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
        path.append(points[-1])
        for x, y in path:
            self.s.cursor(x, y)
            time.sleep(seconds / len(path))

    def swipe(self, target, total, seconds, fingers, kind):
        """Deslize ao vivo: o mesmo que o trackpad manda, em pequenos passos."""
        self.hud("showGesture", kind, fingers, int(seconds * 1000))
        self.ev(f"{target}:begin")
        steps = max(8, int(seconds * 60))
        for _ in range(steps):
            self.ev(f"{target}:delta:{total / steps:.2f}")
            time.sleep(seconds / steps)
        self.ev(f"{target}:end:0")

    def pinch(self, start, finish, seconds, kind):
        self.hud("showGesture", kind, 4, int(seconds * 1000))
        self.ev("launchpad:begin")
        steps = max(8, int(seconds * 60))
        for i in range(1, steps + 1):
            self.ev(f"launchpad:scale:{start + (finish - start) * i / steps:.4f}")
            time.sleep(seconds / steps)
        self.ev("launchpad:end:0")

    def active(self):
        return json.loads(self.s.control("-j", "activewindow"))

    def switch_theme(self, name):
        """Troca o tema no HOME de teste como o omarchy-theme-set faria, com a
        transição do papel de parede e das cores no shell de teste."""
        state = self.s.home / ".local/state/omarchy/current"
        old_bg = str((state / "background").resolve())
        env = {**self.s.base_env(), "OMARCHY_THEME_HEADLESS": "1"}
        subprocess.run(["omarchy-theme-set", name], env=env, check=True, timeout=90,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        colors = base64.b64encode((state / "theme/colors.toml").read_bytes()).decode()
        shell = base64.b64encode((state / "theme/shell.toml").read_bytes()).decode()
        new_bg = str((state / "background").resolve())
        self.ipc("background", "themeTransition", old_bg, new_bg, new_bg, colors, shell)
        subprocess.run(["omarchy-theme-set-gnome"], env=self.s.base_env(), timeout=30,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.s.control("reload")

    # ------------------------------------------------------------ roteiro
    def run(self):
        s = self.s
        width, height = 1920, 1200
        dock_y = 1159

        self.hud("showCard", "Pomarchy OS", "O Omarchy com jeito de Mac")
        self.wait(3.2)
        self.hud("hideCard")
        self.wait(0.8)

        self.caption("Barra de menus e Dock", "O app em uso fica em negrito; o Dock tem os favoritos e os apps abertos")
        self.wait(1.2)
        self.glide([(640, dock_y), (1290, dock_y)], 3.0)
        self.glide([(1290, dock_y), (900, dock_y)], 1.6)
        self.wait(0.4)

        self.caption("Um clique no Dock abre o app", "O ícone quica enquanto o app abre")
        files = self.dock_index("app:org.gnome.Nautilus")
        if files is not None:
            self.ipc("pomar-dock-test", "click", files)
        # No teste o Dock só anota o que abriria (nada sai da sessão isolada);
        # o roteiro abre o app de verdade dentro dela, no mesmo instante.
        s.spawn(["nautilus", str(s.home / "Fotos")])
        self.wait(2.6)
        s.cursor(1900, 600)
        self.wait(0.6)

        self.caption("Pinça com quatro dedos: Launchpad", "Todos os apps numa tela só")
        self.pinch(1.0, 0.5, 0.9, "pinch")
        self.wait(1.8)
        self.caption("Comece a digitar para buscar", "A grade filtra na hora")
        for letter in "term":
            self.ipc("pomar-launchpad-test", "type", letter)
            self.wait(0.25)
        self.wait(1.6)
        self.ipc("pomar-launchpad-test", "clear")
        self.caption("Abrir os dedos fecha o Launchpad")
        self.pinch(1.0, 1.6, 0.8, "spread")
        self.wait(1.4)
        self.hud("hideGesture")

        self.caption("Três dedos para cima: Mission Control", "Todas as janelas ao vivo, e as mesas no topo")
        self.swipe("mission", -300, 0.8, 3, "up")
        self.wait(1.2)
        self.glide([(1900, 700), (700, 750), (1250, 700)], 2.2)
        self.wait(0.8)
        self.caption("Três dedos para baixo: volta para as janelas")
        self.swipe("mission", 300, 0.7, 3, "down")
        self.wait(1.4)

        self.caption("Três dedos para baixo: todas as janelas do app", "App Exposé")
        self.swipe("mission", 280, 0.7, 3, "down")
        self.wait(2.2)
        self.ev("mission:close")
        self.wait(1.0)
        self.hud("hideGesture")

        self.caption("Quatro dedos para os lados: trocar de mesa", "A mesa desliza, como no Mac")
        ws = self.active()["workspace"]["id"]
        s.dispatch(f'hl.dsp.window.move({{ workspace = "{ws + 1}", follow = false }})')
        self.wait(0.8)
        self.hud("showGesture", "left", 4, 600)
        s.dispatch(f'hl.dsp.focus({{ workspace = "{ws + 1}" }})')
        self.wait(1.8)
        self.hud("showGesture", "right", 4, 600)
        s.dispatch(f'hl.dsp.focus({{ workspace = "{ws}" }})')
        self.wait(1.6)
        self.hud("hideGesture")

        self.caption("No Mission Control aparecem todas as mesas", "Clique numa mesa para ir até ela, ou arraste uma janela para lá")
        self.ev("mission:open")
        self.wait(2.4)
        self.ev("mission:close")
        self.wait(1.0)

        self.caption("Alt + Tab: trocar de app", "No teclado de PC o Alt fica onde o ⌘ fica no Mac")
        self.hud("showKeys", "Alt+Tab")
        self.ev("switcher:next")
        self.wait(1.2)
        self.ev("switcher:next")
        self.wait(1.0)
        self.ev("switcher:commit")
        self.wait(1.0)
        self.hud("showKeys", "")

        self.caption("⌘ M: minimizar com o efeito gênio", "A janela escorre para o Dock")
        self.hud("showKeys", "⌘+M")
        target = self.active()["address"]
        self.ev(f"dock:minimize:{target}")
        self.wait(2.2)
        self.hud("showKeys", "")
        self.caption("Um clique no Dock traz a janela de volta")
        minimized = self.dock_center("min:" + target)
        if minimized:
            self.glide([(1900, 700), (minimized[0], dock_y)], 1.2)
        index = self.dock_index("min:" + target)
        if index is not None:
            self.ipc("pomar-dock-test", "click", index)
        self.wait(2.0)
        s.cursor(1900, 600)

        self.caption("⌘ F: tela cheia, com um zoom suave")
        self.hud("showKeys", "⌘+F")
        s.dispatch("hl.dsp.window.fullscreen({})")
        self.wait(1.8)
        s.dispatch("hl.dsp.window.fullscreen({})")
        self.wait(1.4)
        self.hud("showKeys", "")

        self.caption("⌘ W: fechar a janela", "Ela encolhe e some depressa")
        self.hud("showKeys", "⌘+W")
        s.dispatch("hl.dsp.window.close({})")
        self.wait(1.6)
        self.hud("showKeys", "")

        self.caption("O logo abre o menu do sistema", "Com o melhor do Omarchy: menu, atalhos e gravação de tela")
        self.ipc("pomar-menubar-test", "openSystem")
        self.wait(3.2)
        self.ipc("pomar-menubar-test", "closeAll")
        self.caption("O nome do app abre o menu da janela")
        self.ipc("pomar-menubar-test", "openApp")
        self.wait(2.6)
        self.ipc("pomar-menubar-test", "closeAll")
        self.wait(0.4)

        self.caption("⌘ Espaço: o menu do Omarchy continua lá")
        self.hud("showKeys", "⌘+Espaço")
        self.ipc("shell", "summon", "omarchy.menu", "{}")
        self.wait(2.6)
        self.ipc("shell", "hide", "omarchy.menu")
        self.hud("showKeys", "")
        self.wait(0.6)

        self.caption("Ajustes do Pomarchy", "Cada gesto do trackpad com a sua animação")
        self.ipc("shell", "summon", "pomar.settings", '{"page":"trackpad"}')
        self.wait(4.0)
        self.ipc("pomar-settings-test", "page", "dock")
        self.wait(2.8)
        self.ipc("pomar-settings-test", "page", "teclado")
        self.wait(2.8)
        self.ipc("shell", "hide", "pomar.settings")
        self.wait(0.8)

        self.caption("Na primeira vez, as boas-vindas ensinam tudo", "Com os gestos animados no trackpad")
        self.ipc("shell", "summon", "pomar.settings", '{"page":"welcome"}')
        self.wait(2.2)
        self.ipc("pomar-settings-test", "step", 2)
        self.wait(3.0)
        self.ipc("pomar-settings-test", "step", 3)
        self.wait(3.0)
        self.ipc("shell", "hide", "pomar.settings")
        self.wait(0.8)

        self.caption("Tema escuro com um clique", "Janelas, Dock, menus e apps acompanham")
        self.switch_theme("pomarchy-escuro")
        self.wait(1.2)
        for client in s.clients():
            if client["class"] == "foot":
                s.dispatch(f'hl.dsp.window.close({{ window = "address:{client["address"]}" }})')
        self.wait(0.8)
        spawn_terminals(s)
        self.wait(1.4)
        self.swipe("mission", -300, 0.8, 3, "up")
        self.wait(2.0)
        self.swipe("mission", 300, 0.7, 3, "down")
        self.wait(1.2)
        self.hud("hideGesture")
        self.hud("clear")

        self.hud("showCard", "Pomarchy OS", "Instale com um comando e desfaça quando quiser")
        self.wait(3.2)


TERMINAL_A = (r"printf '\n  \033[1mPomarchy OS\033[0m  \033[2mo Omarchy com jeito de Mac\033[0m\n\n';"
              r"for c in 1 2 3 4 5 6; do printf '\033[4%sm      \033[0m' $c; done; printf '\n\n';"
              r"printf '  \033[34m~/Documentos\033[0m \033[32m❯\033[0m ls\n';"
              r"ls --color=always ~/Documentos | sed 's/^/  /'; printf '\n'; exec sh")
TERMINAL_B = r"printf '\n'; cal -3 | sed 's/^/  /'; printf '\n  \033[35mBom dia!\033[0m\n\n'; exec sh"


def demo_files(home):
    """Pastas e arquivos de exemplo para as janelas não aparecerem vazias."""
    docs = home / "Documentos"
    photos = home / "Fotos"
    music = home / "Música"
    for folder in (docs, photos, music):
        folder.mkdir(parents=True, exist_ok=True)
    for name in ("Planejamento 2027.odt", "Orçamento.ods", "Notas da reunião.md", "Viagem.pdf", "Contrato.pdf"):
        (docs / name).write_text("exemplo\n")
    (docs / "Projetos").mkdir(exist_ok=True)
    for index, wallpaper in enumerate(sorted((REPO / "themes").glob("*/backgrounds/*.jpg"))):
        (photos / f"Foto {index + 1}.jpg").write_bytes(wallpaper.read_bytes())
    return docs, photos


def spawn_terminals(session):
    session.spawn(["foot", "-e", "sh", "-c", TERMINAL_A])
    time.sleep(1.0)
    session.spawn(["foot", "-e", "sh", "-c", TERMINAL_B])
    time.sleep(1.2)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else REPO / "out/demo/pomarchy-os.mp4")
    settings = {"language": "pt", "welcome": {"seen": True}}
    with NestedSession(theme="pomarchy", settings=settings) as session:
        foot = session.home / ".config/foot/foot.ini"
        foot.parent.mkdir(parents=True, exist_ok=True)
        foot.write_text("include=~/.local/state/omarchy/current/theme/foot.ini\n[main]\n"
                        "font=JetBrainsMono Nerd Font:size=11\npad=14x14\n")
        session.start_shell()
        time.sleep(3.5)
        session.spawn(["quickshell", "--no-color", "-n", "-p", str(HUD)], log=session.root / "hud.log")
        demo_files(session.home)
        spawn_terminals(session)
        session.cursor(1900, 600)
        recorder = Recorder(session, out).start()
        try:
            Demo(session).run()
        finally:
            recorder.stop()
        print(f"{out} ({recorder.frames} quadros capturados)")


if __name__ == "__main__":
    main()
