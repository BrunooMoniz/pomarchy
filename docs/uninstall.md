# Removing Pomarchy OS

*Em português: [docs/pt/desinstalar.md](pt/desinstalar.md)*

```bash
~/.local/share/pomar/current/uninstall.sh
```

The uninstaller works in this order, and it stops before the first step it
cannot finish safely:

1. **Minimized windows** come back to your current desktop. If Hyprland is
   running but does not list its windows, the uninstaller stops here, before
   anything is turned off. Run from outside a Hyprland session, it skips this step.
2. **Theme**: switches back to the theme you had before Pomarchy (or Omarchy's
   default). If no theme can be applied, it stops here, because removing the
   active theme would leave Omarchy without one.
3. **Plugins off**: turns off exactly the seven `pomar.*` plugins of the
   installed version, and nothing else.
4. **Top bar**: restores your saved bar. The saved copy is archived only after the
   restored bar is confirmed on disk. If the shell keeps writing the old bar back,
   the uninstaller stops and keeps the copy. Run it again later.
5. **Links**: removes only links that point into `~/.local/share/pomar`, including
   the theme-set hook and the `pomar` command.
6. **Launcher entries and icons** that Pomarchy created.
7. **Your files come back**: anything Pomarchy moved aside returns to its place,
   if that place is still free.
8. **Hyprland**: removes the marked block. `~/.config/hypr/hyprland.lua` ends up
   byte-for-byte as it was.
9. **Files**: your settings (`~/.config/pomar`) and the downloaded versions stay.
   `--purge` deletes them too.

Backups in `~/.local/state/pomar/backup/` are never deleted, not even by
`--purge`.

To go back to plain Omarchy without uninstalling, pick any other theme. The
top bar and everything else return to Omarchy's, and nothing Pomarchy adds is
active.
