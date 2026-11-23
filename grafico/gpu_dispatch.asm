; ==========================================
; GPU_DISPATCH — Seletor Automático
; FydelisTech OS v4.2 · VESA + Fallback Genérico
; Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
DEFAULT REL

; Framebuffer compartilhado com VESA/GOP
extern fb_base
extern fb_largura
extern fb_altura
extern fb_pitch
extern fb_bpp

; Drivers de aceleração
extern virtio_detectar
extern virtio_inicializar
extern virtio_preencher_retangulo

; Driver genérico
extern fb_preencher_retangulo

section .data
align 8
gpu_desenhar:   dq 0
gpu_tipo:       dd 0   ; 0=genérico, 1=Intel, 2=Virtio, 3=AMD

section .text
global gpu_inicializar
global gpu_preencher_retangulo
global gpu_obter_tipo

; ==========================================
; ✅ INICIALIZAR — Chamar no início do kernel
; ==========================================
gpu_inicializar:
    cmp     qword [rel fb_base], 0
    jz      .sem_fb

    ; === Tenta Virtio-GPU ===
    call    virtio_detectar
    test    rax, rax
    jnz     .virtio

    ; === Fallback: Framebuffer Genérico ===
    lea     rax, [rel fb_preencher_retangulo]
    mov     [rel gpu_desenhar], rax
    mov     dword [rel gpu_tipo], 0
    mov     rax, 1
    ret

.sem_fb:
    xor     rax, rax
    ret

.virtio:
    call    virtio_inicializar
    test    rax, rax
    jz      .fallback_gen

    lea     rax, [rel virtio_preencher_retangulo]
    mov     [rel gpu_desenhar], rax
    mov     dword [rel gpu_tipo], 2
    mov     rax, 1
    ret

.fallback_gen:
    lea     rax, [rel fb_preencher_retangulo]
    mov     [rel gpu_desenhar], rax
    mov     dword [rel gpu_tipo], 0
    mov     rax, 1
    ret

; ==========================================
; DESENHAR RETÂNGULO
; Entrada: rdi=x, rsi=y, rdx=largura, rcx=altura, r8d=cor (0xAARRGGBB)
; ==========================================
gpu_preencher_retangulo:
    cmp     qword [rel gpu_desenhar], 0
    jz      .fim
    jmp     [rel gpu_desenhar]

.fim:
    ret

; ==========================================
; 📤 RETORNAR TIPO DE DRIVER ATIVO
; Saída: rax = 0=genérico, 1=Intel, 2=Virtio, 3=AMD
; ==========================================
gpu_obter_tipo:
    mov     eax, [rel gpu_tipo]
    ret

; ==========================================
; ALIAS COMPATIBILIDADE LOGIN/TERMINAL
; ==========================================
global gpu_inicializar_todos
gpu_inicializar_todos:
    call    gpu_inicializar
    ret
