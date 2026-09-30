#!/usr/bin/env python3
"""Fotografa todas as telas do Pomarchy, nos temas claro e escuro, no Hyprland
aninhado (isolado). As fotos vão para out/showcase/<tema>-<cena>.png e servem
para a revisão visual.

Uso: tools/showcase.py [tema ...]
"""
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tests"))
from nested import NestedSession  # noqa: E402

OUT = REPO / "out" / "showcase"


def themed_foot(session):
    foot = session.home / ".config/foot/foot.ini"
    foot.parent.mkdir(parents=True, exist_ok=True)
    foot.write_text("include=~/.local/state/omarchy/current/theme/foot.ini\n[main]\n"
                    "font=JetBrainsMono Nerd Font:size=11\npad=14x14\n")


def shoot(theme):
    shots = []

    def shot(session, name):
        path = session.screenshot(OUT / f"{theme}-{name}.png")
        shots.append(path)

    settings = {"language": "pt", "welcome": {"seen": True}}
    with NestedSession(theme=theme, settings=settings) as s:
        themed_foot(s)
        s.start_shell()
        time.sleep(3.5)
        s.spawn(["foot"])
        time.sleep(1.0)
        s.spawn(["nautilus"])
        time.sleep(1.2)
        s.spawn(["foot"])
        time.sleep(1.2)
        s.cursor(1900, 500)
        time.sleep(0.6)
        shot(s, "01-mesa")

        s.cursor(700, 1180)
        time.sleep(0.2)
        s.cursor(760, 1180)
        time.sleep(0.9)
        shot(s, "02-dock-ampliacao")
        s.cursor(1900, 500)
        s.shell_ipc("pomar-dock-test", "rightClick", "2")
        time.sleep(0.8)
        shot(s, "03-dock-menu")
        s.shell_ipc("pomar-dock-test", "dismiss")
        time.sleep(0.4)

        s.event("launchpad:open")
        time.sleep(1.3)
        shot(s, "04-launchpad")
        s.shell_ipc("pomar-launchpad-test", "type", "o")
        time.sleep(0.8)
        shot(s, "05-launchpad-busca")
        s.event("launchpad:close")
        time.sleep(0.9)

        s.shell_ipc("pomar-mission-test", "progressTo", "0.45")
        time.sleep(0.7)
        shot(s, "06-mission-gesto")
        s.event("mission:open")
        time.sleep(1.0)
        s.cursor(960, 600)
        time.sleep(0.6)
        shot(s, "07-mission")
        s.event("mission:close")
        time.sleep(0.9)
        s.cursor(1900, 500)
        s.event("mission:expose")
        time.sleep(1.2)
        shot(s, "08-expose")
        s.event("mission:close")
        time.sleep(0.9)

        s.event("switcher:next")
        time.sleep(0.6)
        shot(s, "09-cmd-tab")
        s.event("switcher:cancel")
        time.sleep(0.4)

        s.shell_ipc("pomar-menubar-test", "openSystem")
        time.sleep(0.6)
        shot(s, "10-menu-sistema")
        s.shell_ipc("pomar-menubar-test", "openApp")
        time.sleep(0.6)
        shot(s, "11-menu-app")
        s.shell_ipc("pomar-menubar-test", "closeAll")
        time.sleep(0.4)

        for index, page in enumerate(("geral", "dock", "trackpad", "teclado")):
            s.shell_ipc("shell", "summon", "pomar.settings", '{"page":"%s"}' % page)
            time.sleep(1.4)
            shot(s, f"{12 + index}-ajustes-{page}")
        s.shell_ipc("shell", "hide", "pomar.settings")
        time.sleep(0.8)

        s.shell_ipc("shell", "summon", "pomar.settings", '{"page":"welcome"}')
        time.sleep(1.6)
        shot(s, "16-boas-vindas-1")
        for step in (2, 3):
            s.shell_ipc("pomar-settings-test", "step", str(step))
            time.sleep(1.4)
            shot(s, f"{15 + step}-boas-vindas-{step + 1}")
    return shots


if __name__ == "__main__":
    for name in sys.argv[1:] or ["pomarchy", "pomarchy-escuro"]:
        for path in shoot(name):
            print(path)
