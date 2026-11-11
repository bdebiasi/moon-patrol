# CLAUDE.md — TDE B: Moon Patrol em Assembly 8086

## Contexto
- Trabalho de Arquitetura de Computadores (UCS), em dupla: jogo inspirado no Moon Patrol, versao simplificada (1 fase, naves com trajetoria fixa, pista plana).
- A apresentacao e obrigatoria e acontece **exclusivamente no GUI Turbo Assembler** (Windows, TASM + DOSBox). Se nao montar e rodar la, o trabalho nao e avaliado.
- A especificacao completa esta em `docs/enunciado.pdf`. Este arquivo e um resumo; em caso de conflito, o PDF manda.
- O desenvolvimento e feito por partes. Prefira mudancas pequenas e testaveis.

## O que o Claude NAO consegue fazer aqui
- Nao e possivel montar nem executar o programa neste ambiente. Nunca afirme que o codigo "funciona" ou "foi testado".
- Ao terminar cada parte, diga exatamente o que testar no GUI Turbo Assembler. O usuario cola os erros do TASM e voce corrige.

## Regras obrigatorias

### 1. Somente instrucoes do 8086
Sem diretivas `.186`, `.286`, `.386`. Proibido:
- `PUSHA`/`POPA`, `ENTER`/`LEAVE`, `BOUND`, `INS`/`OUTS`
- `PUSH` com imediato (ex.: `push 10`)
- `IMUL reg, imediato`
- Deslocamento/rotacao com contagem imediata diferente de 1 (`shl ax, 3` e invalido; use `mov cl, 3` + `shl ax, cl`)
- Registradores de 32 bits (EAX, EBX...), `MOVZX`/`MOVSX`, `JECXZ`, `CWDE`

Fonte do que e permitido: `docs/apostila_8086.pdf`. A `docs/tabela_instrucoes.pdf` cobre 80186+ e 386; use so para consultar flags.

### 2. Sintaxe TASM, modelo small
```asm
.model small
.stack 400h
.data
    ; constantes (EQU) e dados
.code
inicio:
    mov ax, @data
    mov ds, ax
    ; ...
    mov ax, 0003h       ; restaura modo texto antes de sair
    int 10h
    mov ax, 4C00h
    int 21h
end inicio
```
- Procs no formato `Nome proc` ... `ret` ... `Nome endp` (sempre com o nome no `endp`).
- Para rotulos locais `@@`, declarar `LOCALS` no inicio do arquivo.

### 3. Desenho de pixels
- Modo 13h (320x200, 1 byte por pixel, segmento A000h, offset = y*320 + x).
- Imprimir e apagar graficos **somente** via enderecamento indireto (`[DI]`, `[BX+SI]`, `[BX+desloc]`...) ou instrucoes de string (`STOSB`/`STOSW`/`MOVSB`/`MOVSW`, com `REP`).
- Proibido: `INT 10h/0Ch` para pixel e enderecamento direto (`mov es:[1234h], al`).
- `INT 10h` apenas para texto.

### 4. Sem duplicacao de rotinas
Uma rotina generica para cada tarefa, servindo todos os objetos (jipe, naves, rochas, crateras, tiros):
- `DesenhaSprite`: copia bitmap para a tela, pulando a cor transparente
- `ApagaRetangulo`: preenche retangulo com uma cor
- `MoveObjetos`: percorre a tabela de objetos aplicando velocidade
- `ColisaoRet`: teste de sobreposicao entre dois retangulos

Nunca criar `DesenhaNave1`, `DesenhaNave2`, `MoveJipe` separado de `MoveNave` etc.

### 5. Constantes para tudo
Todo valor do enunciado vira `EQU`: posicoes iniciais, tamanhos, velocidades, limites, pontuacoes, quantidade maxima de naves, duracao do jogo, intervalo entre frames. Zero numeros magicos no codigo. Tempos e velocidades precisam ser ajustaveis so pelas constantes.

