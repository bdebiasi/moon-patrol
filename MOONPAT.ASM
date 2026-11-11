;==============================================================================
; MOON PATROL - PARTE 1: TELA INICIAL
;------------------------------------------------------------------------------
; Montador : TASM (GUI Turbo Assembler). Codigo 8086 puro (sem 186/286).
; Video    : modo 13h (320x200, 256 cores). Os pixels sao escritos no
;            segmento A000h somente com enderecamento indireto (ES:[DI]) e
;            instrucoes de string (REP STOSB); a INT 10h e usada apenas para
;            trocar o modo e escrever texto.
; Teclas   : SETA CIMA/BAIXO escolhe, ENTER confirma, ESC sai
;==============================================================================
.MODEL SMALL
.STACK 400h

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
TRANSPARENTE    EQU 0FFh        ; cor pulada pelo DRAW_SPRITE

; --- Moldura das caixas (caracteres de caixa da pagina de codigo 437) ---
BOX_TL          EQU 218         ; canto superior esquerdo
BOX_TR          EQU 191         ; canto superior direito
BOX_BL          EQU 192         ; canto inferior esquerdo
BOX_BR          EQU 217         ; canto inferior direito
BOX_H           EQU 196         ; linha horizontal
BOX_V           EQU 179         ; linha vertical
BOX_ROWS        EQU 3           ; linhas de uma caixa (topo, meio, base)
BOX_BORDERS     EQU 2           ; colunas ocupadas pelas bordas laterais

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
MENU_COL        EQU (TEXT_COLS - MENU_BOX_W) / 2   ; caixa centralizada
MENU_ROW        EQU 18          ; linha do topo da primeira caixa
MENU_STEP       EQU 3           ; linhas entre o topo de uma caixa e a outra

; --- Sprites ---
JEEP_W          EQU 20
JEEP_H          EQU 10
SHIP_W          EQU 14
SHIP_H          EQU 14
SHIP_SIZE       EQU SHIP_W * SHIP_H     ; bytes de cada sprite de nave

; --- Registro da tabela de objetos (todos os campos sao words) ---
OBJ_ATIVO       EQU 0           ; ATIVO ou INATIVO
OBJ_X           EQU 2           ; x (com sinal, pode estar fora da tela)
OBJ_Y           EQU 4           ; y
OBJ_LARG        EQU 6           ; largura em pixels
OBJ_ALT         EQU 8           ; altura em pixels
OBJ_VX          EQU 10          ; velocidade horizontal (pixels/quadro)
OBJ_VY          EQU 12          ; velocidade vertical (pixels/quadro)
OBJ_SPRITE      EQU 14          ; offset do bitmap no DS
OBJ_TAM         EQU 16          ; bytes de cada registro
ATIVO           EQU 1
INATIVO         EQU 0

; --- Animacao da tela inicial ---
FRAME_DELAY_US  EQU 14000       ; duracao de um quadro em microssegundos
ANIM_SHIPS      EQU 3           ; naves na animacao
ANIM_SHIP_VX    EQU 1           ; naves: pixels por quadro (esq. -> dir.)
ANIM_JEEP_VX    EQU 1           ; jipe: pixels por quadro (esq. -> dir.)
ANIM_VY         EQU 0           ; na animacao ninguem anda na vertical
ANIM_SHIP_X0    EQU 40          ; x inicial da primeira nave
ANIM_SHIP_DX    EQU (SCREEN_W + SHIP_W) / ANIM_SHIPS  ; distancia entre naves
ANIM_SHIP_Y     EQU 100         ; y das naves das pontas
ANIM_SHIP_DY    EQU 6           ; desnivel da nave do meio
GROUND_H        EQU 7           ; altura da faixa amarela (menu e pista)
MENU_GROUND_Y   EQU 133         ; primeira linha da faixa amarela do menu
MENU_JEEP_Y     EQU MENU_GROUND_Y - JEEP_H
JEEP_X0         EQU 0           ; posicao inicial do jipe na animacao

; --- Texto ---
CHAR_W          EQU 8           ; largura de um caractere em pixels
CHAR_H          EQU 8           ; altura de um caractere em pixels
DEC_BASE        EQU 10          ; base usada na conversao para decimal
NUM_MAX_DIGITS  EQU 5           ; maior numero de digitos impresso

; --- Layout da tela de jogo (linhas em pixels) ---
STATUS_H        EQU 15          ; barra de status: linhas 0 .. STATUS_H-1
TRACK_Y         EQU 193         ; topo da pista amarela (GROUND_H de altura)
WORD_BYTES      EQU 2           ; bytes de uma word (passo das tabelas DW)

; --- Montanhas (bitmaps em RLE por coluna; ver back_rle / front_rle) ---
; A camada da frente se apoia no topo da pista e e desenhada por cima da
; do fundo. O fundo fica no topo da regiao das montanhas (linha 100) para
; aparecer mais. Limite: a base do fundo (MOUNT_BACK_Y + MOUNT_BACK_H - 1)
; precisa ficar na linha 162 ou abaixo (ultima linha de ceu da frente),
; senao surge uma faixa preta entre as duas camadas.
MOUNT_TOP_Y     EQU 100         ; linha mais alta permitida para montanhas
MOUNT_BACK_W    EQU 256         ; colunas do bitmap do fundo (periodo do scroll)
MOUNT_BACK_H    EQU 64          ; linhas do bitmap do fundo
MOUNT_BACK_Y    EQU MOUNT_TOP_Y                 ; linha do topo do fundo
MOUNT_FRONT_W   EQU 256         ; colunas do bitmap da frente
MOUNT_FRONT_H   EQU 64
MOUNT_FRONT_Y   EQU TRACK_Y - MOUNT_FRONT_H     ; linha do topo da frente
SCROLL_START    EQU 0           ; coluna do bitmap mostrada em x = 0

; --- Barra de status (layout de "status do jogo.png") ---
; [coracoes]            [score]               [relogio] [tempo]
COLOR_SCORE     EQU 0Fh         ; score em branco
COLOR_TIME      EQU 0Ch         ; tempo em vermelho-claro
STATUS_ROW      EQU 0           ; linha de texto do score e do tempo
SCORE_DIGITS    EQU 5
SCORE_COL       EQU (TEXT_COLS - SCORE_DIGITS) / 2  ; score centralizado
TIME_DIGITS     EQU 2
TIME_MARGIN     EQU 2           ; colunas livres a direita do tempo
TIME_COL        EQU TEXT_COLS - TIME_DIGITS - TIME_MARGIN
HEART1_W        EQU 10          ; largura do bitmap de 1 vida
HEART2_W        EQU 14          ; largura do bitmap de 2 vidas
HEART3_W        EQU 18          ; largura do bitmap de 3 vidas
HEART_MAX_W     EQU HEART3_W    ; area apagada antes de redesenhar
HEART_H         EQU 11
HEART_X         EQU 0           ; coracoes no canto esquerdo
HEART_Y         EQU 0
CLOCK_W         EQU 7
CLOCK_H         EQU 8
CLOCK_GAP       EQU 11          ; pixels entre o relogio e o tempo
CLOCK_X         EQU TIME_COL * CHAR_W - CLOCK_GAP - CLOCK_W
CLOCK_Y         EQU STATUS_ROW * CHAR_H

; --- Partida ---
SCORE_START     EQU 0
LIVES_START     EQU 3
GAME_TIME       EQU 60          ; duracao da partida em segundos (<= 99)
PARADO          EQU 0           ; velocidade nula
JEEP_START_X    EQU 0           ; coluna em que o jipe nasce/renasce
JEEP_GAME_Y     EQU TRACK_Y - JEEP_H                ; jipe no chao

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

; Textos do menu e tabela com o endereco de cada um (indice = opcao)
menu_opt_play   DB 'Jogar',0
menu_opt_exit   DB 'Sair',0
menu_ptrs       DW OFFSET menu_opt_play, OFFSET menu_opt_exit
menu_sel        DB OPT_PLAY     ; opcao selecionada

; Moldura das caixas: BOX_ROWS linhas x (esquerda, meio, direita)
box_chars       DB BOX_TL, BOX_H, BOX_TR
                DB BOX_V,  ' ',   BOX_V
                DB BOX_BL, BOX_H, BOX_BR

; Estado da partida
score           DW SCORE_START
lives           DW LIVES_START
time_left       DW GAME_TIME                    ; segundos restantes
back_scroll     DW SCROLL_START                 ; 0 .. MOUNT_BACK_W - 1
front_scroll    DW SCROLL_START                 ; 0 .. MOUNT_FRONT_W - 1
num_buf         DB NUM_MAX_DIGITS + 1 DUP (0)   ; digitos + 0 final

; Sprites: 1 byte por pixel (cor), linha a linha. 0FFh = transparente.
; Cores (paleta padrao de 256 cores do VGA):
;   jipe : 27h rosa, DFh azul-marinho, 35h azul-claro, 86h vinho
;   naves: 4Fh azul, 04h vermelho, 2Ch amarelo
; Jipe 20x10 (Figura 10)
spr_jeep    DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,27h,27h,27h,27h,27h,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0DFh,0FFh,0FFh,0FFh,27h,27h,27h,35h,35h,35h,35h,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,27h,27h,27h,0FFh,86h,27h,27h,27h,27h,35h,35h,35h,35h,35h,35h,27h,0FFh,0FFh
            DB 0FFh,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h
            DB 0FFh,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,86h,86h,86h,0DFh,0DFh
            DB 0FFh,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,27h,0FFh,0FFh
            DB 0FFh,0DFh,35h,27h,27h,27h,0DFh,35h,27h,27h,27h,27h,27h,27h,27h,0DFh,35h,27h,0FFh,0FFh
            DB 35h,0DFh,0DFh,0DFh,0FFh,35h,0DFh,0DFh,0DFh,0FFh,0FFh,0FFh,0FFh,0FFh,35h,0DFh,0DFh,0DFh,0FFh,0FFh
            DB 0DFh,0DFh,0DFh,35h,0FFh,0DFh,0DFh,0DFh,35h,0FFh,0FFh,0FFh,0FFh,0FFh,0DFh,0DFh,0DFh,35h,0FFh,0FFh
            DB 0FFh,35h,0DFh,0FFh,0FFh,0FFh,35h,0DFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,35h,0DFh,0FFh,0FFh,0FFh

; Naves 14x14 (Figura 7), em sequencia: tipo 0, 1, 2
spr_ship1   DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,4Fh,4Fh,04h,4Fh,4Fh,04h,4Fh,4Fh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,2Ch,2Ch,2Ch,4Fh,4Fh,4Fh,4Fh,2Ch,2Ch,2Ch,0FFh,0FFh
            DB 0FFh,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,0FFh
            DB 2Ch,2Ch,2Ch,2Ch,2Ch,0FFh,0FFh,0FFh,0FFh,2Ch,2Ch,2Ch,2Ch,2Ch
            DB 0FFh,0FFh,04h,04h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,04h,04h,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh

spr_ship2   DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,04h,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,04h,0FFh,4Fh,4Fh,0FFh,04h,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,0FFh,0FFh
            DB 0FFh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,0FFh
            DB 4Fh,4Fh,04h,4Fh,4Fh,4Fh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh
            DB 4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,04h,04h,4Fh,04h,4Fh,4Fh,4Fh,4Fh
            DB 4Fh,4Fh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,4Fh,4Fh
            DB 0FFh,4Fh,4Fh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,4Fh,4Fh,0FFh
            DB 0FFh,0FFh,4Fh,4Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,4Fh,4Fh,0FFh,0FFh

spr_ship3   DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,2Ch,2Ch,2Ch,2Ch,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,0FFh,0FFh,0FFh
            DB 0FFh,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,0FFh
            DB 2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch
            DB 2Ch,2Ch,04h,04h,04h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch
            DB 0FFh,2Ch,2Ch,2Ch,2Ch,04h,04h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh

; Tabela inicial da animacao: copiada para anim_tab sempre que o menu abre.
; Campos de cada registro: ATIVO, X, Y, LARG, ALT, VX, VY, SPRITE
anim_tab0   DW ATIVO, ANIM_SHIP_X0, ANIM_SHIP_Y
            DW SHIP_W, SHIP_H, ANIM_SHIP_VX, ANIM_VY, OFFSET spr_ship1
            DW ATIVO, ANIM_SHIP_X0 + ANIM_SHIP_DX, ANIM_SHIP_Y + ANIM_SHIP_DY
            DW SHIP_W, SHIP_H, ANIM_SHIP_VX, ANIM_VY, OFFSET spr_ship2
            DW ATIVO, ANIM_SHIP_X0 + 2 * ANIM_SHIP_DX, ANIM_SHIP_Y
            DW SHIP_W, SHIP_H, ANIM_SHIP_VX, ANIM_VY, OFFSET spr_ship3
            DW ATIVO, JEEP_X0, MENU_JEEP_Y
            DW JEEP_W, JEEP_H, ANIM_JEEP_VX, ANIM_VY, OFFSET spr_jeep
ANIM_TAB_BYTES  EQU $ - anim_tab0
ANIM_OBJS       EQU ANIM_TAB_BYTES / OBJ_TAM    ; naves + jipe

anim_tab    DB ANIM_TAB_BYTES DUP (?)           ; estado atual da animacao

