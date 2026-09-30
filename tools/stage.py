#!/usr/bin/env python3
"""Monta a árvore instalável do Pomarchy num diretório de destino.

O Omarchy não aceita links simbólicos dentro de uma pasta de plugin, então o
código comum (shared/) é copiado para dentro de cada plugin aqui, na
montagem, e não fica duplicado no repositório.

Uso: tools/stage.py DESTINO [--from DIR]
"""
import argparse
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
COPIED = ("hypr", "bin", "hooks", "themes", "applications", "icons", "VERSION", "LICENSE", "README.md",
          "install.sh", "uninstall.sh")


def stage(destination: Path, source: Path = REPO) -> Path:
    destination = destination.resolve()
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    for name in COPIED:
        item = source / name
        if item.is_dir():
            shutil.copytree(item, destination / name, symlinks=False)
        elif item.exists():
            shutil.copy2(item, destination / name)
    # Cada peça é uma pasta na raiz do repositório com manifest.json (como as
    # suítes do marketplace do Omarchy); na versão instalada, vão para plugins/.
    for plugin in sorted(source.iterdir()):
        if not plugin.is_dir() or not (plugin / "manifest.json").is_file():
            continue
        target = destination / "plugins" / plugin.name
        shutil.copytree(plugin, target, symlinks=False,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".qmlls.ini"))
        shutil.copytree(source / "shared", target / "shared", symlinks=False)
    return destination


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("destination", type=Path)
    parser.add_argument("--from", dest="source", type=Path, default=REPO)
    args = parser.parse_args(argv)
    print(stage(args.destination, args.source.resolve()))


if __name__ == "__main__":
    sys.exit(main())
