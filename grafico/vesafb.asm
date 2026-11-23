; ==========================================
; VESAFB.ASM — CORRIGIDO, OTIMIZADO E COM VSYNC
; FydelisTech OS v4.2 · Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
DEFAULT REL
%include "fydelterm.inc"
%include "graphics.inc"

; ========== DADOS ESTENDIDOS ==========
section .bss
align 4096

global fb_base
global fb_endereco
global fb_largura
global fb_altura
global fb_bpp
global fb_linhasize
global fb_pitch

fb_base:          resq 1   ; Ponteiro para o framebuffer
fb_endereco:      resq 1
fb_largura:       resd 1   ; Largura em pixels (32-bit)
fb_altura:        resd 1   ; Altura em pixels (32-bit)
fb_pitch:         resd 1   ; Bytes por linha (32-bit)
fb_bpp:           resd 1   ; Bits por pixel (32-bit)
fb_tamanho:       resd 1
fb_linhasize:     resd 1   ; Largura em bytes

; Geometria do modo texto sobre framebuffer
fonte_largura:    resd 1
fonte_altura:     resd 1
colunas:          resd 1
linhas:           resd 1
buffer_texto:     resq 1
buffer_tamanho:   resd 1

fonte_padrao_l:   equ 8
fonte_padrao_a:   equ 16

section .text
global fb_inicializar
global fb_redimensionar
global fb_recalcular_geometria
global fb_ajustar_fonte
global fb_limpar
global fb_get_geometria
global fb_desenhar_pixel
global fb_preencher_tela
global fb_sincronizar_vsync
global gpu_preencher_tela

; ==========================================
; ⏱️ SINCRONIZAÇÃO SEGURA (Com Timeout para VMSVGA)
; Evita travamento quando a GPU virtual não emula 0x3DA
; ==========================================
fb_sincronizar_vsync:
    push    rdx
    push    rax
    push    rcx

    mov     dx, 0x3DA
    mov     ecx, 50000          ; Limite máximo de ciclos (Timeout anti-travamento)
.aguardar_fim:
    in      al, dx
    test    al, 8
    jz      .fase2
    pause
    dec     ecx
    jnz     .aguardar_fim
    jmp     .sair_vsync

.fase2:
    mov     ecx, 50000
.aguardar_inicio:
    in      al, dx
    test    al, 8
    jnz     .sair_vsync
    pause
    dec     ecx
    jnz     .aguardar_inicio

.sair_vsync:
    pop     rcx
    pop     rax
    pop     rdx
    ret

; ==========================================
; INICIALIZAÇÃO — chamar APÓS preencher fb_base e resolução
; ==========================================
fb_inicializar:
    mov     rax, [rel fb_base]
    test    rax, rax
    jz      .sem_fb

    mov     [rel fb_endereco], rax

    mov     dword [rel fonte_largura], fonte_padrao_l
    mov     dword [rel fonte_altura], fonte_padrao_a

    cmp     dword [rel fb_bpp], 0
    jne     .bpp_ok
    mov     dword [rel fb_bpp], 32
.bpp_ok:

    cmp     dword [rel fb_largura], 0
    jne     .w_ok
    mov     dword [rel fb_largura], 1024
.w_ok:

    cmp     dword [rel fb_altura], 0
    jne     .h_ok
    mov     dword [rel fb_altura], 768
.h_ok:

    ; Calcula linhasize = largura * (bpp/8)
    mov     eax, [rel fb_largura]
    mov     ecx, [rel fb_bpp]
    shr     ecx, 3
    test    ecx, ecx
    jnz     .bpp_div_ok
    mov     ecx, 4
.bpp_div_ok:
    mul     ecx
    mov     [rel fb_linhasize], eax

    cmp     dword [rel fb_pitch], 0
    jne     .pitch_ok
    mov     [rel fb_pitch], eax
.pitch_ok:

    mov     eax, [rel fb_pitch]
    mul     dword [rel fb_altura]
    mov     [rel fb_tamanho], eax

    call    fb_recalcular_geometria
    mov     rax, 1
    ret

.sem_fb:
    xor     rax, rax
    ret

; ==========================================
; LIMPAR TELA com cor sólida (Com VSync)
; Entrada: rdi = cor (0xAARRGGBB)
; ==========================================
fb_limpar:
    jmp     fb_preencher_tela

; ==========================================
; DESENHAR PIXEL — x, y, cor
; rdi = x, rsi = y, rdx = cor (0xAARRGGBB)
; ==========================================
fb_desenhar_pixel:
    mov     r11, [rel fb_base]
    test    r11, r11
    jz      .fora

    ; Valida se X < 0 ou X >= largura
    test    rdi, rdi
    js      .fora
    mov     eax, [rel fb_largura]
    cmp     rdi, rax
    jge     .fora

    ; Valida se Y < 0 ou Y >= altura
    test    rsi, rsi
    js      .fora
    mov     eax, [rel fb_altura]
    cmp     rsi, rax
    jge     .fora

    mov     r9, rdx                   ; Salva cor antes do mul

    ; offset = y * pitch + x * (bpp / 8)
    mov     eax, [rel fb_pitch]
    mul     rsi                       ; rax = y * pitch
    mov     r10, rax

    mov     eax, [rel fb_bpp]
    shr     eax, 3                    ; bytes por pixel
    mul     rdi                       ; rax = x * bytes_por_pixel
    add     rax, r10

    add     rax, r11
    mov     [rax], r9d

.fora:
    ret

