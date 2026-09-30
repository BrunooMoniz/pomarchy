#!/usr/bin/env bash
# Instalador do Pomarchy: o Omarchy 4 com jeito de Mac.
#
#   git clone https://github.com/BrunooMoniz/pomarchy && cd pomarchy && ./install.sh
#   ./install.sh [--yes] [--no-apply] [--no-bar] [--dark] [--lang en|pt]
#
# Pode rodar de novo quantas vezes quiser: o resultado é o mesmo. Nada do que é
# seu se perde; o que for substituído vai para ~/.local/state/pomar/backup/.
# Para desfazer: ~/.local/share/pomar/current/uninstall.sh
#
# Tudo fica dentro de funções e só a última linha roda algo: um arquivo cortado
# no meio não executa nada pela metade.

set -Eeuo pipefail

POMAR_REPO_DEFAULT="https://github.com/BrunooMoniz/pomarchy.git"

# ------------------------------------------------------------------ idioma
# Cópia do pomar_lang e do L do bin/pomar (a regra está explicada lá), para o
# que o instalador diz quando roda sozinho, sem o resto do Pomarchy ao lado (a
# ajuda e o download). Carregado o bin/pomar, valem os dele.
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
Uso: install.sh [opções]

  --yes        instala e aplica sem perguntar nada
  --no-apply   instala, mas não troca o tema agora
  --no-bar     não mexe na barra do Omarchy
  --dark       usa o tema escuro (Pomarchy Escuro)
  --lang en|pt mensagens em inglês (en) ou em português (pt)
  --help       mostra esta ajuda

Para desfazer: ~/.local/share/pomar/current/uninstall.sh
EOF
  else
    cat <<'EOF'
Usage: install.sh [options]

  --yes        installs and applies without asking anything
  --no-apply   installs, but doesn't switch the theme now
  --no-bar     leaves the Omarchy bar alone
  --dark       uses the dark theme (Pomarchy Escuro)
  --lang en|pt messages in English (en) or Portuguese (pt)
  --help       shows this help

To undo: ~/.local/share/pomar/current/uninstall.sh
EOF
  fi
}

# Só anota as opções. A ajuda e os erros esperam o idioma (um --lang pode vir
# depois deles); vale a primeira opção que encerra, --help ou uma desconhecida.
ASSUME_YES=0 APPLY=1 BAR=1 DARK=0 LANG_CHOICE="" ARGS_END=""
parse_args() {
  local value
  while (($#)); do
    case "$1" in
      -y | --yes) ASSUME_YES=1 ;;
      --no-apply) APPLY=0 ;;
      --no-bar) BAR=0 ;;
      --dark) DARK=1 ;;
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

# Sem as ferramentas de montagem ao lado (o install.sh de uma versão já
# instalada, para atualizar): baixa o Pomarchy para ~/.local/share/pomar/src e
# segue de lá.
bootstrap() {
  local repo="${POMAR_REPO:-$POMAR_REPO_DEFAULT}"
  local data="$HOME/.local/share/pomar"
  local src="$data/src" fresh="$data/.src-novo-$$" keep
  if [[ -n ${POMAR_BOOTSTRAPPED:-} ]]; then
    echo "✗ $(L "The downloaded copy of Pomarchy is incomplete (tools/stage.py is missing)." \
      "A cópia baixada do Pomarchy está incompleta (falta tools/stage.py).")" >&2
    exit 1
  fi
  command -v git >/dev/null 2>&1 || {
    echo "✗ $(L "Downloading Pomarchy needs git (the Arch git package). Install it and run again." \
      "Para baixar o Pomarchy é preciso o git (pacote git do Arch). Instale e rode de novo.")" >&2
    exit 1
  }
  if ((!ASSUME_YES)); then
    if ! [[ -t 1 ]] || ! { : </dev/tty; } 2>/dev/null; then
      echo "✗ $(L "There's no terminal to ask before downloading. To go ahead without questions: install.sh --yes" \
        "Sem um terminal para perguntar antes de baixar. Para seguir sem perguntas: install.sh --yes")" >&2
      exit 1
    fi
    local answer=""
    printf '%s ' "$(L "Download the latest Pomarchy ($repo)? Before installing, the installer shows what will change. [Y/n]" \
      "Baixar a versão mais nova do Pomarchy ($repo)? Antes de instalar, o instalador mostra o que muda. [S/n]")" >/dev/tty
    if ! read -r answer </dev/tty; then
      printf '\n%s\n' "$(L "Nothing was changed." "Nada foi mudado.")" >/dev/tty
      exit 0
    fi
    case "${answer,,}" in
      "" | s | sim | y | yes) ;;
      *) printf '%s\n' "$(L "Nothing was changed." "Nada foi mudado.")" >/dev/tty; exit 0 ;;
    esac
  fi
  echo "$(L "Downloading Pomarchy ($repo)..." "Baixando o Pomarchy ($repo)...")"
  mkdir -p "$data"
  rm -rf -- "$fresh"
  if ! git clone --quiet --depth 1 -- "$repo" "$fresh"; then
    rm -rf -- "$fresh"
    echo "✗ $(L "Couldn't download Pomarchy from $repo. Check your internet connection and the address, then try again." \
      "Não consegui baixar o Pomarchy de $repo. Confira a internet e o endereço, e tente de novo.")" >&2
    exit 1
  fi
  if [[ -e $src || -L $src ]]; then
    # A cópia anterior nunca é apagada: vai inteira para o backup.
    keep="$HOME/.local/state/pomar/backup/$(date +%Y%m%d-%H%M%S)-src"
    [[ ! -e $keep && ! -L $keep ]] || keep="$keep-$$"
    mkdir -p -- "$(dirname -- "$keep")"
    mv -T -- "$src" "$keep"
    echo "  $(L "The previous copy was saved in ${keep/#"$HOME"/\~}" "A cópia anterior foi guardada em ${keep/#"$HOME"/\~}")"
  fi
  mv -T -- "$fresh" "$src"
  POMAR_BOOTSTRAPPED=1 exec bash "$src/install.sh" "$@"
}

