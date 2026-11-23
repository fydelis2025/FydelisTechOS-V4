; ======================================
; Video Driver FydelTerm — Modo Gráfico VESA 32-bit
; Renderização via Framebuffer Linear + Decodificador UTF-8
; ======================================
BITS 64
%define BUILDING_VIDEO_DRIVER
%include "fydelterm.inc"

extern fb_base
extern fb_largura
extern fb_altura
extern fb_pitch
extern texto_char

%define MARGIN_X      16
%define MARGIN_Y      36
%define CHAR_W        9
%define CHAR_H        12
%define BG_COLOR      0x00120826   ; Fundo roxo escuro do FydelTerm

section .bss
align 8
cursor_pos      resq 1             ; Índice linear do caractere (linha * cols + col)
input_base_pos  resq 1             ; Trava para impedir apagar o prompt
max_cols        resq 1
max_rows        resq 1

section .data
align 4
current_attr    db DEF_ATTR
utf8_skip       db 0
utf8_lead       db 0
utf8_b2         db 0
current_rgb     dd 0x0000FF9C      ; Verde neon padrão

; Tabela de conversão atributo VGA (0..15) -> RGB 32-bit
align 4
paleta_vga_rgb:
    dd 0x00120826 ; 0: Preto / Fundo
    dd 0x003B82F6 ; 1: Azul
    dd 0x0010B981 ; 2: Verde
    dd 0x0006B6D4 ; 3: Ciano
    dd 0x00EF4444 ; 4: Vermelho
    dd 0x00A855F7 ; 5: Magenta / Roxo
    dd 0x00D97706 ; 6: Marrom / Laranja
    dd 0x00CBD5E1 ; 7: Cinza claro
    dd 0x0064748B ; 8: Cinza escuro
    dd 0x0060A5FA ; 9: Azul claro
    dd 0x0000FF9C ; A: Verde neon
    dd 0x0022D3EE ; B: Ciano neon
    dd 0x00F87171 ; C: Vermelho claro
    dd 0x00E879F9 ; D: Magenta neon
    dd 0x00FACC15 ; E: Amarelo
    dd 0x00F8FAFC ; F: Branco

section .text
global clear_screen, print_string, print_char, print_newline, print_num
global set_input_base, move_cursor, update_cursor, set_color

; --- Recalcula colunas e linhas úteis com base na resolução VESA ---
calc_grid:
    push    rax
    push    rcx
    push    rdx

    mov     eax, [fb_largura]
    sub     eax, (MARGIN_X * 2)
    cmp     eax, CHAR_W
    jge     .w_ok
    mov     eax, 80 * CHAR_W
.w_ok:
    xor     edx, edx
    mov     ecx, CHAR_W
    div     ecx
    mov     [max_cols], rax

    mov     eax, [fb_altura]
    sub     eax, (MARGIN_Y + 16)
    cmp     eax, CHAR_H
    jge     .h_ok
    mov     eax, 25 * CHAR_H
.h_ok:
    xor     edx, edx
    mov     ecx, CHAR_H
    div     ecx
    mov     [max_rows], rax

    pop     rdx
    pop     rcx
    pop     rax
    ret

; --- Desenha um bloco sólido na célula [cursor_pos] (para apagar/backspace) ---
draw_cell_bg:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    cmp     qword [fb_base], 0
    je      .fim

    call    calc_grid
    mov     rax, [cursor_pos]
    xor     rdx, rdx
    mov     rcx, [max_cols]
    div     rcx                    ; RAX = row, RDX = col

    imul    rax, CHAR_H
    add     rax, MARGIN_Y
    mov     edi, eax               ; EDI = Y em pixels

    imul    rdx, CHAR_W
    add     rdx, MARGIN_X
    mov     esi, edx               ; ESI = X em pixels

    mov     r8d, [fb_pitch]
    test    r8d, r8d
    jnz     .pitch_ok
    mov     r8d, [fb_largura]
    shl     r8d, 2
.pitch_ok:
    mov     eax, edi
    imul    rax, r8
    mov     rbx, [fb_base]
    add     rbx, rax
    mov     eax, esi
    shl     rax, 2
    add     rbx, rax               ; RBX = endereço do pixel (0,0) da célula

    mov     eax, BG_COLOR
    mov     ecx, CHAR_H
.lin:
    mov     [rbx], eax
    mov     [rbx+4], eax
    mov     [rbx+8], eax
    mov     [rbx+12], eax
    mov     [rbx+16], eax
    mov     [rbx+20], eax
    mov     [rbx+24], eax
    mov     [rbx+28], eax
    add     rbx, r8
    dec     ecx
    jnz     .lin

