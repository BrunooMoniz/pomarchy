"""O Hyprland de teste não pode encostar no HOME real nem no systemd da sessão.
Regressão do incidente de 30/09/2026 (Lixeira real esvaziada por um teste)."""
import json
import os
import subprocess
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nested  # noqa: E402

SKIP = os.environ.get("POMAR_SKIP_E2E") == "1"

# A sonda nunca EXECUTA comando perigoso: só confere para onde cada nome
# aponta. Se o dublê faltasse, rodar o comando de verdade seria o próprio acidente.
PROBE = r'''
set -u
out="$1"
{
  printf 'HOME=%s\n' "$HOME"
  for v in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do
    printf '%s=%s\n' "$v" "${!v:-}"
  done
  for c in gio uwsm-app gtk-launch systemctl systemd-run xdg-open omarchy omarchy-launch-about omarchy-theme-set pomar; do
    printf 'which:%s=%s\n' "$c" "$(command -v "$c")"
  done
  mkdir -p "$XDG_DATA_HOME/Trash/files" && touch "$XDG_DATA_HOME/Trash/files/sonda"
} > "$out" 2>&1
'''


@unittest.skipIf(SKIP, "POMAR_SKIP_E2E=1")
class IsolationTest(unittest.TestCase):
    def test_everything_stays_inside_the_test_home(self):
        before = nested.fingerprint()
        with nested.NestedSession(theme="pomarchy") as session:
            report = session.root / "sonda.txt"
            probe = session.spawn(["bash", "-c", PROBE, "sonda", str(report)])
            probe.wait(timeout=20)
            text = report.read_text()
            values = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
            root = str(session.root)
            runtime = str(session.runtime)
            self.assertTrue(values["HOME"].startswith(root), text)
            for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"):
                self.assertTrue(values[key].startswith(root), f"{key} vazou: {values[key]}")
            self.assertTrue(values["XDG_RUNTIME_DIR"].startswith(runtime))
            self.assertIn(runtime, values["DBUS_SESSION_BUS_ADDRESS"])
            for key, where in values.items():
                if key.startswith("which:"):
                    self.assertTrue(where.startswith(str(session.stubs)), f"{key[6:]} não é dublê: {where}")
            self.assertTrue((session.home / ".local/share/Trash/files/sonda").exists())
        self.assertEqual(before, nested.fingerprint(), "o HOME real mudou durante o teste")


if __name__ == "__main__":
    unittest.main()