; Montanha do fundo (montanha fundo.png): 256x64, RLE por coluna (de cima para baixo).
; Cada coluna: pares (quantidade, cor) terminados por 0. 0FFh = transparente.
back_rle    DB 24,0FFh,40,03h,0                                         ; col 0
            DB 22,0FFh,2,20h,5,03h,1,20h,34,03h,0                       ; col 1
            DB 21,0FFh,3,20h,4,03h,1,20h,35,03h,0                       ; col 2
            DB 21,0FFh,2,20h,4,03h,1,20h,36,03h,0                       ; col 3
            DB 19,0FFh,4,20h,2,03h,3,20h,36,03h,0                       ; col 4
            DB 19,0FFh,8,20h,37,03h,0                                   ; col 5
            DB 17,0FFh,7,20h,40,03h,0                                   ; col 6
            DB 16,0FFh,10,20h,38,03h,0                                  ; col 7
            DB 17,0FFh,8,20h,39,03h,0                                   ; col 8
            DB 18,0FFh,5,20h,41,03h,0                                   ; col 9
            DB 15,0FFh,7,20h,42,03h,0                                   ; col 10
            DB 14,0FFh,8,20h,42,03h,0                                   ; col 11
            DB 11,0FFh,7,20h,2,03h,1,20h,43,03h,0                       ; col 12
            DB 11,0FFh,7,20h,3,03h,1,20h,42,03h,0                       ; col 13
            DB 10,0FFh,9,20h,3,03h,1,20h,8,03h,1,20h,32,03h,0           ; col 14
            DB 8,0FFh,10,20h,13,03h,1,20h,32,03h,0                      ; col 15
            DB 5,0FFh,13,20h,46,03h,0                                   ; col 16
            DB 19,20h,45,03h,0                                          ; col 17
            DB 1,0FFh,8,20h,3,03h,2,20h,1,03h,2,20h,2,03h,1,20h,44,03h,0 ; col 18
            DB 3,0FFh,2,20h,15,03h,1,20h,43,03h,0                       ; col 19
            DB 7,0FFh,57,03h,0                                          ; col 20
            DB 6,0FFh,3,03h,2,20h,53,03h,0                              ; col 21
            DB 4,0FFh,6,03h,2,20h,52,03h,0                              ; col 22
            DB 3,0FFh,61,03h,0                                          ; col 23
            DB 4,0FFh,3,03h,1,20h,4,03h,3,20h,14,03h,1,20h,34,03h,0     ; col 24
            DB 5,0FFh,6,03h,7,20h,46,03h,0                              ; col 25
            DB 7,0FFh,5,03h,9,20h,5,03h,1,20h,37,03h,0                  ; col 26
            DB 10,0FFh,11,20h,4,03h,2,20h,37,03h,0                      ; col 27
            DB 16,0FFh,6,20h,1,03h,4,20h,37,03h,0                       ; col 28
            DB 19,0FFh,2,03h,5,20h,2,03h,1,20h,35,03h,0                 ; col 29
            DB 21,0FFh,4,20h,2,03h,1,20h,36,03h,0                       ; col 30
            DB 23,0FFh,1,20h,3,03h,1,20h,36,03h,0                       ; col 31
            DB 24,0FFh,40,03h,0                                         ; col 32
            DB 24,0FFh,3,03h,1,20h,36,03h,0                             ; col 33
            DB 23,0FFh,4,03h,3,20h,34,03h,0                             ; col 34
            DB 23,0FFh,3,03h,3,20h,35,03h,0                             ; col 35
            DB 23,0FFh,2,03h,3,20h,36,03h,0                             ; col 36
            DB 22,0FFh,3,03h,5,20h,34,03h,0                             ; col 37
            DB 20,0FFh,4,03h,7,20h,33,03h,0                             ; col 38
            DB 19,0FFh,6,03h,4,20h,2,03h,1,20h,32,03h,0                 ; col 39
            DB 20,0FFh,7,03h,1,20h,36,03h,0                             ; col 40
            DB 21,0FFh,43,03h,0                                         ; col 41
            DB 20,0FFh,44,03h,0                                         ; col 42
            DB 19,0FFh,45,03h,0                                         ; col 43
            DB 17,0FFh,4,03h,1,20h,10,03h,1,20h,31,03h,0                ; col 44
            DB 14,0FFh,6,03h,1,20h,7,03h,1,20h,2,03h,1,20h,32,03h,0     ; col 45
            DB 12,0FFh,11,03h,2,20h,3,03h,1,20h,1,03h,2,20h,32,03h,0    ; col 46
            DB 10,0FFh,14,03h,2,20h,1,03h,3,20h,34,03h,0                ; col 47
            DB 11,0FFh,4,03h,2,20h,3,03h,2,20h,1,03h,7,20h,34,03h,0     ; col 48
            DB 13,0FFh,16,20h,35,03h,0                                  ; col 49
            DB 12,0FFh,17,20h,35,03h,0                                  ; col 50
            DB 11,0FFh,2,20h,1,0FFh,10,20h,1,03h,5,20h,34,03h,0         ; col 51
            DB 11,0FFh,11,20h,2,03h,8,20h,32,03h,0                      ; col 52
            DB 13,0FFh,8,20h,2,03h,8,20h,33,03h,0                       ; col 53
            DB 16,0FFh,13,20h,35,03h,0                                  ; col 54
            DB 21,0FFh,7,20h,36,03h,0                                   ; col 55
            DB 24,0FFh,5,20h,35,03h,0                                   ; col 56
            DB 24,0FFh,6,20h,34,03h,0                                   ; col 57
            DB 26,0FFh,5,20h,33,03h,0                                   ; col 58
            DB 28,0FFh,4,20h,32,03h,0                                   ; col 59
            DB 31,0FFh,3,20h,30,03h,0                                   ; col 60
            DB 32,0FFh,1,03h,1,20h,30,03h,0                             ; col 61
            DB 30,0FFh,4,03h,1,20h,29,03h,0                             ; col 62
            DB 27,0FFh,8,03h,1,20h,28,03h,0                             ; col 63
            DB 26,0FFh,38,03h,0                                         ; col 64
            DB 27,0FFh,37,03h,0                                         ; col 65
            DB 24,0FFh,40,03h,0                                         ; col 66
            DB 22,0FFh,9,03h,1,20h,32,03h,0                             ; col 67
            DB 20,0FFh,10,03h,1,20h,33,03h,0                            ; col 68
            DB 19,0FFh,5,03h,2,20h,3,03h,1,20h,7,03h,1,20h,26,03h,0     ; col 69
            DB 16,0FFh,7,03h,3,20h,1,03h,3,20h,7,03h,1,20h,26,03h,0     ; col 70
            DB 16,0FFh,6,03h,7,20h,35,03h,0                             ; col 71
            DB 17,0FFh,2,03h,2,20h,1,03h,6,20h,36,03h,0                 ; col 72
            DB 19,0FFh,9,20h,1,03h,2,20h,6,03h,2,20h,25,03h,0           ; col 73
            DB 23,0FFh,8,20h,4,03h,2,20h,27,03h,0                       ; col 74
            DB 27,0FFh,2,20h,4,03h,1,20h,30,03h,0                       ; col 75
            DB 23,0FFh,6,20h,3,03h,1,20h,31,03h,0                       ; col 76
            DB 23,0FFh,10,20h,31,03h,0                                  ; col 77
            DB 25,0FFh,5,20h,34,03h,0                                   ; col 78
            DB 28,0FFh,36,03h,0                                         ; col 79
            DB 29,0FFh,5,20h,30,03h,0                                   ; col 80
            DB 32,0FFh,4,20h,28,03h,0                                   ; col 81
            DB 35,0FFh,4,20h,25,03h,0                                   ; col 82
            DB 36,0FFh,4,20h,24,03h,0                                   ; col 83
            DB 34,0FFh,4,20h,3,03h,1,20h,22,03h,0                       ; col 84
            DB 32,0FFh,2,20h,30,03h,0                                   ; col 85
            DB 32,0FFh,32,03h,0                                         ; col 86
            DB 29,0FFh,35,03h,0                                         ; col 87
            DB 27,0FFh,9,03h,1,20h,27,03h,0                             ; col 88
            DB 27,0FFh,8,03h,2,20h,27,03h,0                             ; col 89
            DB 25,0FFh,8,03h,3,20h,28,03h,0                             ; col 90
            DB 21,0FFh,3,20h,7,03h,6,20h,27,03h,0                       ; col 91
            DB 20,0FFh,3,20h,6,03h,6,20h,29,03h,0                       ; col 92
            DB 20,0FFh,2,20h,8,03h,3,20h,31,03h,0                       ; col 93
            DB 21,0FFh,3,20h,6,03h,5,20h,29,03h,0                       ; col 94
            DB 20,0FFh,5,20h,6,03h,6,20h,27,03h,0                       ; col 95
            DB 17,0FFh,6,20h,2,03h,1,20h,5,03h,2,20h,4,03h,1,20h,26,03h,0 ; col 96
            DB 14,0FFh,4,03h,1,20h,1,03h,2,20h,9,03h,3,20h,4,03h,1,20h,25,03h,0 ; col 97
            DB 10,0FFh,4,03h,2,20h,12,03h,2,20h,34,03h,0                ; col 98
            DB 10,0FFh,54,03h,0                                         ; col 99
            DB 12,0FFh,52,03h,0                                         ; col 100
            DB 14,0FFh,3,03h,2,20h,11,03h,1,20h,33,03h,0                ; col 101
            DB 13,0FFh,9,20h,8,03h,1,20h,33,03h,0                       ; col 102
            DB 15,0FFh,5,20h,10,03h,1,20h,33,03h,0                      ; col 103
            DB 16,0FFh,5,20h,43,03h,0                                   ; col 104
            DB 19,0FFh,3,20h,11,03h,1,20h,30,03h,0                      ; col 105
            DB 21,0FFh,4,20h,7,03h,1,20h,31,03h,0                       ; col 106
            DB 20,0FFh,4,20h,5,03h,4,20h,31,03h,0                       ; col 107
            DB 19,0FFh,6,20h,3,03h,3,20h,33,03h,0                       ; col 108
            DB 23,0FFh,1,20h,1,03h,2,20h,1,03h,1,20h,35,03h,0           ; col 109
            DB 25,0FFh,3,20h,1,03h,2,20h,33,03h,0                       ; col 110
            DB 25,0FFh,4,20h,35,03h,0                                   ; col 111
            DB 27,0FFh,37,03h,0                                         ; col 112
            DB 34,0FFh,30,03h,0                                         ; col 113
            DB 32,0FFh,32,03h,0                                         ; col 114
            DB 29,0FFh,35,03h,0                                         ; col 115
            DB 26,0FFh,38,03h,0                                         ; col 116
            DB 26,0FFh,38,03h,0                                         ; col 117
            DB 25,0FFh,39,03h,0                                         ; col 118
            DB 25,0FFh,39,03h,0                                         ; col 119
            DB 22,0FFh,7,20h,35,03h,0                                   ; col 120
            DB 14,0FFh,12,20h,3,03h,1,20h,34,03h,0                      ; col 121
            DB 11,0FFh,12,20h,9,03h,1,20h,31,03h,0                      ; col 122
            DB 2,0FFh,2,03h,10,20h,2,03h,2,20h,2,03h,3,20h,9,03h,1,20h,31,03h,0 ; col 123
            DB 6,03h,2,20h,24,03h,2,20h,30,03h,0                        ; col 124
            DB 34,03h,1,20h,29,03h,0                                    ; col 125
            DB 2,0FFh,33,03h,1,20h,28,03h,0                             ; col 126
            DB 4,0FFh,2,03h,1,20h,3,03h,2,20h,4,03h,3,20h,4,03h,3,20h,38,03h,0 ; col 127
            DB 4,0FFh,10,20h,4,03h,4,20h,42,03h,0                       ; col 128
            DB 6,0FFh,5,20h,1,03h,4,20h,48,03h,0                        ; col 129
            DB 8,0FFh,1,03h,1,20h,54,03h,0                              ; col 130
            DB 7,0FFh,12,03h,5,20h,6,03h,1,20h,33,03h,0                 ; col 131
            DB 5,0FFh,12,03h,4,20h,8,03h,4,20h,31,03h,0                 ; col 132
            DB 10,0FFh,18,03h,8,20h,28,03h,0                            ; col 133
            DB 22,0FFh,5,03h,6,20h,4,03h,1,20h,26,03h,0                 ; col 134
            DB 19,0FFh,8,03h,4,20h,7,03h,1,20h,25,03h,0                 ; col 135
            DB 21,0FFh,7,03h,4,20h,32,03h,0                             ; col 136
            DB 21,0FFh,7,03h,3,20h,33,03h,0                             ; col 137
            DB 23,0FFh,7,03h,2,20h,32,03h,0                             ; col 138
            DB 25,0FFh,5,03h,1,20h,33,03h,0                             ; col 139
            DB 25,0FFh,39,03h,0                                         ; col 140
            DB 30,0FFh,34,03h,0                                         ; col 141
            DB 30,0FFh,34,03h,0                                         ; col 142
            DB 33,0FFh,31,03h,0                                         ; col 143
            DB 33,0FFh,31,03h,0                                         ; col 144
            DB 35,0FFh,2,20h,27,03h,0                                   ; col 145
            DB 35,0FFh,3,20h,26,03h,0                                   ; col 146
            DB 34,0FFh,2,20h,28,03h,0                                   ; col 147
            DB 32,0FFh,2,20h,30,03h,0                                   ; col 148
            DB 32,0FFh,2,20h,30,03h,0                                   ; col 149
            DB 29,0FFh,4,20h,1,03h,1,20h,29,03h,0                       ; col 150
            DB 27,0FFh,2,03h,1,20h,5,03h,1,20h,28,03h,0                 ; col 151
            DB 27,0FFh,37,03h,0                                         ; col 152
            DB 24,0FFh,40,03h,0                                         ; col 153
            DB 24,0FFh,12,03h,1,20h,27,03h,0                            ; col 154
            DB 25,0FFh,10,03h,1,20h,3,03h,1,20h,24,03h,0                ; col 155
            DB 26,0FFh,8,03h,1,20h,3,03h,1,20h,3,03h,1,20h,21,03h,0     ; col 156
            DB 25,0FFh,3,03h,1,20h,5,03h,1,20h,6,03h,1,20h,22,03h,0     ; col 157
            DB 25,0FFh,1,03h,2,20h,4,03h,4,20h,4,03h,2,20h,22,03h,0     ; col 158
            DB 31,0FFh,6,20h,1,03h,3,20h,23,03h,0                       ; col 159
            DB 35,0FFh,8,20h,21,03h,0                                   ; col 160
            DB 35,0FFh,6,20h,4,03h,1,20h,18,03h,0                       ; col 161
            DB 35,0FFh,7,20h,2,03h,1,20h,19,03h,0                       ; col 162
            DB 37,0FFh,8,20h,19,03h,0                                   ; col 163
            DB 38,0FFh,1,03h,4,20h,21,03h,0                             ; col 164
            DB 37,0FFh,1,03h,3,20h,23,03h,0                             ; col 165
            DB 34,0FFh,8,20h,22,03h,0                                   ; col 166
            DB 33,0FFh,8,20h,23,03h,0                                   ; col 167
            DB 31,0FFh,16,03h,8,20h,9,03h,0                             ; col 168
            DB 28,0FFh,16,03h,9,20h,11,03h,0                            ; col 169
            DB 24,0FFh,16,03h,14,20h,10,03h,0                           ; col 170
            DB 24,0FFh,16,03h,14,20h,4,03h,1,20h,5,03h,0                ; col 171
            DB 19,0FFh,16,03h,7,20h,1,03h,10,20h,4,03h,3,20h,4,03h,0    ; col 172
            DB 13,0FFh,16,03h,2,20h,6,03h,1,20h,2,03h,1,20h,5,03h,3,20h,1,03h,3,20h,3,03h,5,20h,3,03h,0 ; col 173
            DB 13,0FFh,33,03h,2,20h,2,03h,2,20h,5,03h,2,20h,5,03h,0     ; col 174
            DB 13,0FFh,18,03h,4,20h,12,03h,1,20h,3,03h,1,20h,6,03h,1,20h,5,03h,0 ; col 175
            DB 17,0FFh,2,03h,2,20h,10,03h,1,20h,2,03h,1,20h,29,03h,0    ; col 176
            DB 16,0FFh,6,03h,2,20h,40,03h,0                             ; col 177
            DB 16,0FFh,11,03h,1,20h,36,03h,0                            ; col 178
            DB 19,0FFh,45,03h,0                                         ; col 179
            DB 18,0FFh,1,03h,2,20h,10,03h,1,20h,32,03h,0                ; col 180
            DB 18,0FFh,11,03h,2,20h,8,03h,1,20h,24,03h,0                ; col 181
            DB 28,0FFh,2,20h,8,03h,1,20h,25,03h,0                       ; col 182
            DB 32,0FFh,4,03h,3,20h,25,03h,0                             ; col 183
            DB 33,0FFh,6,20h,25,03h,0                                   ; col 184
            DB 33,0FFh,3,20h,28,03h,0                                   ; col 185
            DB 37,0FFh,27,03h,0                                         ; col 186
            DB 37,0FFh,27,03h,0                                         ; col 187
            DB 38,0FFh,26,03h,0                                         ; col 188
            DB 38,0FFh,5,03h,1,20h,20,03h,0                             ; col 189
            DB 39,0FFh,3,03h,1,20h,21,03h,0                             ; col 190
            DB 39,0FFh,2,03h,1,20h,22,03h,0                             ; col 191
            DB 37,0FFh,2,20h,25,03h,0                                   ; col 192
            DB 34,0FFh,6,20h,24,03h,0                                   ; col 193
            DB 34,0FFh,4,20h,26,03h,0                                   ; col 194
            DB 31,0FFh,5,20h,28,03h,0                                   ; col 195
            DB 31,0FFh,3,20h,2,03h,3,20h,25,03h,0                       ; col 196
            DB 31,0FFh,2,20h,4,03h,1,20h,1,03h,1,20h,24,03h,0           ; col 197
            DB 31,0FFh,33,03h,0                                         ; col 198
            DB 26,0FFh,38,03h,0                                         ; col 199
            DB 26,0FFh,9,03h,2,20h,27,03h,0                             ; col 200
            DB 26,0FFh,6,03h,1,20h,4,03h,1,20h,26,03h,0                 ; col 201
            DB 28,0FFh,3,03h,1,20h,32,03h,0                             ; col 202
            DB 28,0FFh,3,20h,33,03h,0                                   ; col 203
            DB 29,0FFh,5,20h,5,03h,2,20h,23,03h,0                       ; col 204
            DB 29,0FFh,4,20h,4,03h,2,20h,25,03h,0                       ; col 205
            DB 31,0FFh,6,20h,27,03h,0                                   ; col 206
            DB 31,0FFh,5,20h,28,03h,0                                   ; col 207
            DB 33,0FFh,6,20h,25,03h,0                                   ; col 208
            DB 38,0FFh,2,20h,24,03h,0                                   ; col 209
            DB 39,0FFh,25,03h,0                                         ; col 210
            DB 39,0FFh,25,03h,0                                         ; col 211
            DB 39,0FFh,2,03h,2,20h,21,03h,0                             ; col 212
            DB 39,0FFh,1,20h,24,03h,0                                   ; col 213
            DB 38,0FFh,2,20h,24,03h,0                                   ; col 214
            DB 36,0FFh,3,20h,25,03h,0                                   ; col 215
            DB 36,0FFh,4,03h,1,20h,23,03h,0                             ; col 216
            DB 36,0FFh,28,03h,0                                         ; col 217
            DB 37,0FFh,27,03h,0                                         ; col 218
            DB 37,0FFh,27,03h,0                                         ; col 219
            DB 35,0FFh,1,03h,1,20h,27,03h,0                             ; col 220
            DB 34,0FFh,1,03h,2,20h,27,03h,0                             ; col 221
            DB 33,0FFh,1,03h,2,20h,28,03h,0                             ; col 222
            DB 32,0FFh,1,03h,4,20h,27,03h,0                             ; col 223
            DB 32,0FFh,5,03h,2,20h,25,03h,0                             ; col 224
            DB 31,0FFh,1,00h,8,20h,24,03h,0                             ; col 225
            DB 31,0FFh,1,00h,3,20h,5,03h,1,20h,23,03h,0                 ; col 226
            DB 26,0FFh,7,03h,1,20h,7,03h,1,20h,22,03h,0                 ; col 227
            DB 25,0FFh,9,03h,3,20h,27,03h,0                             ; col 228
            DB 25,0FFh,5,03h,1,20h,6,03h,1,20h,26,03h,0                 ; col 229
            DB 21,0FFh,5,03h,6,20h,6,03h,1,20h,25,03h,0                 ; col 230
            DB 22,0FFh,5,03h,2,20h,35,03h,0                             ; col 231
            DB 11,0FFh,3,03h,11,20h,39,03h,0                            ; col 232
            DB 11,0FFh,8,03h,2,20h,43,03h,0                             ; col 233
            DB 13,0FFh,51,03h,0                                         ; col 234
            DB 13,0FFh,51,03h,0                                         ; col 235
            DB 12,0FFh,10,03h,3,20h,39,03h,0                            ; col 236
            DB 10,0FFh,4,20h,11,03h,2,20h,6,03h,1,20h,30,03h,0          ; col 237
            DB 8,0FFh,8,20h,2,03h,1,20h,13,03h,2,20h,30,03h,0           ; col 238
            DB 4,0FFh,4,03h,1,20h,1,03h,1,20h,1,03h,8,20h,44,03h,0      ; col 239
            DB 2,0FFh,2,03h,2,20h,8,03h,2,20h,14,03h,1,20h,33,03h,0     ; col 240
            DB 31,03h,1,20h,32,03h,0                                    ; col 241
            DB 27,03h,1,20h,4,03h,1,20h,31,03h,0                        ; col 242
            DB 3,20h,2,03h,1,20h,16,03h,2,20h,2,03h,1,20h,5,03h,2,20h,30,03h,0 ; col 243
            DB 2,0FFh,5,20h,13,03h,7,20h,5,03h,3,20h,29,03h,0           ; col 244
            DB 1,0FFh,5,20h,4,03h,2,20h,3,03h,2,20h,2,03h,7,20h,6,03h,4,20h,28,03h,0 ; col 245
            DB 1,0FFh,4,20h,4,03h,4,20h,1,03h,11,20h,8,03h,2,20h,29,03h,0 ; col 246
            DB 2,0FFh,2,20h,4,03h,17,20h,2,03h,1,20h,6,03h,2,20h,28,03h,0 ; col 247
            DB 11,0FFh,16,20h,37,03h,0                                  ; col 248
            DB 11,0FFh,15,20h,38,03h,0                                  ; col 249
            DB 14,0FFh,11,20h,39,03h,0                                  ; col 250
            DB 21,0FFh,3,20h,40,03h,0                                   ; col 251
            DB 22,0FFh,3,20h,2,03h,1,20h,36,03h,0                       ; col 252
            DB 23,0FFh,2,20h,1,03h,1,20h,37,03h,0                       ; col 253
            DB 23,0FFh,3,20h,38,03h,0                                   ; col 254
            DB 24,0FFh,40,03h,0                                         ; col 255

