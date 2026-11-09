;==============================================================================
; MOON PATROL - PARTE 1: TELA INICIAL
;------------------------------------------------------------------------------
; Montador : TASM (GUI Turbo Assembler) ou emu8086 (template EXE)
;            Codigo 8086 puro (sem instrucoes 186/286).
; Video    : modo 13h (320x200, 256 cores). Pixels escritos direto em A000h;
;            a INT 10h e usada apenas para trocar o modo e escrever texto.
; Teclas   : SETA CIMA/BAIXO escolhe, ENTER confirma, ESC sai
;==============================================================================
.MODEL SMALL
.STACK 200h

;==============================================================================
; CONSTANTES
;==============================================================================
; --- Video ---
VIDEO_SEG       EQU 0A000h      ; segmento da memoria de video
SCREEN_W        EQU 320         ; largura da tela em pixels
SCREEN_H        EQU 200         ; altura da tela em pixels
TEXT_COLS       EQU 40          ; colunas de texto no modo 13h (fonte 8x8)
VIDEO_PAGE      EQU 0           ; pagina de video usada pela INT 10h
MODE_GRAPH      EQU 13h         ; modo grafico 320x200x256
MODE_TEXT       EQU 03h         ; modo texto 80x25 (volta ao DOS)

; --- Cores (paleta padrao do VGA) ---
COLOR_BG        EQU 00h         ; fundo (preto)
COLOR_TITLE     EQU 0Ah         ; titulo (verde-claro)
COLOR_SELECT    EQU 0Ch         ; opcao selecionada (vermelho-claro)
COLOR_NORMAL    EQU 0Fh         ; opcao normal / textos (branco)
COLOR_GROUND    EQU 0Eh         ; faixa do chao (amarelo)
TRANSP          EQU 00h         ; cor tratada como transparente nos sprites

; --- Moldura das caixas (ASCII) ---
BOX_TL          EQU '+'         ; canto superior esquerdo
BOX_TR          EQU '+'         ; canto superior direito
BOX_BL          EQU '+'         ; canto inferior esquerdo
BOX_BR          EQU '+'         ; canto inferior direito
BOX_H           EQU '-'         ; linha horizontal
BOX_V           EQU '|'         ; linha vertical

; --- Teclado (scan codes da INT 16h) ---
KEY_UP          EQU 48h
KEY_DOWN        EQU 50h
KEY_ENTER       EQU 1Ch
KEY_ESC         EQU 01h

; --- Titulo (linhas de texto) ---
TITLE1_ROW      EQU 1           ; linha inicial de "MOON"
TITLE1_LINES    EQU 5
TITLE2_ROW      EQU 7           ; linha inicial de "PATROL"
TITLE2_LINES    EQU 5

; --- Menu ---
MENU_ITEMS      EQU 2           ; quantidade de opcoes
OPT_PLAY        EQU 0           ; indice da opcao JOGAR
OPT_EXIT        EQU 1           ; indice da opcao SAIR
MENU_BOX_W      EQU 12          ; largura da caixa (colunas)
MENU_COL        EQU 14          ; (TEXT_COLS - MENU_BOX_W) / 2
MENU_ROW        EQU 18          ; linha do topo da primeira caixa
MENU_STEP       EQU 3           ; linhas entre o topo de uma caixa e a outra
MENU_TXT_LEN    EQU 6           ; bytes reservados para cada texto do menu

; --- Sprites ---
JEEP_W          EQU 20
JEEP_H          EQU 10
SHIP_W          EQU 14
SHIP_H          EQU 14
SHIP_SIZE       EQU SHIP_W * SHIP_H     ; bytes de cada sprite de nave

