; ==========================================
; ⚡ INTEL_GPU.ASM — ACELERAÇÃO 2D PARA INTEL
; Família GMCH · iGPU · Gen3/4/5/6+ (Ring Buffer 64KB + Fallback VESA)
; FydelisTech OS v4.2 · Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
DEFAULT REL
%include "fydelterm.inc"
%include "graphics.inc"

; ========== REGISTRADORES — GMCH / PCI BAR0 ==========
INTEL_GMCH_MMIO_BAR        equ 0x18       ; BAR1 = MMIO do controlador
INTEL_GMCH_OFFSET          equ 0x00000000

; Registradores de controle (Render Ring / Blitter)
INTEL_VIDEO_DISPLAY        equ 0x6100     ; Ativação de saída
INTEL_RING_BUFFER_TAIL     equ 0x2000
INTEL_RING_BUFFER_HEAD     equ 0x2004
INTEL_RING_BUFFER_BASE     equ 0x2008
INTEL_RING_BUFFER_CONTROL  equ 0x2030

; Comandos de aceleração 2D (MI / XY_BLT)
INTEL_CMD_MI_NOOP          equ 0x00000000
INTEL_CMD_FILL_RECT        equ 0x50000000
INTEL_CMD_COPY_BLIT        equ 0x52000000
INTEL_CMD_PIXEL_WRITE      equ 0x40000000

; Máscaras e Limites
RING_BUFFER_ENABLE         equ 0x00000001
RING_BUFFER_SIZE_64KB      equ 0x00000000
RING_BUFFER_BYTES          equ 65536
RING_BUFFER_MASK           equ (RING_BUFFER_BYTES - 1)
INTEL_RING_TIMEOUT         equ 1000000

; ========== EXPORTAÇÕES GLOBAIS ==========
global intel_detectar
global intel_inicializar
global intel_preencher_retangulo
global intel_copiar_blit
global intel_esta_ativo
global intel_ler_status

; ========== EXTERNAIS ==========
extern pci_gpu_obter_info
extern fb_preencher_retangulo
extern fb_base
extern fb_pitch

section .bss
align 4096
intel_ring_buffer:         resb RING_BUFFER_BYTES  ; Buffer real de 64 KB alinhado em 4K
intel_mmio_base:           resq 1
intel_ring_base:           resq 1
intel_ring_tail:           resd 1
intel_placa_ok:            resb 1
intel_ativado:             resb 1
intel_generacao:           resd 1                  ; 3=Gen3, 4=Gen4, etc.

section .text

; ==========================================
; 🔍 DETECTAR — Verificar se é Intel GMCH/iGPU (0x8086)
; ==========================================
intel_detectar:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    and     rsp, -16

    mov     rdi, rsp
    call    pci_gpu_obter_info

    mov     eax, [rsp + 4]          ; tipo da GPU detectada
    cmp     eax, 1                  ; GPU_TIPO_INTEL
    jne     .nao_intel

    mov     rax, [rsp + 8]          ; bar0_fisico (MMIO)
    test    rax, rax
    jz      .nao_intel

    ; Garante que o BAR0 esteja abaixo de 4 GB (coberto pelo identity map inicial)
    mov     rcx, 0x100000000
    cmp     rax, rcx
    jae     .nao_intel

    mov     [rel intel_mmio_base], rax
    mov     byte [rel intel_placa_ok], 1
    mov     rax, 1
    jmp     .fim

.nao_intel:
    mov     byte [rel intel_placa_ok], 0
    xor     rax, rax

.fim:
    mov     rsp, rbp
    pop     rbp
    ret

; ==========================================
; ✅ INICIALIZAR MMIO + RING BUFFER (64 KB)
; ==========================================
intel_inicializar:
    cmp     byte [rel intel_ativado], 1
    je      .pronto

    cmp     byte [rel intel_placa_ok], 1
    je      .configurar_mmio

    call    intel_detectar
    test    rax, rax
    jz      .falha

