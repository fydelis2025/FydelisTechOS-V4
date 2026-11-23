; ==========================================
; FB_SERVER.ASM — COMPOSITOR NO KERNEL (CORRIGIDO)
; Gerenciador de Janelas · Cursor sem Rastro · Clamping Seguro
; FydelisTech OS v4.2 · Salvador • Bahia
; ==========================================
BITS 64
default rel

extern fb_base
extern fb_largura
extern fb_altura
extern fb_pitch
extern fb_preencher_retangulo
extern mouse_ler_posicao

global cursor_restaurar_fundo
global cursor_desenhar_novo

MAX_JANELAS      equ 16
TAM_CURSOR       equ 16

struc Janela
    .x:          resd 1
    .y:          resd 1
    .largura:    resd 1
    .altura:     resd 1
    .cor_fundo:  resd 1
    .visivel:    resb 1
    .pad:        resb 3
    .titulo:     resq 1
endstruc

section .rodata
align 8
; Sprite 16x16 do cursor: 0 = transparente, 1 = borda preta, 2 = preenchimento ciano/branco
cursor_sprite:
    db 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 1,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 1,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0
    db 1,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0
    db 1,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0
    db 1,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0
    db 1,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0
    db 1,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0
    db 1,2,2,2,2,2,1,1,1,1,0,0,0,0,0,0
    db 1,2,2,1,2,2,1,0,0,0,0,0,0,0,0,0
    db 1,2,1,0,1,2,2,1,0,0,0,0,0,0,0,0
    db 1,1,0,0,1,2,2,1,0,0,0,0,0,0,0,0
    db 1,0,0,0,0,1,2,2,1,0,0,0,0,0,0,0
    db 0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

section .bss
align 64
janelas:            resb Janela_size * MAX_JANELAS
janela_ativa:       resd 1
cursor_x:           resd 1
cursor_y:           resd 1
cursor_ant_x:       resd 1
cursor_ant_y:       resd 1
cursor_salvo:       resb 1
cursor_buffer:      resd TAM_CURSOR * TAM_CURSOR

section .text
global ws_inicializar
global ws_criar_janela
global ws_desenhar_janelas
global ws_atualizar_cursor
global ws_verificar_clique
global ws_apresentar

; ==========================================
; INICIALIZAR SERVIDOR DE JANELAS
; ==========================================
ws_inicializar:
    mov     ecx, MAX_JANELAS * Janela_size
    lea     rdi, [janelas]
    xor     rax, rax
    rep     stosb

    mov     dword [janela_ativa], -1
    mov     dword [cursor_x], 0
    mov     dword [cursor_y], 0
    mov     byte [cursor_salvo], 0
    mov     rax, 1
    ret

; ==========================================
; CRIAR JANELA
; Entrada: RDI=x, RSI=y, RDX=larg, RCX=alt, R8D=cor
; Saída: RAX = índice (0..15) ou -1
; ==========================================
ws_criar_janela:
    push    rbx
    push    r12

    xor     rbx, rbx
    lea     r12, [janelas]

.procurar:
    cmp     rbx, MAX_JANELAS
    jge     .cheio

    cmp     byte [r12 + Janela.visivel], 0
    je      .encontrada

    add     r12, Janela_size
    inc     rbx
    jmp     .procurar

.encontrada:
    ; Clampa X e Y iniciais para nunca serem negativos
    test    edi, edi
    jns     .x_init_ok
    xor     edi, edi
.x_init_ok:
    test    esi, esi
    jns     .y_init_ok
    xor     esi, esi
.y_init_ok:

    mov     [r12 + Janela.x], edi
    mov     [r12 + Janela.y], esi
    mov     [r12 + Janela.largura], edx
    mov     [r12 + Janela.altura], ecx
    mov     [r12 + Janela.cor_fundo], r8d
    mov     byte [r12 + Janela.visivel], 1
    mov     [janela_ativa], ebx

    mov     rax, rbx
    pop     r12
    pop     rbx
    ret