### 6. Cabecalho em toda rotina (obrigatorio na avaliacao)
```asm
;------------------------------------------------------------
; DesenhaSprite
; Funcao:  copia um sprite para a memoria de video, pulando
;          pixels com a cor TRANSPARENTE.
; Entrada: SI = endereco do sprite (DS)
;          AX = x, BX = y
; Saida:   nenhuma (registradores preservados)
;------------------------------------------------------------
```
- Preservar com `push`/`pop` todo registrador que nao for saida.
- Comentarios explicando cada bloco relevante.

### 7. Arquivos
- Nomes no formato 8.3 (ex.: `MOON.ASM`, `SPRITES.INC`), por causa do DOSBox.
- Conteudo ASCII puro; preferir CRLF.
- Comentarios em portugues **sem acentos e sem cedilha** (evita lixo de encoding no TASM e no editor do GUI Turbo Assembler).

## Arquitetura sugerida
- **Loop principal:** le teclado sem esperar → atualiza estado → desenha → pausa (`INT 15h/86h`) → repete.
- **Tabelas de objetos:** registros de tamanho fixo com offsets em `EQU` (ex.: `OBJ_ATIVO`, `OBJ_X`, `OBJ_Y`, `OBJ_LARG`, `OBJ_ALT`, `OBJ_SPRITE`, `OBJ_TIPO`, `OBJ_HITS`, `OBJ_PONTUADO`), acessados com `[BX+OBJ_X]`. E isso que permite as rotinas genericas.
- **Sprites:** `db` linha a linha, 1 byte = 1 cor. Uma cor reservada `TRANSPARENTE EQU 0FFh` e pulada na copia.
- **Endereco de linha:** usar tabela de 200 words com o offset de cada linha (evita `MUL` por pixel), ou y*320 = (y shl 8) + (y shl 6) usando CL.
- **Ordem de desenho por frame:** terreno → obstaculos → jipe → tiros. No espaco lunar, apagar com preto e redesenhar.
- **Opcional (reduz flicker):** sincronizar com o retraco vertical (porta 3DAh, bit 3, via `IN AL, DX`).

## Armadilhas conhecidas
- **ES em conflito:** o desenho usa ES = A000h, mas `INT 10h/13h` le a string em ES:BP. Salvar ES, fazer ES = DS, chamar a interrupcao e restaurar.
- **MOVSB/MOVSW:** copiam DS:SI → ES:DI. Sprite fica no DS, destino com ES = A000h. Executar `CLD` uma vez.
- **Limite de 64 KB do segmento de dados (.model small):** os bitmaps brutos das montanhas (320x95 ≈ 30 KB cada) estouram o segmento se forem dois. Usar representacao compacta (perfil de altura por coluna, RLE) ou `.FARDATA` trocando DS na hora de ler.
- **Desempenho no DOSBox:** redesenhar ~30 KB por frame pode pesar. Preferir `REP MOVSW`/`REP STOSW` e redesenhar so o que muda.
- **DIV:** a divisao de 16 bits usa DX:AX (zerar DX antes); a de 8 bits usa AX (zerar AH antes). Overflow trava o programa (INT 0).
- **Texto no modo 13h:** grade de 40x25 caracteres (fonte 8x8). Arte ASCII precisa caber em 40 colunas: usar fonte estreita ou quebrar em linhas. Linha/coluna de texto nao e coordenada de pixel.
- **Caracteres de caixa do menu (218, 191, 192, 217, 196, 179):** sempre como numero (`db 218`), nunca o caractere literal (viraria UTF-8 multibyte).
- **Strings TASM:** aspa simples dentro de `'...'` deve ser escrita como `''`. Atencao ao transcrever a arte ASCII.
- **Teclado (`INT 16h/00h`):** o scan code vem em AH. Cima 48h, baixo 50h, esquerda 4Bh, direita 4Dh, Enter 1Ch, espaco 39h. Comparar AH, porque as setas retornam AL = 0. A repeticao automatica do BIOS limita teclas seguradas; handler proprio de `INT 09h` (via `INT 21h/25h`) e melhoria opcional.
- **Erros nos slides da materia (nao copiar):**
  - `mov 3Fh` → o correto e `mov ah, 3Fh`
  - `mov dx, buffer` → o correto e `mov dx, offset buffer`
  - Retorno da `INT 21h/42h` aparece como DS:AX → o correto e DX:AX
  - `VetWord DB 1,2,3` usado com `STOSW` → deveria ser `DW`
  - `DW 100 DUP (?)` aloca 200 bytes, nao 100
  - `LES` descrito carregando DS → carrega ES

