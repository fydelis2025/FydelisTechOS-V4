; ======================================
; EDITOR FYDEL v3.0 — Estilo Nano
; Buffer de texto, edição completa, F10 salvar, ESC sair
; Conectado ao fs.asm real (FAT32) · De Salvador • Bahia
; ======================================
BITS 64
default rel
%include "fydelterm.inc"

extern clear_screen, print_string, print_char, print_newline
extern get_key, move_cursor

; Funções reais do driver FAT32 (fs.asm)
extern salvar_arquivo        ; rdi=nome, rsi=buffer, rdx=tamanho -> rax=1 ok
extern carregar_arquivo      ; rdi=nome, rsi=buffer, rdx=tamanho_max -> rax=bytes lidos

global do_fydel

; ==========================================
; CONSTANTES
; ==========================================
EDIT_BUF_TAM    equ 8192
TAM_ARG_MAX     equ 64
TELAS_COLS      equ 80
TELAS_LINS      equ 25

TECLA_ACIMA     equ 0x48
TECLA_ABAIXO    equ 0x50
TECLA_ESQ       equ 0x4B
TECLA_DIR       equ 0x4D
TECLA_HOME      equ 0x47
TECLA_END       equ 0x4F
TECLA_BACKSPACE equ 0x08
TECLA_TAB       equ 0x09
TECLA_ENTER     equ 0x0D
TECLA_LF        equ 0x0A

section .data
nome_arquivo:   times TAM_ARG_MAX db 0
msg_titulo:     db 'FYDEL Editor - F10 - Salvar  ESC - Sair  F1 Ajuda', 0
msg_modificado: db '*Modificado* ', 0
msg_limpar_bar: db '                                        ', 0
msg_salvar_ok:  db 'Salvo: ', 0
msg_sem_fs:     db 'ERRO ao gravar arquivo no disco FAT32!', 0
msg_arq_vazio:  db 'Informe o nome: ', 0
msg_conf_sair:  db 'Descartar alteracoes? (S/N) ', 0
msg_ajuda:      db 'FYDEL: Setas movem | Enter nova linha | Backspace apaga | F10 salva | ESC sai', 0
msg_editando:   db 'Editando novo arquivo (sem nome informado)', 0
msg_nome_salvar:  db 'Salvar como (ex: /fyd/usuario/documentos/nota.txt): ', 0
msg_pausa_ajuda:  db 'Pressione qualquer tecla...', 0
barra_status:   db 0

section .bss
alignb 8
buffer_edit:    resb EDIT_BUF_TAM
editor_cursor:  resq 1          ; Variável isolada para evitar conflito com o driver de vídeo
tam_texto:      resq 1          
modificado:     resb 1

section .text

; ==========================================
; do_fydel — entrada do editor
; ==========================================
do_fydel:
    push    rbx
    push    rsi
    push    rdi

    ; zera buffer e estado
    lea     rdi, [rel buffer_edit]
    mov     rcx, EDIT_BUF_TAM
    xor     al, al
    rep     stosb
    lea     rdi, [rel nome_arquivo]
    mov     rcx, TAM_ARG_MAX
    xor     al, al
    rep     stosb
    mov     qword [rel tam_texto], 0
    mov     qword [rel editor_cursor], 0
    mov     byte [rel modificado], 0

.sem_nome:
    cmp     byte [rel nome_arquivo], 0
    je      .iniciar_vazio
    lea     rdi, [rel nome_arquivo]
    lea     rsi, [rel buffer_edit]
    mov     rdx, EDIT_BUF_TAM - 1
    call    carregar_arquivo
    cmp     rax, 0
    jl      .iniciar_vazio
    mov     [rel tam_texto], rax

.iniciar_vazio:
    call    renderizar

.loop_principal:
    call    get_key

    ; --- Sair (ESC = 27) ---
    cmp     al, 27
    je      .tentar_sair

    ; --- Salvar (F10 = 0x92) ---
    cmp     al, 0x92
    je      .salvar

    ; --- Ajuda (F1 = 0x91) ---
    cmp     al, 0x91
    je      .mostrar_ajuda

    ; --- Enter ---
    cmp     al, TECLA_ENTER
    je      .tecla_enter
    cmp     al, TECLA_LF
    je      .tecla_enter

    ; --- Backspace ---
    cmp     al, TECLA_BACKSPACE
    je      .tecla_backspace

    ; --- Setas / Home / End (teclas estendidas) ---
    cmp     al, 0
    je      .tecla_estendida
    cmp     al, 0xE0
    je      .tecla_estendida

    ; --- Caractere imprimível ---
    cmp     al, 32
    jb      .loop_principal
    cmp     al, 126
    ja      .loop_principal
    call    inserir_char
    call    renderizar
    jmp     .loop_principal

.tecla_enter:
    mov     al, TECLA_LF
    call    inserir_char
    call    renderizar
    jmp     .loop_principal