.cheio:
    mov     rax, -1
    pop     r12
    pop     rbx
    ret

; ==========================================
; DESENHAR TODAS AS JANELAS VISÍVEIS
; ==========================================
ws_desenhar_janelas:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Restaura fundo sob o cursor antes de redesenhar janelas
    call    cursor_restaurar_fundo

    xor     rbx, rbx
    lea     r12, [janelas]

.loop:
    cmp     rbx, MAX_JANELAS
    jge     .fim

    cmp     byte [r12 + Janela.visivel], 0
    je      .proxima

    mov     r13d, [r12 + Janela.x]
    mov     r14d, [r12 + Janela.y]
    mov     r15d, [r12 + Janela.largura]
    add     r15d, r13d                  ; x2
    mov     ecx, [r12 + Janela.altura]
    add     ecx, r14d                   ; y2

    ; 1. Borda externa roxo neon (2px) com clamping >= 0
    mov     edi, r13d
    sub     edi, 2
    jns     .borda_x_ok
    xor     edi, edi
.borda_x_ok:
    mov     esi, r14d
    sub     esi, 2
    jns     .borda_y_ok
    xor     esi, esi
.borda_y_ok:
    mov     edx, r15d
    add     edx, 2
    add     ecx, 2
    mov     r8d, 0xFF9D4EDD
    call    fb_preencher_retangulo

    ; 2. Corpo da janela
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    mov     ecx, [r12 + Janela.altura]
    add     ecx, r14d
    mov     r8d, [r12 + Janela.cor_fundo]
    call    fb_preencher_retangulo

    ; 3. Barra de título (28px de altura)
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    mov     ecx, r14d
    add     ecx, 28
    mov     r8d, 0xFF1E0E3D
    call    fb_preencher_retangulo

.proxima:
    add     r12, Janela_size
    inc     rbx
    jmp     .loop

.fim:
    ; Redesenha o cursor por cima das janelas atualizadas (salva o novo fundo)
    call    cursor_desenhar_novo

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; --- Restaura pixels salvos em cursor_buffer na posição anterior ---
cursor_restaurar_fundo:
    cmp     byte [cursor_salvo], 0
    je      .ret
    cmp     qword [fb_base], 0
    je      .ret

    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12d, [cursor_ant_x]
    mov     r13d, [cursor_ant_y]
    test    r12d, r12d
    js      .fim_rest
    test    r13d, r13d
    js      .fim_rest

    mov     r14d, [fb_pitch]
    lea     r15, [cursor_buffer]

    xor     ebx, ebx                    ; linha 0..15
.lin:
    mov     eax, r13d
    add     eax, ebx
    cmp     eax, [fb_altura]
    jge     .fim_rest

    imul    rax, r14
    add     rax, [fb_base]
    lea     rdi, [rax + r12*4]

    xor     ecx, ecx                    ; col 0..15
.col:
    mov     edx, r12d
    add     edx, ecx
    cmp     edx, [fb_largura]
    jge     .prox_lin

    mov     eax, [r15 + rcx*4]
    mov     [rdi + rcx*4], eax
    inc     ecx
    cmp     ecx, TAM_CURSOR
    jl      .col

.prox_lin:
    add     r15, TAM_CURSOR * 4
    inc     ebx
    cmp     ebx, TAM_CURSOR
    jl      .lin

.fim_rest:
    mov     byte [cursor_salvo], 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
.ret:
    ret

; --- Salva fundo atual e desenha sprite 16x16 do cursor ---
cursor_desenhar_novo:
    cmp     qword [fb_base], 0
    je      .ret

    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12d, [cursor_x]
    mov     r13d, [cursor_y]
    test    r12d, r12d
    jns     .cx_ok
    xor     r12d, r12d
.cx_ok:
    test    r13d, r13d
    jns     .cy_ok
    xor     r13d, r13d
.cy_ok:
    mov     [cursor_ant_x], r12d
    mov     [cursor_ant_y], r13d

    mov     r14d, [fb_pitch]
    lea     r15, [cursor_buffer]
    lea     r8, [cursor_sprite]

    xor     ebx, ebx
