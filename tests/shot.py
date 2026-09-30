#!/usr/bin/env python3
"""Fotografa o Pomarchy no Hyprland aninhado, sem tocar no desktop real.

Exemplos:
  tests/shot.py --out /tmp/pomar.png
  tests/shot.py --apps foot,nautilus --event launchpad:open --out /tmp/lp.png
  tests/shot.py --theme pomarchy-escuro --event mission:open --wait 3 --out /tmp/mc.png
  tests/shot.py --steps 'event:dock:show;sleep:1;shot:/tmp/a.png;event:launchpad:open;sleep:1.5;shot:/tmp/b.png'

Sai com a lista de avisos e erros de QML do log do shell, para quem está
desenvolvendo enxergar o que quebrou.
"""
import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from nested import NestedSession  # noqa: E402


def interesting(log):
    keep = []
    for line in log.splitlines():
        low = line.lower()
        if "pomar" in low and ("warn" in low or "error" in low or "qml" in low or "typeerror" in low or "referenceerror" in low):
            keep.append(line)
        elif "POMAR_" in line:
            keep.append(line)
    return keep


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--theme", default="pomarchy")
    parser.add_argument("--apps", default="foot,foot", help="apps para abrir antes (separados por vírgula)")
    parser.add_argument("--settings", default=None, help="JSON de ajustes do Pomarchy")
    parser.add_argument("--event", action="append", default=[], help="evento pomar>>alvo:verbo[:arg]")
    parser.add_argument("--wait", type=float, default=2.0)
    parser.add_argument("--out", default="/tmp/pomar-shot.png")
    parser.add_argument("--steps", default="", help="sequência: event:X;sleep:N;shot:ARQ;keys:ARGS;dispatch:LUA;cursor:X,Y;ipc:ALVO METODO ARGS")
    parser.add_argument("--log", action="store_true", help="imprime o log inteiro do shell")
    args = parser.parse_args()

    settings = json.loads(args.settings) if args.settings else None
    with NestedSession(theme=args.theme, settings=settings) as session:
        session.start_shell()
        time.sleep(3.5)
        for index, app in enumerate(a for a in args.apps.split(",") if a):
            session.spawn([app])
            time.sleep(0.8)
        time.sleep(1.0)
        for event in args.event:
            session.event(event)
            time.sleep(0.3)
        if args.steps:
            for step in args.steps.split(";"):
                kind, _, value = step.partition(":")
                if kind == "event":
                    session.event(value)
                elif kind == "sleep":
                    time.sleep(float(value))
                elif kind == "shot":
                    print("foto:", session.screenshot(value))
                elif kind == "cursor":
                    x, y = value.split(",")
                    print("cursor:", session.cursor(float(x), float(y)))
                elif kind == "keys":
                    session.keys(*value.split())
                elif kind == "dispatch":
                    print("dispatch:", session.dispatch(value))
                elif kind == "ipc":
                    print("ipc:", session.shell_ipc(*value.split()))
        else:
            time.sleep(args.wait)
            print("foto:", session.screenshot(args.out))
        log = session.shell_log()
        lua = [l for l in session.hyprland_log().splitlines() if "Lua error" in l]
        if args.log:
            print(log)
        else:
            for line in interesting(log)[-60:]:
                print(line)
        for line in lua:
            print("HYPRLAND:", line)


if __name__ == "__main__":
    main()
