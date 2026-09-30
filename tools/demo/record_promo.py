#!/usr/bin/env python3
"""Grava a matéria-prima do vídeo curto do Pomarchy OS (LinkedIn, README,
YouTube): uma animação por cena, no Hyprland aninhado (isolado), sem legendas.
As legendas, os cartões e a música entram depois, em tools/demo/edit_promo.py,
a partir das marcas de tempo de cada cena gravadas ao lado do vídeo.

Uso: tools/demo/record_promo.py pt|en [saida.mp4]
"""
import json
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tests"))
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(REPO / "tools/demo"))
from nested import NestedSession  # noqa: E402
from previews import BASHRC, PALETTE, curate_apps  # noqa: E402
from record_demo import HUD, Demo, Recorder  # noqa: E402

FOLDERS = {
    "pt": ("Documentos", "Downloads", "Imagens", "Música", "Projetos", "Vídeos"),
    "en": ("Documents", "Downloads", "Pictures", "Music", "Projects", "Videos"),
}
LANG_ENV = {
    # Sem pt_BR instalado no sistema: os apps ficam no padrão; o Pomarchy fala
    # português pelo ajuste de idioma.
    "pt": {"LANG": "C.UTF-8"},
    "en": {"LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "LANGUAGE": "en"},
}


class Promo(Demo):
    def __init__(self, session, lang):
        super().__init__(session)
        self.lang = lang
        self.env = LANG_ENV[lang]
        self.marks = []
        self.t0 = None

    def mark(self, name):
        self.marks.append({"scene": name, "t": round(time.monotonic() - self.t0, 3)})

    def controls_for(self, address, timeout=6.0):
        """Os botões da janela, já parados no lugar (como quem espera para clicar)."""
        deadline = time.monotonic() + timeout
        previous = None
        while time.monotonic() < deadline:
            info = json.loads(self.ipc("pomar-dock-test", "windowControls"))
            group = next((w for w in info["windows"] if w["address"] == address), None)
            if info["settled"] and group and group == previous:
                return group
            previous = group if info["settled"] else None
            time.sleep(0.12)
        raise RuntimeError(f"os botões de {address} não apareceram")

    def pointer_to(self, x, y, seconds=0.6):
        cx, cy = (int(v) for v in self.s.control("cursorpos").strip().split(","))
        self.glide([(cx, cy), (x, y)], seconds)
        self.s.click(x, y, "move")  # um movimento de verdade no fim: o hover chega

    def click_at(self, x, y, seconds=0.5):
        self.pointer_to(x, y, seconds)
        self.s.click(x, y)

    def newest(self, before):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            fresh = [c for c in self.s.clients() if c["address"] not in before]
            if fresh:
                return fresh[0]
            time.sleep(0.1)
        raise RuntimeError("a janela nova não abriu")

    def reopen_terminals(self):
        """O foot só pega as cores novas ao abrir: fecha e abre de novo (e a
        animação de abrir aparece)."""
        for client in self.s.clients():
            if client["class"] == "foot":
                self.s.dispatch(f'hl.dsp.window.close({{ window = "address:{client["address"]}" }})')
        self.wait(0.5)
        spawn_windows(self.s, self.lang)

    def omarchy_bar(self):
        """O que o gancho de tema faz ao sair do Pomarchy: a barra do Omarchy de fábrica."""
        path = self.s.home / ".config/omarchy/shell.json"
        data = json.loads(path.read_text())
        default = json.loads(Path("/usr/share/omarchy/config/omarchy/shell.json").read_text())
        data["bar"] = default["bar"]
        path.write_text(json.dumps(data, indent=2) + "\n")
        self.ipc("shell", "reloadConfig")

    def run(self):
        s = self.s
        dock_y = self.dock_center("app:org.gnome.Nautilus")[1]
        self.t0 = time.monotonic()
        self.wait(0.6)

        self.mark("dock")
        self.glide([(560, dock_y), (1360, dock_y)], 2.4)
        self.glide([(1360, dock_y), (760, dock_y)], 1.2)
        self.wait(0.3)

        self.mark("open")
        files = self.dock_center("app:org.gnome.Nautilus")
        before = {c["address"] for c in s.clients()}
        if files:
            self.click_at(files[0], files[1], 0.4)
        # No teste o Dock só anota o que abriria; o roteiro abre o app na sessão isolada.
        s.spawn(["nautilus", str(s.home / FOLDERS[self.lang][2])], **self.env)
        window = self.newest(before)["address"]
        self.wait(1.6)

        self.mark("minimize")
        group = self.controls_for(window)
        self.pointer_to(group["close"][0], group["close"][1], 0.7)
        self.wait(0.45)
        self.click_at(*group["minimize"], seconds=0.25)
        self.wait(1.5)

        self.mark("restore")
        minimized = self.dock_center("min:" + window)
        index = self.dock_index("min:" + window)
        if minimized and index is not None:
            self.pointer_to(minimized[0], minimized[1], 0.6)
            self.ipc("pomar-dock-test", "click", index)
        self.wait(1.7)

        self.mark("zoom")
        group = self.controls_for(window)
        self.click_at(*group["zoom"], seconds=0.6)
        self.wait(1.5)
        group = self.controls_for(window)
        self.click_at(*group["zoom"], seconds=0.3)
        self.wait(1.3)

        self.mark("close")
        group = self.controls_for(window)
        self.click_at(*group["close"], seconds=0.5)
        self.wait(1.2)
        s.cursor(1900, 560)

        self.mark("mission")
        self.swipe("mission", -300, 0.8, 3, "up")
        self.wait(0.6)
        self.glide([(1900, 560), (700, 620), (1250, 600)], 1.4)
        self.swipe("mission", 300, 0.7, 3, "down")
        self.wait(0.9)
        self.hud("hideGesture")

        self.mark("spaces")
        ws = self.active()["workspace"]["id"]
        s.spawn(["foot", "--title", "Terminal", "-e", "bash", "-c", PALETTE], **self.env)
        self.wait(0.9)
        s.dispatch(f'hl.dsp.window.move({{ workspace = "{ws + 1}", follow = false }})')
        self.wait(0.4)
        self.hud("showGesture", "left", 4, 600)
        s.dispatch(f'hl.dsp.focus({{ workspace = "{ws + 1}" }})')
        self.wait(1.3)
        self.hud("showGesture", "right", 4, 600)
        s.dispatch(f'hl.dsp.focus({{ workspace = "{ws}" }})')
        self.wait(1.1)
        self.hud("hideGesture")

        self.mark("launchpad")
        self.pinch(1.0, 0.5, 0.8, "pinch")
        self.wait(1.1)
        for letter in "obs":
            self.ipc("pomar-launchpad-test", "type", letter)
            self.wait(0.22)
        self.wait(0.9)
        self.ipc("pomar-launchpad-test", "clear")
        self.pinch(1.0, 1.6, 0.7, "spread")
        self.wait(1.0)
        self.hud("hideGesture")

        self.mark("switcher")
        self.hud("showKeys", "Alt+Tab")
        self.ev("switcher:next")
        self.wait(0.9)
        self.ev("switcher:next")
        self.wait(0.8)
        self.ev("switcher:commit")
        self.wait(0.7)
        self.hud("showKeys", "")

        self.mark("dark")
        self.switch_theme("pomarchy-escuro")
        self.wait(0.8)
        self.reopen_terminals()
        self.wait(1.4)

        self.mark("omarchy")
        self.switch_theme("tokyo-night")
        self.omarchy_bar()
        self.wait(0.6)
        self.reopen_terminals()
        self.wait(2.2)
        self.mark("end")


def spawn_windows(session, lang):
    session.spawn(["foot", "--title", "notes.md", "-e", "nvim", "+set nonumber", "+set laststatus=0",
                   str(session.home / "notes.md")], **LANG_ENV[lang])
    time.sleep(1.1)
    session.spawn(["foot", "--title", "Terminal", "-e", "bash", "-c", PALETTE], **LANG_ENV[lang])
    time.sleep(1.1)


def main():
    lang = sys.argv[1] if len(sys.argv) > 1 else "pt"
    out = Path(sys.argv[2] if len(sys.argv) > 2 else REPO / f"out/promo/raw-{lang}.mp4")
    settings = {"language": lang, "welcome": {"seen": True}}
    with NestedSession(theme="pomarchy", settings=settings, mode="1920x1080@60") as session:
        curate_apps(session)
        home = session.home
        foot = home / ".config/foot/foot.ini"
        foot.parent.mkdir(parents=True, exist_ok=True)
        foot.write_text("include=~/.local/state/omarchy/current/theme/foot.ini\n[main]\n"
                        "font=JetBrainsMono Nerd Font:size=11\npad=14x14\n")
        (home / ".bashrc").write_text(BASHRC)
        for name in FOLDERS[lang]:
            (home / name).mkdir(exist_ok=True)
        pictures = home / FOLDERS[lang][2]
        for index, wallpaper in enumerate(sorted((REPO / "themes").glob("*/backgrounds/*.jpg"))):
            (pictures / f"{index + 1:02d}.jpg").write_bytes(wallpaper.read_bytes())
        doc = REPO / ("docs/install.md" if lang == "en" else "README.md")
        (home / "notes.md").write_text(doc.read_text())
        session.start_shell()
        time.sleep(3.5)
        session.spawn(["quickshell", "--no-color", "-n", "-p", str(HUD)], log=session.root / "hud.log")
        spawn_windows(session, lang)
        session.cursor(1900, 560)
        time.sleep(1.0)
        promo = Promo(session, lang)
        recorder = Recorder(session, out).start()
        try:
            promo.run()
        finally:
            recorder.stop()
        (out.with_suffix(".json")).write_text(json.dumps({"lang": lang, "marks": promo.marks}, indent=2) + "\n")
        print(f"{out} ({recorder.frames} quadros)")


if __name__ == "__main__":
    main()