# ------------------------------------------------------------------ erros
LOG=""
explain_recovery() {
  printf '  %s\n' "$(L "Nothing of yours was lost." "Nada do que é seu foi perdido.")"
  [[ -z $BACKUP_DIR ]] || printf '  %s %s\n' "$(L "Copies of what was replaced:" "Cópias do que foi substituído:")" "$(pretty "$BACKUP_DIR")"
  [[ -z $LOG ]] || printf '  %s %s\n' "$(L "Details in" "Detalhes em")" "$(pretty "$LOG")"
  printf '  %s' "$(L "You can run the installer again." "Pode rodar o instalador de novo.")"
  [[ ! -f $POMAR_CURRENT/uninstall.sh ]] || printf ' %s %s' "$(L "To undo:" "Para desfazer:")" "$(pretty "$POMAR_CURRENT/uninstall.sh")"
  printf '\n'
}

fail() {
  printf '\n%s✗ %s%s\n' "$POMAR_C_ERR" "$*" "$POMAR_C_OFF" >&2
  explain_recovery >&2
  exit 1
}

on_error() {
  local status=$? line="$1"
  trap - ERR
  printf '\n%s✗ %s%s\n' "$POMAR_C_ERR" "$(L "Something went wrong in the installer (line $line)." \
    "Algo deu errado no instalador (linha $line).")" "$POMAR_C_OFF" >&2
  explain_recovery >&2
  exit "$status"
}

# --------------------------------------------------------------- 1. requisitos
check_requirements() {
  step 1 "$(L "Checking this computer" "Conferindo o computador")"
  [[ $EUID -ne 0 ]] || need "$(L "Run this as your own user, not as root: Pomarchy installs just for you." \
    "Rode como o seu usuário, não como root: o Pomarchy se instala só para você.")"
  local omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"
  command -v omarchy >/dev/null 2>&1 ||
    need "$(L "Couldn't find Omarchy on this computer. Pomarchy is made for Omarchy 4 (omarchy.org)." \
      "Não achei o Omarchy neste computador. O Pomarchy é feito para o Omarchy 4 (omarchy.org).")"
  if [[ ! -f $omarchy_path/shell/shell.qml ]] || ! command -v omarchy-shell >/dev/null 2>&1; then
    need "$(L "This Omarchy is an older version. Pomarchy needs Omarchy 4; update Omarchy and run again." \
      "Este Omarchy é de uma versão antiga. O Pomarchy precisa do Omarchy 4; atualize o Omarchy e rode de novo.")"
  fi
  ok "Omarchy 4"
  command -v hyprctl >/dev/null 2>&1 || need "$(L "Couldn't find Hyprland (hyprctl), which comes with Omarchy 4." \
    "Não achei o Hyprland (hyprctl), que vem com o Omarchy 4.")"
  if [[ ! -f $HYPR_CONFIG ]]; then
    if [[ -f $HOME/.config/hypr/hyprland.conf ]]; then
      need "$(L "Your Hyprland configuration is still the old kind (hyprland.conf). Pomarchy needs Omarchy 4, which uses ~/.config/hypr/hyprland.lua." \
        "A configuração do Hyprland ainda é a antiga (hyprland.conf). O Pomarchy precisa do Omarchy 4, que usa ~/.config/hypr/hyprland.lua.")"
    fi
    need "$(L "Couldn't find ~/.config/hypr/hyprland.lua. To recreate the Omarchy default: omarchy refresh config hypr/hyprland.lua" \
      "Não achei ~/.config/hypr/hyprland.lua. Para recriar o padrão do Omarchy: omarchy refresh config hypr/hyprland.lua")"
  fi
  ok "Hyprland"
  command -v python3 >/dev/null 2>&1 || need "$(L "Python 3 is missing (the Arch python package). Install it and run again." \
    "Falta o Python 3 (pacote python do Arch). Instale e rode de novo.")"
  ok "Python 3"
}

# ---------------------------------------------------------------- 2. versão
RELEASE_ID="" RELEASE_FROM_GIT=0 POMAR_VERSION="" RELEASE_CHANGED=0
PREVIOUS_RELEASE="" SHELL_RESTART_PENDING=0

release_id() {
  local sha top
  POMAR_VERSION=$(tr -d '[:space:]' <"$SRC_DIR/VERSION" 2>/dev/null || true)
  POMAR_VERSION="${POMAR_VERSION:-0}"
  if command -v git >/dev/null 2>&1 &&
    top=$(git -C "$SRC_DIR" rev-parse --show-toplevel 2>/dev/null) && [[ $top -ef $SRC_DIR ]] &&
    sha=$(git -C "$SRC_DIR" rev-parse --short HEAD 2>/dev/null); then
    RELEASE_FROM_GIT=1
    [[ -z $(git -C "$SRC_DIR" status --porcelain 2>/dev/null) ]] || sha+="-dirty"
    RELEASE_ID="$sha"
  else
    RELEASE_FROM_GIT=0
    RELEASE_ID="$POMAR_VERSION-$(date +%Y%m%d-%H%M%S)"
  fi
}