; ==========================================
; PREENCHER RETÂNGULO LOCAL (Sem conflito com fb_generico)
; Entrada: rdi = x, rsi = y, rdx = largura, rcx = altura, r8d = cor
; ==========================================
vesafb_preencher_retangulo:
    mov     r10, [rel fb_base]
    test    r10, r10
    jz      .fim_rect

    test    rdx, rdx
    jle     .fim_rect
    test    rcx, rcx
    jle     .fim_rect

    ; Clipping X < 0
    test    rdi, rdi
    jns     .clip_y0
    add     rdx, rdi
    xor     rdi, rdi
    test    rdx, rdx
    jle     .fim_rect

.clip_y0:
    ; Clipping Y < 0
    test    rsi, rsi
    jns     .clip_x1
    add     rcx, rsi
    xor     rsi, rsi
    test    rcx, rcx
    jle     .fim_rect

.clip_x1:
    mov     eax, [rel fb_largura]
    cmp     rdi, rax
    jge     .fim_rect
    mov     r9, rdi
    add     r9, rdx
    cmp     r9, rax
    jle     .clip_y1
    mov     rdx, rax
    sub     rdx, rdi

.clip_y1:
    mov     eax, [rel fb_altura]
    cmp     rsi, rax
    jge     .fim_rect
    mov     r9, rsi
    add     r9, rcx
    cmp     r9, rax
    jle     .desenhar_rect
    mov     rcx, rax
    sub     rcx, rsi

.desenhar_rect:
    push    rbx
    push    rdi
    push    rsi
    push    r11

    mov     r11d, [rel fb_pitch]
    mov     rax, rsi
    imul    rax, r11
    add     r10, rax
    lea     r10, [r10 + rdi * 4]

    mov     rbx, rcx                ; altura
    mov     eax, r8d                ; cor 32-bit

.loop_rect_y:
    mov     rdi, r10
    mov     rcx, rdx                ; largura
    rep     stosd

    add     r10, r11
    dec     rbx
    jnz     .loop_rect_y

    pop     r11
    pop     rsi
    pop     rdi
    pop     rbx

.fim_rect:
    ret

; ==========================================
; PREENCHER TELA (Corrigido com Pitch e VSync)
; Entrada: rdi = cor (0xAARRGGBB)
; ==========================================
fb_preencher_tela:
    mov     rbx, [rel fb_base]
    test    rbx, rbx
    jz      .fim

    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    r8
    push    r9

    ; Sincroniza com o VSync para eliminar tearing
    call    fb_sincronizar_vsync

    mov     rbx, [rel fb_base]
    mov     eax, edi                  ; Cor 32-bit para stosd
    mov     r8d, [rel fb_pitch]       ; Bytes por linha
    mov     edx, [rel fb_altura]      ; Altura em linhas
    mov     r9, r8
    shr     r9, 2                     ; Quantidade de dwords por linha

.linha_preencher:
    mov     rcx, r9
    mov     rdi, rbx
    rep     stosd

    add     rbx, r8
    dec     edx
    jnz     .linha_preencher

    pop     r9
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
.fim:
    ret

; ==========================================
; RECALCULAR COLUNAS × LINHAS
; ==========================================
fb_recalcular_geometria:
    mov     eax, [rel fb_largura]
    xor     edx, edx
    div     dword [rel fonte_largura]
    mov     [rel colunas], eax

    mov     eax, [rel fb_altura]
    xor     edx, edx
    div     dword [rel fonte_altura]
    mov     [rel linhas], eax

    mov     eax, [rel colunas]
    mul     dword [rel linhas]
    shl     eax, 1
    mov     [rel buffer_tamanho], eax
    ret

; ==========================================
; REDIMENSIONAR
; ==========================================
fb_redimensionar:
    cmp     edi, 640
    jl      .param_invalido
    cmp     esi, 480
    jl      .param_invalido

    push    rbx
    movsxd  rbx, dword [rel colunas]
    push    rbx
    movsxd  rbx, dword [rel linhas]
    push    rbx

    mov     dword [rel fb_largura], edi
    mov     dword [rel fb_altura], esi

    call    fb_ajustar_fonte
    call    fb_recalcular_geometria

    add     rsp, 24
    mov     rax, 1
    pop     rbx
    ret

.param_invalido:
    xor     rax, rax
    ret

; ==========================================
; AJUSTAR FONTE
; ==========================================
fb_ajustar_fonte:
    mov     eax, [rel fb_largura]
    mov     edx, 100
    mul     edx
    mov     ecx, 1024
    xor     edx, edx
    div     ecx

    cmp     eax, 70
    jge     .escala_min_ok
    mov     eax, 70
.escala_min_ok:
    cmp     eax, 150
    jle     .escala_max_ok
    mov     eax, 150
.escala_max_ok:

    mov     ecx, eax
    mov     eax, fonte_padrao_l
    mul     ecx
    mov     edx, 0
    mov     r8d, 100
    div     r8d
    mov     [rel fonte_largura], eax

    mov     eax, fonte_padrao_a
    mul     ecx
    mov     edx, 0
    div     r8d
    mov     [rel fonte_altura], eax

    cmp     dword [rel fonte_largura], 6
    jge     .l_ok
    mov     dword [rel fonte_largura], 6
.l_ok:
    cmp     dword [rel fonte_altura], 12
    jge     .a_ok
    mov     dword [rel fonte_altura], 12
.a_ok:
    ret

; ==========================================
; RETORNAR GEOMETRIA PARA C
; ==========================================
fb_get_geometria:
    mov     eax, [rel colunas]
    mov     [rdi], eax
    mov     eax, [rel linhas]
    mov     [rdi+4], eax
    mov     eax, [rel fonte_largura]
    mov     [rdi+8], eax
    mov     eax, [rel fonte_altura]
    mov     [rdi+12], eax
    ret

; ==========================================
; ALIASES DE COMPATIBILIDADE GLOBAL
; ==========================================
gpu_preencher_tela:
    jmp     fb_preencher_tela