## Especificacao resumida

### Layout da tela (sugestao de constantes; ajustar se necessario)
| Regiao | Linhas |
|---|---|
| Barra de status | 0–14 |
| Espaco lunar (naves) | 15–100 |
| Montanhas | a partir da 100, altura maxima 95 |
| Pista amarela (0Eh) | 7 px de altura na base: 193–199 |
| Jipe no chao | topo em 183 (pista − altura do jipe) |

### Tamanhos (largura x altura)
- Jipe: 20x10
- Nave: 14x14 (3 tipos)
- Cratera: 14x7 (3 tipos, dentro da pista)
- Rocha: 12x10 (4 tipos, sobre a pista)
- Coracoes: 18x11 (um bitmap para cada estado: 3, 2 e 1 vida)
- Relogio: 7x8
- Tiro da nave: 2x4, branco
- Tiro frontal do jipe: 4x2, vermelho, alcance de 50 px
- Tiro superior do jipe: amarelo (tamanho nao especificado)

Os bitmaps oficiais sao imagens no enunciado (Figuras 5, 6, 7, 10, 11, 12). Ao transcrever, conferir as dimensoes.

### Cores
- Paleta padrao do modo 13h: indices 0–15 = tabela do enunciado; 16–255 podem ser usados para tons extras (marrom e laranja das rochas e crateras).
- Titulo: 0Ah (verde claro)
- Opcao selecionada: 0Ch (vermelho claro)
- Opcao nao selecionada: 0Fh (branco)
- Pista: 0Eh (amarelo)
- GAME OVER: vermelho

### Telas
- **Inicial:**
  - Titulo "Moon Patrol" em arte ASCII (patorjk.com/software/taag), cor 0Ah, no topo.
  - Animacao ciclica do jipe e das 3 naves, da esquerda para a direita, reaparecendo a esquerda.
  - Menu "Jogar" / "Sair" em caixas. Setas cima/baixo navegam, Enter executa.
- **Jogo:** barra de status com score de 5 digitos a esquerda, coracoes no centro e relogio + tempo restante a direita, atualizado a cada 1 s.
- **Game Over:**
  - Ocorre com vidas = 0 ou tempo = 0.
  - "GAME OVER" em arte ASCII vermelha, centralizado em 2 linhas, com o score final abaixo.
  - Qualquer tecla volta para a tela inicial.

### Jipe
- Setas esquerda/direita, limitado a metade esquerda da tela. Velocidade maior que a das naves.
- **Seta cima = salto trapezoidal:**
  1. Sobe 3 px/frame ate 15 px de altura.
  2. Mantem a altura por 5 px de deslocamento horizontal.
  3. Desce 3 px/frame.
  - O deslocamento horizontal continua normalmente durante o salto.
- **Espaco:** dispara o canhao superior e o frontal ao mesmo tempo.
  - Tiro superior sobe ate atingir uma nave ou a linha 15.
  - Tiro frontal anda ate atingir um obstaculo ou completar 50 px.
- **Morte** (tiro de nave, cratera sem salto ou rocha): −1 vida e o jipe renasce na coluna 0.

### Naves
- Grupo de 1 a 3 naves do mesmo tipo; quantidade e tipo aleatorios.
- Surgem pela direita, com x inicial aleatorio na metade direita e y aleatorio dentro de 15–100. Sem sobreposicao e com distancia horizontal minima de 30 px entre elas.
- Movem da direita para a esquerda e sao removidas ao atingir o limite esquerdo.
- Um novo grupo so e gerado depois que todas as naves do grupo anterior sairam ou foram destruidas.
- Disparam verticalmente para baixo; o tiro para na superficie ou no jipe.
- Colisao: extremidade inferior do tiro sobrepoe o retangulo do jipe.
- Pontuacao: 100 pontos por nave destruida.