; --- Animacao da tela inicial ---
FRAME_DELAY_US  EQU 14000       ; duracao de um quadro em microssegundos
ANIM_SHIPS      EQU 3           ; naves na animacao
SHIP_SPEED      EQU 1           ; pixels por quadro (direita -> esquerda)
JEEP_SPEED      EQU 1           ; pixels por quadro (esquerda -> direita)
SHIP_CYCLE      EQU SCREEN_W + SHIP_W   ; percurso completo de uma nave
JEEP_CYCLE      EQU SCREEN_W + JEEP_W   ; percurso completo do jipe
GROUND_Y        EQU 133         ; primeira linha da faixa amarela
GROUND_H        EQU 7           ; altura da faixa amarela
JEEP_Y          EQU GROUND_Y - JEEP_H
JEEP_X0         EQU 0           ; posicao inicial do jipe

; --- Tela provisoria do jogo ---
WIP_ROW1        EQU 11
WIP_ROW2        EQU 13

;==============================================================================
; MACROS
;==============================================================================
; Salvam/restauram os registradores de uso geral (PUSHA/POPA nao existem no 8086)
PUSH_ALL MACRO
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
ENDM

POP_ALL MACRO
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
ENDM

;==============================================================================
; DADOS
;==============================================================================
.DATA
; ASCII art do titulo (so caracteres do teclado): cada linha termina em 0
; e todas as linhas de um bloco tem a mesma largura
title_moon      DB ' __  __  ___   ___  _   _ ',0
                DB '|  \/  |/ _ \ / _ \| \ | |',0
                DB '| |\/| | | | | | | |  \| |',0
                DB '| |  | | |_| | |_| | |\  |',0
                DB '|_|  |_|\___/ \___/|_| \_|',0

title_patrol    DB ' ____   _  _____ ____   ___  _     ',0
                DB '|  _ \ / \|_   _|  _ \ / _ \| |    ',0
                DB '| |_) / _ \ | | | |_) | | | | |    ',0
                DB '|  __/ ___ \| | |  _ <| |_| | |___ ',0
                DB '|_| /_/   \_\_| |_| \_\\___/|_____|',0

; Textos do menu: cada um ocupa MENU_TXT_LEN bytes (completar com zeros)
menu_text       DB 'JOGAR',0
                DB 'SAIR',0,0
menu_sel        DB OPT_PLAY     ; opcao selecionada

; Moldura das caixas: 3 linhas x (esquerda, meio, direita)
box_chars       DB BOX_TL, BOX_H, BOX_TR
                DB BOX_V,  ' ',   BOX_V
                DB BOX_BL, BOX_H, BOX_BR

str_wip1        DB 'JOGO EM CONSTRUCAO',0
str_wip2        DB 'PRESSIONE UMA TECLA',0

; Estado da animacao
ship_x0         DW 40, 151, 262                 ; x inicial de cada nave
ship_x          DW ANIM_SHIPS DUP (0)           ; x atual (com sinal)
ship_y          DW 100, 106, 100                ; y de cada nave
ship_type       DW 0, 1, 2                      ; tipo (sprite) de cada nave
jeep_x          DW JEEP_X0

; Sprites: 1 byte por pixel (cor), linha a linha. 00h = transparente.
; Cores (paleta padrao de 256 cores do VGA):
;   jipe : 27h rosa, DFh azul-marinho, 35h azul-claro, 86h vinho
;   naves: 4Fh azul, 04h vermelho, 2Ch amarelo
; Jipe 20x10 (Figura 10)
spr_jeep    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,27h,27h,27h,27h,27h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,0DFh,00h,00h,00h,27h,27h,27h,35h,35h,35h,35h,00h,00h,00h
            DB 00h,00h,27h,27h,27h,00h,86h,27h,27h,27h,27h,35h,35h,35h,35h,35h,35h,27h,00h,00h
            DB 00h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h
            DB 00h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,86h,86h,86h,0DFh,0DFh
            DB 00h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,00h,00h
            DB 00h,0DFh,35h,27h,27h,27h,0DFh,35h,27h,27h,27h,27h,27h,27h,27h,0DFh,35h,27h,00h,00h
            DB 35h,0DFh,0DFh,0DFh,00h,35h,0DFh,0DFh,0DFh,00h,00h,00h,00h,00h,35h,0DFh,0DFh,0DFh,00h,00h
            DB 0DFh,0DFh,0DFh,35h,00h,0DFh,0DFh,0DFh,35h,00h,00h,00h,00h,00h,0DFh,0DFh,0DFh,35h,00h,00h
            DB 00h,35h,0DFh,00h,00h,00h,35h,0DFh,00h,00h,00h,00h,00h,00h,00h,35h,0DFh,00h,00h,00h