.lin:
    mov     eax, r13d
    add     eax, ebx
    cmp     eax, [fb_altura]
    jge     .fim_des

    imul    rax, r14
    add     rax, [fb_base]
    lea     rdi, [rax + r12*4]

    xor     ecx, ecx
.col:
    mov     edx, r12d
    add     edx, ecx
    cmp     edx, [fb_largura]
    jge     .prox_lin

    ; Salva pixel original no buffer
    mov     eax, [rdi + rcx*4]
    mov     [r15 + rcx*4], eax

    ; Desenha pixel do ponteiro se não for transparente
    movzx   edx, byte [r8 + rcx]
    test    edx, edx
    jz      .skip_px
    cmp     edx, 1
    je      .cor_borda
    mov     dword [rdi + rcx*4], 0xFF00F5D4   ; Preenchimento ciano neon
    jmp     .skip_px
.cor_borda:
    mov     dword [rdi + rcx*4], 0xFF0A0414   ; Contorno escuro
.skip_px:
    inc     ecx
    cmp     ecx, TAM_CURSOR
    jl      .col

.prox_lin:
    add     r15, TAM_CURSOR * 4
    add     r8, TAM_CURSOR
    inc     ebx
    cmp     ebx, TAM_CURSOR
    jl      .lin

.fim_des:
    mov     byte [cursor_salvo], 1
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
.ret:
    ret

; ==========================================
; ATUALIZAR CURSOR (Lê mouse PS/2 e redesenha)
; ==========================================
ws_atualizar_cursor:
    call    mouse_ler_posicao
    ; EDI = X, ESI = Y, EAX = botões

    ; Clampa X entre 0 e fb_largura - 1
    test    edi, edi
    jns     .x_min_ok
    xor     edi, edi
.x_min_ok:
    mov     edx, [fb_largura]
    dec     edx
    cmp     edi, edx
    jle     .x_max_ok
    mov     edi, edx
.x_max_ok:

    ; Clampa Y entre 0 e fb_altura - 1
    test    esi, esi
    jns     .y_min_ok
    xor     esi, esi
.y_min_ok:
    mov     edx, [fb_altura]
    dec     edx
    cmp     esi, edx
    jle     .y_max_ok
    mov     esi, edx
.y_max_ok:

    cmp     byte [cursor_salvo], 0
    je      .mover
    cmp     edi, [cursor_x]
    jne     .mover
    cmp     esi, [cursor_y]
    je      .fim

.mover:
    push    rdi
    push    rsi
    call    cursor_restaurar_fundo
    pop     rsi
    pop     rdi

    mov     [cursor_x], edi
    mov     [cursor_y], esi
    call    cursor_desenhar_novo

.fim:
    ret

; ==========================================
; VERIFICAR CLIQUE EM JANELA
; Saída: RAX = índice da janela clicada (se botão esq pressionado) ou -1
; ==========================================
ws_verificar_clique:
    call    mouse_ler_posicao
    test    eax, 0x01                   ; Botão esquerdo pressionado?
    jz      .nenhum

    xor     rcx, rcx
    lea     rdx, [janelas]
.loop:
    cmp     rcx, MAX_JANELAS
    jge     .nenhum

    cmp     byte [rdx + Janela.visivel], 0
    je      .prox

    mov     r8d, [rdx + Janela.x]
    cmp     edi, r8d
    jl      .prox
    add     r8d, [rdx + Janela.largura]
    cmp     edi, r8d
    jge     .prox

    mov     r9d, [rdx + Janela.y]
    cmp     esi, r9d
    jl      .prox
    add     r9d, [rdx + Janela.altura]
    cmp     esi, r9d
    jge     .prox

    mov     [janela_ativa], ecx
    mov     rax, rcx
    ret

.prox:
    add     rdx, Janela_size
    inc     rcx
    jmp     .loop

.nenhum:
    mov     rax, -1
    ret

ws_apresentar:
    ret
