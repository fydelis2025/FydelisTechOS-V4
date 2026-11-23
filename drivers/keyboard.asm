; ======================================
; Keyboard Driver — Versão Clássica (Estilo v1)
; FydelisTech OS v2.0
; ======================================
BITS 64
%include "fydelterm.inc"

section .data
align 8
current_layout dq 0   ; 0=US QWERTY, 1=PT-BR

section .text
global get_key
global set_layout_ptbr, set_layout_us

get_key:
    in      al, 0x64
    test    al, 1
    jz      get_key
    in      al, 0x60

    cmp     al, 0xE0
    je      .extended_key
    test    al, 0x80
    jnz     get_key

    ; --- Interceção direta das Teclas de Função no fluxo principal ---
    cmp     al, 0x3B        ; F1 (Make code padrão)
    je      .tecla_f1
    cmp     al, 0x44        ; F10 (Make code padrão)
    je      .tecla_f10

    cmp     al, 0x1C
    je      .enter
    cmp     al, 0x0E
    je      .bs
    cmp     al, 0x39
    je      .espaco
    cmp     al, 0x0F
    je      .tab

    movzx   rax, al
    cmp     qword [current_layout], 1
    je      .use_ptbr
    mov     rbx, scancodes_us
    jmp     .traduz
.use_ptbr:
    mov     rbx, scancodes_ptbr
.traduz:
    xlatb
    test    al, al
    jz      get_key
    ret

.extended_key:
    in      al, 0x64
    test    al, 1
    jz      .extended_key
    in      al, 0x60
    test    al, 0x80
    jnz     get_key
    cmp     al, 0x48
    je      .seta_cima
    cmp     al, 0x4B
    je      .seta_esquerda
    cmp     al, 0x4D
    je      .seta_direita
    cmp     al, 0x50
    je      .seta_baixo
    jmp     get_key

.enter:
    mov     al, KEY_ENTER
    ret
.bs:
    mov     al, KEY_BACKSPACE
    ret
.espaco:
    mov     al, KEY_SPACE
    ret
.tab:
    mov     al, KEY_TAB
    ret
.seta_cima:
    mov     al, 0x81
    ret
.seta_esquerda:
    mov     al, 0x82
    ret
.seta_direita:
    mov     al, 0x83
    ret
.seta_baixo:
    mov     al, 0x84
    ret
.tecla_f1:
    mov     al, 0x91        ; Código único para F1 (Ajuda)
    ret
.tecla_f10:
    mov     al, 0x92        ; Código único para F10 (Salvar)
    ret

set_layout_us:
    mov     qword [current_layout], 0
    ret
set_layout_ptbr:
    mov     qword [current_layout], 1
    ret

; ======================================
; TABELA PT-BR — ÍNDICE EXATO POR SCANCODE
; ======================================
section .rodata
align 16
scancodes_ptbr:
db 0, 27,'1','2','3','4','5','6','7','8','9','0', 39, '=', KEY_BACKSPACE, KEY_TAB
db 'q','w','e','r','t','y','u','i','o','p', 180, 96, KEY_NEWLINE, 0,'a','s'
db 'd','f','g','h','j','k','l', 0x87, 126, 94, 0, 92, 'z','x','c','v'
db 'b','n','m',',','.','-',  0,'*',  0,KEY_SPACE,  0,  0,  0,  0,  0,  0
times 128-($-scancodes_ptbr) db 0

scancodes_us:
db 0, 27,'1','2','3','4','5','6','7','8','9','0','-','=', KEY_BACKSPACE, KEY_TAB
db 'q','w','e','r','t','y','u','i','o','p','[',']', KEY_NEWLINE, 0,'a','s'
db 'd','f','g','h','j','k','l',';', 39, 96,  0, 92, 'z','x','c','v'
db 'b','n','m',',','.','/',  0,'*',  0,KEY_SPACE,  0,  0,  0,  0,  0,  0
times 128-($-scancodes_us) db 0