.configurar_mmio:
    mov     rdx, [rel intel_mmio_base]
    test    rdx, rdx
    jz      .falha

    ; 1. Desativa o Ring Buffer antes de reprogramar
    mov     dword [rdx + INTEL_RING_BUFFER_CONTROL], 0

    ; 2. Zera os 64 KB do Ring Buffer dedicado
    lea     rdi, [rel intel_ring_buffer]
    mov     [rel intel_ring_base], rdi
    mov     rcx, RING_BUFFER_BYTES / 8
    xor     rax, rax
    rep     stosq

    ; 3. Configura endereço base físico, Head e Tail
    mov     rax, [rel intel_ring_base]
    mov     dword [rdx + INTEL_RING_BUFFER_HEAD], 0
    mov     dword [rdx + INTEL_RING_BUFFER_TAIL], 0
    mov     dword [rdx + INTEL_RING_BUFFER_BASE], eax
    mov     dword [rel intel_ring_tail], 0

    ; 4. Ativa Ring Buffer com tamanho de 64 KB
    mov     dword [rdx + INTEL_RING_BUFFER_CONTROL], RING_BUFFER_ENABLE | RING_BUFFER_SIZE_64KB

    mov     dword [rel intel_generacao], 4
    mov     byte [rel intel_ativado], 1

.pronto:
    mov     rax, 1
    ret

.falha:
    mov     byte [rel intel_ativado], 0
    xor     rax, rax
    ret

; ==========================================
; ⏳ SINCRONIZAR RING BUFFER (HEAD == TAIL)
; ==========================================
intel_esperar_ocioso:
    push    rcx
    push    rdx
    mov     rdx, [rel intel_mmio_base]
    mov     ecx, INTEL_RING_TIMEOUT
.aguarda:
    mov     eax, [rdx + INTEL_RING_BUFFER_HEAD]
    and     eax, RING_BUFFER_MASK
    cmp     eax, [rel intel_ring_tail]
    je      .ocioso
    pause
    dec     ecx
    jnz     .aguarda
    xor     eax, eax
    jmp     .fim
.ocioso:
    mov     rax, 1
.fim:
    pop     rdx
    pop     rcx
    ret

; ==========================================
; 🎨 PREENCHER RETÂNGULO — ACELERADO 2D
; Entrada (Padrão FydelisTech OS):
;   rdi = x, rsi = y, rdx = largura, rcx = altura, r8d = cor (XRGB8888)
; ==========================================
intel_preencher_retangulo:
    cmp     byte [rel intel_ativado], 1
    jne     .fallback

    test    rdx, rdx
    jle     .concluido
    test    rcx, rcx
    jle     .concluido

    push    rbx
    push    r9
    push    r10

    ; Converte (x, y, w, h) -> coordenadas absolutas (x1, y1, x2, y2)
    mov     eax, edi                ; x1
    mov     ebx, esi                ; y1
    add     edx, eax                ; x2 = x1 + largura
    add     ecx, ebx                ; y2 = y1 + altura

    ; Calcula posição atual no Ring Buffer (com wrap-around de 64 KB)
    mov     r9d, [rel intel_ring_tail]
    mov     r10, [rel intel_ring_base]

    ; Pacote XY_COLOR_BLT (6 DWORDs = 24 bytes)
    mov     dword [r10 + r9 + 0],  INTEL_CMD_FILL_RECT | (4 << 8)
    mov     dword [r10 + r9 + 4],  eax              ; x1
    mov     dword [r10 + r9 + 8],  ebx              ; y1
    mov     dword [r10 + r9 + 12], edx              ; x2
    mov     dword [r10 + r9 + 16], ecx              ; y2
    mov     dword [r10 + r9 + 20], r8d              ; cor ARGB

    ; Avança Tail em 24 bytes (alinhado em QWORD) e dispara execução
    add     r9d, 24
    and     r9d, RING_BUFFER_MASK
    mov     [rel intel_ring_tail], r9d

    mov     rdx, [rel intel_mmio_base]
    mov     [rdx + INTEL_RING_BUFFER_TAIL], r9d

    call    intel_esperar_ocioso

    pop     r10
    pop     r9
    pop     rbx