; Tabela de colunas: a entrada j aponta para a coluna (j mod 256).
; Tem 256 + 320 entradas: desenhar uma tela inteira a partir de
; qualquer scroll (0 .. 255) nunca precisa testar a emenda.
back_cols   DW back_rle + 0, back_rle + 5, back_rle + 16, back_rle + 27, back_rle + 38, back_rle + 49
            DW back_rle + 56, back_rle + 63, back_rle + 70, back_rle + 77, back_rle + 84, back_rle + 91
            DW back_rle + 98, back_rle + 109, back_rle + 120, back_rle + 135, back_rle + 146, back_rle + 153
            DW back_rle + 158, back_rle + 177, back_rle + 188, back_rle + 193, back_rle + 202, back_rle + 211
            DW back_rle + 216, back_rle + 233, back_rle + 242, back_rle + 255, back_rle + 266, back_rle + 277
            DW back_rle + 290, back_rle + 301, back_rle + 312, back_rle + 317, back_rle + 326, back_rle + 335
            DW back_rle + 344, back_rle + 353, back_rle + 362, back_rle + 371, back_rle + 384, back_rle + 393
            DW back_rle + 398, back_rle + 403, back_rle + 408, back_rle + 421, back_rle + 438, back_rle + 455
            DW back_rle + 468, back_rle + 485, back_rle + 492, back_rle + 499, back_rle + 514, back_rle + 525
            DW back_rle + 536, back_rle + 543, back_rle + 550, back_rle + 557, back_rle + 564, back_rle + 571
            DW back_rle + 578, back_rle + 585, back_rle + 594, back_rle + 603, back_rle + 612, back_rle + 617
            DW back_rle + 622, back_rle + 627, back_rle + 636, back_rle + 645, back_rle + 662, back_rle + 679
            DW back_rle + 688, back_rle + 701, back_rle + 716, back_rle + 727, back_rle + 738, back_rle + 749
            DW back_rle + 756, back_rle + 763, back_rle + 768, back_rle + 775, back_rle + 782, back_rle + 789
            DW back_rle + 796, back_rle + 807, back_rle + 814, back_rle + 819, back_rle + 824, back_rle + 833
            DW back_rle + 842, back_rle + 851, back_rle + 862, back_rle + 873, back_rle + 884, back_rle + 895
            DW back_rle + 906, back_rle + 925, back_rle + 946, back_rle + 959, back_rle + 964, back_rle + 969
            DW back_rle + 982, back_rle + 993, back_rle + 1004, back_rle + 1011, back_rle + 1022, back_rle + 1033
            DW back_rle + 1044, back_rle + 1055, back_rle + 1070, back_rle + 1081, back_rle + 1088, back_rle + 1093
            DW back_rle + 1098, back_rle + 1103, back_rle + 1108, back_rle + 1113, back_rle + 1118, back_rle + 1123
            DW back_rle + 1128, back_rle + 1135, back_rle + 1146, back_rle + 1157, back_rle + 1178, back_rle + 1189
            DW back_rle + 1196, back_rle + 1205, back_rle + 1226, back_rle + 1237, back_rle + 1248, back_rle + 1257
            DW back_rle + 1270, back_rle + 1283, back_rle + 1292, back_rle + 1305, back_rle + 1318, back_rle + 1327
            DW back_rle + 1336, back_rle + 1345, back_rle + 1354, back_rle + 1359, back_rle + 1364, back_rle + 1369
            DW back_rle + 1374, back_rle + 1379, back_rle + 1386, back_rle + 1393, back_rle + 1400, back_rle + 1407
            DW back_rle + 1414, back_rle + 1425, back_rle + 1438, back_rle + 1443, back_rle + 1448, back_rle + 1457
            DW back_rle + 1470, back_rle + 1487, back_rle + 1504, back_rle + 1521, back_rle + 1532, back_rle + 1539
            DW back_rle + 1550, back_rle + 1561, back_rle + 1568, back_rle + 1577, back_rle + 1586, back_rle + 1593
            DW back_rle + 1600, back_rle + 1609, back_rle + 1618, back_rle + 1627, back_rle + 1640, back_rle + 1657
            DW back_rle + 1686, back_rle + 1703, back_rle + 1724, back_rle + 1741, back_rle + 1750, back_rle + 1759
            DW back_rle + 1764, back_rle + 1777, back_rle + 1790, back_rle + 1801, back_rle + 1810, back_rle + 1817
            DW back_rle + 1824, back_rle + 1829, back_rle + 1834, back_rle + 1839, back_rle + 1848, back_rle + 1857
            DW back_rle + 1866, back_rle + 1873, back_rle + 1880, back_rle + 1887, back_rle + 1894, back_rle + 1905
            DW back_rle + 1920, back_rle + 1925, back_rle + 1930, back_rle + 1939, back_rle + 1952, back_rle + 1961
            DW back_rle + 1968, back_rle + 1979, back_rle + 1990, back_rle + 1997, back_rle + 2004, back_rle + 2011
            DW back_rle + 2018, back_rle + 2023, back_rle + 2028, back_rle + 2037, back_rle + 2044, back_rle + 2051
            DW back_rle + 2058, back_rle + 2067, back_rle + 2072, back_rle + 2077, back_rle + 2082, back_rle + 2091
            DW back_rle + 2100, back_rle + 2109, back_rle + 2118, back_rle + 2127, back_rle + 2136, back_rle + 2149
            DW back_rle + 2162, back_rle + 2171, back_rle + 2184, back_rle + 2197, back_rle + 2206, back_rle + 2215
            DW back_rle + 2224, back_rle + 2229, back_rle + 2234, back_rle + 2243, back_rle + 2258, back_rle + 2273
            DW back_rle + 2290, back_rle + 2307, back_rle + 2314, back_rle + 2325, back_rle + 2346, back_rle + 2361
            DW back_rle + 2384, back_rle + 2403, back_rle + 2422, back_rle + 2429, back_rle + 2436, back_rle + 2443
            DW back_rle + 2450, back_rle + 2461, back_rle + 2472, back_rle + 2479, back_rle + 0, back_rle + 5
            DW back_rle + 16, back_rle + 27, back_rle + 38, back_rle + 49, back_rle + 56, back_rle + 63
            DW back_rle + 70, back_rle + 77, back_rle + 84, back_rle + 91, back_rle + 98, back_rle + 109
            DW back_rle + 120, back_rle + 135, back_rle + 146, back_rle + 153, back_rle + 158, back_rle + 177
            DW back_rle + 188, back_rle + 193, back_rle + 202, back_rle + 211, back_rle + 216, back_rle + 233
            DW back_rle + 242, back_rle + 255, back_rle + 266, back_rle + 277, back_rle + 290, back_rle + 301
            DW back_rle + 312, back_rle + 317, back_rle + 326, back_rle + 335, back_rle + 344, back_rle + 353
            DW back_rle + 362, back_rle + 371, back_rle + 384, back_rle + 393, back_rle + 398, back_rle + 403
            DW back_rle + 408, back_rle + 421, back_rle + 438, back_rle + 455, back_rle + 468, back_rle + 485
            DW back_rle + 492, back_rle + 499, back_rle + 514, back_rle + 525, back_rle + 536, back_rle + 543
            DW back_rle + 550, back_rle + 557, back_rle + 564, back_rle + 571, back_rle + 578, back_rle + 585
            DW back_rle + 594, back_rle + 603, back_rle + 612, back_rle + 617, back_rle + 622, back_rle + 627
            DW back_rle + 636, back_rle + 645, back_rle + 662, back_rle + 679, back_rle + 688, back_rle + 701
            DW back_rle + 716, back_rle + 727, back_rle + 738, back_rle + 749, back_rle + 756, back_rle + 763
            DW back_rle + 768, back_rle + 775, back_rle + 782, back_rle + 789, back_rle + 796, back_rle + 807
            DW back_rle + 814, back_rle + 819, back_rle + 824, back_rle + 833, back_rle + 842, back_rle + 851
            DW back_rle + 862, back_rle + 873, back_rle + 884, back_rle + 895, back_rle + 906, back_rle + 925
            DW back_rle + 946, back_rle + 959, back_rle + 964, back_rle + 969, back_rle + 982, back_rle + 993
            DW back_rle + 1004, back_rle + 1011, back_rle + 1022, back_rle + 1033, back_rle + 1044, back_rle + 1055
            DW back_rle + 1070, back_rle + 1081, back_rle + 1088, back_rle + 1093, back_rle + 1098, back_rle + 1103
            DW back_rle + 1108, back_rle + 1113, back_rle + 1118, back_rle + 1123, back_rle + 1128, back_rle + 1135
            DW back_rle + 1146, back_rle + 1157, back_rle + 1178, back_rle + 1189, back_rle + 1196, back_rle + 1205
            DW back_rle + 1226, back_rle + 1237, back_rle + 1248, back_rle + 1257, back_rle + 1270, back_rle + 1283
            DW back_rle + 1292, back_rle + 1305, back_rle + 1318, back_rle + 1327, back_rle + 1336, back_rle + 1345
            DW back_rle + 1354, back_rle + 1359, back_rle + 1364, back_rle + 1369, back_rle + 1374, back_rle + 1379
            DW back_rle + 1386, back_rle + 1393, back_rle + 1400, back_rle + 1407, back_rle + 1414, back_rle + 1425
            DW back_rle + 1438, back_rle + 1443, back_rle + 1448, back_rle + 1457, back_rle + 1470, back_rle + 1487
            DW back_rle + 1504, back_rle + 1521, back_rle + 1532, back_rle + 1539, back_rle + 1550, back_rle + 1561
            DW back_rle + 1568, back_rle + 1577, back_rle + 1586, back_rle + 1593, back_rle + 1600, back_rle + 1609
            DW back_rle + 1618, back_rle + 1627, back_rle + 1640, back_rle + 1657, back_rle + 1686, back_rle + 1703
            DW back_rle + 1724, back_rle + 1741, back_rle + 1750, back_rle + 1759, back_rle + 1764, back_rle + 1777
            DW back_rle + 1790, back_rle + 1801, back_rle + 1810, back_rle + 1817, back_rle + 1824, back_rle + 1829
            DW back_rle + 1834, back_rle + 1839, back_rle + 1848, back_rle + 1857, back_rle + 1866, back_rle + 1873
            DW back_rle + 1880, back_rle + 1887, back_rle + 1894, back_rle + 1905, back_rle + 1920, back_rle + 1925
            DW back_rle + 1930, back_rle + 1939, back_rle + 1952, back_rle + 1961, back_rle + 1968, back_rle + 1979
            DW back_rle + 1990, back_rle + 1997, back_rle + 2004, back_rle + 2011, back_rle + 2018, back_rle + 2023
            DW back_rle + 2028, back_rle + 2037, back_rle + 2044, back_rle + 2051, back_rle + 2058, back_rle + 2067
            DW back_rle + 2072, back_rle + 2077, back_rle + 2082, back_rle + 2091, back_rle + 2100, back_rle + 2109
            DW back_rle + 2118, back_rle + 2127, back_rle + 2136, back_rle + 2149, back_rle + 2162, back_rle + 2171
            DW back_rle + 2184, back_rle + 2197, back_rle + 2206, back_rle + 2215, back_rle + 2224, back_rle + 2229
            DW back_rle + 2234, back_rle + 2243, back_rle + 2258, back_rle + 2273, back_rle + 2290, back_rle + 2307
            DW back_rle + 2314, back_rle + 2325, back_rle + 2346, back_rle + 2361, back_rle + 2384, back_rle + 2403
            DW back_rle + 2422, back_rle + 2429, back_rle + 2436, back_rle + 2443, back_rle + 2450, back_rle + 2461
            DW back_rle + 2472, back_rle + 2479, back_rle + 0, back_rle + 5, back_rle + 16, back_rle + 27
            DW back_rle + 38, back_rle + 49, back_rle + 56, back_rle + 63, back_rle + 70, back_rle + 77
            DW back_rle + 84, back_rle + 91, back_rle + 98, back_rle + 109, back_rle + 120, back_rle + 135
            DW back_rle + 146, back_rle + 153, back_rle + 158, back_rle + 177, back_rle + 188, back_rle + 193
            DW back_rle + 202, back_rle + 211, back_rle + 216, back_rle + 233, back_rle + 242, back_rle + 255
            DW back_rle + 266, back_rle + 277, back_rle + 290, back_rle + 301, back_rle + 312, back_rle + 317
            DW back_rle + 326, back_rle + 335, back_rle + 344, back_rle + 353, back_rle + 362, back_rle + 371
            DW back_rle + 384, back_rle + 393, back_rle + 398, back_rle + 403, back_rle + 408, back_rle + 421
            DW back_rle + 438, back_rle + 455, back_rle + 468, back_rle + 485, back_rle + 492, back_rle + 499
            DW back_rle + 514, back_rle + 525, back_rle + 536, back_rle + 543, back_rle + 550, back_rle + 557
            DW back_rle + 564, back_rle + 571, back_rle + 578, back_rle + 585, back_rle + 594, back_rle + 603