; Naves 14x14 (Figura 7), em sequencia: tipo 0, 1, 2
spr_ship1   DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,4Fh,4Fh,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,00h,00h,00h,00h
            DB 00h,00h,00h,4Fh,4Fh,04h,4Fh,4Fh,04h,4Fh,4Fh,00h,00h,00h
            DB 00h,00h,00h,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,00h,00h,00h
            DB 00h,00h,2Ch,2Ch,2Ch,4Fh,4Fh,4Fh,4Fh,2Ch,2Ch,2Ch,00h,00h
            DB 00h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,00h
            DB 2Ch,2Ch,2Ch,2Ch,2Ch,00h,00h,00h,00h,2Ch,2Ch,2Ch,2Ch,2Ch
            DB 00h,00h,04h,04h,00h,00h,00h,00h,00h,00h,04h,04h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

spr_ship2   DB 00h,00h,00h,00h,00h,00h,4Fh,4Fh,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,4Fh,4Fh,4Fh,4Fh,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,00h,00h,00h,00h
            DB 00h,00h,00h,00h,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,00h,00h,00h,00h
            DB 00h,00h,00h,00h,4Fh,4Fh,4Fh,04h,4Fh,4Fh,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,4Fh,4Fh,4Fh,4Fh,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,04h,00h,4Fh,4Fh,00h,04h,00h,00h,00h,00h
            DB 00h,00h,4Fh,4Fh,00h,00h,00h,00h,00h,00h,4Fh,4Fh,00h,00h
            DB 00h,4Fh,4Fh,4Fh,4Fh,00h,00h,00h,00h,4Fh,4Fh,4Fh,4Fh,00h
            DB 4Fh,4Fh,04h,4Fh,4Fh,4Fh,00h,00h,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh
            DB 4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,04h,04h,4Fh,04h,4Fh,4Fh,4Fh,4Fh
            DB 4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,00h,00h,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh
            DB 00h,4Fh,4Fh,4Fh,4Fh,00h,00h,00h,00h,4Fh,4Fh,4Fh,4Fh,00h
            DB 00h,00h,4Fh,4Fh,00h,00h,00h,00h,00h,00h,4Fh,4Fh,00h,00h

spr_ship3   DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,2Ch,2Ch,2Ch,2Ch,00h,00h,00h,00h,00h
            DB 00h,00h,00h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,00h,00h,00h
            DB 00h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,00h
            DB 2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch
            DB 2Ch,2Ch,04h,04h,04h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch
            DB 00h,2Ch,2Ch,2Ch,2Ch,04h,04h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,00h
            DB 00h,00h,00h,00h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
            DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

;==============================================================================
; CODIGO
;==============================================================================
.CODE

;------------------------------------------------------------------------------
; MAIN
; Funcao : ponto de entrada; alterna entre menu e jogo ate o usuario sair
; Entrada: nenhuma
; Saida  : retorna ao DOS
;------------------------------------------------------------------------------
MAIN PROC
    mov  ax, @data
    mov  ds, ax
    cld
    mov  al, MODE_GRAPH
    call SET_MODE
main_menu:
    call MENU_RUN               ; AL = opcao escolhida
    cmp  al, OPT_PLAY
    jne  main_exit
    call GAME_RUN
    jmp  main_menu
main_exit:
    mov  al, MODE_TEXT
    call SET_MODE
    mov  ax, 4C00h
    int  21h
MAIN ENDP

