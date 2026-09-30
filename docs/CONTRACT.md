# Pomarchy: contrato interno

Pomarchy é um tema completo para o Omarchy 4 que dá ao desktop a experiência do
macOS para quem está chegando do Mac: Dock, Launchpad, Mission Control, Cmd+Tab,
barra de menus e gestos no trackpad. Público: pessoa não técnica. Tudo precisa
ser visual, óbvio e bonito ("premium"); nada exige terminal para o uso diário.

## Peças

| Peça | Onde | Tipo no Omarchy |
| --- | --- | --- |
| Tema claro e escuro | `themes/pomarchy`, `themes/pomarchy-escuro` | tema (cores, `shell.*.toml`, papéis de parede) |
| Gestos, atalhos, animações | `hypr/pomar.lua` | incluído no `~/.config/hypr/hyprland.lua` por bloco marcado |
| Base (fonte, boas-vindas) | `pomar.core` | `service`, keepLoaded |
| Barra de menus (logo + app ativo) | `pomar.menubar` | `bar-widget` |
| Dock | `pomar.dock` | `panel`, keepLoaded |
| Launchpad | `pomar.launchpad` | `overlay`, keepLoaded |
| Mission Control e App Exposé | `pomar.mission` | `overlay`, keepLoaded |
| Alternador de apps (Cmd+Tab) | `pomar.switcher` | `overlay`, keepLoaded |
| Ajustes e boas-vindas | `pomar.settings` | `panel` (sob demanda) |
| Código comum | `shared/` | copiado para dentro de cada plugin por `tools/stage.py` |

O Omarchy não aceita link simbólico dentro de plugin. `shared/` NÃO existe dentro
de `<id>/` na raiz do repositório; `tools/stage.py DESTINO` monta a árvore
instalável copiando `shared/` para `plugins/<id>/shared/`. Importe assim:

```qml
import "shared"                          // PomarSettings, PomarEvents, HyprClients, Glass
import "shared/Tokens.js" as Tokens
import "shared/Apps.js" as Apps
import "shared/I18n.js" as I18n
import qs.Commons                        // Color, Style do Omarchy
```

## Ativo ou não

`PomarSettings.active` é verdadeiro quando o tema atual começa com `pomar` ou
`alwaysOn` está ligado. Com `active` falso nenhuma superfície do Pomarchy aparece e
nenhum evento é atendido. O `hypr/pomar.lua` segue a mesma regra.

## Ajustes

Um JSON só: `~/.config/pomar/settings.json`. Padrões em `shared/Defaults.js`
(espelhados em `hypr/pomar.lua`). Ler com `settings.get("dock.iconSize", 54)`,
escrever com `settings.set("dock.autohide", true)`. Chave nova: acrescente nos
DOIS lugares de padrões e no teste de contrato.

## Eventos (barramento)

Formato no socket2 do Hyprland: `custom>>pomar>>alvo:verbo[:arg]`. Receber:

```qml
PomarEvents {
  onCommand: function(target, verb, arg) { if (target === "launchpad") ... }
}
```

Publicar: `events.send("dock", "show")`. Do terminal:
`hyprctl dispatch 'hl.dsp.event("pomar>>launchpad:toggle")'`.

| Alvo | Verbos |
| --- | --- |
| `launchpad` | `toggle`, `open`, `close`, `begin`, `scale:<float>` (pinça ao vivo: a escala absoluta do libinput, 1.0 no início, < 1 juntando os dedos, > 1 abrindo), `end:<0 ou 1 cancelado>` |
| `mission` | `toggle`, `open`, `close`, `expose[:<id do app>]` (janelas de um app; sem arg = app ativo), `begin`, `delta:<px>` (deslocamento vertical desde o último update, negativo = para cima), `end:<0/1>` |
| `switcher` | `next`, `prev`, `commit`, `cancel`, `quit` |
| `dock` | `autohide-toggle`, `show`, `hide`, `minimized` (uma janela acabou de ser minimizada) |
| `overlay` | `opened:<nome>`: quem abre um overlay avisa; os outros fecham |

## Janelas e mesas

`HyprClients` dá `clients` (janelas normais, ordem de uso recente), `allClients`,
`workspaces`, `monitors`, `toplevelFor(address)` (para `ScreencopyView`) e
`isMinimized(client)`. Minimizar = mover para a mesa especial
`special:pomar-minimized`. Restaurar:

```js
events.dispatch('hl.dsp.window.move({ window = "address:0x..", workspace = "3", follow = true })')
```

Dispatchers Lua úteis (via `events.dispatch`): `hl.dsp.focus({ window = "address:0x.." })`,
`hl.dsp.focus({ workspace = "2" })`, `hl.dsp.window.close({ window = "address:0x.." })`,
`hl.dsp.window.move({ window = ..., workspace = "2", follow = false })`.