; Montanha da frente (montanha frente.png): 256x64, RLE por coluna (de cima para baixo).
; Cada coluna: pares (quantidade, cor) terminados por 0. 0FFh = transparente.
front_rle   DB 24,0FFh,40,31h,0                                         ; col 0
            DB 24,0FFh,40,31h,0                                         ; col 1
            DB 24,0FFh,40,31h,0                                         ; col 2
            DB 24,0FFh,40,31h,0                                         ; col 3
            DB 23,0FFh,41,31h,0                                         ; col 4
            DB 23,0FFh,41,31h,0                                         ; col 5
            DB 23,0FFh,41,31h,0                                         ; col 6
            DB 23,0FFh,3,31h,1,02h,37,31h,0                             ; col 7
            DB 22,0FFh,4,31h,1,02h,37,31h,0                             ; col 8
            DB 22,0FFh,4,31h,1,02h,37,31h,0                             ; col 9
            DB 22,0FFh,42,31h,0                                         ; col 10
            DB 22,0FFh,42,31h,0                                         ; col 11
            DB 22,0FFh,42,31h,0                                         ; col 12
            DB 22,0FFh,42,31h,0                                         ; col 13
            DB 22,0FFh,2,31h,1,02h,39,31h,0                             ; col 14
            DB 22,0FFh,2,31h,1,02h,39,31h,0                             ; col 15
            DB 21,0FFh,3,31h,1,02h,39,31h,0                             ; col 16
            DB 21,0FFh,3,31h,1,02h,39,31h,0                             ; col 17
            DB 21,0FFh,2,31h,2,02h,39,31h,0                             ; col 18
            DB 21,0FFh,2,31h,1,02h,40,31h,0                             ; col 19
            DB 20,0FFh,3,31h,1,02h,40,31h,0                             ; col 20
            DB 20,0FFh,2,31h,2,02h,40,31h,0                             ; col 21
            DB 19,0FFh,3,31h,2,02h,40,31h,0                             ; col 22
            DB 19,0FFh,3,31h,1,02h,41,31h,0                             ; col 23
            DB 19,0FFh,2,31h,1,02h,42,31h,0                             ; col 24
            DB 19,0FFh,2,31h,1,02h,42,31h,0                             ; col 25
            DB 18,0FFh,3,31h,1,02h,42,31h,0                             ; col 26
            DB 18,0FFh,46,31h,0                                         ; col 27
            DB 18,0FFh,46,31h,0                                         ; col 28
            DB 17,0FFh,3,31h,1,02h,43,31h,0                             ; col 29
            DB 17,0FFh,3,31h,1,02h,43,31h,0                             ; col 30
            DB 17,0FFh,3,31h,1,02h,43,31h,0                             ; col 31
            DB 16,0FFh,48,31h,0                                         ; col 32
            DB 16,0FFh,48,31h,0                                         ; col 33
            DB 16,0FFh,48,31h,0                                         ; col 34
            DB 15,0FFh,49,31h,0                                         ; col 35
            DB 15,0FFh,49,31h,0                                         ; col 36
            DB 14,0FFh,50,31h,0                                         ; col 37
            DB 14,0FFh,50,31h,0                                         ; col 38
            DB 14,0FFh,50,31h,0                                         ; col 39
            DB 13,0FFh,51,31h,0                                         ; col 40
            DB 13,0FFh,12,31h,1,02h,38,31h,0                            ; col 41
            DB 12,0FFh,13,31h,1,02h,38,31h,0                            ; col 42
            DB 12,0FFh,13,31h,1,02h,38,31h,0                            ; col 43
            DB 11,0FFh,14,31h,1,02h,38,31h,0                            ; col 44
            DB 11,0FFh,13,31h,1,02h,39,31h,0                            ; col 45
            DB 11,0FFh,13,31h,1,02h,39,31h,0                            ; col 46
            DB 10,0FFh,54,31h,0                                         ; col 47
            DB 9,0FFh,55,31h,0                                          ; col 48
            DB 9,0FFh,55,31h,0                                          ; col 49
            DB 8,0FFh,56,31h,0                                          ; col 50
            DB 8,0FFh,56,31h,0                                          ; col 51
            DB 7,0FFh,57,31h,0                                          ; col 52
            DB 7,0FFh,57,31h,0                                          ; col 53
            DB 6,0FFh,8,31h,1,02h,49,31h,0                              ; col 54
            DB 6,0FFh,8,31h,1,02h,49,31h,0                              ; col 55
            DB 5,0FFh,7,31h,1,02h,51,31h,0                              ; col 56
            DB 4,0FFh,8,31h,1,02h,51,31h,0                              ; col 57
            DB 4,0FFh,7,31h,1,02h,52,31h,0                              ; col 58
            DB 3,0FFh,8,31h,1,02h,52,31h,0                              ; col 59
            DB 2,0FFh,1,02h,6,31h,1,02h,13,31h,1,02h,40,31h,0           ; col 60
            DB 2,0FFh,1,02h,6,31h,1,02h,13,31h,1,02h,40,31h,0           ; col 61
            DB 3,0FFh,1,02h,4,31h,1,02h,13,31h,1,02h,41,31h,0           ; col 62
            DB 4,0FFh,4,31h,1,02h,13,31h,1,02h,41,31h,0                 ; col 63
            DB 4,0FFh,1,02h,2,31h,1,02h,13,31h,2,02h,41,31h,0           ; col 64
            DB 4,0FFh,1,02h,2,31h,1,02h,13,31h,2,02h,41,31h,0           ; col 65
            DB 5,0FFh,3,02h,12,31h,2,02h,42,31h,0                       ; col 66
            DB 5,0FFh,3,02h,12,31h,2,02h,42,31h,0                       ; col 67
            DB 4,0FFh,3,02h,13,31h,2,02h,42,31h,0                       ; col 68
            DB 4,0FFh,3,02h,12,31h,3,02h,42,31h,0                       ; col 69
            DB 3,0FFh,2,02h,13,31h,4,02h,42,31h,0                       ; col 70
            DB 3,0FFh,2,02h,5,31h,1,02h,7,31h,5,02h,41,31h,0            ; col 71
            DB 2,0FFh,2,02h,6,31h,1,02h,6,31h,6,02h,41,31h,0            ; col 72
            DB 2,0FFh,2,02h,6,31h,1,02h,6,31h,5,02h,42,31h,0            ; col 73
            DB 2,0FFh,2,02h,6,31h,1,02h,5,31h,6,02h,42,31h,0            ; col 74
            DB 3,0FFh,1,02h,6,31h,2,02h,3,31h,8,02h,41,31h,0            ; col 75
            DB 4,0FFh,1,02h,2,31h,5,02h,2,31h,9,02h,41,31h,0            ; col 76
            DB 4,0FFh,8,02h,2,31h,8,02h,42,31h,0                        ; col 77
            DB 6,0FFh,16,02h,42,31h,0                                   ; col 78
            DB 6,0FFh,15,02h,43,31h,0                                   ; col 79
            DB 8,0FFh,13,02h,43,31h,0                                   ; col 80
            DB 8,0FFh,12,02h,5,31h,1,02h,38,31h,0                       ; col 81
            DB 9,0FFh,11,02h,5,31h,1,02h,38,31h,0                       ; col 82
            DB 9,0FFh,10,02h,5,31h,1,02h,39,31h,0                       ; col 83
            DB 11,0FFh,8,02h,5,31h,1,02h,39,31h,0                       ; col 84
            DB 11,0FFh,7,02h,5,31h,2,02h,39,31h,0                       ; col 85
            DB 12,0FFh,6,02h,5,31h,2,02h,39,31h,0                       ; col 86
            DB 12,0FFh,6,02h,4,31h,3,02h,39,31h,0                       ; col 87
            DB 13,0FFh,6,02h,2,31h,3,02h,40,31h,0                       ; col 88
            DB 14,0FFh,5,02h,1,31h,4,02h,40,31h,0                       ; col 89
            DB 14,0FFh,9,02h,41,31h,0                                   ; col 90
            DB 15,0FFh,8,02h,41,31h,0                                   ; col 91
            DB 15,0FFh,9,02h,40,31h,0                                   ; col 92
            DB 16,0FFh,7,02h,41,31h,0                                   ; col 93
            DB 16,0FFh,7,02h,8,31h,1,02h,32,31h,0                       ; col 94
            DB 16,0FFh,8,02h,7,31h,1,02h,32,31h,0                       ; col 95
            DB 17,0FFh,8,02h,5,31h,1,02h,33,31h,0                       ; col 96
            DB 18,0FFh,6,02h,6,31h,1,02h,33,31h,0                       ; col 97
            DB 18,0FFh,6,02h,6,31h,1,02h,33,31h,0                       ; col 98
            DB 18,0FFh,5,02h,6,31h,1,02h,34,31h,0                       ; col 99
            DB 19,0FFh,4,02h,6,31h,1,02h,34,31h,0                       ; col 100
            DB 19,0FFh,3,02h,6,31h,2,02h,34,31h,0                       ; col 101
            DB 20,0FFh,2,02h,2,31h,1,02h,3,31h,2,02h,34,31h,0           ; col 102
            DB 20,0FFh,2,02h,1,31h,2,02h,1,31h,3,02h,35,31h,0           ; col 103
            DB 21,0FFh,4,02h,1,31h,2,02h,4,31h,1,02h,2,31h,1,02h,28,31h,0 ; col 104
            DB 21,0FFh,7,02h,4,31h,2,02h,1,31h,1,02h,28,31h,0           ; col 105
            DB 22,0FFh,5,02h,4,31h,4,02h,29,31h,0                       ; col 106
            DB 22,0FFh,5,02h,4,31h,4,02h,29,31h,0                       ; col 107
            DB 23,0FFh,4,02h,5,31h,2,02h,30,31h,0                       ; col 108
            DB 23,0FFh,3,02h,6,31h,1,02h,31,31h,0                       ; col 109
            DB 23,0FFh,2,02h,39,31h,0                                   ; col 110
            DB 24,0FFh,1,02h,9,31h,1,02h,29,31h,0                       ; col 111
            DB 24,0FFh,10,31h,1,02h,29,31h,0                            ; col 112
            DB 24,0FFh,10,31h,1,02h,29,31h,0                            ; col 113
            DB 23,0FFh,41,31h,0                                         ; col 114
            DB 23,0FFh,8,31h,1,02h,32,31h,0                             ; col 115
            DB 22,0FFh,9,31h,1,02h,32,31h,0                             ; col 116
            DB 22,0FFh,42,31h,0                                         ; col 117
            DB 21,0FFh,8,31h,1,02h,34,31h,0                             ; col 118
            DB 21,0FFh,8,31h,1,02h,34,31h,0                             ; col 119
            DB 19,0FFh,9,31h,1,02h,35,31h,0                             ; col 120
            DB 19,0FFh,9,31h,1,02h,35,31h,0                             ; col 121
            DB 18,0FFh,46,31h,0                                         ; col 122
            DB 16,0FFh,2,02h,21,31h,1,02h,24,31h,0                      ; col 123
            DB 16,0FFh,2,02h,21,31h,1,02h,24,31h,0                      ; col 124
            DB 16,0FFh,3,02h,19,31h,1,02h,25,31h,0                      ; col 125
            DB 17,0FFh,2,02h,6,31h,1,02h,12,31h,1,02h,25,31h,0          ; col 126
            DB 18,0FFh,2,02h,5,31h,1,02h,11,31h,2,02h,25,31h,0          ; col 127
            DB 18,0FFh,4,02h,2,31h,1,02h,12,31h,1,02h,26,31h,0          ; col 128
            DB 17,0FFh,4,02h,3,31h,1,02h,11,31h,2,02h,26,31h,0          ; col 129
            DB 17,0FFh,3,02h,8,31h,1,02h,6,31h,3,02h,26,31h,0           ; col 130
            DB 17,0FFh,2,02h,9,31h,1,02h,6,31h,2,02h,27,31h,0           ; col 131
            DB 16,0FFh,2,02h,9,31h,2,02h,5,31h,3,02h,27,31h,0           ; col 132
            DB 16,0FFh,3,02h,8,31h,2,02h,5,31h,3,02h,27,31h,0           ; col 133
            DB 17,0FFh,3,02h,5,31h,3,02h,5,31h,4,02h,27,31h,0           ; col 134
            DB 18,0FFh,2,02h,5,31h,3,02h,5,31h,5,02h,26,31h,0           ; col 135
            DB 19,0FFh,2,02h,3,31h,3,02h,5,31h,6,02h,26,31h,0           ; col 136
            DB 19,0FFh,3,02h,1,31h,3,02h,5,31h,6,02h,27,31h,0           ; col 137
            DB 20,0FFh,6,02h,4,31h,7,02h,27,31h,0                       ; col 138
            DB 21,0FFh,4,02h,4,31h,7,02h,28,31h,0                       ; col 139
            DB 22,0FFh,3,02h,3,31h,7,02h,29,31h,0                       ; col 140
            DB 22,0FFh,3,02h,3,31h,7,02h,29,31h,0                       ; col 141
            DB 23,0FFh,3,02h,1,31h,9,02h,28,31h,0                       ; col 142
            DB 23,0FFh,13,02h,28,31h,0                                  ; col 143
            DB 24,0FFh,11,02h,29,31h,0                                  ; col 144
            DB 25,0FFh,9,02h,30,31h,0                                   ; col 145
            DB 25,0FFh,9,02h,30,31h,0                                   ; col 146
            DB 26,0FFh,9,02h,29,31h,0                                   ; col 147
            DB 26,0FFh,9,02h,29,31h,0                                   ; col 148
            DB 27,0FFh,9,02h,28,31h,0                                   ; col 149
            DB 27,0FFh,8,02h,9,31h,1,02h,19,31h,0                       ; col 150
            DB 28,0FFh,7,02h,9,31h,1,02h,19,31h,0                       ; col 151
            DB 28,0FFh,8,02h,28,31h,0                                   ; col 152
            DB 29,0FFh,7,02h,6,31h,1,02h,21,31h,0                       ; col 153
            DB 29,0FFh,6,02h,7,31h,1,02h,21,31h,0                       ; col 154
            DB 30,0FFh,6,02h,5,31h,1,02h,22,31h,0                       ; col 155
            DB 31,0FFh,5,02h,5,31h,1,02h,22,31h,0                       ; col 156
            DB 32,0FFh,5,02h,4,31h,1,02h,22,31h,0                       ; col 157
            DB 32,0FFh,5,02h,3,31h,2,02h,22,31h,0                       ; col 158
            DB 33,0FFh,4,02h,3,31h,1,02h,23,31h,0                       ; col 159
            DB 33,0FFh,5,02h,1,31h,2,02h,23,31h,0                       ; col 160
            DB 33,0FFh,5,02h,1,31h,2,02h,23,31h,0                       ; col 161
            DB 34,0FFh,6,02h,24,31h,0                                   ; col 162
            DB 34,0FFh,6,02h,24,31h,0                                   ; col 163
            DB 34,0FFh,5,02h,25,31h,0                                   ; col 164
            DB 34,0FFh,5,02h,25,31h,0                                   ; col 165
            DB 34,0FFh,1,31h,3,02h,26,31h,0                             ; col 166
            DB 34,0FFh,1,31h,4,02h,25,31h,0                             ; col 167
            DB 33,0FFh,3,31h,3,02h,25,31h,0                             ; col 168
            DB 33,0FFh,3,31h,3,02h,25,31h,0                             ; col 169
            DB 33,0FFh,4,31h,3,02h,24,31h,0                             ; col 170
            DB 32,0FFh,5,31h,3,02h,24,31h,0                             ; col 171
            DB 32,0FFh,6,31h,1,02h,25,31h,0                             ; col 172
            DB 32,0FFh,6,31h,1,02h,25,31h,0                             ; col 173
            DB 32,0FFh,6,31h,1,02h,25,31h,0                             ; col 174
            DB 31,0FFh,7,31h,1,02h,25,31h,0                             ; col 175
            DB 31,0FFh,8,31h,1,02h,24,31h,0                             ; col 176
            DB 31,0FFh,8,31h,1,02h,24,31h,0                             ; col 177
            DB 29,0FFh,11,31h,1,02h,23,31h,0                            ; col 178
            DB 29,0FFh,11,31h,1,02h,23,31h,0                            ; col 179
            DB 28,0FFh,36,31h,0                                         ; col 180
            DB 27,0FFh,37,31h,0                                         ; col 181
            DB 27,0FFh,37,31h,0                                         ; col 182
            DB 26,0FFh,38,31h,0                                         ; col 183
            DB 24,0FFh,40,31h,0                                         ; col 184
            DB 24,0FFh,40,31h,0                                         ; col 185
            DB 22,0FFh,42,31h,0                                         ; col 186
            DB 22,0FFh,42,31h,0                                         ; col 187
            DB 23,0FFh,7,31h,1,02h,33,31h,0                             ; col 188
            DB 23,0FFh,7,31h,1,02h,33,31h,0                             ; col 189
            DB 24,0FFh,6,31h,2,02h,32,31h,0                             ; col 190
            DB 24,0FFh,1,02h,5,31h,2,02h,32,31h,0                       ; col 191
            DB 22,0FFh,3,02h,3,31h,3,02h,33,31h,0                       ; col 192
            DB 22,0FFh,2,02h,3,31h,4,02h,33,31h,0                       ; col 193
            DB 22,0FFh,3,02h,1,31h,4,02h,34,31h,0                       ; col 194
            DB 23,0FFh,6,02h,35,31h,0                                   ; col 195
            DB 24,0FFh,6,02h,34,31h,0                                   ; col 196
            DB 25,0FFh,4,02h,35,31h,0                                   ; col 197
            DB 25,0FFh,3,02h,4,31h,1,02h,31,31h,0                       ; col 198
            DB 26,0FFh,2,02h,4,31h,1,02h,31,31h,0                       ; col 199
            DB 26,0FFh,3,02h,2,31h,1,02h,32,31h,0                       ; col 200
            DB 27,0FFh,2,02h,2,31h,1,02h,32,31h,0                       ; col 201
            DB 28,0FFh,1,02h,1,31h,1,02h,33,31h,0                       ; col 202
            DB 28,0FFh,3,02h,33,31h,0                                   ; col 203
            DB 29,0FFh,2,02h,33,31h,0                                   ; col 204
            DB 29,0FFh,2,02h,33,31h,0                                   ; col 205
            DB 30,0FFh,34,31h,0                                         ; col 206
            DB 30,0FFh,34,31h,0                                         ; col 207
            DB 30,0FFh,34,31h,0                                         ; col 208
            DB 29,0FFh,35,31h,0                                         ; col 209
            DB 28,0FFh,36,31h,0                                         ; col 210
            DB 28,0FFh,36,31h,0                                         ; col 211
            DB 27,0FFh,2,31h,1,02h,34,31h,0                             ; col 212
            DB 26,0FFh,3,31h,1,02h,34,31h,0                             ; col 213
            DB 25,0FFh,3,31h,1,02h,35,31h,0                             ; col 214
            DB 25,0FFh,3,31h,1,02h,35,31h,0                             ; col 215
            DB 24,0FFh,40,31h,0                                         ; col 216
            DB 24,0FFh,40,31h,0                                         ; col 217
            DB 23,0FFh,41,31h,0                                         ; col 218
            DB 22,0FFh,42,31h,0                                         ; col 219
            DB 21,0FFh,43,31h,0                                         ; col 220
            DB 20,0FFh,3,31h,1,02h,40,31h,0                             ; col 221
            DB 19,0FFh,3,31h,2,02h,40,31h,0                             ; col 222
            DB 18,0FFh,4,31h,1,02h,41,31h,0                             ; col 223
            DB 17,0FFh,4,31h,1,02h,42,31h,0                             ; col 224
            DB 16,0FFh,4,31h,2,02h,42,31h,0                             ; col 225
            DB 15,0FFh,4,31h,2,02h,43,31h,0                             ; col 226
            DB 14,0FFh,4,31h,1,02h,45,31h,0                             ; col 227
            DB 12,0FFh,52,31h,0                                         ; col 228
            DB 11,0FFh,4,31h,2,02h,47,31h,0                             ; col 229
            DB 9,0FFh,5,31h,2,02h,48,31h,0                              ; col 230
            DB 9,0FFh,55,31h,0                                          ; col 231
            DB 10,0FFh,18,31h,1,02h,35,31h,0                            ; col 232
            DB 11,0FFh,17,31h,1,02h,35,31h,0                            ; col 233
            DB 11,0FFh,1,02h,10,31h,1,02h,4,31h,1,02h,36,31h,0          ; col 234
            DB 9,0FFh,3,02h,10,31h,1,02h,4,31h,1,02h,36,31h,0           ; col 235
            DB 8,0FFh,3,02h,6,31h,1,02h,9,31h,1,02h,36,31h,0            ; col 236
            DB 8,0FFh,2,02h,6,31h,1,02h,10,31h,1,02h,36,31h,0           ; col 237
            DB 9,0FFh,2,02h,5,31h,1,02h,47,31h,0                        ; col 238
            DB 9,0FFh,3,02h,3,31h,1,02h,48,31h,0                        ; col 239
            DB 10,0FFh,3,02h,1,31h,2,02h,5,31h,1,02h,4,31h,1,02h,37,31h,0 ; col 240
            DB 11,0FFh,5,02h,5,31h,1,02h,4,31h,1,02h,37,31h,0           ; col 241
            DB 13,0FFh,2,02h,5,31h,1,02h,4,31h,2,02h,37,31h,0           ; col 242
            DB 14,0FFh,3,02h,2,31h,2,02h,3,31h,3,02h,37,31h,0           ; col 243
            DB 14,0FFh,8,02h,1,31h,3,02h,38,31h,0                       ; col 244
            DB 16,0FFh,6,02h,1,31h,2,02h,39,31h,0                       ; col 245
            DB 17,0FFh,9,02h,38,31h,0                                   ; col 246
            DB 17,0FFh,8,02h,39,31h,0                                   ; col 247
            DB 19,0FFh,6,02h,39,31h,0                                   ; col 248
            DB 20,0FFh,5,02h,39,31h,0                                   ; col 249
            DB 21,0FFh,4,02h,39,31h,0                                   ; col 250
            DB 21,0FFh,4,02h,39,31h,0                                   ; col 251
            DB 22,0FFh,2,02h,40,31h,0                                   ; col 252
            DB 22,0FFh,2,02h,40,31h,0                                   ; col 253
            DB 23,0FFh,1,02h,40,31h,0                                   ; col 254
            DB 24,0FFh,40,31h,0                                         ; col 255