;------------------------------------------------------------------------------
; MENU_RUN
; Funcao : desenha a tela inicial e roda a animacao ate uma opcao ser escolhida
; Entrada: nenhuma
; Saida  : AL = opcao escolhida (OPT_PLAY ou OPT_EXIT)
; Altera : AX
;------------------------------------------------------------------------------
MENU_RUN PROC
    call CLEAR_SCREEN
    call DRAW_TITLE
    call DRAW_GROUND
    call ANIM_INIT
    mov  [menu_sel], OPT_PLAY
    call DRAW_MENU
    call FLUSH_KEYS
mr_frame:
    call WAIT_FRAME
    call ANIM_STEP
    call GET_KEY_NB             ; AX = tecla ou 0
    or   ax, ax
    jz   mr_frame
    cmp  ah, KEY_UP
    je   mr_up
    cmp  ah, KEY_DOWN
    je   mr_down
    cmp  ah, KEY_ENTER
    je   mr_enter
    cmp  ah, KEY_ESC
    je   mr_esc
    jmp  mr_frame
mr_up:
    dec  [menu_sel]
    jns  mr_redraw
    mov  [menu_sel], MENU_ITEMS - 1     ; volta para a ultima opcao
    jmp  mr_redraw
mr_down:
    inc  [menu_sel]
    cmp  [menu_sel], MENU_ITEMS
    jb   mr_redraw
    mov  [menu_sel], 0                  ; volta para a primeira opcao
mr_redraw:
    call DRAW_MENU
    jmp  mr_frame
mr_esc:
    mov  [menu_sel], OPT_EXIT
mr_enter:
    mov  al, [menu_sel]
    ret
MENU_RUN ENDP

;------------------------------------------------------------------------------
; GAME_RUN (PROVISORIO - sera substituido pelo jogo nas proximas partes)
; Funcao : mostra um aviso e espera uma tecla
; Entrada: nenhuma
; Saida  : nenhuma
;------------------------------------------------------------------------------
GAME_RUN PROC
    PUSH_ALL
    call CLEAR_SCREEN
    mov  bl, COLOR_NORMAL
    xor  al, al                 ; area = tela inteira
    mov  ah, TEXT_COLS
    mov  si, OFFSET str_wip1
    call CENTER_TEXT
    mov  dh, WIP_ROW1
    call PRINT_STRING
    mov  si, OFFSET str_wip2
    call CENTER_TEXT
    mov  dh, WIP_ROW2
    call PRINT_STRING
    call FLUSH_KEYS
    call WAIT_KEY
    POP_ALL
    ret
GAME_RUN ENDP

;------------------------------------------------------------------------------
; DRAW_TITLE
; Funcao : escreve "MOON PATROL" em ASCII art, centralizado
; Entrada: nenhuma
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_TITLE PROC
    PUSH_ALL
    mov  bl, COLOR_TITLE
    xor  al, al                 ; area = tela inteira
    mov  ah, TEXT_COLS
    mov  si, OFFSET title_moon
    call CENTER_TEXT            ; DL = coluna
    mov  dh, TITLE1_ROW
    mov  cx, TITLE1_LINES
    call PRINT_BLOCK
    mov  si, OFFSET title_patrol
    call CENTER_TEXT
    mov  dh, TITLE2_ROW
    mov  cx, TITLE2_LINES
    call PRINT_BLOCK
    POP_ALL
    ret
DRAW_TITLE ENDP

;------------------------------------------------------------------------------
; DRAW_MENU
; Funcao : desenha todas as opcoes em caixas; a selecionada em COLOR_SELECT
; Entrada: [menu_sel] = indice da opcao selecionada
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_MENU PROC
    PUSH_ALL
    xor  di, di                 ; DI = indice da opcao
    mov  dh, MENU_ROW
dm_item:
    mov  bl, COLOR_NORMAL
    mov  ax, di
    cmp  al, [menu_sel]
    jne  dm_draw
    mov  bl, COLOR_SELECT
