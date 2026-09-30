# Desinstalar o Pomarchy OS

```bash
~/.local/share/pomar/current/uninstall.sh
```

O desinstalador segue esta ordem e para antes do primeiro passo que não consegue
fazer com segurança:

1. **Janelas minimizadas** voltam para a sua mesa atual. Se o Hyprland estiver
   rodando mas não listar as janelas, o desinstalador para aqui, antes de
   desligar qualquer coisa. Fora de uma sessão do Hyprland, este passo é pulado.
2. **Tema**: volta para o tema que você usava antes do Pomarchy (ou o padrão do
   Omarchy). Se nenhum tema puder ser aplicado, ele para aqui: tirar o tema em uso
   deixaria o Omarchy sem tema nenhum.
3. **Peças desligadas**: desliga exatamente as sete peças `pomar.*` da versão
   instalada, e nada mais.
4. **Barra de cima**: devolve a sua barra guardada. A cópia guardada só é
   arquivada depois de conferir, no disco, que a barra voltou. Se o shell
   continuar gravando a barra antiga por cima, o desinstalador para e mantém a
   cópia; rode de novo depois.
5. **Links**: tira só os links que apontam para `~/.local/share/pomar`, inclusive
   o gancho de troca de tema e o comando `pomar`.
6. **Atalhos e ícones do lançador** que o Pomarchy criou.
7. **Seus arquivos voltam**: o que o Pomarchy tirou do lugar volta para lá, se o
   lugar ainda estiver livre.
8. **Hyprland**: tira o bloco marcado. O `~/.config/hypr/hyprland.lua` fica
   igual ao de antes, byte a byte.
9. **Arquivos**: seus ajustes (`~/.config/pomar`) e as versões baixadas ficam.
   Com `--purge`, eles são apagados também.

As cópias de segurança em `~/.local/state/pomar/backup/` nunca são apagadas,
nem com `--purge`.

Para voltar ao Omarchy puro sem desinstalar, escolha qualquer outro tema. A barra
de cima e todo o resto voltam a ser os do Omarchy, e nada do Pomarchy fica ativo.