; Tabela de colunas: a entrada j aponta para a coluna (j mod 256).
; Tem 256 + 320 entradas: desenhar uma tela inteira a partir de
; qualquer scroll (0 .. 255) nunca precisa testar a emenda.
front_cols  DW front_rle + 0, front_rle + 5, front_rle + 10, front_rle + 15, front_rle + 20, front_rle + 25
            DW front_rle + 30, front_rle + 35, front_rle + 44, front_rle + 53, front_rle + 62, front_rle + 67
            DW front_rle + 72, front_rle + 77, front_rle + 82, front_rle + 91, front_rle + 100, front_rle + 109
            DW front_rle + 118, front_rle + 127, front_rle + 136, front_rle + 145, front_rle + 154, front_rle + 163
            DW front_rle + 172, front_rle + 181, front_rle + 190, front_rle + 199, front_rle + 204, front_rle + 209
            DW front_rle + 218, front_rle + 227, front_rle + 236, front_rle + 241, front_rle + 246, front_rle + 251
            DW front_rle + 256, front_rle + 261, front_rle + 266, front_rle + 271, front_rle + 276, front_rle + 281
            DW front_rle + 290, front_rle + 299, front_rle + 308, front_rle + 317, front_rle + 326, front_rle + 335
            DW front_rle + 340, front_rle + 345, front_rle + 350, front_rle + 355, front_rle + 360, front_rle + 365
            DW front_rle + 370, front_rle + 379, front_rle + 388, front_rle + 397, front_rle + 406, front_rle + 415
            DW front_rle + 424, front_rle + 439, front_rle + 454, front_rle + 469, front_rle + 482, front_rle + 497
            DW front_rle + 512, front_rle + 523, front_rle + 534, front_rle + 545, front_rle + 556, front_rle + 567
            DW front_rle + 582, front_rle + 597, front_rle + 612, front_rle + 627, front_rle + 642, front_rle + 657
            DW front_rle + 668, front_rle + 675, front_rle + 682, front_rle + 689, front_rle + 700, front_rle + 711
            DW front_rle + 722, front_rle + 733, front_rle + 744, front_rle + 755, front_rle + 766, front_rle + 777
            DW front_rle + 788, front_rle + 795, front_rle + 802, front_rle + 809, front_rle + 816, front_rle + 827
            DW front_rle + 838, front_rle + 849, front_rle + 860, front_rle + 871, front_rle + 882, front_rle + 893
            DW front_rle + 904, front_rle + 919, front_rle + 934, front_rle + 953, front_rle + 968, front_rle + 979
            DW front_rle + 990, front_rle + 1001, front_rle + 1012, front_rle + 1019, front_rle + 1030, front_rle + 1039
            DW front_rle + 1048, front_rle + 1053, front_rle + 1062, front_rle + 1071, front_rle + 1076, front_rle + 1085
            DW front_rle + 1094, front_rle + 1103, front_rle + 1112, front_rle + 1117, front_rle + 1128, front_rle + 1139
            DW front_rle + 1150, front_rle + 1165, front_rle + 1180, front_rle + 1195, front_rle + 1210, front_rle + 1225
            DW front_rle + 1240, front_rle + 1255, front_rle + 1270, front_rle + 1285, front_rle + 1300, front_rle + 1315
            DW front_rle + 1330, front_rle + 1341, front_rle + 1352, front_rle + 1363, front_rle + 1374, front_rle + 1385
            DW front_rle + 1392, front_rle + 1399, front_rle + 1406, front_rle + 1413, front_rle + 1420, front_rle + 1427
            DW front_rle + 1434, front_rle + 1445, front_rle + 1456, front_rle + 1463, front_rle + 1474, front_rle + 1485
            DW front_rle + 1496, front_rle + 1507, front_rle + 1518, front_rle + 1529, front_rle + 1540, front_rle + 1551
            DW front_rle + 1562, front_rle + 1569, front_rle + 1576, front_rle + 1583, front_rle + 1590, front_rle + 1599
            DW front_rle + 1608, front_rle + 1617, front_rle + 1626, front_rle + 1635, front_rle + 1644, front_rle + 1653
            DW front_rle + 1662, front_rle + 1671, front_rle + 1680, front_rle + 1689, front_rle + 1698, front_rle + 1707
            DW front_rle + 1716, front_rle + 1721, front_rle + 1726, front_rle + 1731, front_rle + 1736, front_rle + 1741
            DW front_rle + 1746, front_rle + 1751, front_rle + 1756, front_rle + 1765, front_rle + 1774, front_rle + 1783
            DW front_rle + 1794, front_rle + 1805, front_rle + 1816, front_rle + 1827, front_rle + 1834, front_rle + 1841
            DW front_rle + 1848, front_rle + 1859, front_rle + 1870, front_rle + 1881, front_rle + 1892, front_rle + 1903
            DW front_rle + 1910, front_rle + 1917, front_rle + 1924, front_rle + 1929, front_rle + 1934, front_rle + 1939
            DW front_rle + 1944, front_rle + 1949, front_rle + 1954, front_rle + 1963, front_rle + 1972, front_rle + 1981
            DW front_rle + 1990, front_rle + 1995, front_rle + 2000, front_rle + 2005, front_rle + 2010, front_rle + 2015
            DW front_rle + 2024, front_rle + 2033, front_rle + 2042, front_rle + 2051, front_rle + 2060, front_rle + 2069
            DW front_rle + 2078, front_rle + 2083, front_rle + 2092, front_rle + 2101, front_rle + 2106, front_rle + 2115
            DW front_rle + 2124, front_rle + 2139, front_rle + 2154, front_rle + 2169, front_rle + 2184, front_rle + 2195
            DW front_rle + 2206, front_rle + 2225, front_rle + 2240, front_rle + 2255, front_rle + 2270, front_rle + 2281
            DW front_rle + 2292, front_rle + 2299, front_rle + 2306, front_rle + 2313, front_rle + 2320, front_rle + 2327
            DW front_rle + 2334, front_rle + 2341, front_rle + 2348, front_rle + 2355, front_rle + 0, front_rle + 5
            DW front_rle + 10, front_rle + 15, front_rle + 20, front_rle + 25, front_rle + 30, front_rle + 35
            DW front_rle + 44, front_rle + 53, front_rle + 62, front_rle + 67, front_rle + 72, front_rle + 77
            DW front_rle + 82, front_rle + 91, front_rle + 100, front_rle + 109, front_rle + 118, front_rle + 127
            DW front_rle + 136, front_rle + 145, front_rle + 154, front_rle + 163, front_rle + 172, front_rle + 181
            DW front_rle + 190, front_rle + 199, front_rle + 204, front_rle + 209, front_rle + 218, front_rle + 227
            DW front_rle + 236, front_rle + 241, front_rle + 246, front_rle + 251, front_rle + 256, front_rle + 261
            DW front_rle + 266, front_rle + 271, front_rle + 276, front_rle + 281, front_rle + 290, front_rle + 299
            DW front_rle + 308, front_rle + 317, front_rle + 326, front_rle + 335, front_rle + 340, front_rle + 345
            DW front_rle + 350, front_rle + 355, front_rle + 360, front_rle + 365, front_rle + 370, front_rle + 379
            DW front_rle + 388, front_rle + 397, front_rle + 406, front_rle + 415, front_rle + 424, front_rle + 439
            DW front_rle + 454, front_rle + 469, front_rle + 482, front_rle + 497, front_rle + 512, front_rle + 523
            DW front_rle + 534, front_rle + 545, front_rle + 556, front_rle + 567, front_rle + 582, front_rle + 597
            DW front_rle + 612, front_rle + 627, front_rle + 642, front_rle + 657, front_rle + 668, front_rle + 675
            DW front_rle + 682, front_rle + 689, front_rle + 700, front_rle + 711, front_rle + 722, front_rle + 733
            DW front_rle + 744, front_rle + 755, front_rle + 766, front_rle + 777, front_rle + 788, front_rle + 795
            DW front_rle + 802, front_rle + 809, front_rle + 816, front_rle + 827, front_rle + 838, front_rle + 849
            DW front_rle + 860, front_rle + 871, front_rle + 882, front_rle + 893, front_rle + 904, front_rle + 919
            DW front_rle + 934, front_rle + 953, front_rle + 968, front_rle + 979, front_rle + 990, front_rle + 1001
            DW front_rle + 1012, front_rle + 1019, front_rle + 1030, front_rle + 1039, front_rle + 1048, front_rle + 1053
            DW front_rle + 1062, front_rle + 1071, front_rle + 1076, front_rle + 1085, front_rle + 1094, front_rle + 1103
            DW front_rle + 1112, front_rle + 1117, front_rle + 1128, front_rle + 1139, front_rle + 1150, front_rle + 1165
            DW front_rle + 1180, front_rle + 1195, front_rle + 1210, front_rle + 1225, front_rle + 1240, front_rle + 1255
            DW front_rle + 1270, front_rle + 1285, front_rle + 1300, front_rle + 1315, front_rle + 1330, front_rle + 1341
            DW front_rle + 1352, front_rle + 1363, front_rle + 1374, front_rle + 1385, front_rle + 1392, front_rle + 1399
            DW front_rle + 1406, front_rle + 1413, front_rle + 1420, front_rle + 1427, front_rle + 1434, front_rle + 1445
            DW front_rle + 1456, front_rle + 1463, front_rle + 1474, front_rle + 1485, front_rle + 1496, front_rle + 1507
            DW front_rle + 1518, front_rle + 1529, front_rle + 1540, front_rle + 1551, front_rle + 1562, front_rle + 1569
            DW front_rle + 1576, front_rle + 1583, front_rle + 1590, front_rle + 1599, front_rle + 1608, front_rle + 1617
            DW front_rle + 1626, front_rle + 1635, front_rle + 1644, front_rle + 1653, front_rle + 1662, front_rle + 1671
            DW front_rle + 1680, front_rle + 1689, front_rle + 1698, front_rle + 1707, front_rle + 1716, front_rle + 1721
            DW front_rle + 1726, front_rle + 1731, front_rle + 1736, front_rle + 1741, front_rle + 1746, front_rle + 1751
            DW front_rle + 1756, front_rle + 1765, front_rle + 1774, front_rle + 1783, front_rle + 1794, front_rle + 1805
            DW front_rle + 1816, front_rle + 1827, front_rle + 1834, front_rle + 1841, front_rle + 1848, front_rle + 1859
            DW front_rle + 1870, front_rle + 1881, front_rle + 1892, front_rle + 1903, front_rle + 1910, front_rle + 1917
            DW front_rle + 1924, front_rle + 1929, front_rle + 1934, front_rle + 1939, front_rle + 1944, front_rle + 1949
            DW front_rle + 1954, front_rle + 1963, front_rle + 1972, front_rle + 1981, front_rle + 1990, front_rle + 1995
            DW front_rle + 2000, front_rle + 2005, front_rle + 2010, front_rle + 2015, front_rle + 2024, front_rle + 2033
            DW front_rle + 2042, front_rle + 2051, front_rle + 2060, front_rle + 2069, front_rle + 2078, front_rle + 2083
            DW front_rle + 2092, front_rle + 2101, front_rle + 2106, front_rle + 2115, front_rle + 2124, front_rle + 2139
            DW front_rle + 2154, front_rle + 2169, front_rle + 2184, front_rle + 2195, front_rle + 2206, front_rle + 2225
            DW front_rle + 2240, front_rle + 2255, front_rle + 2270, front_rle + 2281, front_rle + 2292, front_rle + 2299
            DW front_rle + 2306, front_rle + 2313, front_rle + 2320, front_rle + 2327, front_rle + 2334, front_rle + 2341
            DW front_rle + 2348, front_rle + 2355, front_rle + 0, front_rle + 5, front_rle + 10, front_rle + 15
            DW front_rle + 20, front_rle + 25, front_rle + 30, front_rle + 35, front_rle + 44, front_rle + 53
            DW front_rle + 62, front_rle + 67, front_rle + 72, front_rle + 77, front_rle + 82, front_rle + 91
            DW front_rle + 100, front_rle + 109, front_rle + 118, front_rle + 127, front_rle + 136, front_rle + 145
            DW front_rle + 154, front_rle + 163, front_rle + 172, front_rle + 181, front_rle + 190, front_rle + 199
            DW front_rle + 204, front_rle + 209, front_rle + 218, front_rle + 227, front_rle + 236, front_rle + 241
            DW front_rle + 246, front_rle + 251, front_rle + 256, front_rle + 261, front_rle + 266, front_rle + 271
            DW front_rle + 276, front_rle + 281, front_rle + 290, front_rle + 299, front_rle + 308, front_rle + 317
            DW front_rle + 326, front_rle + 335, front_rle + 340, front_rle + 345, front_rle + 350, front_rle + 355
            DW front_rle + 360, front_rle + 365, front_rle + 370, front_rle + 379, front_rle + 388, front_rle + 397
            DW front_rle + 406, front_rle + 415, front_rle + 424, front_rle + 439, front_rle + 454, front_rle + 469

