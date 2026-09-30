#!/usr/bin/env bash
# Desinstalador do Pomarchy: devolve o Omarchy ao que era antes.
#
#   ~/.local/share/pomar/current/uninstall.sh [--purge] [--lang en|pt]
#
# Volta o tema e a barra de antes, desliga as peças do Pomarchy e tira os links, os
# atalhos do lançador e o bloco do hyprland.lua (que fica igual ao original,
# byte a byte). Seus ajustes (~/.config/pomar) e as versões baixadas ficam, a
# não ser com --purge. As cópias de segurança em ~/.local/state/pomar/backup
# nunca são apagadas: podem ter coisas suas.

set -Eeuo pipefail

# ------------------------------------------------------------------ idioma
# Cópia do pomar_lang e do L do bin/pomar (a regra está explicada lá), para o
# que o desinstalador diz quando não acha o bin/pomar. Carregado o bin/pomar,
# valem os dele.
pomar_lang() {
  local choice="${1:-}" value settings=""
  if [[ -z $choice ]]; then
    value="${POMAR_LANG:-}"
    case "${value,,}" in en | pt) choice="${value,,}" ;; esac
  fi
  [[ ${HOME:-} != /* ]] || settings="$HOME/.config/pomar/settings.json"
  if [[ -z $choice && -n $settings && -f $settings ]]; then
    value=""
    { read -r -d '' value <"$settings"; } 2>/dev/null || true
    if [[ $value =~ \"language\"[[:space:]]*:[[:space:]]*\"([A-Za-z]*)\" ]]; then
      value="${BASH_REMATCH[1],,}"
      if [[ $value == en || $value == pt ]]; then choice="$value"; fi
    fi
  fi
  if [[ -z $choice ]]; then
    for value in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}" "${LANGUAGE:-}"; do
      if [[ ${value,,} == pt* ]]; then
        choice=pt
        break
      fi
    done
  fi
  POMAR_UI_LANG="${choice:-en}"
  export POMAR_UI_LANG
}

L() {
  if [[ ${POMAR_UI_LANG:-en} == pt ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}

usage() {
  if [[ ${POMAR_UI_LANG:-en} == pt ]]; then
    cat <<'EOF'
Uso: uninstall.sh [--purge] [--lang en|pt]

  --purge   apaga também os ajustes (~/.config/pomar) e as versões baixadas
            (~/.local/share/pomar); as cópias de segurança continuam
  --lang en|pt
            mensagens em inglês (en) ou em português (pt)
  --help    mostra esta ajuda
EOF
  else
    cat <<'EOF'
Usage: uninstall.sh [--purge] [--lang en|pt]

  --purge   also deletes the settings (~/.config/pomar) and the downloaded
            versions (~/.local/share/pomar); the backups stay
  --lang en|pt
            messages in English (en) or Portuguese (pt)
  --help    shows this help
EOF
  fi
}

# Só anota as opções. A ajuda e os erros esperam o idioma (um --lang pode vir
# depois deles); vale a primeira opção que encerra, --help ou uma desconhecida.
PURGE=0 LANG_CHOICE="" ARGS_END=""
parse_args() {
  local value
  while (($#)); do
    case "$1" in
      --purge) PURGE=1 ;;
      --lang | --lang=*)
        if [[ $1 == --lang=* ]]; then
          value="${1#--lang=}"
        elif (($# > 1)); then
          shift
          value="$1"
        else
          value=""
        fi
        case "${value,,}" in
          en | pt) LANG_CHOICE="${value,,}" ;;
          *) ARGS_END="${ARGS_END:-lang:$value}" ;;
        esac
        ;;
      -h | --help) ARGS_END="${ARGS_END:-help}" ;;
      *) ARGS_END="${ARGS_END:-option:$1}" ;;
    esac
    shift
  done
}

# Com o idioma escolhido: a ajuda, ou o erro da opção.
finish_args() {
  case "$ARGS_END" in
    "") return 0 ;;
    help)
      usage
      exit 0
      ;;
    lang:*)
      printf '%s\n\n' "$(L "Unknown language: \"${ARGS_END#lang:}\" (use en or pt)" \
        "Idioma desconhecido: \"${ARGS_END#lang:}\" (use en ou pt)")" >&2
      ;;
    *) printf '%s\n\n' "$(L "Unknown option: ${ARGS_END#option:}" "Opção desconhecida: ${ARGS_END#option:}")" >&2 ;;
  esac
  usage >&2
  exit 2
}

LOG=""
fail() {
  printf '\n%s✗ %s%s\n' "$POMAR_C_ERR" "$*" "$POMAR_C_OFF" >&2
  printf '  %s\n' "$(L "Details in $(pretty "$LOG"). You can run the uninstaller again." \
    "Detalhes em $(pretty "$LOG"). Pode rodar o desinstalador de novo.")" >&2
  exit 1
}

on_error() {
  local status=$? line="$1"
  trap - ERR
  printf '\n%s✗ %s%s\n' "$POMAR_C_ERR" "$(L "Something went wrong in the uninstaller (line $line)." \
    "Algo deu errado no desinstalador (linha $line).")" "$POMAR_C_OFF" >&2
  printf '  %s\n' "$(L "Details in $(pretty "$LOG"). You can run the uninstaller again." \
    "Detalhes em $(pretty "$LOG"). Pode rodar o desinstalador de novo.")" >&2
  exit "$status"
}

# ------------------------------------------------- 1. janelas minimizadas
# O Dock guarda as janelas minimizadas numa mesa escondida; sem o Dock, elas
# sumiriam de vista. Voltam para a mesa ativa antes de desligar qualquer coisa.
restore_minimized() {
  step 1 "$(L "Minimized windows" "Janelas minimizadas")"
  if ! hypr_running; then
    ok "$(L "Hyprland isn't running; there are no windows to bring back" "O Hyprland não está rodando; não há janelas para devolver")"
    return 0
  fi
  local clients active workspace address out count=0 failed=0
  clients=$(hyprctl -j clients 2>/dev/null) && pomar_py json-list "$clients" ||
    fail "$(L "Couldn't ask Hyprland for the minimized windows; stopped before turning anything off." \
      "Não consegui perguntar ao Hyprland pelas janelas minimizadas; parei antes de desligar qualquer coisa.")"
  active=$(hyprctl -j activeworkspace 2>/dev/null) || active="{}"
  workspace=$(pomar_py active-workspace "$active")
  while IFS= read -r address; do
    [[ -n $address ]] || continue
    # O hyprctl pode sair com 0 e responder um erro: só "ok" (ou nada) vale.
    if out=$(hyprctl dispatch "hl.dsp.window.move({ window = \"address:$address\", workspace = \"$workspace\", follow = false })" 2>&1) &&
      [[ -z $out || $out == ok ]]; then
      count=$((count + 1))
    else
      printf 'Janela %s não voltou: %s\n' "$address" "$out" >>"$LOG"
      failed=$((failed + 1))
    fi
  done < <(pomar_py minimized-windows "$clients")
  if ((failed)); then
    fail "$(L "$failed window(s) minimized to the Dock didn't come back to the desktop; stopped before turning anything off." \
      "$failed janela(s) minimizada(s) no Dock não voltaram para a mesa; parei antes de desligar qualquer coisa.")"
  fi
  if ((count)); then
    ok "$(L "$count minimized window(s) back on desktop $workspace" "$count janela(s) minimizada(s) de volta na mesa $workspace")"
  else
    ok "$(L "No minimized windows" "Nenhuma janela minimizada")"
  fi
}

# ------------------------------------------------------------------ 2. tema
# Sem conseguir trocar de tema, para aqui: tirar o tema em uso deixaria o
# Omarchy sem tema nenhum. O tema de antes só é esquecido depois da troca.
restore_theme() {
  step 2 "$(L "Theme" "Tema")"
  local current previous=""
  current=$(current_theme)
  if [[ $current != pomar* ]]; then
    ok "$(L "The current theme ($(theme_title "${current:-unknown}")) isn't a Pomarchy theme; leaving it as is" \
      "O tema atual ($(theme_title "${current:-desconhecido}")) não é do Pomarchy; fica como está")"
    rm -f -- "$POMAR_PREVIOUS_THEME"
    return 0
  fi
  [[ -f $POMAR_PREVIOUS_THEME ]] && previous=$(tr -d '[:space:]' <"$POMAR_PREVIOUS_THEME")
  [[ -n $previous && $previous != pomar* ]] || previous="$OMARCHY_DEFAULT_THEME"
  if omarchy theme set "$previous" >>"$LOG" 2>&1; then
    ok "$(L "Back to the $(theme_title "$previous") theme" "De volta ao tema $(theme_title "$previous")")"
  elif [[ $previous != "$OMARCHY_DEFAULT_THEME" ]] && omarchy theme set "$OMARCHY_DEFAULT_THEME" >>"$LOG" 2>&1; then
    warn "$(L "The previous theme ($(theme_title "$previous")) no longer exists; used $(theme_title "$OMARCHY_DEFAULT_THEME") instead" \
      "O tema de antes ($(theme_title "$previous")) não existe mais; usei o $(theme_title "$OMARCHY_DEFAULT_THEME")")"
  else
    fail "$(L "Couldn't switch the theme (tried $(theme_title "$previous") and $(theme_title "$OMARCHY_DEFAULT_THEME")). \
To avoid leaving Omarchy without a theme, I stopped before removing anything. Pick another theme in \
Menu > Style > Theme and run the uninstaller again." \
      "Não consegui trocar o tema (tentei $(theme_title "$previous") e $(theme_title "$OMARCHY_DEFAULT_THEME")). \
Para não deixar o Omarchy sem tema, parei antes de tirar qualquer coisa. Escolha outro tema em \
Menu > Estilo > Tema e rode o desinstalador de novo.")"
  fi
  rm -f -- "$POMAR_PREVIOUS_THEME"
}

# ------------------------------------------------------------ 3. peças
# Só os ids das peças desta versão (os manifestos dela e os links que apontam
# para ela), nunca "qualquer coisa que comece com pomar.".
POMAR_IDS=()
POMAR_SHELL_IDS=()
collect_ids() {
  local dir id kinds name
  local -A seen=()
  while IFS=$'\t' read -r dir id kinds name; do
    [[ -n $id && -z ${seen[$id]:-} ]] || continue
    seen[$id]=1
    POMAR_IDS+=("$id")
    [[ ,$kinds, == *,bar-widget,* ]] || POMAR_SHELL_IDS+=("$id")
  done < <(
    pomar_py plugins-in "$POMAR_CURRENT/plugins"
    pomar_py plugins-in "$OMARCHY_PLUGINS" --links-into "$POMAR_DATA"
  )
}

turn_off_plugins() {
  step 3 "$(L "Turning off the Pomarchy plugins" "Desligando as peças do Pomarchy")"
  local id
  collect_ids
  if ((${#POMAR_IDS[@]} == 0)); then
    ok "$(L "No Pomarchy plugins to turn off" "Nenhuma peça do Pomarchy para desligar")"
    return 0
  fi
  if ((${#POMAR_SHELL_IDS[@]})) && shell_running; then
    for id in "${POMAR_SHELL_IDS[@]}"; do
      omarchy plugin disable "$id" >>"$LOG" 2>&1 || true
    done
    # O shell grava o shell.json um instante depois; espera antes do passo 4
    # mexer no mesmo arquivo, senão uma gravação apagaria a outra.
    wait_until 30 0.1 pomar_py plugins-check off "${POMAR_SHELL_IDS[@]}" >/dev/null || true
  fi
  # Sem shell (ou se ele não respondeu), tira direto do shell.json; a barra de
  # menus do Pomarchy sai da barra aqui também.
  kit plugins-off "${POMAR_IDS[@]}" || fail "$(L "Couldn't update $(pretty "$OMARCHY_SHELL_JSON")." "Não consegui atualizar o $(pretty "$OMARCHY_SHELL_JSON").")"
  ok "$(L "${#POMAR_SHELL_IDS[@]} plugins turned off" "${#POMAR_SHELL_IDS[@]} peças desligadas")"
}

# ------------------------------------------------------------ 4. barra
restore_bar() {
  step 4 "$(L "Bar" "Barra")"
  bar_restore_firmly || fail "$(L "Couldn't bring back the Omarchy bar." "Não consegui voltar a barra do Omarchy.")"
  # Uma barra guardada que já tinha peças do Pomarchy não pode trazê-las de volta.
  kit plugins-off "${POMAR_IDS[@]}" || fail "$(L "Couldn't update $(pretty "$OMARCHY_SHELL_JSON")." "Não consegui atualizar o $(pretty "$OMARCHY_SHELL_JSON").")"
}

# ------------------------------------------------------------ 5. links
remove_links() {
  step 5 "$(L "Themes, plugins and the pomar command" "Temas, peças e o comando pomar")"
  local link removed=0
  for link in "$OMARCHY_THEMES"/* "$OMARCHY_PLUGINS"/* "$POMAR_BIN_LINK" "$HOME/.local/bin/pomarchy" "$POMAR_THEME_HOOK"; do
    [[ -L $link ]] && points_into_pomar "$link" || continue
    rm -f -- "$link"
    removed=$((removed + 1))
  done
  if ((removed)) && shell_running; then
    omarchy-shell shell rescanPlugins >>"$LOG" 2>&1 || true
  fi
  ok "$(L "$removed Pomarchy links removed (only the ones pointing into $(pretty "$POMAR_DATA"))" \
    "$removed links do Pomarchy tirados (só os que apontavam para $(pretty "$POMAR_DATA"))")"
}

# ---------------------------------------------------------- 6. lançador
remove_launchers() {
  step 6 "$(L "Launcher shortcuts" "Atalhos no lançador")"
  local file removed=0 icons=0
  for file in "$APPS_DIR"/*.desktop; do
    is_pomar_desktop "$file" || continue
    rm -f -- "$file"
    removed=$((removed + 1))
  done
  for file in "$ICONS_DIR"/*.svg; do
    is_pomar_icon "$file" || continue
    rm -f -- "$file"
    icons=$((icons + 1))
  done
  ((icons == 0)) || update_icon_cache
  ok "$(L "$removed Pomarchy shortcuts and $icons icons removed" "$removed atalhos e $icons ícones do Pomarchy tirados")"
}

# ------------------------------------------- 7. o que foi tirado do lugar
restore_moved() {
  step 7 "$(L "What Pomarchy had set aside" "O que o Pomarchy tinha guardado")"
  kit restore-moves || fail "$(L "Couldn't put back what was kept in $(pretty "$POMAR_BACKUPS")." "Não consegui devolver o que estava guardado em $(pretty "$POMAR_BACKUPS").")"
  [[ $PY_STATUS != 0 ]] || ok "$(L "Nothing to put back" "Nada para devolver")"
}

# ---------------------------------------------------------- 8. Hyprland
unhook_hyprland() {
  step 8 "Hyprland"
  local copy
  if [[ ! -f $HYPR_CONFIG ]]; then
    ok "$(L "No $(pretty "$HYPR_CONFIG"); nothing to remove" "Sem $(pretty "$HYPR_CONFIG"); nada a tirar")"
    return 0
  fi
  copy=$(snapshot "$HYPR_CONFIG")
  if ! kit hypr-remove "$HYPR_CONFIG"; then
    rm -f -- "$copy"
    fail "$(L "Couldn't take Pomarchy out of $(pretty "$HYPR_CONFIG")." "Não consegui tirar o Pomarchy do $(pretty "$HYPR_CONFIG").")"
  fi
  keep_snapshot "$copy" "hypr/hyprland.lua" "$HYPR_CONFIG"
  if [[ $PY_STATUS != changed ]]; then
    ok "$(L "$(pretty "$HYPR_CONFIG") already had no Pomarchy block" "O $(pretty "$HYPR_CONFIG") já estava sem o Pomarchy")"
    return 0
  fi
  ok "$(L "Pomarchy block removed; $(pretty "$HYPR_CONFIG") is back to how it was" "Bloco do Pomarchy tirado; o $(pretty "$HYPR_CONFIG") voltou a ser como era")"
  if hypr_running; then
    hyprctl reload >>"$LOG" 2>&1 || true
    ok "$(L "Hyprland reloaded" "Hyprland recarregado")"
  fi
}

# ------------------------------------------------------------ 9. arquivos
purge_files() {
  step 9 "$(L "Pomarchy files" "Arquivos do Pomarchy")"
  if ((!PURGE)); then
    ok "$(L "Kept your settings ($(pretty "$POMAR_CONFIG")) and the downloaded versions ($(pretty "$POMAR_DATA"))" \
      "Ficaram seus ajustes ($(pretty "$POMAR_CONFIG")) e as versões baixadas ($(pretty "$POMAR_DATA"))")"
    return 0
  fi
  rm -rf -- "$POMAR_CONFIG"
  if [[ -d $POMAR_STATE ]]; then
    find "$POMAR_STATE" -mindepth 1 -maxdepth 1 ! -name backup -exec rm -rf -- {} +
    rmdir -- "$POMAR_STATE" 2>/dev/null || true
  fi
  ok "$(L "Settings deleted" "Ajustes apagados")"
  # Por último: este script mora aqui dentro (o Linux deixa terminar mesmo assim).
  rm -rf -- "$POMAR_DATA"
  ok "$(L "Downloaded versions deleted" "Versões baixadas apagadas")"
}

summary() {
  printf '\n%s%s%s\n' "$POMAR_C_BOLD" "$(L "Done: Pomarchy has been uninstalled." "Pronto: o Pomarchy foi desinstalado.")" "$POMAR_C_OFF"
  if ((!PURGE)); then
    echo "  $(L "To also delete the settings and the versions:" "Para apagar também os ajustes e as versões:") $(pretty "$POMAR_CURRENT/uninstall.sh") --purge"
  fi
  if [[ -d $POMAR_BACKUPS ]]; then
    echo "  $(L "Backups of what Pomarchy replaced:" "Cópias de segurança do que o Pomarchy substituiu:") $(pretty "$POMAR_BACKUPS")"
  fi
}

main() {
  parse_args "$@"
  local here lib
  here=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
  lib="$here/bin/pomar"
  [[ -f $lib ]] || lib="$HOME/.local/share/pomar/current/bin/pomar"
  if [[ -f $lib ]]; then
    # shellcheck source=bin/pomar
    source "$lib"
  fi
  pomar_lang "$LANG_CHOICE"
  finish_args
  if [[ ! -f $lib ]]; then
    echo "✗ $(L "Couldn't find the Pomarchy files (bin/pomar); there's nothing to uninstall." \
      "Não achei os arquivos do Pomarchy (bin/pomar); não há o que desinstalar.")" >&2
    exit 1
  fi
  POMAR_INDENT="   "
  command -v python3 >/dev/null 2>&1 || need "$(L "Python 3 is missing (the Arch python package). Install it and run again." \
    "Falta o Python 3 (pacote python do Arch). Instale e rode de novo.")"

  take_lock
  rm -f -- "$POMAR_STATE"/.copia.* # sobras de uma execução interrompida
  LOG="$POMAR_STATE/uninstall.log"
  printf 'Pomarchy: desinstalação em %s\nOpções: %s\n\n' "$(date -Is)" "$*" >"$LOG"
  trap 'on_error $LINENO' ERR

  printf '%s%s%s\n' "$POMAR_C_BOLD" "$(L "Pomar: uninstall" "Pomar: desinstalação")" "$POMAR_C_OFF"
  local shell_copy
  shell_copy=$(snapshot "$OMARCHY_SHELL_JSON")
  restore_minimized
  restore_theme
  turn_off_plugins
  restore_bar
  keep_snapshot "$shell_copy" "omarchy/shell.json" "$OMARCHY_SHELL_JSON"
  remove_links
  remove_launchers
  restore_moved
  unhook_hyprland
  purge_files
  summary
}

main "$@"
