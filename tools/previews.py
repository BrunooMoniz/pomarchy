#!/usr/bin/env python3
"""Fotografa o Pomarchy no Hyprland aninhado (isolado) e gera todas as imagens
públicas: o preview.png de cada tema (seletor de temas do Omarchy), o
preview.png da raiz (cartão do marketplace), as fotos do README em
docs/screenshots/ e as do site do Omarchy em out/site/.

Uma sessão de verdade, como o site pede: editor, terminal e Arquivos lado a
lado, com o Dock e os botões das janelas. Em inglês (o público é o do Omarchy),
sem cursor, sem notificação e sem nada da máquina de quem gera (o prompt e os
títulos das janelas são neutros).

Uso: tools/previews.py
"""
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tests"))
from nested import NestedSession  # noqa: E402

OUT = REPO / "out" / "gallery"
SITE = REPO / "out" / "site"
SHOTS = REPO / "docs" / "screenshots"
ENGLISH = {"LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "LANGUAGE": "en"}

# Só o que vem com o Omarchy (e os atalhos do Pomarchy): o Launchpad e o Dock
# das fotos não podem mostrar os apps da máquina de quem gera as imagens.
STOCK_SYSTEM_APPS = {
    "chromium", "org.gnome.Nautilus", "org.gnome.Evince", "libreoffice-writer", "libreoffice-calc",
    "libreoffice-impress", "obsidian", "localsend", "btop", "com.obsproject.Studio", "org.gnome.DiskUtility",
    "aether", "omacalc", "omacut", "omawrite", "org.kde.kdenlive", "com.github.PintaProject.Pinta",
    "com.github.xournalpp.xournalpp",
}
DOCK = ["org.gnome.Nautilus", "pomar:launchpad", "chromium", "WhatsApp", "HEY", "Google Photos", "obsidian", "foot"]

BASHRC = r"""
PS1='\[\e[1;34m\]~/projects\[\e[0m\] \[\e[32m\]❯\[\e[0m\] '
PROMPT_COMMAND='printf "\e]0;Terminal\a"'
"""

PALETTE = (r"printf '\n  \033[1mPomarchy OS\033[0m  \033[2mthe Mac-style desktop for Omarchy\033[0m\n\n';"
           r"for c in 0 1 2 3 4 5 6 7; do printf '\033[4%sm      \033[0m' $c; done; printf '\n';"
           r"for c in 0 1 2 3 4 5 6 7; do printf '\033[10%sm      \033[0m' $c; done; printf '\n\n';"
           r"printf '\033[1;34m~/projects\033[0m \033[32m❯\033[0m ls\n';"
           r"printf '\033[1;34mdock\033[0m  \033[1;34mlaunchpad\033[0m  notes.md  \033[32minstall.sh\033[0m\n\n';"
           r"exec bash -i")


def curate_apps(session):
    """Troca os atalhos copiados da máquina pelos do Omarchy de fábrica e esconde
    do Launchpad os apps do sistema que não vêm com o Omarchy."""
    apps = session.home / ".local/share/applications"
    shutil.rmtree(apps, ignore_errors=True)
    apps.mkdir(parents=True)
    for source in (Path("/usr/share/omarchy/applications"), REPO / "applications"):
        for entry in source.glob("*.desktop"):
            shutil.copy2(entry, apps / entry.name)
    hidden = sorted({entry.stem for folder in (Path("/usr/share/applications"), Path("/usr/local/share/applications"))
                     if folder.is_dir() for entry in folder.glob("*.desktop")} - STOCK_SYSTEM_APPS)
    path = session.home / ".config/pomar/settings.json"
    settings = json.loads(path.read_text())
    settings["launchpad"] = {"enabled": True, "hidden": hidden}
    settings["dock"] = {"seeded": True, "favorites": DOCK}
    path.write_text(json.dumps(settings, indent=2) + "\n")


def prepare(session):
    curate_apps(session)
    home = session.home
    foot = home / ".config/foot/foot.ini"
    foot.parent.mkdir(parents=True, exist_ok=True)
    foot.write_text("include=~/.local/state/omarchy/current/theme/foot.ini\n[main]\n"
                    "font=JetBrainsMono Nerd Font:size=11\npad=14x14\n")
    (home / ".bashrc").write_text(BASHRC)
    for name in ("Documents", "Downloads", "Music", "Pictures", "Projects", "Videos"):
        (home / name).mkdir(exist_ok=True)
    (home / "Projects" / "install.md").write_text((REPO / "docs/install.md").read_text())


def desktop(session):
    """Editor à esquerda, Arquivos e terminal à direita; o editor com foco."""
    session.spawn(["foot", "--title", "install.md", "-e", "nvim", "+set nonumber", "+set laststatus=0",
                   str(session.home / "Projects" / "install.md")], **ENGLISH)
    time.sleep(1.4)
    session.spawn(["nautilus", str(session.home)], **ENGLISH)
    time.sleep(1.6)
    session.spawn(["foot", "--title", "Terminal", "-e", "bash", "-c", PALETTE], **ENGLISH)
    time.sleep(1.4)
    editor = next(c for c in session.clients() if c["title"] == "install.md")
    session.dispatch(f'hl.dsp.focus({{ window = "address:{editor["address"]}" }})')
    time.sleep(1.8)  # sem mexer o mouse: o cursor some (cursor.inactive_timeout)


def shoot(session, name):
    path = OUT / f"{name}.png"
    session.screenshot(path)
    return path


def session_for(theme):
    return NestedSession(theme=theme, mode="1920x1080@60",
                         settings={"language": "en", "welcome": {"seen": True}},
                         extra_lua="hl.config({ cursor = { inactive_timeout = 1 } })")


def light():
    with session_for("pomarchy") as s:
        prepare(s)
        s.start_shell()
        time.sleep(3.5)
        desktop(s)
        shots = {"desktop-light": shoot(s, "desktop-light")}
        s.event("launchpad:open")
        time.sleep(2.2)
        shots["launchpad"] = shoot(s, "launchpad")
        s.event("launchpad:close")
        time.sleep(1.0)
        s.event("mission:open")
        time.sleep(2.2)
        shots["mission-control"] = shoot(s, "mission-control")
        s.event("mission:close")
        time.sleep(1.0)
        s.shell_ipc("shell", "summon", "pomar.settings", '{"page":"dock"}')
        time.sleep(2.2)
        shots["settings"] = shoot(s, "settings")
        return shots


def dark():
    with session_for("pomarchy-escuro") as s:
        prepare(s)
        s.start_shell()
        time.sleep(3.5)
        desktop(s)
        return {"desktop-dark": shoot(s, "desktop-dark")}


def magick(*args):
    subprocess.run(["magick", *map(str, args)], check=True)


def export(shots):
    SHOTS.mkdir(parents=True, exist_ok=True)
    SITE.mkdir(parents=True, exist_ok=True)
    magick(shots["desktop-light"], "-resize", "1800x1012!", "-strip", REPO / "themes/pomarchy/preview.png")
    magick(shots["desktop-dark"], "-resize", "1800x1012!", "-strip", REPO / "themes/pomarchy-escuro/preview.png")
    shutil.copy(shots["desktop-light"], REPO / "preview.png")
    for name, source in (("desktop", "desktop-light"), ("dark", "desktop-dark"), ("launchpad", "launchpad"),
                         ("mission-control", "mission-control"), ("settings", "settings")):
        magick(shots[source], "-strip", "-resize", "1600x900", "-quality", "82", SHOTS / f"{name}.webp")
    # O site do Omarchy pede 1200x675 com menos de uns 100 KB.
    for name, source in (("pomarchy", "desktop-light"), ("pomarchy-escuro", "desktop-dark")):
        target = SITE / f"{name}.webp"
        for quality in (80, 74, 68, 62):
            magick(shots[source], "-strip", "-resize", "1200x675!", "-quality", str(quality), target)
            if target.stat().st_size < 100_000:
                break


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    shots = {**light(), **dark()}
    export(shots)
    for path in sorted([*SHOTS.glob("*.webp"), *SITE.glob("*.webp"), REPO / "preview.png",
                        *REPO.glob("themes/*/preview.png")]):
        print(f"{path.relative_to(REPO)}  {path.stat().st_size // 1024} KB")
