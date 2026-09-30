# Instalar o Pomarchy OS

```bash
git clone https://github.com/BrunooMoniz/pomarchy
cd pomarchy
./install.sh --lang pt
```

O Pomarchy se instala só para o seu usuário: nunca pede direitos de
administrador e só mexe nos arquivos listados abaixo. Pode rodar o instalador
quantas vezes quiser, inclusive para atualizar depois de um `git pull`. Ele
reconhece o que já está no lugar e o resultado é sempre o mesmo.

## O que acontece, passo a passo

Antes do passo 2, o instalador mostra esta lista e pergunta `Instalar? [S/n]`.
Com `--yes`, não pergunta. Sem um terminal e sem `--yes`, ele para e não muda
nada. Ctrl+D também conta como "não".

1. **Confere o computador**: Omarchy 4, Hyprland com a configuração em Lua e Python 3.
2. **Prepara os arquivos**: monta uma versão em `~/.local/share/pomar/releases/`
   e aponta `~/.local/share/pomar/current` para ela. Antes, confere cada peça
   com `omarchy plugin validate`.
3. **Temas**: põe os links do *Pomarchy* e do *Pomarchy Escuro* em `~/.config/omarchy/themes/`.
4. **Peças**: põe os links das sete peças `pomar.*` em `~/.config/omarchy/plugins/`.
5. **Hyprland**: acrescenta um bloco marcado ao `~/.config/hypr/hyprland.lua`,
   logo depois dos padrões do Omarchy. O bloco carrega os gestos, os atalhos e as
   animações do Pomarchy, que só agem com um tema Pomarchy ativo. O arquivo novo
   é conferido com `luac -p` antes de ser gravado, e o Hyprland é recarregado.
   Se aparecer um erro novo causado pelo Pomarchy, o instalador tira o bloco e o
   arquivo volta a ser como era.
6. **Ajustes**: cria `~/.config/pomar/settings.json` na primeira vez. Se você já
   usa três dedos para os lados em outro gesto, o Pomarchy passa para quatro.
7. **Lançador**: acrescenta Launchpad, Mission Control e Ajustes do Pomarchy à lista de apps.
8. **Comando e gancho de tema**: cria `~/.local/bin/pomar` e o gancho que troca a
   barra de cima quando você muda de tema.
9. **Liga as peças** pelo shell em uso. Numa atualização, reinicia o shell para
   carregar o código novo. Com a tela bloqueada ele não reinicia; nesse caso o
   reinício fica para a próxima vez que o instalador rodar.
10. **Barra de cima**: com um tema Pomarchy, a barra de menus do Mac. A sua barra
    é guardada antes em `~/.local/state/pomar/bar-backup.json`.
11. **Tema**: aplica o *Pomarchy*, ou o *Pomarchy Escuro* com `--dark` ou se você
    já usava o escuro.

O que precisar sair do lugar vai para `~/.local/state/pomar/backup/<data>/` e
fica anotado em `~/.local/state/pomar/movidos.jsonl`, para a desinstalação pôr
de volta.

## Opções

| Opção | O que faz |
| --- | --- |
| `--yes` | instala e aplica sem perguntar |
| `--no-apply` | instala, mas mantém o seu tema por enquanto; a barra acompanha esse tema |
| `--no-bar` | não mexe na barra do Omarchy, nem depois, numa troca de tema |
| `--dark` | usa o tema escuro |
| `--lang en` / `--lang pt` | a língua do instalador |

## Se algo parecer estranho

```bash
pomar doctor
```

Ele confere cada peça e diz o que rodar para consertar. O registro da instalação
fica em `~/.local/state/pomar/install.log`.
