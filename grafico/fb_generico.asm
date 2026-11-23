; ==========================================
; FB_GENÉRICO — Framebuffer por Software (32-bit XRGB8888)
; FydelisTech OS v4.2
; ==========================================
BITS 64

extern fb_base
extern fb_largura
extern fb_altura
extern fb_pitch
extern fb_bpp

section .text
global fb_preencher_retangulo

; Entrada: RDI=x1, RSI=y1, RDX=x2, RCX=y2, R8D=cor
fb_preencher_retangulo:
    cmp     qword [rel fb_base], 0
    jz      .fim

    ; Leitura segura de 32 bits (zera os 32 bits superiores)
    mov     r9d, [rel fb_largura]
    mov     r10d, [rel fb_altura]

    ; Clipping de limites
    test    rdi, rdi
    js      .x1_zero
    jmp     .chk_x1
.x1_zero:
    xor     rdi, rdi
.chk_x1:
    test    rsi, rsi
    js      .y1_zero
    jmp     .chk_y1
.y1_zero:
    xor     rsi, rsi
.chk_y1:
    cmp     rdi, r9
    jge     .fim
    cmp     rsi, r10
    jge     .fim

    cmp     rdx, r9
    cmovg   rdx, r9
    cmp     rcx, r10
    cmovg   rcx, r10

    ; Largura (R10) e Altura (R11) em pixels
    mov     r10, rdx
    sub     r10, rdi
    jle     .fim

    mov     r11, rcx
    sub     r11, rsi
    jle     .fim

    ; Pitch em bytes (fallback largura * 4)
    mov     r9d, [rel fb_pitch]
    test    r9d, r9d
    jnz     .pitch_ok
    mov     r9d, [rel fb_largura]
    shl     r9d, 2
.pitch_ok:

    ; Endereço inicial = fb_base + (y1 * pitch) + (x1 * 4)
    mov     rax, rsi
    imul    rax, r9
    mov     rdx, [rel fb_base]
    add     rdx, rax
    lea     rdx, [rdx + rdi*4]      ; RDX = ponteiro da primeira linha

    mov     eax, r8d                ; Cor 32-bit para rep stosd

.linha:
    mov     rdi, rdx
    mov     rcx, r10
    rep     stosd

    add     rdx, r9
    dec     r11
    jnz     .linha

.fim:
    ret