.fim:
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; --- Define a cor atual (RDI = atributo VGA 0..15 ou cor RGB 32-bit) ---
set_color:
    mov     [current_attr], dil
    cmp     rdi, 0xFF
    ja      .rgb_direto
    and     edi, 0x0F
    mov     rax, paleta_vga_rgb
    mov     eax, [rax + rdi*4]
    mov     [current_rgb], eax
    ret
.rgb_direto:
    mov     [current_rgb], edi
    ret

; --- Imprime AL no framebuffer VESA (com decodificador UTF-8) ---
print_char:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8

    cmp     qword [fb_base], 0
    je      .fim

    ; 1. Verifica se estamos no meio de uma sequência multi-byte UTF-8
    cmp     byte [utf8_skip], 0
    jne     .utf8_cont

    ; 2. Verifica início de sequência UTF-8 (>= 0x80)
    cmp     al, 0x80
    jb      .ascii_normal
    cmp     al, 0xC0
    jb      .fim                   ; Byte de continuação órfão: ignora
    cmp     al, 0xE0
    jb      .utf8_2bytes
    cmp     al, 0xF0
    jb      .utf8_3bytes

    ; 4 bytes (Emojis como 🇧🇷, 🧠, 💾): ignora os próximos 3 bytes
    mov     byte [utf8_skip], 3
    mov     [utf8_lead], al
    jmp     .fim

.utf8_2bytes:
    mov     byte [utf8_skip], 1
    mov     [utf8_lead], al
    jmp     .fim

.utf8_3bytes:
    mov     byte [utf8_skip], 2
    mov     [utf8_lead], al
    jmp     .fim

.utf8_cont:
    dec     byte [utf8_skip]
    mov     bl, [utf8_lead]

    ; Sequência de 2 bytes (0xC2 / 0xC3 — Acentos Latin-1)
    cmp     bl, 0xC2
    je      .map_c2
    cmp     bl, 0xC3
    je      .map_c3

    ; Sequência de 3 bytes (0xE2 — Bordas e Setas Unicode)
    cmp     bl, 0xE2
    je      .map_e2

    ; Sequência de 4 bytes (Emojis): aguarda terminar e descarta
    cmp     byte [utf8_skip], 0
    jne     .fim
    mov     byte [utf8_lead], 0
    jmp     .fim

.map_c2:
    mov     byte [utf8_lead], 0
    cmp     al, 0xB7               ; '·'
    jne     .fim
    mov     al, '-'
    jmp     .ascii_normal

.map_c3:
    mov     byte [utf8_lead], 0
    cmp     al, 0x87               ; 'Ç'
    je      .ch_C
    cmp     al, 0xA7               ; 'ç'
    je      .ch_c
    cmp     al, 0x86
    jbe     .ch_A                  ; À..Å
    cmp     al, 0x8B
    jbe     .ch_E                  ; È..Ë
    cmp     al, 0x8F
    jbe     .ch_I                  ; Ì..Ï
    cmp     al, 0x91
    je      .ch_N                  ; Ñ
    cmp     al, 0x98
    jbe     .ch_O                  ; Ò..Ö
    cmp     al, 0x9C
    jbe     .ch_U                  ; Ù..Ü
    cmp     al, 0xA0
    jb      .fim
    cmp     al, 0xA6
    jbe     .ch_a                  ; à..å
    cmp     al, 0xAB
    jbe     .ch_e                  ; è..ë
    cmp     al, 0xAF
    jbe     .ch_i                  ; ì..ï
    cmp     al, 0xB1
    je      .ch_n                  ; ñ
    cmp     al, 0xB8
    jbe     .ch_o                  ; ò..ö
    cmp     al, 0xBC
    jbe     .ch_u                  ; ù..ü
    jmp     .fim

.ch_A: mov al, 'A'
       jmp .ascii_normal
.ch_C: mov al, 'C'
       jmp .ascii_normal
.ch_E: mov al, 'E'
       jmp .ascii_normal
.ch_I: mov al, 'I'
       jmp .ascii_normal
.ch_N: mov al, 'N'
       jmp .ascii_normal
.ch_O: mov al, 'O'
       jmp .ascii_normal
.ch_U: mov al, 'U'
       jmp .ascii_normal
.ch_a: mov al, 'a'
       jmp .ascii_normal
.ch_c: mov al, 'c'
       jmp .ascii_normal
.ch_e: mov al, 'e'
       jmp .ascii_normal
.ch_i: mov al, 'i'
       jmp .ascii_normal
.ch_n: mov al, 'n'
       jmp .ascii_normal
.ch_o: mov al, 'o'
       jmp .ascii_normal
.ch_u: mov al, 'u'
       jmp .ascii_normal

.map_e2:
    cmp     byte [utf8_skip], 1
    jne     .e2_byte3
    mov     [utf8_b2], al          ; Guarda o 2º byte
    jmp     .fim