; Coracoes - 1 vida (10x11, vidas.png). 0FFh = transparente.
spr_heart1  DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh
            DB 0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0FFh,0FFh

; Coracoes - 2 vidas (14x11, vidas.png). 0FFh = transparente.
spr_heart2  DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh
            DB 0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0FFh,0FFh

; Coracoes - 3 vidas (18x11, vidas.png). 0FFh = transparente.
spr_heart3  DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh
            DB 0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0Ch,0Ch,0Ch,0Ch,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0FFh,0FFh
            DB 0FFh,0FFh,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0Ch,0Ch,0FFh,0FFh,0FFh,0FFh

; Relogio (7x8, relogio.png). 0FFh = transparente.
spr_clock   DB 0FFh,0FFh,0Eh,0Eh,0Eh,0FFh,0FFh
            DB 0FFh,0Eh,0Eh,00h,0Eh,0Eh,0FFh
            DB 0Eh,0Eh,0Eh,00h,0Eh,0Eh,0Eh
            DB 0Eh,0Eh,0Eh,00h,0Eh,0Eh,0Eh
            DB 0Eh,0Eh,0Eh,00h,00h,00h,0Eh
            DB 0Eh,0Eh,0Eh,0Eh,0Eh,0Eh,0Eh
            DB 0FFh,0Eh,0Eh,0Eh,0Eh,0Eh,0FFh
            DB 0FFh,0FFh,0Eh,0Eh,0Eh,0FFh,0FFh