dm_draw:
    mov  dl, MENU_COL
    mov  cx, MENU_BOX_W
    call DRAW_TEXT_BOX
    mov  ax, di
    mov  cl, MENU_TXT_LEN
    mul  cl                     ; AX = indice * MENU_TXT_LEN
    mov  si, OFFSET menu_text
    add  si, ax                 ; SI = texto da opcao
    mov  al, MENU_COL
    mov  ah, MENU_BOX_W
    call CENTER_TEXT            ; DL = coluna centralizada na caixa
    inc  dh                     ; linha do meio da caixa
    call PRINT_STRING
    add  dh, MENU_STEP - 1      ; topo da proxima caixa
    inc  di
    cmp  di, MENU_ITEMS
    jb   dm_item
    POP_ALL
    ret
DRAW_MENU ENDP

;------------------------------------------------------------------------------
; DRAW_GROUND
; Funcao : desenha a faixa amarela do chao
; Entrada: nenhuma
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_GROUND PROC
    PUSH_ALL
    xor  ax, ax
    mov  bx, GROUND_Y
    mov  cx, SCREEN_W
    mov  dx, GROUND_H
    mov  bp, COLOR_GROUND
    call FILL_RECT
    POP_ALL
    ret
DRAW_GROUND ENDP

;------------------------------------------------------------------------------
; ANIM_INIT
; Funcao : coloca naves e jipe nas posicoes iniciais da animacao
; Entrada: nenhuma
; Saida  : ship_x[] e jeep_x inicializados
;------------------------------------------------------------------------------
ANIM_INIT PROC
    PUSH_ALL
    push es
    push ds
    pop  es
    mov  si, OFFSET ship_x0
    mov  di, OFFSET ship_x
    mov  cx, ANIM_SHIPS
    cld
    rep  movsw
    mov  [jeep_x], JEEP_X0
    pop  es
    POP_ALL
    ret
ANIM_INIT ENDP

;------------------------------------------------------------------------------
; ANIM_STEP
; Funcao : avanca um quadro da animacao (apaga, move e redesenha cada objeto).
;          As naves vao para a esquerda e o jipe para a direita; ao sair
;          totalmente da tela, cada objeto reaparece do lado oposto.
; Entrada: ship_x[], jeep_x
; Saida  : ship_x[], jeep_x atualizados e desenhados
;------------------------------------------------------------------------------
ANIM_STEP PROC
    PUSH_ALL
    xor  di, di                 ; DI = indice*2 da nave
as_ship:
    mov  ax, [ship_x + di]
    mov  bx, [ship_y + di]
    mov  cx, SHIP_W
    mov  dx, SHIP_H
    mov  bp, COLOR_BG
    call FILL_RECT              ; apaga na posicao antiga
    sub  ax, SHIP_SPEED
    cmp  ax, -SHIP_W
    jg   as_ship_ok
    add  ax, SHIP_CYCLE         ; saiu pela esquerda: volta pela direita
as_ship_ok:
    mov  [ship_x + di], ax
    push ax
    mov  ax, [ship_type + di]
    call SHIP_SPRITE            ; SI = sprite do tipo
    pop  ax
    call DRAW_SPRITE
    add  di, 2
    cmp  di, ANIM_SHIPS * 2
    jb   as_ship

    mov  ax, [jeep_x]
    mov  bx, JEEP_Y
    mov  cx, JEEP_W
    mov  dx, JEEP_H
    mov  bp, COLOR_BG
    call FILL_RECT
    add  ax, JEEP_SPEED
    cmp  ax, SCREEN_W
    jl   as_jeep_ok
    sub  ax, JEEP_CYCLE         ; saiu pela direita: volta pela esquerda
as_jeep_ok:
    mov  [jeep_x], ax
    mov  si, OFFSET spr_jeep
    call DRAW_SPRITE
    POP_ALL
    ret
ANIM_STEP ENDP

;==============================================================================
; ROTINAS GENERICAS DE VIDEO (reutilizaveis no jogo)
;==============================================================================