.e2_byte3:
    mov     byte [utf8_lead], 0
    mov     bl, [utf8_b2]
    cmp     bl, 0x95               ; Box Drawing (╔ ═ ║ ╚ ╝)
    je      .box_char
    cmp     bl, 0x96               ; Setas/Triângulos (▶)
    je      .arrow_char
    cmp     bl, 0x80               ; Pontuação (• —)
    je      .punct_char
    jmp     .fim

.box_char:
    cmp     al, 0x90               ; '═'
    je      .box_eq
    cmp     al, 0x91               ; '║'
    je      .box_pipe
    mov     al, '+'                ; Cantos ╔ ╗ ╚ ╝
    jmp     .ascii_normal
.box_eq:
    mov     al, '='
    jmp     .ascii_normal
.box_pipe:
    mov     al, '|'
    jmp     .ascii_normal

.arrow_char:
    mov     al, '>'
    jmp     .ascii_normal

.punct_char:
    mov     al, '-'
    jmp     .ascii_normal

    ; 3. Processamento ASCII padrão
.ascii_normal:
    cmp     al, KEY_ENTER
    je      .nova_linha
    cmp     al, 10
    je      .nova_linha
    cmp     al, 13
    je      .fim
    cmp     al, KEY_BACKSPACE
    je      .apaga
    cmp     al, 8
    je      .apaga

    mov     r8b, al                ; R8B = caractere ASCII
    call    calc_grid

    ; Converte cursor_pos em (X, Y) em pixels
    mov     rax, [cursor_pos]
    xor     rdx, rdx
    mov     rcx, [max_cols]
    div     rcx                    ; RAX = linha, RDX = coluna

    imul    rax, CHAR_H
    add     rax, MARGIN_Y
    mov     edi, eax               ; EDI = Y

    imul    rdx, CHAR_W
    add     rdx, MARGIN_X
    mov     esi, edx               ; ESI = X

    mov     ecx, [current_rgb]
    call    texto_char

    inc     qword [cursor_pos]
    jmp     .verifica_rolagem

.apaga:
    mov     rax, [input_base_pos]
    cmp     qword [cursor_pos], rax
    jle     .fim

    dec     qword [cursor_pos]
    call    draw_cell_bg
    jmp     .fim

.nova_linha:
    call    calc_grid
    mov     rax, [cursor_pos]
    xor     rdx, rdx
    mov     rcx, [max_cols]
    div     rcx
    inc     rax
    mul     rcx
    mov     [cursor_pos], rax

.verifica_rolagem:
    call    calc_grid
    mov     rax, [max_cols]
    imul    rax, [max_rows]
    cmp     qword [cursor_pos], rax
    jl      .fim
    call    clear_screen

.fim:
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; --- Define onde o usuário pode apagar (fim do prompt) ---
set_input_base:
    mov     rax, [cursor_pos]
    mov     [input_base_pos], rax
    ret

; --- Compatibilidade com editor/cursor ---
move_cursor:
update_cursor:
    ret

; --- Imprime string RSI ---
print_string:
    push    rax
    push    rsi
.prox:
    lodsb
    test    al, al
    jz      .fim_str
    call    print_char
    jmp     .prox
.fim_str:
    pop     rsi
    pop     rax
    ret

; --- Nova Linha ---
print_newline:
    push    rax
    mov     al, 10
    call    print_char
    pop     rax
    ret

; --- Limpa a área de texto no framebuffer VESA ---
clear_screen:
    push    rax
    push    rcx
    push    rdx
    push    rdi

    mov     byte [utf8_skip], 0
    mov     byte [utf8_lead], 0

    cmp     qword [fb_base], 0
    je      .reset_pos

    mov     r8d, [fb_pitch]
    test    r8d, r8d
    jnz     .pitch_ok
    mov     r8d, [fb_largura]
    shl     r8d, 2
.pitch_ok:
    mov     eax, [fb_altura]
    imul    rax, r8
    shr     rax, 2                 ; total de dwords no framebuffer
    mov     rcx, rax
    mov     rdi, [fb_base]
    mov     eax, BG_COLOR
    rep     stosd

.reset_pos:
    mov     qword [cursor_pos], 0
    mov     qword [input_base_pos], 0

    pop     rdi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; --- Imprime o número contido em RAX em formato decimal ---
print_num:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi

    mov     rcx, 10
    xor     rsi, rsi

.div_loop:
    xor     rdx, rdx
    div     rcx
    push    rdx
    inc     rsi
    test    rax, rax
    jnz     .div_loop

.print_loop:
    pop     rax
    add     al, '0'
    call    print_char
    dec     rsi
    jnz     .print_loop

    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret
