# CLAUDE.md — TDE B: Moon Patrol em Assembly 8086

## Contexto
- Trabalho de Arquitetura de Computadores (UCS), em dupla: jogo inspirado no Moon Patrol, versao simplificada (1 fase, naves com trajetoria fixa, pista plana).
- A apresentacao e obrigatoria e acontece **exclusivamente no GUI Turbo Assembler** (Windows, TASM + DOSBox). Se nao montar e rodar la, o trabalho nao e avaliado.
- A especificacao completa esta em `conteudo-trabalho-arquitetura/PDF-trabalho-a-ser-feito.pdf`. Este arquivo e um resumo; em caso de conflito, o PDF manda.
- O desenvolvimento e feito por partes. Prefira mudancas pequenas e testaveis.

## Validacao
- Verificar se o GUI Turbo Assembler esta disponivel. So afirmar que montou ou executou quando isso tiver sido observado; distinguir revisao estatica de teste de execucao.
- Ao terminar cada parte, registrar os testes realizados e o que ainda precisa ser conferido no GUI Turbo Assembler.
- Etapa 4: TASM 4.1/TLINK 7.1 do GUI Turbo Assembler montaram/vincularam sem erros ou avisos no DOSBox 0.74-3. Testes temporarios em Assembly passaram para 1024 geracoes de pares, os sete tipos, 4000 quadros de geracao/scroll, espacamentos, bordas de colisao, salto completo sobre cada tipo, perda unica de vida, reposicao, pontos unicos, reciclagem, registradores, comparacao dos pixels da pista/montanhas/status e acionamento do Game Over por vidas zeradas. Conferencia visual executada do menu/partida e, em roteiro temporario, dos sete sprites, salto com +50, coracoes apos colisao e Game Over preservando o placar. Montagem pela linha de comando das ferramentas da instalacao; repetir pela interface do IDE na apresentacao.

## Regras obrigatorias

### 1. Somente instrucoes do 8086
Sem diretivas `.186`, `.286`, `.386`. Proibido:
- `PUSHA`/`POPA`, `ENTER`/`LEAVE`, `BOUND`, `INS`/`OUTS`
- `PUSH` com imediato (ex.: `push 10`)
- `IMUL reg, imediato`
- Deslocamento/rotacao com contagem imediata diferente de 1 (`shl ax, 3` e invalido; use `mov cl, 3` + `shl ax, cl`)
- Registradores de 32 bits (EAX, EBX...), `MOVZX`/`MOVSX`, `JECXZ`, `CWDE`

Referencia de instrucoes fornecida: `conteudo-trabalho-arquitetura/PDF-conteudo-1.pdf`. Os exemplos dos slides devem ser conferidos quanto a compatibilidade com 8086.

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
- `INT 10h` para texto e troca de modo; nunca para desenhar/apagar pixels.

### 4. Sem duplicacao de rotinas
Uma rotina generica para cada tarefa, servindo todos os objetos (jipe, naves, rochas, crateras, tiros):
- `DesenhaSprite`: copia bitmap para a tela, pulando a cor transparente
- `ApagaRetangulo`: preenche retangulo com uma cor
- `MoveObjetos`: percorre a tabela de objetos aplicando velocidade
- `ColisaoRet`: teste de sobreposicao entre dois retangulos

Evitar rotinas de desenho ou aplicacao de velocidade duplicadas por tipo de objeto. Controles e regras especificas (como o salto em `GAME_STEP`) podem ser separados, reutilizando `MOVE_OBJECTS`.

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
- **Ordem de desenho por frame:** terreno → obstaculos → jipe → tiros. No menu, apagar com preto. No jogo, apagar as posicoes antigas, restaurar o terreno e entao redesenhar os objetos; preto sozinho danifica as montanhas.
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

### Servicos uteis (conferir parametros no enunciado, pp. 15-16)
- **Texto colorido:** `INT 10h/13h` (AL = 0, BL = cor, BH = pagina, DH/DL = linha/coluna, CX = tamanho, ES:BP = string).
- **Pausa entre frames:** `INT 15h/86h`, com CX:DX = microssegundos (ex.: 30 ms → CX = 0, DX = 7530h).
- **Teclado sem esperar:** `INT 16h/01h` (ZF = 1 significa buffer vazio); depois `INT 16h/00h` para ler e remover a tecla.
- **Relogio de 1 s:** `INT 21h/2Ch` (segundos em DH; atualizar quando o valor mudar).
- **Aleatoriedade:** `RANDOM_RANGE` usa LCG de 16 bits (semente = semente*25173 + 13849), semeado pelos centesimos do relogio DOS ao iniciar a partida.
- **Tamanho de bloco em tempo de montagem:** `TAM EQU $ - rotulo`.

Nao inventar funcoes de interrupcao: usar so o que esta documentado nos PDFs.

## Minimo entregavel (sem isso o trabalho nao e avaliado)
- [x] Tela inicial completa e funcional
- [x] Barra de status completa
- [x] Geracao aleatoria de grupos de naves, movimento e remocao a esquerda (tiros das naves sao opcionais)
- [x] Scroll continuo do terreno com recomposicao pela direita
- [x] Movimento horizontal na metade esquerda e salto com seta para cima
- [x] Colisao com cratera/rocha reduz uma vida e recoloca o jipe em X=0
- [x] Pontuacao por obstaculo superado, concedida uma unica vez
- [x] Crateras e rochas conforme as regras (resistencias identificadas por tipo; tiros opcionais pendentes)
- [x] Game Over por vidas ou tempo, com placar; tecla volta ao menu
- [x] Constantes para as definicoes implementadas
- [x] Cabecalho em todas as rotinas

**Especificacao completa e minimo avaliavel:** os tiros do jipe e das naves estao descritos nas secoes de requisitos, mas sao explicitamente dispensados no Minimo Entregavel (p. 14). Sao opcionais para esse minimo e contam como pontuacao complementar; elementos extras, como parallax, tambem sao complementares. Os demais itens da lista acima continuam obrigatorios. A etapa 4 acrescenta obstaculos, colisoes, perda de vidas e pontuacao ao minimo implementado. Os tiros e as resistencias a disparos ainda nao foram implementados.

## Ambiguidades do enunciado (deixar parametrizado)
- "5 px de deslocamento horizontal" no topo: o contador acompanha o deslocamento real do terreno (`JUMP_WORLD_VX = SCROLL_SPEED`), mesmo quando o jipe esta parado na tela ou na borda. A interpretacao adotada e o avanco do jipe em relacao ao mundo, representado pelo scroll.
- Linhas exatas das montanhas e da pista (100 + 95 = 195 ultrapassa o topo da pista em 193).
- Crateras: qualquer sobreposicao horizontal com o retangulo do jipe, quando seus pneus tocam a linha da pista, conta como queda. `RECT_HIT` recebe extensao inferior de 1 pixel para incluir esse contato; no ar nao ha queda. Rochas usam os retangulos completos, sem extensao.
- Tamanho do tiro superior do jipe.