.tecla_estendida:
    call    get_key             ; Captura o código real da tecla estendida
    cmp     al, TECLA_ESQ
    je      .cursor_esq
    cmp     al, TECLA_DIR
    je      .cursor_dir
    cmp     al, TECLA_ACIMA
    je      .cursor_cima
    cmp     al, TECLA_ABAIXO
    je      .cursor_baixo
    cmp     al, TECLA_HOME
    je      .cursor_home
    cmp     al, TECLA_END
    je      .cursor_end
    jmp     .loop_principal

.cursor_esq:
    cmp     qword [rel editor_cursor], 0
    je      .loop_principal
    dec     qword [rel editor_cursor]
    call    renderizar
    jmp     .loop_principal

.cursor_dir:
    mov     rax, [rel editor_cursor]
    cmp     rax, [rel tam_texto]
    jae     .loop_principal
    inc     qword [rel editor_cursor]
    call    renderizar
    jmp     .loop_principal

.cursor_home:
    mov     rcx, [rel editor_cursor]
    test    rcx, rcx
    jz      .render_loop
.loop_home:
    test    rcx, rcx
    jz      .set_home
    mov     al, [rel buffer_edit + rcx - 1]
    cmp     al, TECLA_LF
    je      .set_home
    dec     rcx
    jmp     .loop_home
.set_home:
    mov     [rel editor_cursor], rcx
.render_loop:
    call    renderizar
    jmp     .loop_principal

.cursor_end:
    mov     rcx, [rel editor_cursor]
.loop_end:
    cmp     rcx, [rel tam_texto]
    jae     .set_end
    mov     al, [rel buffer_edit + rcx]
    cmp     al, TECLA_LF
    je      .set_end
    inc     rcx
    jmp     .loop_end
.set_end:
    mov     [rel editor_cursor], rcx
    call    renderizar
    jmp     .loop_principal

.cursor_cima:
    call    cursor_linha_acima
    call    renderizar
    jmp     .loop_principal

.cursor_baixo:
    call    cursor_linha_abaixo
    call    renderizar
    jmp     .loop_principal

.tecla_backspace:
    cmp     qword [rel editor_cursor], 0
    je      .loop_principal
    call    apagar_char
    call    renderizar
    jmp     .loop_principal

.mostrar_ajuda:
    call    clear_screen
    lea     rsi, [rel msg_ajuda]
    call    print_string
    call    print_newline
    lea     rsi, [rel msg_pausa_ajuda]
    call    print_string
    call    get_key
    call    renderizar
    jmp     .loop_principal

.salvar:
    cmp     byte [rel nome_arquivo], 0
    jne     .salvar_agora
    call    renderizar
    lea     rsi, [rel msg_nome_salvar]
    call    print_string
    call    ler_nome_arquivo
.salvar_agora:
    lea     rdi, [rel nome_arquivo]
    lea     rsi, [rel buffer_edit]
    mov     rdx, [rel tam_texto]
    call    salvar_arquivo
    cmp     rax, 1
    je      .salvou
    lea     rsi, [rel msg_sem_fs]
    call    print_string
    call    print_newline
    lea     rsi, [rel msg_pausa_ajuda]
    call    print_string
    call    get_key
    jmp     .salvar_fim
.salvou:
    mov     byte [rel modificado], 0
.salvar_fim:
    call    renderizar
    jmp     .loop_principal

.tentar_sair:
    cmp     byte [rel modificado], 0
    je      .sair
    lea     rsi, [rel msg_conf_sair]
    call    print_string
    call    get_key
    or      al, 32
    cmp     al, 's'
    je      .sair
    call    renderizar
    jmp     .loop_principal

.sair:
    call    clear_screen
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ==========================================
; inserir_char — insere AL na posição do cursor
; ==========================================
inserir_char:
    push    rax
    push    rbx
    push    rcx
    push    rsi
    push    rdi

    mov     bl, al

    mov     rcx, [rel tam_texto]
    cmp     rcx, EDIT_BUF_TAM - 1
    jae     .fim_inserir

    mov     rax, [rel tam_texto]
    sub     rax, [rel editor_cursor]
    jz      .escreve_direto

    lea     rsi, [rel buffer_edit]
    add     rsi, [rel tam_texto]
    dec     rsi
    lea     rdi, [rel buffer_edit]
    add     rdi, [rel tam_texto]
    mov     rcx, [rel tam_texto]
    sub     rcx, [rel editor_cursor]
    std
    rep     movsb
    cld

.escreve_direto:
    lea     rdi, [rel buffer_edit]
    add     rdi, [rel editor_cursor]
    mov     byte [rdi], bl

    inc     qword [rel editor_cursor]
    inc     qword [rel tam_texto]
    mov     byte [rel modificado], 1

.fim_inserir:
    pop     rdi
    pop     rsi
    pop     rcx
    pop     rbx
    pop     rax
    ret
    