current_release() {
  local link
  link=$(readlink -- "$POMAR_CURRENT" 2>/dev/null) || return 0
  printf '%s' "${link##*/}"
}

# Troca o link "current" de uma vez só (rename): nunca há um instante sem ele.
switch_current() {
  local wanted="releases/$RELEASE_ID" temporary="$POMAR_DATA/.current-novo-$$"
  if [[ -L $POMAR_CURRENT && $(readlink -- "$POMAR_CURRENT") == "$wanted" ]]; then
    return 0
  fi
  if [[ -e $POMAR_CURRENT && ! -L $POMAR_CURRENT ]]; then
    backup_move "$POMAR_CURRENT" "share-pomar-current"
  fi
  rm -f -- "$temporary"
  ln -s -- "$wanted" "$temporary"
  mv -Tf -- "$temporary" "$POMAR_CURRENT"
  RELEASE_CHANGED=1
  # Se a instalação parar antes do passo 9, a próxima ainda reinicia o shell
  # (ele segue com as peças antigas na memória até isso).
  if [[ -n $PREVIOUS_RELEASE ]] && plugins_changed && shell_running; then
    mkdir -p -- "$POMAR_STATE"
    : >"$POMAR_SHELL_RESTART"
  fi
}

stage_release() {
  step 2 "$(L "Preparing the Pomarchy files" "Preparando os arquivos do Pomarchy")"
  release_id
  mkdir -p "$POMAR_RELEASES"
  local staging="$POMAR_RELEASES/.montando-$$" target previous plugin old count=0
  rm -rf -- "$staging"
  python3 "$SRC_DIR/tools/stage.py" "$staging" >>"$LOG" 2>&1 ||
    fail "$(L "Couldn't assemble the Pomarchy files." "Não consegui montar os arquivos do Pomarchy.")"
  for plugin in "$staging"/plugins/*/; do
    plugin=${plugin%/}
    if ! omarchy plugin validate "$plugin" >>"$LOG" 2>&1; then
      rm -rf -- "$staging"
      fail "$(L "The ${plugin##*/} plugin didn't pass the Omarchy check (omarchy plugin validate)." \
        "A peça ${plugin##*/} não passou na conferência do Omarchy (omarchy plugin validate).")"
    fi
    count=$((count + 1))
  done

  previous=$(current_release)
  PREVIOUS_RELEASE="$previous"
  target="$POMAR_RELEASES/$RELEASE_ID"
  if [[ -d $target && ! -L $target ]] && pomar_py same-tree "$staging" "$target"; then
    rm -rf -- "$staging"
  elif ((!RELEASE_FROM_GIT)) && [[ -n $previous && -d $POMAR_RELEASES/$previous ]] &&
    pomar_py same-tree "$staging" "$POMAR_RELEASES/$previous"; then
    # Mesma versão, sem git para dar nome: fica a que já estava instalada.
    rm -rf -- "$staging"
    RELEASE_ID="$previous"
  else
    if [[ -e $target || -L $target ]]; then
      old="$POMAR_RELEASES/.antiga-$$"
      mv -T -- "$target" "$old"
      mv -T -- "$staging" "$target"
      rm -rf -- "$old"
    else
      mv -T -- "$staging" "$target"
    fi
    RELEASE_CHANGED=1
  fi
  switch_current
  pomar_py prune-releases "$POMAR_RELEASES" "$RELEASE_ID" 2
  ok "$(L "Pomarchy $POMAR_VERSION ($RELEASE_ID) in $(pretty "$POMAR_CURRENT")" "Pomarchy $POMAR_VERSION ($RELEASE_ID) em $(pretty "$POMAR_CURRENT")")"
  ok "$(L "$count plugins checked by Omarchy" "$count peças conferidas pelo Omarchy")"
}

# ----------------------------------------------------------- 3 e 4. links
LINKS_CHANGED=0
place_link() {
  local target="$1" link="$2" label="$3" temporary
  if [[ -L $link && $(readlink -- "$link") == "$target" ]]; then
    return 0
  fi
  if [[ -L $link ]] && points_into_pomar "$link"; then
    : # link antigo do próprio Pomarchy: só troca
  elif [[ -e $link || -L $link ]]; then
    backup_move "$link" "$label"
  fi
  mkdir -p -- "$(dirname -- "$link")"
  temporary="$(dirname -- "$link")/.pomar-novo-$$-${link##*/}"
  rm -f -- "$temporary"
  ln -s -- "$target" "$temporary"
  mv -Tf -- "$temporary" "$link"
  LINKS_CHANGED=1
}

link_themes() {
  step 3 "$(L "Themes" "Temas")"
  mkdir -p "$OMARCHY_THEMES"
  local theme name
  for theme in "$POMAR_CURRENT"/themes/*/; do
    name=${theme%/}
    name=${name##*/}
    place_link "$POMAR_CURRENT/themes/$name" "$OMARCHY_THEMES/$name" "themes/$name"
  done
  # Nomes de antes do Pomarchy OS: o link antigo sai, o tema novo já está no lugar.
  for name in pomar pomar-escuro; do
    if [[ -L $OMARCHY_THEMES/$name ]] && points_into_pomar "$OMARCHY_THEMES/$name"; then
      rm -f -- "$OMARCHY_THEMES/$name"
    fi
  done
  ok "$(L "Pomarchy and Pomarchy Escuro in $(pretty "$OMARCHY_THEMES")" "Pomarchy e Pomarchy Escuro em $(pretty "$OMARCHY_THEMES")")"
}