### Terreno e obstaculos
- **Scroll:** continuo da direita para a esquerda, largura minima de 320 px, com emenda sem descontinuidade (o fim do cenario conecta com o inicio). Altura variavel ate 95 px. Montanhas e montes sao dois bitmaps sobrepostos.
- **Crateras:**
  - Geradas aleatoriamente pela direita e andam junto com o terreno.
  - Distancia minima de 150 px entre crateras consecutivas.
  - Saltar sobre uma cratera: +50 (uma unica vez por cratera). Cair nela: −1 vida.
- **Rochas:**
  - Ficam entre duas crateras e andam junto com o terreno.
  - Tipos:
    - Rocha 1: indestrutivel, precisa ser saltada.
    - Rochas 2 e 3: destruidas com 1 tiro.
    - Rocha 4: destruida com 2 tiros consecutivos.
  - Destruir ou saltar uma rocha: +50.

### Servicos uteis (conferir parametros em `docs/interrupcoes.pdf`)
- **Texto colorido:** `INT 10h/13h` (AL = 0, BL = cor, BH = pagina, DH/DL = linha/coluna, CX = tamanho, ES:BP = string).
- **Pausa entre frames:** `INT 15h/86h`, com CX:DX = microssegundos (ex.: 30 ms → CX = 0, DX = 7530h).
- **Teclado sem esperar:** `INT 16h/01h` (ZF = 1 significa buffer vazio); depois `INT 16h/00h` para ler e remover a tecla.
- **Relogio de 1 s:** `INT 21h/2Ch` (segundos em DH; atualizar quando o valor mudar).
- **Aleatoriedade:** LCG de 16 bits proprio (ex.: semente = semente*25173 + 13849), semeado com o tick de `INT 1Ah/00h` (DX).
- **Tamanho de bloco em tempo de montagem:** `TAM EQU $ - rotulo`.

Nao inventar funcoes de interrupcao: usar so o que esta documentado nos PDFs.

## Minimo entregavel (sem isso o trabalho nao e avaliado)
- [ ] Tela inicial completa e funcional
- [ ] Barra de status completa
- [ ] Geracao aleatoria de grupos de naves, movimento e remocao a esquerda (tiros das naves sao opcionais)
- [ ] Scroll continuo do terreno com recomposicao pela direita
- [ ] Salto com seta para cima; jipe some ao atingir cratera ou rocha, e as vidas sao atualizadas
- [ ] Pontuacao correta
- [ ] Crateras e rochas conforme as regras
- [ ] Game Over por vidas ou tempo, com placar; tecla volta ao menu
- [ ] Constantes para todas as definicoes
- [ ] Cabecalho em todas as rotinas

**Opcionais (pontuacao extra):** tiros do jipe (frontal e superior), tiros das naves e qualquer elemento extra (ex.: parallax entre montanhas e montes).

## Ambiguidades do enunciado (deixar parametrizado)
- "5 px de deslocamento horizontal" no topo do salto: conta o scroll do cenario ou o movimento do jipe?
- Linhas exatas das montanhas e da pista (100 + 95 = 195 ultrapassa o topo da pista em 193).
- Criterio exato de queda na cratera (quanto do jipe precisa estar sobre ela).
- Tamanho do tiro superior do jipe.

## Documentos de referencia (`docs/`)
- `enunciado.pdf`: especificacao do TDE (fonte da verdade)
- `apostila_8086.pdf`: apostila do Koliver, referencia de cada instrucao do 8086/88
- `slides_8086.pdf`: estrutura do programa, diretivas e conjunto de instrucoes
- `slides_vetores.pdf`: vetores, modos de enderecamento e instrucoes de string
- `slides_video.pdf`: rotinas de interrupcao, macros, video, mouse e arquivos
- `interrupcoes.pdf`: Apendice II, referencia das interrupcoes do PC
- `tabela_instrucoes.pdf`: tabela rapida (80186+; ver regra 1)

## Forma de trabalho
- Responder em portugues, de forma direta.
- Antes de escrever uma rotina nova, verificar se uma rotina generica existente resolve.
- Ao criar ou alterar uma proc, informar quais registradores ela usa e altera.