; Bitmap e largura dos coracoes para cada numero de vidas (indice = vidas - 1)
heart_ptrs  DW OFFSET spr_heart1, OFFSET spr_heart2, OFFSET spr_heart3
heart_ws    DW HEART1_W, HEART2_W, HEART3_W

; Tabela inicial dos objetos do jogo (por enquanto so o jipe).
; Campos de cada registro: ATIVO, X, Y, LARG, ALT, VX, VY, SPRITE
game_tab0   DW ATIVO, JEEP_START_X, JEEP_GAME_Y
            DW JEEP_W, JEEP_H, PARADO, PARADO, OFFSET spr_jeep
GAME_TAB_BYTES  EQU $ - game_tab0
GAME_OBJS       EQU GAME_TAB_BYTES / OBJ_TAM

game_tab    DB GAME_TAB_BYTES DUP (?)           ; estado atual dos objetos

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
    push bx
    mov  bx, MENU_GROUND_Y
    call DRAW_GROUND
    pop  bx
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
    mov  [menu_sel], OPT_PLAY           ; volta para a primeira opcao
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
; GAME_RUN
; Funcao : laco principal do jogo. Por enquanto so inicializa a partida,
;          desenha a tela de jogo e espera ESC para voltar ao menu
;          (le teclado sem esperar -> [atualiza] -> [desenha] -> pausa)
; Entrada: nenhuma
; Saida  : nenhuma
;------------------------------------------------------------------------------
GAME_RUN PROC
    PUSH_ALL
    call GAME_INIT
    call DRAW_GAME_SCREEN
    call FLUSH_KEYS
gr_frame:
    call WAIT_FRAME
    call GET_KEY_NB             ; AX = tecla ou 0
    or   ax, ax
    jz   gr_frame
    cmp  ah, KEY_ESC
    jne  gr_frame               ; demais teclas: ainda sem acao
    POP_ALL
    ret
GAME_RUN ENDP

;------------------------------------------------------------------------------
; GAME_INIT
; Funcao : coloca a partida no estado inicial (score, vidas, tempo, scroll
;          do terreno e tabela de objetos)
; Entrada: nenhuma
; Saida  : variaveis da partida e game_tab inicializadas
;------------------------------------------------------------------------------
GAME_INIT PROC
    push cx
    push si
    push di
    mov  [score], SCORE_START
    mov  [lives], LIVES_START
    mov  [time_left], GAME_TIME
    mov  [back_scroll], SCROLL_START
    mov  [front_scroll], SCROLL_START
    mov  si, OFFSET game_tab0
    mov  di, OFFSET game_tab
    mov  cx, GAME_TAB_BYTES
    call COPY_BYTES
    pop  di
    pop  si
    pop  cx
    ret
GAME_INIT ENDP

;------------------------------------------------------------------------------
; DRAW_GAME_SCREEN
; Funcao : desenha a tela de jogo completa, na ordem
;          terreno -> objetos -> barra de status
; Entrada: estado da partida e game_tab
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_GAME_SCREEN PROC
    push cx
    push di
    call CLEAR_SCREEN
    call DRAW_TERRAIN
    mov  di, OFFSET game_tab
    mov  cx, GAME_OBJS
    call DRAW_OBJECTS
    call DRAW_STATUS
    pop  di
    pop  cx
    ret
DRAW_GAME_SCREEN ENDP

;------------------------------------------------------------------------------
; DRAW_TERRAIN
; Funcao : desenha a montanha do fundo, a montanha da frente por cima dela
;          e a pista
; Entrada: [back_scroll], [front_scroll] = coluna de cada bitmap em x = 0
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_TERRAIN PROC
    PUSH_ALL
    mov  bx, OFFSET back_cols
    mov  ax, [back_scroll]
    mov  dx, MOUNT_BACK_Y
    call DRAW_RLE_LAYER
    mov  bx, OFFSET front_cols
    mov  ax, [front_scroll]
    mov  dx, MOUNT_FRONT_Y
    call DRAW_RLE_LAYER
    mov  bx, TRACK_Y
    call DRAW_GROUND            ; pista amarela
    POP_ALL
    ret
DRAW_TERRAIN ENDP

;------------------------------------------------------------------------------
; DRAW_STATUS
; Funcao : desenha a barra de status inteira (score, vidas e tempo)
; Entrada: [score], [lives], [time_left]
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_STATUS PROC
    call DRAW_SCORE
    call DRAW_LIVES
    call DRAW_TIME
    ret
DRAW_STATUS ENDP

;------------------------------------------------------------------------------
; DRAW_SCORE
; Funcao : escreve o score com SCORE_DIGITS digitos, no centro da barra
; Entrada: [score]
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_SCORE PROC
    PUSH_ALL
    mov  ax, [score]
    mov  cx, SCORE_DIGITS
    mov  dh, STATUS_ROW
    mov  dl, SCORE_COL
    mov  bl, COLOR_SCORE
    call PRINT_NUMBER
    POP_ALL
    ret
DRAW_SCORE ENDP

;------------------------------------------------------------------------------
; DRAW_LIVES
; Funcao : apaga a area dos coracoes e desenha o bitmap do numero de vidas
;          atual, no canto esquerdo da barra (com 0 vidas a area fica
;          vazia). Cada estado tem a sua largura (tabela heart_ws).
; Entrada: [lives] (0 .. LIVES_START)
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_LIVES PROC
    PUSH_ALL
    mov  ax, HEART_X
    mov  bx, HEART_Y
    mov  cx, HEART_MAX_W
    mov  dx, HEART_H
    mov  bp, COLOR_BG
    call FILL_RECT              ; apaga o estado anterior (o mais largo)
    mov  si, [lives]
    or   si, si
    jz   dlv_done
    dec  si
    shl  si, 1                  ; SI = (vidas - 1) * 2 (tabelas de words)
    mov  cx, [heart_ws + si]    ; CX = largura do estado atual
    mov  si, [heart_ptrs + si]  ; SI = bitmap do estado atual
    call DRAW_SPRITE