link_plugins() {
  step 4 "$(L "Pomarchy plugins in Omarchy" "Peças do Pomarchy no Omarchy")"
  mkdir -p "$OMARCHY_PLUGINS"
  local dir id kinds name link count=0
  local -a stale=()
  while IFS=$'\t' read -r dir id kinds name; do
    place_link "$POMAR_CURRENT/plugins/$dir" "$OMARCHY_PLUGINS/$dir" "plugins/$dir"
    count=$((count + 1))
  done < <(pomar_py plugins-in "$POMAR_CURRENT/plugins")
  # Peça que existia numa versão anterior e saiu desta: tira o link que sobrou.
  for link in "$OMARCHY_PLUGINS"/*; do
    if [[ -L $link && ! -e $link ]] && points_into_pomar "$link"; then
      stale+=("${link##*/}")
      rm -f -- "$link"
      LINKS_CHANGED=1
    fi
  done
  if ((${#stale[@]})); then
    kit plugins-off "${stale[@]}" || fail "$(L "Couldn't update $(pretty "$OMARCHY_SHELL_JSON")." "Não consegui atualizar o $(pretty "$OMARCHY_SHELL_JSON").")"
  fi
  ok "$(L "$count plugins in $(pretty "$OMARCHY_PLUGINS")" "$count peças em $(pretty "$OMARCHY_PLUGINS")")"
}

# ------------------------------------------------------------- 5. Hyprland
HYPR_WATCH=0 HYPR_BASELINE="" HYPR_ROLLED_BACK=0 HYPR_SKIPPED=0

hypr_settle() { sleep "${POMAR_HYPR_SETTLE:-0.5}"; }

# O mesmo erro com outro número de linha continua sendo o mesmo erro: o bloco
# do Pomarchy empurra as linhas de baixo do hyprland.lua.
normalize_error() { sed -E 's/:[0-9]+(:[0-9]+)?:/:#:/g; s/([Ll]ine|[Ll]inha) [0-9]+/\1 #/g' <<<"$1"; }

# Erros que não existiam antes do Pomarchy mexer (os que a pessoa já tinha não
# são culpa do Pomarchy e não disparam nada), mais o aviso do bloco quando o
# pomar.lua não carrega.
hypr_new_errors() {
  local now line key
  local -A known=()
  now=$(hypr_errors)
  while IFS= read -r line; do
    [[ -n $line ]] && known["$(normalize_error "$line")"]=1
  done <<<"$HYPR_BASELINE"
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    key=$(normalize_error "$line")
    [[ -n ${known[$key]:-} ]] || printf '%s\n' "$line"
  done <<<"$now"
  if [[ -s $POMAR_HYPR_ERROR ]]; then
    printf '%s %s\n' "$(L "pomar.lua failed to load:" "O pomar.lua não carregou:")" "$(head -n 1 "$POMAR_HYPR_ERROR")"
  fi
}

# Recarrega e confere. Se aparece erro novo, tira o bloco do Pomarchy e confere de
# novo: se sumiu, o erro era do Pomarchy (o hyprland.lua fica como era e avisa);
# se continuou, não era (o bloco volta e só avisa).
hypr_verify() {
  local when="$1" errors
  rm -f -- "$POMAR_HYPR_ERROR"
  hyprctl reload >>"$LOG" 2>&1 || true
  hypr_settle
  errors=$(hypr_new_errors)
  if [[ -z $errors ]]; then
    ok "$(L "Hyprland reloaded, no errors" "Hyprland recarregado, sem erros")"
    return 0
  fi
  printf '%s (%s):\n%s\n' "$(L "New Hyprland errors" "Erros novos do Hyprland")" "$when" "$errors" >>"$LOG"
  local ours=0
  [[ ! -s $POMAR_HYPR_ERROR ]] || ours=1 # o pomar.lua não carregou: é do Pomarchy
  local removed=1
  kit hypr-remove "$HYPR_CONFIG" || removed=0
  rm -f -- "$POMAR_HYPR_ERROR"
  hyprctl reload >>"$LOG" 2>&1 || true
  hypr_settle
  if ((!removed)); then
    warn "$(L "Hyprland complained about the configuration with Pomarchy: $(head -n 1 <<<"$errors")" \
      "O Hyprland reclamou da configuração com o Pomarchy: $(head -n 1 <<<"$errors")")"
    warn "$(L "Couldn't take the Pomarchy block out of $(pretty "$HYPR_CONFIG"); gestures may stay off. See: pomar doctor" \
      "Não consegui tirar o bloco do Pomarchy do $(pretty "$HYPR_CONFIG"); os gestos podem ficar desligados. Veja: pomar doctor")"
    return 0
  fi
  if ((ours)) || [[ -z $(hypr_new_errors) ]]; then
    HYPR_ROLLED_BACK=1
    warn "$(L "Hyprland complained about the configuration with Pomarchy: $(head -n 1 <<<"$errors")" \
      "O Hyprland reclamou da configuração com o Pomarchy: $(head -n 1 <<<"$errors")")"
    warn "$(L "Removed the Pomarchy block from $(pretty "$HYPR_CONFIG"), which is back to how it was before Pomarchy; the rest of Pomarchy stays." \
      "Tirei o bloco do Pomarchy do $(pretty "$HYPR_CONFIG"), que voltou a ser como era antes do Pomarchy; o resto do Pomarchy continua.")"
    return 0
  fi
  kit hypr-add "$HYPR_CONFIG" || true
  hyprctl reload >>"$LOG" 2>&1 || true
  warn "$(L "Hyprland shows an error that doesn't come from Pomarchy: $(head -n 1 <<<"$errors")" \
    "O Hyprland mostra um erro que não vem do Pomarchy: $(head -n 1 <<<"$errors")")"
  note "$(L "Check your files in ~/.config/hypr." "Confira os seus arquivos em ~/.config/hypr.")"
}

hook_hyprland() {
  step 5 "$(L "Gestures, shortcuts and animations in Hyprland" "Gestos, atalhos e animações no Hyprland")"
  local copy changed
  if hypr_running; then
    HYPR_WATCH=1
    HYPR_BASELINE=$(hypr_errors)
  fi
  copy=$(snapshot "$HYPR_CONFIG")
  if ! kit hypr-add "$HYPR_CONFIG"; then
    # O kit já explicou (o arquivo não passaria no luac, ou o bloco está pela
    # metade) e não gravou nada; o resto do Pomarchy segue sem os gestos.
    rm -f -- "$copy"
    HYPR_SKIPPED=1
    warn "$(L "Pomarchy's gestures and shortcuts stay off until that's fixed; the rest carries on." \
      "Os gestos e atalhos do Pomarchy ficam desligados até isso ser resolvido; o resto continua.")"
    return 0
  fi
  changed="$PY_STATUS"
  keep_snapshot "$copy" "hypr/hyprland.lua" "$HYPR_CONFIG"
  if [[ $changed == changed ]]; then
    ok "$(L "Pomarchy hooked into $(pretty "$HYPR_CONFIG") (the previous version is in the backup)" \
      "Pomarchy ligado no $(pretty "$HYPR_CONFIG") (a versão anterior está no backup)")"
  else
    ok "$(L "Already hooked into $(pretty "$HYPR_CONFIG")" "Já estava ligado no $(pretty "$HYPR_CONFIG")")"
  fi
  if ((!HYPR_WATCH)); then
    note "$(L "Hyprland isn't running right now; this takes effect at your next login" "O Hyprland não está rodando agora; vale a partir do próximo login")"
  elif [[ $changed == changed ]] || ((RELEASE_CHANGED)); then
    hypr_verify "$(L "after hooking Pomarchy in" "depois de ligar o Pomarchy")"
  fi
}

# Com o tema aplicado o pomar.lua passa a agir de verdade: confere de novo.
hypr_check_after_theme() {
  ((HYPR_WATCH && !HYPR_ROLLED_BACK && !HYPR_SKIPPED)) || return 0
  hypr_verify "$(L "after applying the theme" "depois de aplicar o tema")"
}

# --------------------------------------------------------------- 6. ajustes
init_settings() {
  step 6 "$(L "Settings" "Ajustes")"
  kit settings-init || fail "$(L "Couldn't create the Pomarchy settings." "Não consegui criar os ajustes do Pomarchy.")"
}

# ------------------------------------------------------- 7. lançador
install_launchers() {
  step 7 "$(L "Launcher shortcuts" "Atalhos no lançador")"
  mkdir -p "$APPS_DIR" "$ICONS_DIR"
  local file name dest icons_changed=0
  for file in "$POMAR_CURRENT"/applications/*.desktop; do
    [[ -f $file ]] || continue
    name=${file##*/}
    dest="$APPS_DIR/$name"
    if [[ -e $dest || -L $dest ]] && ! is_pomar_desktop "$dest"; then
      backup_move "$dest" "applications/$name"
    fi
    kit install-desktop "$file" "$dest" "$POMAR_CURRENT/bin/pomar" || fail "$(L "Couldn't create $(pretty "$dest")." "Não consegui criar $(pretty "$dest").")"
  done
  for file in "$POMAR_CURRENT"/icons/*.svg; do
    [[ -f $file ]] || continue
    name=${file##*/}
    dest="$ICONS_DIR/$name"
    if [[ -e $dest || -L $dest ]] && ! is_pomar_icon "$dest"; then
      backup_move "$dest" "icons/$name"
    fi
    kit write-copy "$file" "$dest" || fail "$(L "Couldn't copy the $name icon." "Não consegui copiar o ícone $name.")"
    [[ $PY_STATUS == unchanged ]] || icons_changed=1
  done
  ((icons_changed == 0)) || update_icon_cache
  ok "$(L "Launchpad, Mission Control and Pomarchy Settings" "Launchpad, Mission Control e Ajustes do Pomarchy")"
}