## Apps

`Apps.entryFor(DesktopEntries, classeOuId, webIndex)`, `Apps.appKey(DesktopEntries, classe, webIndex)`,
`Apps.iconSource(Quickshell, entry, id)` e `Apps.launchGuarded(Quickshell, desktopId)` (abre como
o lançador do Omarchy, via `uwsm-app -- gtk-launch`; com `POMAR_TEST=1` só anota no log).
`webIndex = Apps.webappIndex(DesktopEntries.applications.values)` liga as janelas dos webapps
do Omarchy (`chrome-HOST__...`) ao .desktop certo; passe sempre que resolver app de janela.
`dock.favorites` vazio só ganha a lista inicial enquanto `dock.seeded` for falso.
Abrir os Ajustes de outro plugin: `omarchy-shell shell summon pomar.settings '{"page":"dock"}'`
(o shell só deixa cada plugin abrir a si mesmo). Apps escondidos do lançador do Omarchy:
`$OMARCHY_PATH/default/omarchy/launcher.hides` e o script
`$OMARCHY_PATH/shell/services/hidden-entries.sh`.

## Visual

- Material: `Glass` (vidro com filete e sombra). O desfoque vem do Hyprland pelas
  regras de camada no `pomar.lua`: use `WlrLayershell.namespace` `pomar-dock`,
  `pomar-menu`, `pomar-switcher`, `pomar-tooltip`, `pomar-launchpad`,
  `pomar-mission` ou `pomar-settings`. Outro nome fica sem desfoque.
- Cores: `Color.*` e `Style.*` do Omarchy para o que é do tema; `Tokens.*` para
  as derivações (vidro, filete, rótulos, hover). `dark = Tokens.isDark(Color.background)`.
- Fonte: `Style.fontFamily` (o `pomar.core` põe a fonte de interface do Mac mais
  próxima disponível).
- Movimento: `Tokens.motion`. Easing.OutCubic para entrar, OutQuint para
  assentar, OutBack leve só para "quicar". Nada pisca; tudo tem transição.
- Textos: pt-BR e inglês. Cada plugin tem seu `Strings.js` com
  `{ chave: { pt, en } }` e usa `I18n.tr(TABELA, chave, lang)` com
  `lang = I18n.resolve(settings.get("language"), Quickshell.env("LANG"))`.
- Mouse passa por onde não há conteúdo: `PanelWindow.mask: Region { item: ... }`.

## Contrato de overlay/painel do Omarchy

Raiz = `Item` com `property bool opened`, `function open(payloadJson)`,
`function close()`. O shell chama `open` no `summon` e `close` no `hide`.
Overlays keepLoaded ficam carregados desde o início e abrem por evento.

## Provar

Nunca no desktop real (o overlay rouba o teclado de quem está usando). Em
30/09/2026 um teste esvaziou a Lixeira real porque o harness só trocava o HOME;
hoje `tests/nested.py` isola HOME e todas as XDG, usa D-Bus e runtime próprios,
troca por dublês tudo que tem efeito no sistema (abrir app, lixeira, tema,
desligar) e acusa se alguma pasta sensível do HOME real mudar. Qualquer comando
externo novo que o Pomarchy passar a chamar entra na lista `STUBBED` de lá.

```bash
tests/shot.py --out /tmp/x.png                       # desktop com o tema Pomarchy
tests/shot.py --event launchpad:open --out /tmp/lp.png
tests/shot.py --steps 'event:mission:open;sleep:1.2;shot:/tmp/a.png;keys:-k Escape;sleep:.6;shot:/tmp/b.png'
```

`tests/shot.py` sobe um Hyprland aninhado com HOME temporário, aplica o tema de
verdade (`omarchy-theme-set` headless dentro do HOME de teste), monta os plugins,
roda o shell real do Omarchy num D-Bus isolado, abre apps, manda eventos e tira
foto da tela virtual. Mostra no fim os avisos de QML que mencionam o Pomarchy.
Passos aceitos em `--steps`: `event:`, `sleep:`, `shot:`, `keys:` (wtype), `dispatch:`
(Lua), `cursor:X,Y` (move o ponteiro de verdade, hover funciona) e `ipc:ALVO METODO ARGS`.
Clique não dá para simular: exponha ganchos de teste num
`IpcHandler { target: "pomar-<nome>-test"; enabled: Quickshell.env("POMAR_TEST") === "1" }`
(o harness sobe o shell com `POMAR_TEST=1`; fora dos testes o gancho não existe).
Suites: `python3 -m unittest discover -s tests -v`.