;------------------------------------------------------------------------------
; SET_MODE
; Funcao : troca o modo de video
; Entrada: AL = modo (MODE_GRAPH ou MODE_TEXT)
; Saida  : nenhuma
;------------------------------------------------------------------------------
SET_MODE PROC
    push ax
    xor  ah, ah
    int  10h
    pop  ax
    ret
SET_MODE ENDP

;------------------------------------------------------------------------------
; WAIT_FRAME
; Funcao : espera a duracao de um quadro (FRAME_DELAY_US) com a INT 15h/86h
; Entrada: nenhuma
; Saida  : nenhuma
;------------------------------------------------------------------------------
WAIT_FRAME PROC
    push ax
    push cx
    push dx
    xor  cx, cx                 ; CX:DX = tempo em microssegundos
    mov  dx, FRAME_DELAY_US
    mov  ah, 86h
    int  15h
    pop  dx
    pop  cx
    pop  ax
    ret
WAIT_FRAME ENDP

;------------------------------------------------------------------------------
; SHIP_SPRITE
; Funcao : devolve o endereco do sprite de um tipo de nave
; Entrada: AL = tipo (0, 1 ou 2)
; Saida  : SI = endereco do sprite
;------------------------------------------------------------------------------
SHIP_SPRITE PROC
    push ax
    mov  ah, SHIP_SIZE
    mul  ah                     ; AX = tipo * SHIP_SIZE
    mov  si, OFFSET spr_ship1
    add  si, ax
    pop  ax
    ret
SHIP_SPRITE ENDP

;------------------------------------------------------------------------------
; CALC_OFFSET
; Funcao : calcula o deslocamento de um pixel na memoria de video
; Entrada: AX = x, BX = y
; Saida  : DI = y*320 + x
;------------------------------------------------------------------------------
CALC_OFFSET PROC
    push bx
    push cx
    mov  di, bx
    mov  cl, 8
    shl  di, cl                 ; y*256
    mov  cl, 6
    shl  bx, cl                 ; y*64
    add  di, bx
    add  di, ax
    pop  cx
    pop  bx
    ret
CALC_OFFSET ENDP

;------------------------------------------------------------------------------
; CLIP_H
; Funcao : recorta horizontalmente um retangulo nas bordas da tela
; Entrada: AX = x (com sinal, pode ser negativo), CX = largura
; Saida  : AX = x recortado (>= 0), CX = largura visivel (0 = fora da tela),
;          DX = colunas cortadas a esquerda
;------------------------------------------------------------------------------
CLIP_H PROC
    push bx
    xor  dx, dx
    cmp  ax, 0
    jge  clp_right
    mov  dx, ax
    neg  dx                     ; DX = colunas fora pela esquerda
    sub  cx, dx
    jle  clp_none
    xor  ax, ax
clp_right:
    mov  bx, ax
    add  bx, cx
    sub  bx, SCREEN_W           ; BX = colunas fora pela direita
    jle  clp_ok
    sub  cx, bx
    jg   clp_ok
clp_none:
    xor  cx, cx
clp_ok:
    pop  bx
    ret
CLIP_H ENDP

;------------------------------------------------------------------------------
; FILL_RECT
; Funcao : pinta um retangulo de uma cor (REP STOSB), com recorte horizontal
; Entrada: AX = x (com sinal), BX = y, CX = largura, DX = altura,
;          BP = cor (byte baixo)
; Saida  : nenhuma
;------------------------------------------------------------------------------
FILL_RECT PROC
    PUSH_ALL
    push es
    push dx
    call CLIP_H                 ; AX = x0, CX = largura visivel
    pop  dx
    cmp  cx, 0
    je   fr_done
    call CALC_OFFSET            ; DI = inicio na memoria de video
    mov  bx, dx                 ; BX = linhas restantes
    mov  dx, cx                 ; DX = largura visivel
    mov  ax, VIDEO_SEG
    mov  es, ax
    mov  ax, bp                 ; AL = cor
    cld