## Estado implementado nesta etapa
- Menu e sprites preservados. `GAME_RUN` atualiza o relogio, verifica tempo/vidas, le uma tecla sem bloquear, apaga objetos antigos, chama `GAME_STEP`, restaura `DRAW_TERRAIN`, redesenha `DRAW_OBJECTS` e chama `WAIT_FRAME`. ESC retorna ao menu.
- `GAME_STEP` define VX pelas setas (6 pixels por evento de tecla), chama `MOVE_OBJECTS` para todos os objetos e limita o jipe a X=0..140. A partida usa `GAME_FRAME_US=60000`; o menu mantem 14000. Ajustes autorizados para permitir transpor as rochas com colisao retangular completa, preservando altura e passos verticais do salto. Saltar e avancar para a direita permite a travessia; a leitura BIOS continua dependente da repeticao das setas.
- Salto: Y vai de 183 a 168 e volta em passos de 3; `OBJ_VY` e a altura indicam a etapa. Apenas `jump_top_left` foi acrescentada ao estado, sem novo salto no ar.
- Leitura BIOS preservada: teclas seguradas dependem da repeticao automatica, sem leitura simultanea de teclas. As setas horizontais funcionam durante todas as etapas do salto.
- Redesenho usa as rotinas existentes, sem buffer adicional. As rotinas de sprite/retangulo recortam somente na horizontal: os chamadores devem garantir `0 <= Y` e `Y + altura <= SCREEN_H`. O jipe fica em Y=168..183 (ultima linha 192); objetos do menu tambem ficam dentro da tela.
- Scroll: ambas as camadas avancam `SCROLL_SPEED` pixels por quadro. Os tiles RLE existentes de 256 colunas se repetem para preencher os 320 pixels da tela; as tabelas estendidas unem fim/inicio. `DRAW_TERRAIN` restaura o ceu nas transparencias da camada do fundo (`CL=COLOR_BG`); na frente, `CL=TRANSPARENTE` preserva a camada anterior. A frente so tem transparencia ate a linha 162, ja coberta pelo fundo (100..163), portanto toda a faixa e recomposta sem limpeza separada. A pista e recomposta por `DRAW_GROUND` dentro de `DRAW_TERRAIN` a cada quadro, antes dos objetos, para apagar crateras sem rastros.
- Naves: `game_tab` contem o jipe, 3 vagas de naves e 4 vagas de obstaculos. `SHIPS_STEP` desativa X <= -14 e so gera outro grupo quando todas sairam. Sorteia quantidade 1..3, tipo comum e X inicial que acomoda o grupo inteiro em 160..306; as demais posicoes seguem a separacao de 44 pixels (30 livres). Cada Y e sorteado em 15..86. `MOVE_OBJECTS` move todas, com VX=-1 e VY=0.
- Tempo: `UPDATE_TIME` usa `INT 21h/2Ch`, acumula centesimos e desconta segundos completos, inclusive quadros demorados e virada do minuto. Deve ser chamada ao menos uma vez por minuto. So redesenha o tempo quando ha desconto.
- `GAME_OVER` reutiliza texto centralizado/ASCII em dois blocos vermelhos, imprime o score final e espera uma nova tecla. O laco encerra por tempo ou vidas zerados.
- Obstaculos: dois pares cratera/rocha reutilizam os mesmos registros e rotinas graficas/de movimento. As crateras tem 14x7, as rochas 12x10; os sete bitmaps seguem as Figuras 11/12. O interior da cratera e preto, representando o buraco; o exterior das rochas e transparente.
- `OBSTACLES_STEP` recicla o par quando ambos sairam totalmente. Gera a cratera em X >= 320, com pelo menos 150 pixels livres apos a ultima, mais variacao aleatoria. A rocha fica na faixa entre essa cratera e a proxima, com margens de 40 pixels. Os obstaculos andam com VX=-SCROLL_SPEED.
- Registros agora tem 20 bytes: `OBJ_TIPO` identifica crateras 1..3 e rochas 4..7; `OBJ_RESOLVIDO=1` indica que o obstaculo ja rendeu pontos ou causou perda de vida. O resultado nao se repete, inclusive ao voltar sobre um obstaculo, ate a vaga ser reciclada. Tipos de rocha preservam a futura resistencia, sem implementar tiros/HP nesta etapa.
- `RECT_HIT` e generica para dois retangulos. Colisao resolve o obstaculo, desconta uma vida, atualiza coracoes, copia somente o registro inicial do jipe e zera o contador do salto. O Game Over existente atende vidas zeradas. Passar completamente pelo obstaculo sem colidir concede 50 pontos e atualiza o score; o placar final e preservado.
- `RANDOM_RANGE` mistura os bytes da semente antes de obter o resto, evitando repeticoes dos bits baixos em sorteios de quatro tipos.
- Pendentes: disparos frontal/superior do jipe e das naves, resistencias das rochas aos tiros e colisoes/pontuacao envolvendo projeteis (opcionais para o minimo). Conferir a entrega final pela interface do GUI Turbo Assembler.

## Documentos de referencia (`conteudo-trabalho-arquitetura/`)
- `PDF-trabalho-a-ser-feito.pdf`: especificacao do TDE (fonte da verdade).
- `PDF-conteudo-1.pdf`: estrutura de programas e instrucoes do 8086/88.
- `PDF-conteudo-2.pdf`: vetores, enderecamento indireto e instrucoes de string.
- `PDF-exercicios-conteudo.pdf`: o arquivo fornecido contem uma unica pagina em branco.

## Forma de trabalho
- Responder em portugues, de forma direta.
- Antes de escrever uma rotina nova, verificar se uma rotina generica existente resolve.
- Ao criar ou alterar uma proc, informar quais registradores ela usa e altera.