; ==========================================
; apagar_char
; ==========================================
apagar_char:
    push    rcx
    push    rsi
    push    rdi

    dec     qword [rel editor_cursor]
    dec     qword [rel tam_texto]

    lea     rdi, [rel buffer_edit]
    add     rdi, [rel editor_cursor]
    lea     rsi, [rel buffer_edit]
    add     rsi, [rel editor_cursor]
    inc     rsi
    mov     rcx, [rel tam_texto]
    sub     rcx, [rel editor_cursor]
    inc     rcx
    cld
    rep     movsb

    mov     byte [rel modificado], 1
    pop     rdi
    pop     rsi
    pop     rcx
    ret

; ==========================================
; cursor_linha_acima
; ==========================================
cursor_linha_acima:
    push    rcx
    push    rdx
    push    r8

    mov     rcx, [rel editor_cursor]
    test    rcx, rcx
    jz      .fim

    mov     r8, rcx
    xor     rdx, rdx
.calc_col:
    test    r8, r8
    jz      .col_ok
    mov     al, [rel buffer_edit + r8 - 1]
    cmp     al, TECLA_LF
    je      .col_ok
    inc     rdx
    dec     r8
    jmp     .calc_col
.col_ok:

    dec     rcx
.sobe:
    test    rcx, rcx
    jz      .achou
    mov     al, [rel buffer_edit + rcx - 1]
    cmp     al, TECLA_LF
    je      .achou
    dec     rcx
    jmp     .sobe
.achou:
    sub     rcx, 1
    sub     rcx, rdx
    jns     .ok
    xor     rcx, rcx
.ok:
    mov     [rel editor_cursor], rcx
.fim:
    pop     r8
    pop     rdx
    pop     rcx
    ret

; ==========================================
; cursor_linha_abaixo
; ==========================================
cursor_linha_abaixo:
    push    rcx
    push    rdx

    mov     rcx, [rel editor_cursor]
    xor     rdx, rdx
.calc_col2:
    test    rcx, rcx
    jz      .col_ok2
    mov     al, [rel buffer_edit + rcx - 1]
    cmp     al, TECLA_LF
    je      .col_ok2
    inc     rdx
    dec     rcx
    jmp     .calc_col2
.col_ok2:

    mov     rcx, [rel editor_cursor]
.desce:
    cmp     rcx, [rel tam_texto]
    jae     .fim2
    mov     al, [rel buffer_edit + rcx]
    cmp     al, TECLA_LF
    je      .nova_linha
    inc     rcx
    jmp     .desce
.nova_linha:
    inc     rcx
.avanca:
    test    rdx, rdx
    jz      .ok2
    cmp     rcx, [rel tam_texto]
    jae     .ok2
    mov     al, [rel buffer_edit + rcx]
    cmp     al, TECLA_LF
    je      .ok2
    inc     rcx
    dec     rdx
    jmp     .avanca
.ok2:
    mov     [rel editor_cursor], rcx
.fim2:
    pop     rdx
    pop     rcx
    ret

; ==========================================
; renderizar — redesenha tela
; ==========================================
renderizar:
    push    rsi
    push    rcx
    push    rbx

    call    clear_screen
    lea     rsi, [rel msg_titulo]
    call    print_string
    call    print_newline

    xor     rbx, rbx             
.loop_impr:
    cmp     rbx, [rel tam_texto]
    jge     .fim_impr

    lea     rsi, [rel buffer_edit]
    mov     al, [rsi + rbx]      

    cmp     al, TECLA_LF
    je      .e_lf
    call    print_char
    jmp     .cont
.e_lf:
    call    print_newline
.cont:
    inc     rbx
    jmp     .loop_impr
.fim_impr:

    call    print_newline
    lea     rsi, [rel msg_limpar_bar]
    call    print_string
    call    print_newline

    call    posicionar_cursor
    pop     rbx
    pop     rcx
    pop     rsi
    ret

; ==========================================
; posicionar_cursor
; ==========================================
posicionar_cursor:
    push    rcx
    push    rdx
    push    r8

    xor     rcx, rcx
    xor     rdx, rdx
    xor     r8, r8
.loop_pos:
    cmp     r8, [rel editor_cursor]
    jae     .fim_pos
    mov     al, [rel buffer_edit + r8]
    cmp     al, TECLA_LF
    jne     .cont_pos
    inc     rcx
    xor     rdx, rdx
    jmp     .prox_pos
.cont_pos:
    inc     rdx
.prox_pos:
    inc     r8
    jmp     .loop_pos
.fim_pos:
    mov     rdi, rcx
    mov     rsi, rdx
    call    move_cursor
    pop     r8
    pop     rdx
    pop     rcx
    ret
    
; ler_nome_arquivo
ler_nome_arquivo:
    push    rsi
    push    rdi
    lea     rdi, [rel nome_arquivo]
    xor     rcx, rcx
.loop_nome:
    call    get_key
    cmp     al, TECLA_ENTER
    je      .fim_nome
    test    al, al
    jz      .loop_nome
    cmp     rcx, TAM_ARG_MAX - 1
    jae     .loop_nome
    mov     [rdi + rcx], al
    inc     rcx
    call    print_char
    jmp     .loop_nome
.fim_nome:
    mov     byte [rdi + rcx], 0
    call    print_newline
    pop     rdi
    pop     rsi
    ret