fr_row:
    mov  cx, dx
    rep  stosb
    add  di, SCREEN_W
    sub  di, dx                 ; inicio da proxima linha
    dec  bx
    jnz  fr_row
fr_done:
    pop  es
    POP_ALL
    ret
FILL_RECT ENDP

;------------------------------------------------------------------------------
; DRAW_SPRITE
; Funcao : desenha um sprite (1 byte/pixel) com transparencia (cor TRANSP)
;          e recorte horizontal. Nao faz recorte vertical.
; Entrada: SI = endereco do sprite (DS), AX = x (com sinal), BX = y,
;          CX = largura, DX = altura
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_SPRITE PROC
    PUSH_ALL
    push es
    mov  bp, cx                 ; BP = largura total do sprite
    push dx
    call CLIP_H                 ; AX = x0, CX = larg. visivel, DX = cortadas
    pop  di                     ; DI = altura (temporario)
    cmp  cx, 0
    je   dsp_done
    add  si, dx                 ; pula colunas cortadas a esquerda
    sub  bp, cx                 ; BP = bytes a pular no fim de cada linha
    mov  dx, di                 ; DX = altura
    call CALC_OFFSET            ; DI = inicio na memoria de video
    mov  bx, dx                 ; BX = linhas restantes
    mov  dx, cx                 ; DX = largura visivel
    mov  ax, VIDEO_SEG
    mov  es, ax
    cld
dsp_row:
    mov  cx, dx
dsp_pixel:
    lodsb
    cmp  al, TRANSP
    je   dsp_next
    mov  es:[di], al
dsp_next:
    inc  di
    loop dsp_pixel
    add  si, bp
    add  di, SCREEN_W
    sub  di, dx                 ; inicio da proxima linha
    dec  bx
    jnz  dsp_row
dsp_done:
    pop  es
    POP_ALL
    ret
DRAW_SPRITE ENDP

;------------------------------------------------------------------------------
; CLEAR_SCREEN
; Funcao : pinta a tela inteira com COLOR_BG
; Entrada: nenhuma
; Saida  : nenhuma
;------------------------------------------------------------------------------
CLEAR_SCREEN PROC
    PUSH_ALL
    xor  ax, ax
    xor  bx, bx
    mov  cx, SCREEN_W
    mov  dx, SCREEN_H
    mov  bp, COLOR_BG
    call FILL_RECT
    POP_ALL
    ret
CLEAR_SCREEN ENDP

;==============================================================================
; ROTINAS GENERICAS DE TEXTO (INT 10h)
;==============================================================================

;------------------------------------------------------------------------------
; PUT_CHAR
; Funcao : escreve um caractere (repetido) na posicao de texto indicada
; Entrada: AL = caractere, BL = cor, CX = repeticoes (>= 1),
;          DH = linha (0-24), DL = coluna (0-39)
; Saida  : nenhuma
;------------------------------------------------------------------------------
PUT_CHAR PROC
    push ax
    push bx
    push ax
    mov  ah, 02h                ; posiciona o cursor
    mov  bh, VIDEO_PAGE
    int  10h
    pop  ax
    mov  ah, 09h                ; escreve caractere com cor
    mov  bh, VIDEO_PAGE
    int  10h
    pop  bx
    pop  ax
    ret
PUT_CHAR ENDP

;------------------------------------------------------------------------------
; PRINT_STRING
; Funcao : escreve uma string terminada em 0
; Entrada: SI = string (DS), DH = linha, DL = coluna, BL = cor
; Saida  : SI = byte seguinte ao 0 final (inicio da proxima string)
;------------------------------------------------------------------------------
PRINT_STRING PROC
    push ax
    push cx
    push dx
    mov  cx, 1
ps_next:
    lodsb
    cmp  al, 0
    je   ps_end
    call PUT_CHAR
    inc  dl
    jmp  ps_next
ps_end:
    pop  dx
    pop  cx
    pop  ax
    ret
PRINT_STRING ENDP