# ------------------------------------------------------------ 8. comando
link_command() {
  step 8 "$(L "The pomar command" "Comando pomar")"
  place_link "$POMAR_CURRENT/bin/pomar" "$POMAR_BIN_LINK" "local-bin/pomar"
  place_link "$POMAR_CURRENT/bin/pomar" "$HOME/.local/bin/pomarchy" "local-bin/pomarchy"
  ok "$(pretty "$POMAR_BIN_LINK") ($(L "try: pomar help" "experimente: pomar help"))"
  # A barra acompanha o tema: ao sair do Pomarchy, volta a do Omarchy.
  place_link "$POMAR_CURRENT/hooks/theme-set" "$POMAR_THEME_HOOK" "hooks/theme-set.d/50-pomarchy"
  ok "$(L "The Omarchy bar comes back when the theme isn't Pomarchy" "Barra do Omarchy de volta quando o tema não é Pomarchy")"
}

# -------------------------------------------------------- 9. ligar as peças
plugins_known() {
  local listing
  listing=$(omarchy plugin list --json 2>/dev/null) || return 1
  pomar_py plugins-known "$listing" "$@"
}

# Atualização com o shell aberto: ele guarda na memória o código das peças que
# já carregou (mesmo id e versão, o rescanPlugins não troca). Só um shell novo
# carrega o código novo. O omarchy restart shell se recusa com a tela
# bloqueada; aí as peças novas ficam para o próximo login.
# As peças mudaram de uma versão para a outra? Sem as duas para comparar (mesmo
# nome de versão refeita por cima, ou a anterior já apagada), diz que sim.
plugins_changed() {
  local old="$POMAR_RELEASES/$PREVIOUS_RELEASE/plugins" new="$POMAR_RELEASES/$RELEASE_ID/plugins"
  [[ $PREVIOUS_RELEASE != "$RELEASE_ID" && -d $old && -d $new ]] || return 0
  ! pomar_py same-tree "$old" "$new"
}

