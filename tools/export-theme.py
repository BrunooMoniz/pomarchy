#!/usr/bin/env python3
"""Monta os repositórios só de tema (omarchy-pomarchy-theme e
omarchy-pomarchy-escuro-theme) a partir de themes/, com os arquivos na raiz, que
é como o `omarchy theme install <url>` espera. Os repositórios de tema não são
editados à mão: tudo sai daqui, e o Pomarchy continua sendo a fonte.

Uso: python3 tools/export-theme.py [DESTINO]   (padrão: out/theme-repos)
"""
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SUITE = "https://github.com/BrunooMoniz/pomarchy"
THEMES = {
    "pomarchy": ("Pomarchy", "light", "claro"),
    "pomarchy-escuro": ("Pomarchy Escuro", "dark", "escuro"),
}

README = """# {title}

The {kind} theme of [Pomarchy OS]({suite}), a Mac-style desktop for Omarchy 4.

![{title}](preview.png)

```bash
omarchy theme install https://github.com/BrunooMoniz/{repo}
```

This theme brings the colors, the wallpapers and the look of the Omarchy shell.
The Dock, Launchpad, Mission Control, window buttons and the Mac menu bar come
with Pomarchy OS itself:

```bash
git clone {suite}
cd pomarchy
./install.sh
```

If you install Pomarchy OS later, its installer moves this folder to
`~/.local/state/pomar/backup/` and links its own copy of the theme in its
place, so both stay the same theme.

Made for Pomarchy OS. The files here are generated from the
[Pomarchy repository]({suite}/tree/main/themes/{name}); send changes there.

## Em português

O tema {kind_pt} do [Pomarchy OS]({suite}), o Omarchy 4 com jeito de Mac.

```bash
omarchy theme install https://github.com/BrunooMoniz/{repo}
```

Sozinho, ele traz as cores, os papéis de parede e o visual do shell do Omarchy.
O Dock, o Launchpad, o Mission Control, os botões nas janelas e a barra de menus
do Mac vêm com o Pomarchy OS: veja o [repositório]({suite}). Se você instalar o
Pomarchy OS depois, o instalador guarda esta pasta em
`~/.local/state/pomar/backup/` e põe a cópia dele do tema no lugar.

MIT © 2026 Bruno Moniz
"""


def export(name, destination):
    title, kind, kind_pt = THEMES[name]
    repo = f"omarchy-{name}-theme"
    target = destination / repo
    if target.exists():
        # Mantém o .git de um clone do repositório público, troca todo o resto.
        for item in target.iterdir():
            if item.name != ".git":
                shutil.rmtree(item) if item.is_dir() else item.unlink()
    target.mkdir(parents=True, exist_ok=True)
    source = REPO / "themes" / name
    for item in source.iterdir():
        if item.is_symlink():
            raise SystemExit(f"{item}: link simbólico não vai para o repositório do tema")
        if item.is_dir():
            shutil.copytree(item, target / item.name)
        else:
            shutil.copy2(item, target / item.name)
    (target / "README.md").write_text(README.format(title=title, kind=kind, kind_pt=kind_pt, suite=SUITE, repo=repo,
                                                    name=name))
    shutil.copy2(REPO / "LICENSE", target / "LICENSE")
    return target


if __name__ == "__main__":
    destination = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "out" / "theme-repos"
    for theme in THEMES:
        print(export(theme, destination))