;------------------------------------------------------------------------------
; PRINT_BLOCK
; Funcao : escreve varias strings consecutivas, uma por linha (ASCII art)
; Entrada: SI = primeira string, CX = numero de linhas,
;          DH = linha inicial, DL = coluna, BL = cor
; Saida  : SI = byte seguinte a ultima string
;------------------------------------------------------------------------------
PRINT_BLOCK PROC
    push cx
    push dx
pb_next:
    call PRINT_STRING
    inc  dh
    loop pb_next
    pop  dx
    pop  cx
    ret
PRINT_BLOCK ENDP

;------------------------------------------------------------------------------
; STR_LEN
; Funcao : conta os caracteres de uma string terminada em 0
; Entrada: SI = string (DS)
; Saida  : CX = tamanho
;------------------------------------------------------------------------------
STR_LEN PROC
    push ax
    push si
    xor  cx, cx
sl_next:
    lodsb
    cmp  al, 0
    je   sl_end
    inc  cx
    jmp  sl_next
sl_end:
    pop  si
    pop  ax
    ret
STR_LEN ENDP

;------------------------------------------------------------------------------
; CENTER_TEXT
; Funcao : calcula a coluna para centralizar uma string numa area
; Entrada: SI = string, AL = coluna inicial da area, AH = largura da area
; Saida  : DL = coluna onde a string deve comecar
;------------------------------------------------------------------------------
CENTER_TEXT PROC
    push cx
    call STR_LEN
    mov  dl, ah
    sub  dl, cl
    shr  dl, 1
    add  dl, al
    pop  cx
    ret
CENTER_TEXT ENDP

;------------------------------------------------------------------------------
; DRAW_TEXT_BOX
; Funcao : desenha uma caixa de 3 linhas com caracteres de moldura
; Entrada: DH = linha do topo, DL = coluna esquerda, CX = largura (>= 3),
;          BL = cor
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_TEXT_BOX PROC
    PUSH_ALL
    mov  di, cx                 ; DI = largura total
    mov  si, OFFSET box_chars
    mov  ah, 3                  ; AH = linhas da caixa
dtb_row:
    push dx
    lodsb                       ; lado esquerdo
    mov  cx, 1
    call PUT_CHAR
    inc  dl
    lodsb                       ; meio (repetido)
    mov  cx, di
    sub  cx, 2
    call PUT_CHAR
    add  dl, cl
    lodsb                       ; lado direito
    mov  cx, 1
    call PUT_CHAR
    pop  dx
    inc  dh
    dec  ah
    jnz  dtb_row
    POP_ALL
    ret
DRAW_TEXT_BOX ENDP

;==============================================================================
; ROTINAS GENERICAS DE TECLADO (INT 16h)
;==============================================================================

;------------------------------------------------------------------------------
; GET_KEY_NB
; Funcao : le uma tecla sem esperar
; Entrada: nenhuma
; Saida  : AX = 0 se nao ha tecla; senao AH = scan code, AL = ASCII
;------------------------------------------------------------------------------
GET_KEY_NB PROC
    mov  ah, 01h
    int  16h
    jz   gk_none
    xor  ah, ah
    int  16h
    ret
gk_none:
    xor  ax, ax
    ret
GET_KEY_NB ENDP

;------------------------------------------------------------------------------
; WAIT_KEY
; Funcao : espera uma tecla
; Entrada: nenhuma
; Saida  : AH = scan code, AL = ASCII
;------------------------------------------------------------------------------
WAIT_KEY PROC
    xor  ah, ah
    int  16h
    ret
WAIT_KEY ENDP

;------------------------------------------------------------------------------
; FLUSH_KEYS
; Funcao : descarta as teclas pendentes no buffer do teclado
; Entrada: nenhuma
; Saida  : nenhuma
;------------------------------------------------------------------------------
FLUSH_KEYS PROC
    push ax
fk_next:
    call GET_KEY_NB
    or   ax, ax
    jnz  fk_next
    pop  ax
    ret
FLUSH_KEYS ENDP

END MAIN