restart_shell_for_update() {
  if omarchy restart shell >>"$LOG" 2>&1; then
    # O shell novo já foi aberto; só pode demorar a responder.
    rm -f -- "$POMAR_SHELL_RESTART"
    wait_until 100 0.1 shell_running || true
    return 0
  fi
  SHELL_RESTART_PENDING=1
  mkdir -p -- "$POMAR_STATE"
  : >"$POMAR_SHELL_RESTART" # a próxima instalação tenta de novo
  omarchy-shell shell rescanPlugins >>"$LOG" 2>&1 || true
}

enable_plugins() {
  step 9 "$(L "Turning on the Dock, Launchpad and friends" "Ligando o Dock, o Launchpad e companhia")"
  local dir id kinds name
  local -a ids=() names=() failed=()
  while IFS=$'\t' read -r dir id kinds name; do
    [[ ,$kinds, == *,bar-widget,* ]] && continue # a barra de menus entra no passo 10
    ids+=("$id")
    names+=("$name")
  done < <(pomar_py plugins-in "$POMAR_CURRENT/plugins")
  ((${#ids[@]})) || return 0

  if shell_running; then
    if { ((RELEASE_CHANGED)) && [[ -n $PREVIOUS_RELEASE ]] && plugins_changed; } || [[ -f $POMAR_SHELL_RESTART ]]; then
      restart_shell_for_update
    elif ((RELEASE_CHANGED || LINKS_CHANGED)); then
      omarchy-shell shell rescanPlugins >>"$LOG" 2>&1 || true
    fi
    wait_until 50 0.1 plugins_known "${ids[@]}" || true
    for id in "${ids[@]}"; do
      omarchy plugin enable "$id" >>"$LOG" 2>&1 || failed+=("$id")
    done
    # O shell grava o shell.json um instante depois de responder. Espera essa
    # gravação antes de mexer no arquivo, senão uma apagaria a outra.
    wait_until 30 0.1 pomar_py plugins-check on "${ids[@]}" >/dev/null || true
    kit plugins-on "${ids[@]}" || fail "$(L "Couldn't update $(pretty "$OMARCHY_SHELL_JSON")." "Não consegui atualizar o $(pretty "$OMARCHY_SHELL_JSON").")"
    if ((${#failed[@]})); then
      warn "$(L "The shell didn't turn these on right away: ${failed[*]}. They're saved to turn on at your next login." \
        "O shell não ligou na hora: ${failed[*]}. Ficou gravado para ligar no próximo login.")"
    fi
  else
    rm -f -- "$POMAR_SHELL_RESTART" # o próximo shell já abre com as peças novas
    kit plugins-on "${ids[@]}" || fail "$(L "Couldn't update $(pretty "$OMARCHY_SHELL_JSON")." "Não consegui atualizar o $(pretty "$OMARCHY_SHELL_JSON").")"
    note "$(L "The Omarchy shell isn't open right now; the plugins turn on by themselves at your next login" \
      "O shell do Omarchy não está aberto agora; as peças ligam sozinhas no próximo login")"
  fi
  for name in "${names[@]}"; do ok "$name"; done
}

# ------------------------------------------------------ 10 e 11. aplicar
can_prompt() { [[ -t 1 ]] && { : </dev/tty; } 2>/dev/null; }

apply_now() {
  ((ASSUME_YES)) && return 0
  can_prompt || return 0
  local answer=""
  printf '\n%s%s%s ' "$POMAR_C_BOLD" "$(L "Apply Pomarchy now? [Y/n]" "Aplicar o Pomarchy agora? [S/n]")" "$POMAR_C_OFF" >/dev/tty
  read -r answer </dev/tty || return 1 # Ctrl+D não é sim
  case "${answer,,}" in
    "" | s | sim | y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

BAR_APPLIED=0 THEME_APPLIED=""

# Antes de mudar qualquer coisa: diz o que vai mudar e pergunta. Com --yes segue
# direto; sem um terminal para perguntar (e sem --yes), não instala.
confirm_install() {
  ((ASSUME_YES)) && return 0
  if ! can_prompt; then
    printf '✗ %s\n' "$(L "There's no terminal to ask before installing. To install without questions: install.sh --yes" \
      "Sem um terminal para perguntar antes de instalar. Para instalar sem perguntas: install.sh --yes")" >&2
    exit 1
  fi
  {
    printf '\n%s\n' "$(L "Pomarchy will:" "O Pomarchy vai:")"
    printf '  • %s\n' "$(L "copy its files to ~/.local/share/pomar" "copiar os arquivos dele para ~/.local/share/pomar")"
    printf '  • %s\n' "$(L "put the Pomarchy themes and 7 plugins in ~/.config/omarchy (links to that copy)" \
      "pôr os temas Pomarchy e 7 peças em ~/.config/omarchy (links para essa cópia)")"
    printf '  • %s\n' "$(L "add a marked block to ~/.config/hypr/hyprland.lua (gestures, shortcuts and animations)" \
      "acrescentar um bloco marcado ao ~/.config/hypr/hyprland.lua (gestos, atalhos e animações)")"
    printf '  • %s\n' "$(L "turn the plugins on in ~/.config/omarchy/shell.json, plus a hook for theme changes" \
      "ligar as peças no ~/.config/omarchy/shell.json e um gancho na troca de tema")"
    printf '  • %s\n' "$(L "create your settings in ~/.config/pomar" "criar os seus ajustes em ~/.config/pomar")"
    printf '  • %s\n' "$(L "create launcher shortcuts and icons, and the pomar and pomarchy commands in ~/.local/bin" \
      "criar atalhos e ícones no lançador e os comandos pomar e pomarchy em ~/.local/bin")"
    if ((APPLY)); then printf '  • %s\n' "$(L "apply the Pomarchy theme" "aplicar o tema Pomarchy")"; fi
    if ((BAR)); then
      printf '  • %s\n' "$(L "swap the bar for the Mac menu bar (yours is kept)" \
        "trocar a barra pela barra de menus do Mac (a sua fica guardada)")"
    fi
    printf '  %s\n' "$(L "Anything replaced goes to ~/.local/state/pomar/backup. To undo: uninstall.sh" \
      "O que for substituído vai para ~/.local/state/pomar/backup. Para desfazer: uninstall.sh")"
    printf '\n%s%s%s ' "$POMAR_C_BOLD" "$(L "Install? [Y/n]" "Instalar? [S/n]")" "$POMAR_C_OFF"
  } >/dev/tty
  local answer=""
  if ! read -r answer </dev/tty; then # Ctrl+D ou terminal fechado: não é sim
    printf '\n%s\n' "$(L "Nothing was changed." "Nada foi mudado.")" >/dev/tty
    exit 0
  fi
  case "${answer,,}" in
    "" | s | sim | y | yes) ASSUME_YES=1 ;; # já respondeu: não pergunta de novo
    *) printf '%s\n' "$(L "Nothing was changed." "Nada foi mudado.")" >/dev/tty; exit 0 ;;
  esac
}

apply_bar() {
  step 10 "$(L "Menu bar" "Barra de menus")"
  # Com o tema Pomarchy a caminho, a barra do Mac; sem trocar de tema, a barra
  # acompanha o tema atual (outro tema fica com a barra do Omarchy).
  if ((APPLY)); then
    cmd_bar mac || fail "$(L "Couldn't change the bar." "Não consegui mudar a barra.")"
  else
    cmd_bar auto || fail "$(L "Couldn't change the bar." "Não consegui mudar a barra.")"
  fi
  BAR_APPLIED=1
}

apply_theme() {
  local theme="pomarchy" current
  step 11 "$(L "Theme" "Tema")"
  current=$(current_theme)
  # Quem já usa o Pomarchy escuro (ou o Pomar Escuro, nome antigo) continua nele.
  if ((DARK)) || [[ $current == pomarchy-escuro || $current == pomar-escuro ]]; then
    theme="pomarchy-escuro"
  fi
  if [[ -n $current && $current != pomar* ]]; then
    printf '%s\n' "$current" >"$POMAR_PREVIOUS_THEME"
  fi
  if [[ $current == "$theme" ]] && ((!RELEASE_CHANGED)); then
    ok "$(L "The $(theme_title "$theme") theme is already active" "O tema $(theme_title "$theme") já está ativo")"
    THEME_APPLIED="$theme"
    return 0
  fi
  note "$(L "Applying the $(theme_title "$theme") theme (this takes a few seconds)..." "Aplicando o tema $(theme_title "$theme") (leva alguns segundos)...")"
  if omarchy theme set "$theme" >>"$LOG" 2>&1; then
    ok "$(L "$(theme_title "$theme") theme applied" "Tema $(theme_title "$theme") aplicado")"
    THEME_APPLIED="$theme"
    hypr_check_after_theme
  else
    warn "$(L "Omarchy couldn't apply the theme right now. Pick \"$(theme_title "$theme")\" in Menu > Style > Theme." \
      "O Omarchy não conseguiu aplicar o tema agora. Escolha \"$(theme_title "$theme")\" em Menu > Estilo > Tema.")"
  fi
}

# ------------------------------------------------------------------ 12. fim
summary() {
  local spaces mission pinch
  if [[ -z $THEME_APPLIED ]]; then # --no-apply com o Pomarchy já em uso
    case $(current_theme) in pomarchy | pomarchy-escuro) THEME_APPLIED=$(current_theme) ;; esac
  fi
  IFS=$'\t' read -r spaces mission pinch < <(pomar_py settings-summary)
  printf '\n%s%s%s\n\n' "$POMAR_C_BOLD" "$(L "Done! Pomarchy is installed." "Pronto! O Pomarchy está instalado.")" "$POMAR_C_OFF"
  if [[ -n $THEME_APPLIED ]]; then
    echo "  $(L "The $(theme_title "$THEME_APPLIED") theme, with the Dock, Launchpad, Mission Control and menu bar." \
      "Tema $(theme_title "$THEME_APPLIED"), com Dock, Launchpad, Mission Control e barra de menus.")"
    if ((HYPR_ROLLED_BACK || HYPR_SKIPPED)); then
      echo "  $(L "Pomarchy's gestures and shortcuts were left off (Hyprland complained); see: pomar doctor" \
        "Os gestos e atalhos do Pomarchy ficaram desligados (o Hyprland reclamou); veja: pomar doctor")"
    else
      echo "   • $(L "Switch desktops: swipe sideways with $spaces fingers" "Trocar de mesa: $spaces dedos para os lados")"
      echo "   • $(L "Mission Control: swipe up with $mission fingers, or SUPER+CTRL+↑" "Mission Control: $mission dedos para cima, ou SUPER+CTRL+↑")"
      if [[ $pinch == 1 ]]; then
        echo "   • $(L "Launchpad: pinch with 4 fingers, or SUPER+ALT+SPACE" "Launchpad: pinça com 4 dedos, ou SUPER+ALT+ESPAÇO")"
      else
        echo "   • $(L "Launchpad: SUPER+ALT+SPACE or the icon in the Dock" "Launchpad: SUPER+ALT+ESPAÇO ou o ícone no Dock")"
      fi
      echo "   • $(L "Switch apps: ALT+TAB (where the Mac's ⌘ key sits)" "Trocar de app: ALT+TAB (onde fica o ⌘ do Mac)")"
    fi
    echo "   • $(L "Settings: look for \"Pomarchy Settings\" in the launcher (or run: pomar open settings)" \
      "Ajustes: procure \"Ajustes do Pomarchy\" no lançador (ou rode: pomar open settings)")"
  else
    echo "  $(L "The theme wasn't switched now, so Pomarchy doesn't show up yet." "O tema não foi trocado agora, então o Pomarchy ainda não aparece.")"
    echo "  $(L "To turn it on: omarchy theme set pomarchy (or pick Pomarchy in Menu > Style > Theme)" \
      "Para ligar: omarchy theme set pomarchy (ou escolha Pomarchy em Menu > Estilo > Tema)")"
    ((BAR_APPLIED)) || ((!BAR)) || echo "  $(L "Mac-style menu bar: pomar bar mac" "Barra de menus no estilo Mac: pomar bar mac")"
  fi
  if ((SHELL_RESTART_PENDING)); then
    echo "  $(L "The Dock, the bar and the rest of Pomarchy switch to the new version at your next login" \
      "O Dock, a barra e o resto do Pomarchy passam para a versão nova no próximo login")"
    echo "  $(L "(or right now: omarchy restart shell)." "(ou agora mesmo: omarchy restart shell).")"
  fi
  echo ""
  echo "  $(L "If something looks off: pomar doctor" "Se algo parecer estranho: pomar doctor")"
  echo "  $(L "To undo everything:" "Para desfazer tudo:") $(pretty "$POMAR_CURRENT/uninstall.sh")"
  [[ -z $BACKUP_DIR ]] || echo "  $(L "Copies of what was replaced:" "Cópias do que foi substituído:") $(pretty "$BACKUP_DIR")"
}

main() {
  parse_args "$@"
  local self="${BASH_SOURCE[0]:-}" here="" shell_copy
  if [[ -n $self && -f $self ]]; then
    here=$(cd -- "$(dirname -- "$self")" && pwd)
  fi
  if [[ -n $here && -f $here/bin/pomar ]]; then
    # shellcheck source=bin/pomar
    source "$here/bin/pomar"
  fi
  pomar_lang "$LANG_CHOICE"
  finish_args
  if [[ -z $here || ! -f $here/tools/stage.py || ! -f $here/bin/pomar ]]; then
    bootstrap "$@"
  fi
  SRC_DIR="$here"
  POMAR_INDENT="   "
  # Quem escolheu a barra do Omarchy (pomar bar restore, --no-bar) continua com ela.
  if [[ -f $POMAR_STATE/barra && $(<"$POMAR_STATE/barra") == omarchy ]]; then BAR=0; fi

  printf '%s%s%s\n' "$POMAR_C_BOLD" "$(L "Pomarchy OS: Omarchy with a Mac feel" "Pomarchy OS: o Omarchy com jeito de Mac")" "$POMAR_C_OFF"
  check_requirements
  confirm_install
  take_lock
  rm -f -- "$POMAR_STATE"/.copia.* # sobras de uma instalação interrompida
  LOG="$POMAR_STATE/install.log"
  printf 'Pomarchy: instalação em %s\nOrigem: %s\nOpções: %s\n\n' "$(date -Is)" "$SRC_DIR" "$*" >"$LOG"
  trap 'on_error $LINENO' ERR
  shell_copy=$(snapshot "$OMARCHY_SHELL_JSON")
  pomar_py shell-origin-note >>"$LOG" 2>&1 || true # antes de o shell encher um shell.json vazio
  stage_release
  link_themes
  link_plugins
  hook_hyprland
  init_settings
  install_launchers
  link_command
  enable_plugins
  if ((!BAR)); then
    pomar_py mac-bar-choose off # o gancho de troca de tema também respeita o --no-bar
  fi
  if ((BAR || APPLY)); then
    if apply_now; then
      if ((BAR)); then apply_bar; fi
      if ((APPLY)); then apply_theme; fi
    else
      note "$(L "Everything is installed, without applying it now." "Tudo instalado, sem aplicar agora.")"
    fi
  fi
  keep_snapshot "$shell_copy" "omarchy/shell.json" "$OMARCHY_SHELL_JSON"
  summary
}

main "$@"