.concluido:
    mov     rax, 1
    ret

.fallback:
    jmp     fb_preencher_retangulo

; ==========================================
; 📋 COPIAR BLIT (BITBLT ACELERADO 2D)
; Entrada: rdi=src_x, rsi=src_y, rdx=dst_x, rcx=dst_y, r8=largura, r9=altura
; ==========================================
intel_copiar_blit:
    cmp     byte [rel intel_ativado], 1
    jne     .fallback_blit

    test    r8, r8
    jle     .blit_ok
    test    r9, r9
    jle     .blit_ok

    push    rbx
    push    r10
    push    r11

    mov     r10d, [rel intel_ring_tail]
    mov     r11,  [rel intel_ring_base]

    ; Pacote XY_SRC_COPY_BLT (8 DWORDs = 32 bytes)
    mov     dword [r11 + r10 + 0],  INTEL_CMD_COPY_BLIT | (6 << 8)
    mov     dword [r11 + r10 + 4],  edx             ; dst_x1
    mov     dword [r11 + r10 + 8],  ecx             ; dst_y1
    add     edx, r8d
    add     ecx, r9d
    mov     dword [r11 + r10 + 12], edx             ; dst_x2
    mov     dword [r11 + r10 + 16], ecx             ; dst_y2
    mov     dword [r11 + r10 + 20], edi             ; src_x1
    mov     dword [r11 + r10 + 24], esi             ; src_y1
    mov     dword [r11 + r10 + 28], INTEL_CMD_MI_NOOP

    add     r10d, 32
    and     r10d, RING_BUFFER_MASK
    mov     [rel intel_ring_tail], r10d

    mov     rdx, [rel intel_mmio_base]
    mov     [rdx + INTEL_RING_BUFFER_TAIL], r10d

    call    intel_esperar_ocioso

    pop     r11
    pop     r10
    pop     rbx
.blit_ok:
    mov     rax, 1
    ret

.fallback_blit:
    ; Cópia por software linha a linha no framebuffer linear
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     r10, [rel fb_base]
    test    r10, r10
    jz      .fim_sw

    mov     r11d, [rel fb_pitch]
    xor     r12, r12                ; contador de linhas
.loop_y:
    cmp     r12, r9
    jge     .fim_sw

    ; Origem: fb_base + (src_y + lin) * pitch + src_x * 4
    mov     rax, rsi
    add     rax, r12
    imul    rax, r11
    lea     rbx, [r10 + rax]
    lea     rbx, [rbx + rdi * 4]

    ; Destino: fb_base + (dst_y + lin) * pitch + dst_x * 4
    mov     rax, rcx
    add     rax, r12
    imul    rax, r11
    lea     r13, [r10 + rax]
    lea     r13, [r13 + rdx * 4]

    push    rsi
    push    rdi
    push    rcx
    mov     rsi, rbx
    mov     rdi, r13
    mov     rcx, r8
    rep     movsd
    pop     rcx
    pop     rdi
    pop     rsi

    inc     r12
    jmp     .loop_y

.fim_sw:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    mov     rax, 1
    ret

; ==========================================
; 📊 STATUS DO DRIVER (Padrão Systray/Painel)
; Retorno: bit 0 = ativado, bit 1 = placa_ok
; ==========================================
intel_esta_ativo:
    movzx   rax, byte [rel intel_ativado]
    ret

intel_ler_status:
    xor     rax, rax
    mov     al, [rel intel_placa_ok]
    shl     al, 1
    or      al, [rel intel_ativado]
    ret