dlv_done:
    POP_ALL
    ret
DRAW_LIVES ENDP

;------------------------------------------------------------------------------
; DRAW_TIME
; Funcao : desenha o relogio e o tempo restante, a direita da barra
; Entrada: [time_left]
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_TIME PROC
    PUSH_ALL
    mov  si, OFFSET spr_clock
    mov  ax, CLOCK_X
    mov  bx, CLOCK_Y
    mov  cx, CLOCK_W
    mov  dx, CLOCK_H
    call DRAW_SPRITE
    mov  ax, [time_left]
    mov  cx, TIME_DIGITS
    mov  dh, STATUS_ROW
    mov  dl, TIME_COL
    mov  bl, COLOR_TIME
    call PRINT_NUMBER
    POP_ALL
    ret
DRAW_TIME ENDP

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
    ; cor da caixa: selecionada ou normal
    mov  bl, COLOR_NORMAL
    mov  ax, di
    cmp  al, [menu_sel]
    jne  dm_draw
    mov  bl, COLOR_SELECT
dm_draw:
    mov  dl, MENU_COL
    mov  cx, MENU_BOX_W
    call DRAW_TEXT_BOX
    ; texto da opcao, centralizado na linha do meio da caixa
    mov  si, di
    shl  si, 1                  ; SI = indice * 2 (tabela de words)
    mov  si, [menu_ptrs + si]   ; SI = texto da opcao
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
; Funcao : desenha a faixa amarela do chao (GROUND_H linhas, tela inteira)
; Entrada: BX = linha do topo da faixa
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_GROUND PROC
    PUSH_ALL
    xor  ax, ax
    mov  cx, SCREEN_W
    mov  dx, GROUND_H
    mov  bp, COLOR_GROUND
    call FILL_RECT
    POP_ALL
    ret
DRAW_GROUND ENDP

;------------------------------------------------------------------------------
; ANIM_INIT
; Funcao : copia a tabela inicial (anim_tab0) para a tabela de trabalho
;          (anim_tab), recolocando naves e jipe nas posicoes iniciais
; Entrada: nenhuma
; Saida  : anim_tab inicializada
;------------------------------------------------------------------------------
ANIM_INIT PROC
    push cx
    push si
    push di
    mov  si, OFFSET anim_tab0
    mov  di, OFFSET anim_tab
    mov  cx, ANIM_TAB_BYTES
    call COPY_BYTES
    pop  di
    pop  si
    pop  cx
    ret
ANIM_INIT ENDP

;------------------------------------------------------------------------------
; COPY_BYTES
; Funcao : copia um bloco de bytes dentro do segmento de dados (REP MOVSB)
; Entrada: SI = origem (DS), DI = destino (DS), CX = quantidade de bytes
; Saida  : nenhuma (registradores preservados)
;------------------------------------------------------------------------------
COPY_BYTES PROC
    push cx
    push si
    push di
    push es
    push ds
    pop  es                     ; ES = DS (destino da copia)
    cld
    rep  movsb
    pop  es
    pop  di
    pop  si
    pop  cx
    ret
COPY_BYTES ENDP

;------------------------------------------------------------------------------
; ANIM_STEP
; Funcao : avanca um quadro da animacao: apaga, move e redesenha todos os
;          objetos da anim_tab. Todos andam da esquerda para a direita e,
;          ao sair pela direita, reaparecem pela esquerda.
; Entrada: anim_tab
; Saida  : anim_tab atualizada e desenhada
;------------------------------------------------------------------------------
ANIM_STEP PROC
    push cx
    push di
    mov  di, OFFSET anim_tab
    mov  cx, ANIM_OBJS
    call ERASE_OBJECTS          ; apaga nas posicoes antigas
    call MOVE_OBJECTS           ; aplica as velocidades
    call WRAP_OBJECTS           ; quem saiu pela direita volta pela esquerda
    call DRAW_OBJECTS           ; desenha nas posicoes novas
    pop  di
    pop  cx
    ret
ANIM_STEP ENDP

;==============================================================================
; ROTINAS GENERICAS DA TABELA DE OBJETOS (servem para todos os objetos)
;==============================================================================

;------------------------------------------------------------------------------
; MOVE_OBJECTS
; Funcao : soma a velocidade (OBJ_VX, OBJ_VY) a posicao (OBJ_X, OBJ_Y) de
;          cada objeto ativo da tabela
; Entrada: DI = inicio da tabela (DS), CX = quantidade de registros
; Saida  : nenhuma (registradores preservados)
;------------------------------------------------------------------------------
MOVE_OBJECTS PROC
    push ax
    push cx
    push di
    jcxz mo_done
mo_next:
    cmp  word ptr [di + OBJ_ATIVO], INATIVO
    je   mo_skip
    mov  ax, [di + OBJ_VX]
    add  [di + OBJ_X], ax
    mov  ax, [di + OBJ_VY]
    add  [di + OBJ_Y], ax
mo_skip:
    add  di, OBJ_TAM            ; proximo registro
    loop mo_next
mo_done:
    pop  di
    pop  cx
    pop  ax
    ret
MOVE_OBJECTS ENDP

;------------------------------------------------------------------------------
; WRAP_OBJECTS
; Funcao : faz cada objeto ativo que saiu totalmente pela direita da tela
;          reaparecer logo antes da borda esquerda (x = x - SCREEN_W - LARG)
; Entrada: DI = inicio da tabela (DS), CX = quantidade de registros
; Saida  : nenhuma (registradores preservados)
;------------------------------------------------------------------------------
WRAP_OBJECTS PROC
    push ax
    push cx
    push di
    jcxz wo_done
wo_next:
    cmp  word ptr [di + OBJ_ATIVO], INATIVO
    je   wo_skip
    mov  ax, [di + OBJ_X]
    cmp  ax, SCREEN_W
    jl   wo_skip                ; ainda visivel (ou entrando pela esquerda)
    sub  ax, SCREEN_W
    sub  ax, [di + OBJ_LARG]
    mov  [di + OBJ_X], ax
wo_skip:
    add  di, OBJ_TAM            ; proximo registro
    loop wo_next
wo_done:
    pop  di
    pop  cx
    pop  ax
    ret
WRAP_OBJECTS ENDP

;------------------------------------------------------------------------------
; ERASE_OBJECTS
; Funcao : apaga cada objeto ativo da tabela pintando o seu retangulo
;          com COLOR_BG
; Entrada: DI = inicio da tabela (DS), CX = quantidade de registros
; Saida  : nenhuma (registradores preservados)
;------------------------------------------------------------------------------
ERASE_OBJECTS PROC
    PUSH_ALL
    jcxz eo_done
    mov  bp, COLOR_BG           ; cor usada para apagar
eo_next:
    cmp  word ptr [di + OBJ_ATIVO], INATIVO
    je   eo_skip
    push cx                     ; guarda o contador de registros
    mov  ax, [di + OBJ_X]
    mov  bx, [di + OBJ_Y]
    mov  cx, [di + OBJ_LARG]
    mov  dx, [di + OBJ_ALT]
    call FILL_RECT
    pop  cx
eo_skip:
    add  di, OBJ_TAM            ; proximo registro
    loop eo_next
eo_done:
    POP_ALL
    ret
ERASE_OBJECTS ENDP

;------------------------------------------------------------------------------
; DRAW_OBJECTS
; Funcao : desenha o sprite (OBJ_SPRITE) de cada objeto ativo da tabela
; Entrada: DI = inicio da tabela (DS), CX = quantidade de registros
; Saida  : nenhuma (registradores preservados)
;------------------------------------------------------------------------------
DRAW_OBJECTS PROC
    PUSH_ALL
    jcxz do_done
do_next:
    cmp  word ptr [di + OBJ_ATIVO], INATIVO
    je   do_skip
    push cx                     ; guarda o contador de registros
    mov  si, [di + OBJ_SPRITE]
    mov  ax, [di + OBJ_X]
    mov  bx, [di + OBJ_Y]
    mov  cx, [di + OBJ_LARG]
    mov  dx, [di + OBJ_ALT]
    call DRAW_SPRITE
    pop  cx
do_skip:
    add  di, OBJ_TAM            ; proximo registro
    loop do_next
do_done:
    POP_ALL
    ret
DRAW_OBJECTS ENDP

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
; Funcao : devolve o endereco do sprite de um tipo de nave (sera usada na
;          geracao aleatoria dos grupos de naves)
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
    je   fr_done                ; totalmente fora da tela
    or   dx, dx
    jz   fr_done                ; altura 0: nada a pintar
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
; Funcao : desenha um sprite (1 byte/pixel) pulando a cor TRANSPARENTE,
;          com recorte horizontal. Nao faz recorte vertical.
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
    je   dsp_done               ; totalmente fora da tela
    or   di, di
    jz   dsp_done               ; altura 0: nada a desenhar
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
    cmp  al, TRANSPARENTE
    je   dsp_next
    mov  es:[di], al            ; enderecamento indireto via DI
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

;------------------------------------------------------------------------------
; DRAW_RLE_LAYER
; Funcao : desenha uma camada de terreno guardada em RLE por coluna,
;          ocupando a largura inteira da tela. A coluna x da tela recebe a
;          coluna (scroll + x) do bitmap; a tabela de colunas ja vem
;          estendida (largura + SCREEN_W entradas), entao a emenda do fim
;          com o inicio do bitmap sai sem nenhum teste.
;          Cada coluna RLE e uma lista de pares (quantidade, cor), de cima
;          para baixo, terminada por 0; a cor TRANSPARENTE so pula linhas.
; Entrada: BX = tabela de colunas da camada (DW, offsets no DS),
;          AX = scroll (coluna do bitmap mostrada em x = 0; 0 .. largura-1),
;          DX = linha do topo da camada
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_RLE_LAYER PROC
    PUSH_ALL
    push es
    shl  ax, 1                  ; scroll * 2 (tabela de words)
    add  bx, ax                 ; BX = entrada da coluna mostrada em x = 0
    push bx
    xor  ax, ax
    mov  bx, dx
    call CALC_OFFSET            ; DI = offset de video de (0, topo)
    pop  bx
    mov  bp, di                 ; BP = topo da coluna atual da tela
    mov  ax, VIDEO_SEG
    mov  es, ax
    cld
    mov  dx, SCREEN_W           ; DX = colunas da tela que faltam
rl_col:
    mov  si, [bx]               ; SI = RLE desta coluna
    mov  di, bp                 ; DI = topo da coluna na tela
rl_run:
    lodsb                       ; AL = quantidade de pixels
    or   al, al
    jz   rl_next                ; 0 = fim da coluna
    mov  cl, al
    xor  ch, ch                 ; CX = quantidade
    lodsb                       ; AL = cor
    cmp  al, TRANSPARENTE
    je   rl_skip
rl_pixel:
    mov  es:[di], al            ; enderecamento indireto via DI
    add  di, SCREEN_W           ; desce uma linha
    loop rl_pixel
    jmp  rl_run
rl_skip:
    add  di, SCREEN_W           ; transparente: so desce, sem pintar
    loop rl_skip
    jmp  rl_run
rl_next:
    add  bx, WORD_BYTES         ; proxima entrada da tabela
    inc  bp                     ; proxima coluna da tela
    dec  dx
    jnz  rl_col
    pop  es
    POP_ALL
    ret
DRAW_RLE_LAYER ENDP

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
; PRINT_NUMBER
; Funcao : escreve um numero sem sinal em decimal com zeros a esquerda
;          (ex.: 50 com 5 digitos -> "00050")
; Entrada: AX = valor, CX = digitos (1 .. NUM_MAX_DIGITS),
;          DH = linha, DL = coluna, BL = cor
; Saida  : nenhuma
;------------------------------------------------------------------------------
PRINT_NUMBER PROC
    PUSH_ALL
    mov  di, OFFSET num_buf
    add  di, cx
    mov  byte ptr [di], 0       ; terminador da string
    mov  si, dx                 ; guarda linha/coluna
    mov  bp, DEC_BASE
pn_digit:
    xor  dx, dx                 ; DX:AX / 10 (DX zerado evita overflow)
    div  bp                     ; AX = quociente, DX = resto (digito)
    add  dl, '0'
    dec  di
    mov  [di], dl               ; digitos gravados da direita p/ esquerda
    loop pn_digit
    mov  dx, si                 ; DH/DL = linha/coluna
    mov  si, di                 ; SI = primeiro digito
    call PRINT_STRING
    POP_ALL
    ret
PRINT_NUMBER ENDP

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
; Funcao : desenha uma caixa de BOX_ROWS linhas com caracteres de moldura
; Entrada: DH = linha do topo, DL = coluna esquerda,
;          CX = largura (>= BOX_BORDERS + 1), BL = cor
; Saida  : nenhuma
;------------------------------------------------------------------------------
DRAW_TEXT_BOX PROC
    PUSH_ALL
    mov  di, cx                 ; DI = largura total
    mov  si, OFFSET box_chars
    mov  ah, BOX_ROWS           ; AH = linhas restantes da caixa
dtb_row:
    push dx
    lodsb                       ; lado esquerdo
    mov  cx, 1
    call PUT_CHAR
    inc  dl
    lodsb                       ; meio (repetido)
    mov  cx, di
    sub  cx, BOX_BORDERS
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
