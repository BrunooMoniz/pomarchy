# Installing Pomarchy OS

*Em português: [docs/pt/instalar.md](pt/instalar.md)*

```bash
git clone https://github.com/BrunooMoniz/pomarchy
cd pomarchy
./install.sh
```

Pomarchy installs only for your user. It never asks for administrator rights, and it only
changes the files listed below. Run the installer as often as you like: it
detects what is already in place, and the result is always the same.

## What happens, step by step

Before step 2 the installer prints this list and asks `Install? [Y/n]`. With
`--yes` it skips the question. Without a terminal and without `--yes` it stops
and changes nothing. Ctrl+D counts as "no" too.

1. **Check the computer**: Omarchy 4, Hyprland with the Lua config, Python 3.
2. **Prepare the files**: builds a version under `~/.local/share/pomar/releases/`
   and points `~/.local/share/pomar/current` at it. Each plugin is checked
   with `omarchy plugin validate` first.
3. **Themes**: links *Pomarchy* and *Pomarchy Escuro* into `~/.config/omarchy/themes/`.
4. **Plugins**: links the seven `pomar.*` plugins into `~/.config/omarchy/plugins/`.
5. **Hyprland**: adds one marked block to `~/.config/hypr/hyprland.lua`, right
   after Omarchy's defaults. The block loads Pomarchy's gestures, shortcuts and
   animations, which only act while a Pomarchy theme is active. The new file is
   checked with `luac -p` before it is written, and Hyprland is reloaded. If the
   reload shows a new error caused by Pomarchy, the installer removes the block
   again, and your file goes back to what it was before.
6. **Settings**: creates `~/.config/pomar/settings.json` the first time. If you
   already use three-finger swipes elsewhere, Pomarchy moves to four fingers.
7. **Launcher**: adds Launchpad, Mission Control and Pomarchy Settings to the app list.
8. **Command and theme hook**: adds `~/.local/bin/pomar` and the theme-set hook
   that switches the top bar when you change themes.
9. **Plugins on**: turns the plugins on through the running shell. On an update
   it restarts the shell so the new code loads. It never does this while the
   screen is locked; if the screen is locked, it restarts on the next run
   instead.
10. **Top bar**: with a Pomarchy theme, the Mac menu bar. Your bar is saved to
    `~/.local/state/pomar/bar-backup.json` first.
11. **Theme**: applies *Pomarchy* (or *Pomarchy Escuro* with `--dark`, or if
    you were already using the dark one).

Anything that has to move out of the way goes to
`~/.local/state/pomar/backup/<date>/` and is listed in
`~/.local/state/pomar/movidos.jsonl`, so that uninstalling can put it back.

## Options

| Option | What it does |
| --- | --- |
| `--yes` | install and apply without asking |
| `--no-apply` | install, but keep your current theme; the bar follows that theme |
| `--no-bar` | leave the Omarchy top bar alone, also on later theme changes |
| `--dark` | use the dark theme |
| `--lang en` / `--lang pt` | the installer's language |

## When something looks wrong

```bash
pomar doctor
```

It checks every piece and says what to run to fix it. The installer log is at
`~/.local/state/pomar/install.log`.
