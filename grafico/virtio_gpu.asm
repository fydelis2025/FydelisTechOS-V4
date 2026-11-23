; ==========================================
; ⚡ VIRTIO_GPU.ASM — ACELERAÇÃO QEMU / VIRTUALBOX VIRTIO-GPU
; Framebuffer Sincronizado + Virtqueue MMIO + Fallback VESA
; FydelisTech OS v4.2 · Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
DEFAULT REL
%include "fydelterm.inc"
%include "graphics.inc"

; ========== VIRTIO PCI & DISPOSITIVOS ==========
VIRTIO_VENDOR_ID                  equ 0x1AF4
VIRTIO_DEV_GPU                    equ 0x1050
VIRTIO_GPU_BASE_FALLBACK          equ 0xFEB00000

; Registradores Virtio MMIO / Status
VIRTIO_STATUS_ACKNOWLEDGE         equ 0x01
VIRTIO_STATUS_DRIVER              equ 0x02
VIRTIO_STATUS_DRIVER_OK           equ 0x04
VIRTIO_STATUS_FEATURES_OK         equ 0x08

; Comandos de controle Virtio-GPU 2D
VIRTIO_GPU_CMD_GET_DISPLAY_INFO   equ 0x0100
VIRTIO_GPU_CMD_RESOURCE_CREATE_2D equ 0x0101
VIRTIO_GPU_CMD_SET_SCANOUT        equ 0x0103
VIRTIO_GPU_CMD_RESOURCE_FLUSH     equ 0x0104
VIRTIO_GPU_CMD_TRANSFER_TO_HOST   equ 0x0105
VIRTIO_GPU_RESP_OK_NODATA         equ 0x1100

; Descritores Virtqueue e Recurso Padrão
VIRTQ_DESC_F_NEXT                 equ 1
VIRTQ_DESC_F_WRITE                equ 2
VIRTIO_GPU_RES_ID_PADRAO          equ 1
VIRTIO_VQ_POLL_LIMIT              equ 0x000FFFFF

; Formatos de pixel (compatível com XRGB8888 / B8G8R8A8)
VIRTIO_GPU_FORMAT_B8G8R8A8        equ 1
VIRTIO_GPU_FORMAT_B8G8R8X8        equ 2

; ========== EXPORTAÇÕES GLOBAIS ==========
global virtio_detectar
global virtio_inicializar
global virtio_preencher_retangulo
global virtio_copiar_blit
global virtio_enviar_transfer_flush
global virtio_configurar_virtqueue
global virtio_esta_ativo
global virtio_ler_status

; ========== EXTERNAIS ==========
extern pci_gpu_obter_info
extern fb_preencher_retangulo
extern fb_base
extern fb_largura
extern fb_altura
extern fb_pitch

section .bss
align 4096
virtio_vq_ring:           resb 4096         ; Fila Virtqueue alinhada em página 4K
vgpu_cmd_buf:             resb 64           ; Buffer de comando (transfer/flush)
vgpu_resp_buf:            resb 64           ; Buffer de resposta do host
virtio_mmio_base:         resq 1
fb_virtio_endereco:       resq 1
vgpu_desc_table:          resq 1            ; Endereço físico/virtual da tabela de descritores
vgpu_avail_ring:          resq 1            ; Endereço do Available Ring
vgpu_used_ring:           resq 1            ; Endereço do Used Ring
vgpu_notify_mmio:         resq 1            ; Endereço MMIO/BAR de notificação da queue 0
vgpu_last_used_idx:       resw 1            ; Último used.idx consumido
vgpu_avail_seq:           resw 1            ; Contador sequencial de avail.idx
virtio_pitch_bytes:       resd 1
resolucao_largura:        resd 1
resolucao_altura:         resd 1
virtio_placa_ok:          resb 1
virtio_gpu_ativado:       resb 1

section .text

; ==========================================
; 🔍 DETECTAR VIRTIO-GPU (PCI Vendor 0x1AF4 / Tipo 4)
; ==========================================
virtio_detectar:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    and     rsp, -16

    mov     rdi, rsp
    call    pci_gpu_obter_info

    mov     eax, [rsp + 4]          ; tipo da GPU (GPU_TIPO_VIRTIO = 4)
    cmp     eax, 4
    jne     .nao_virtio

    mov     rax, [rsp + 8]          ; bar0_fisico obtido do barramento PCI
    test    rax, rax
    jnz     .salva_bar0
    mov     rax, VIRTIO_GPU_BASE_FALLBACK

.salva_bar0:
    mov     [rel virtio_mmio_base], rax
    mov     byte [rel virtio_placa_ok], 1
    mov     rax, 1
    jmp     .fim

.nao_virtio:
    mov     byte [rel virtio_placa_ok], 0
    xor     rax, rax

.fim:
    mov     rsp, rbp
    pop     rbp
    ret

; ==========================================
; ⚙️ CONFIGURAR PONTEIROS DA VIRTQUEUE 2D
; Entrada: rdi=desc_table, rsi=avail_ring, rdx=used_ring, rcx=notify_mmio
; ==========================================
virtio_configurar_virtqueue:
    mov     [rel vgpu_desc_table], rdi
    mov     [rel vgpu_avail_ring], rsi
    mov     [rel vgpu_used_ring], rdx
    mov     [rel vgpu_notify_mmio], rcx
    mov     word [rel vgpu_last_used_idx], 0
    mov     word [rel vgpu_avail_seq], 0
    mov     rax, 1
    ret

; ==========================================
; ✅ INICIALIZAR — Sincroniza Framebuffer e Virtqueue
; ==========================================
virtio_inicializar:
    cmp     byte [rel virtio_gpu_ativado], 1
    je      .pronto

    cmp     byte [rel virtio_placa_ok], 1
    je      .configurar

    call    virtio_detectar
    test    rax, rax
    jz      .falha

.configurar:
    mov     rax, [rel fb_base]
    test    rax, rax
    jz      .falha
    mov     [rel fb_virtio_endereco], rax

    mov     eax, [rel fb_largura]
    test    eax, eax
    jz      .falha
    mov     [rel resolucao_largura], eax

    mov     ecx, [rel fb_altura]
    test    ecx, ecx
    jz      .falha
    mov     [rel resolucao_altura], ecx

    mov     edx, [rel fb_pitch]
    test    edx, edx
    jnz     .salva_pitch
    mov     edx, eax
    shl     edx, 2                  ; pitch padrão = largura * 4 bytes

.salva_pitch:
    mov     [rel virtio_pitch_bytes], edx

    ; Limpa área da Virtqueue 2D (controlq) e contadores de fila
    lea     rdi, [rel virtio_vq_ring]
    mov     rcx, 4096 / 8
    xor     rax, rax
    rep     stosq
    mov     word [rel vgpu_last_used_idx], 0
    mov     word [rel vgpu_avail_seq], 0

    mov     byte [rel virtio_gpu_ativado], 1

.pronto:
    mov     rax, 1
    ret

.falha:
    mov     byte [rel virtio_gpu_ativado], 0
    xor     rax, rax
    ret

; ==========================================
; 🎨 PREENCHER RETÂNGULO — ACELERADO 2D (VIRTIO)
; Entrada (Padrão FydelisTech OS):
;   rdi = x, rsi = y, rdx = largura, rcx = altura, r8d = cor (XRGB8888)
; ==========================================
virtio_preencher_retangulo:
    cmp     byte [rel virtio_gpu_ativado], 1
    jne     .fallback

    mov     r10, [rel fb_virtio_endereco]
    test    r10, r10
    jz      .fallback

    test    rdx, rdx
    jle     .concluido
    test    rcx, rcx
    jle     .concluido

    ; Clipping esquerdo (x < 0)
    test    rdi, rdi
    jns     .clip_y
    add     rdx, rdi
    xor     rdi, rdi
    test    rdx, rdx
    jle     .concluido

.clip_y:
    ; Clipping superior (y < 0)
    test    rsi, rsi
    jns     .clip_direita
    add     rcx, rsi
    xor     rsi, rsi
    test    rcx, rcx
    jle     .concluido

.clip_direita:
    mov     eax, [rel resolucao_largura]
    cmp     rdi, rax
    jge     .concluido
    mov     r9, rdi
    add     r9, rdx
    cmp     r9, rax
    jle     .clip_inferior
    mov     rdx, rax
    sub     rdx, rdi

.clip_inferior:
    mov     eax, [rel resolucao_altura]
    cmp     rsi, rax
    jge     .concluido
    mov     r9, rsi
    add     r9, rcx
    cmp     r9, rax
    jle     .desenhar
    mov     rcx, rax
    sub     rcx, rsi

.desenhar:
    push    rbx
    push    rdi
    push    rsi
    push    r11

    mov     r11d, [rel virtio_pitch_bytes]

    ; Ponteiro inicial: fb_virtio_endereco + (y * pitch) + (x * 4)
    mov     rax, rsi
    imul    rax, r11
    add     r10, rax
    lea     r10, [r10 + rdi * 4]

    mov     rbx, rcx                ; contador de linhas (altura)
    mov     eax, r8d                ; cor 32-bit para rep stosd

.loop_linha:
    mov     rdi, r10
    mov     rcx, rdx                ; largura em pixels
    rep     stosd

    add     r10, r11                ; próxima linha usando pitch real
    dec     rbx
    jnz     .loop_linha

    pop     r11
    pop     rsi
    pop     rdi
    pop     rbx

.concluido:
    mov     rax, 1
    ret

.fallback:
    jmp     fb_preencher_retangulo

; ==========================================
; 📋 COPIAR BLIT (BITBLT 2D VIRTIO)
; Entrada: rdi=src_x, rsi=src_y, rdx=dst_x, rcx=dst_y, r8=largura, r9=altura
; ==========================================
virtio_copiar_blit:
    mov     r10, [rel fb_virtio_endereco]
    test    r10, r10
    jnz     .blit_tem_fb
    mov     r10, [rel fb_base]
    test    r10, r10
    jz      .fim_blit

.blit_tem_fb:
    test    r8, r8
    jle     .fim_blit
    test    r9, r9
    jle     .fim_blit

    push    rbx
    push    rsi
    push    rdi
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r14d, [rel resolucao_largura]
    test    r14d, r14d
    jnz     .w_ok
    mov     r14d, [rel fb_largura]
.w_ok:
    mov     r15d, [rel resolucao_altura]
    test    r15d, r15d
    jnz     .h_ok
    mov     r15d, [rel fb_altura]
.h_ok:

    mov     r11d, [rel virtio_pitch_bytes]
    test    r11d, r11d
    jnz     .pitch_ok
    mov     r11d, [rel fb_pitch]
.pitch_ok:

    ; Clipping src_x < 0
    test    rdi, rdi
    jns     .blit_src_y0
    add     r8, rdi
    sub     rdx, rdi
    xor     rdi, rdi

.blit_src_y0:
    ; Clipping src_y < 0
    test    rsi, rsi
    jns     .blit_dst_x0
    add     r9, rsi
    sub     rcx, rsi
    xor     rsi, rsi

.blit_dst_x0:
    ; Clipping dst_x < 0
    test    rdx, rdx
    jns     .blit_dst_y0
    add     r8, rdx
    sub     rdi, rdx
    xor     rdx, rdx

.blit_dst_y0:
    ; Clipping dst_y < 0
    test    rcx, rcx
    jns     .blit_bounds_x
    add     r9, rcx
    sub     rsi, rcx
    xor     rcx, rcx

.blit_bounds_x:
    test    rdi, rdi
    js      .blit_pop_fim
    test    rsi, rsi
    js      .blit_pop_fim
    test    rdx, rdx
    js      .blit_pop_fim
    test    rcx, rcx
    js      .blit_pop_fim
    test    r8, r8
    jle     .blit_pop_fim
    test    r9, r9
    jle     .blit_pop_fim

    ; Limita largura à borda direita (src_x e dst_x)
    mov     rax, rdi
    add     rax, r8
    cmp     rax, r14
    jbe     .blit_lim_dx
    mov     r8, r14
    sub     r8, rdi

.blit_lim_dx:
    mov     rax, rdx
    add     rax, r8
    cmp     rax, r14
    jbe     .blit_check_w
    mov     r8, r14
    sub     r8, rdx

.blit_check_w:
    test    r8, r8
    jle     .blit_pop_fim

    ; Limita altura à borda inferior (src_y e dst_y)
    mov     rax, rsi
    add     rax, r9
    cmp     rax, r15
    jbe     .blit_lim_dy
    mov     r9, r15
    sub     r9, rsi

.blit_lim_dy:
    mov     rax, rcx
    add     rax, r9
    cmp     rax, r15
    jbe     .blit_check_h
    mov     r9, r15
    sub     r9, rcx

.blit_check_h:
    test    r9, r9
    jle     .blit_pop_fim

    ; Se dst_y > src_y, copia de baixo para cima para evitar sobreposição
    cmp     rcx, rsi
    jg      .blit_reverso

    xor     r12, r12
.loop_blit_y:
    cmp     r12, r9
    jge     .blit_pop_fim

    mov     rax, rsi
    add     rax, r12
    imul    rax, r11
    lea     rbx, [r10 + rax]
    lea     rbx, [rbx + rdi * 4]

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
    jmp     .loop_blit_y

.blit_reverso:
    mov     r12, r9
    dec     r12
.loop_blit_rev_y:
    cmp     r12, 0
    jl      .blit_pop_fim

    mov     rax, rsi
    add     rax, r12
    imul    rax, r11
    lea     rbx, [r10 + rax]
    lea     rbx, [rbx + rdi * 4]

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

    dec     r12
    jmp     .loop_blit_rev_y

.blit_pop_fim:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     rdi
    pop     rsi
    pop     rbx

.fim_blit:
    mov     rax, 1
    ret

; ==========================================
; 🔄 ENVIAR TRANSFER_TO_HOST + RESOURCE_FLUSH
; Entrada: rdi=x, rsi=y, rdx=largura, rcx=altura
; Retorno: rax = 1 sucesso, 0 falha ou fila não configurada
; ==========================================
virtio_enviar_transfer_flush:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    cmp     byte [rel virtio_gpu_ativado], 1
    jne     .flush_erro
    mov     rax, [rel vgpu_desc_table]
    test    rax, rax
    jz      .flush_erro
    mov     rax, [rel vgpu_avail_ring]
    test    rax, rax
    jz      .flush_erro
    mov     rax, [rel vgpu_used_ring]
    test    rax, rax
    jz      .flush_erro

    ; 1. Monta VIRTIO_GPU_CMD_TRANSFER_TO_HOST (0x0105)
    lea     rbx, [rel vgpu_cmd_buf]
    mov     dword [rbx + 0],  VIRTIO_GPU_CMD_TRANSFER_TO_HOST
    mov     dword [rbx + 4],  0
    mov     qword [rbx + 8],  0
    mov     dword [rbx + 16], 0
    mov     dword [rbx + 20], 0
    mov     [rbx + 24], r12d
    mov     [rbx + 28], r13d
    mov     [rbx + 32], r14d
    mov     [rbx + 36], r15d

    mov     eax, [rel virtio_pitch_bytes]
    imul    rax, r13
    lea     rax, [rax + r12 * 4]
    mov     [rbx + 40], rax                 ; offset dentro do recurso
    mov     dword [rbx + 48], VIRTIO_GPU_RES_ID_PADRAO
    mov     dword [rbx + 52], 0

    lea     rdi, [rel vgpu_resp_buf]
    mov     dword [rdi + 0], 0

    mov     rdi, rbx
    mov     rsi, 56
    lea     rdx, [rel vgpu_resp_buf]
    mov     rcx, 24
    call    .submeter_e_aguardar
    test    rax, rax
    jz      .flush_erro

    lea     rdi, [rel vgpu_resp_buf]
    cmp     dword [rdi + 0], VIRTIO_GPU_RESP_OK_NODATA
    jne     .flush_erro

    ; 2. Monta VIRTIO_GPU_CMD_RESOURCE_FLUSH (0x0104)
    lea     rbx, [rel vgpu_cmd_buf]
    mov     dword [rbx + 0],  VIRTIO_GPU_CMD_RESOURCE_FLUSH
    mov     dword [rbx + 4],  0
    mov     qword [rbx + 8],  0
    mov     dword [rbx + 16], 0
    mov     dword [rbx + 20], 0
    mov     [rbx + 24], r12d
    mov     [rbx + 28], r13d
    mov     [rbx + 32], r14d
    mov     [rbx + 36], r15d
    mov     dword [rbx + 40], VIRTIO_GPU_RES_ID_PADRAO
    mov     dword [rbx + 44], 0

    lea     rdi, [rel vgpu_resp_buf]
    mov     dword [rdi + 0], 0

    mov     rdi, rbx
    mov     rsi, 48
    lea     rdx, [rel vgpu_resp_buf]
    mov     rcx, 24
    call    .submeter_e_aguardar
    test    rax, rax
    jz      .flush_erro

    lea     rdi, [rel vgpu_resp_buf]
    cmp     dword [rdi + 0], VIRTIO_GPU_RESP_OK_NODATA
    jne     .flush_erro

    mov     rax, 1
    jmp     .flush_fim

.flush_erro:
    xor     rax, rax

.flush_fim:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; Submete par de descritores (comando -> resposta) e aguarda used.idx
; Entrada: rdi=cmd_ptr, rsi=cmd_len, rdx=resp_ptr, rcx=resp_len
.submeter_e_aguardar:
    push    rbx
    push    r8
    push    r9

    mov     rbx, [rel vgpu_desc_table]
    mov     [rbx + 0],  rdi
    mov     [rbx + 8],  esi
    mov     word  [rbx + 12], VIRTQ_DESC_F_NEXT
    mov     word  [rbx + 14], 1

    mov     [rbx + 16], rdx
    mov     [rbx + 24], ecx
    mov     word  [rbx + 28], VIRTQ_DESC_F_WRITE
    mov     word  [rbx + 30], 0

    mov     r8, [rel vgpu_avail_ring]
    movzx   eax, word [rel vgpu_avail_seq]
    and     eax, 0x00FF
    mov     word [r8 + 4 + rax * 2], 0

    mfence
    inc     word [rel vgpu_avail_seq]
    mov     ax, [rel vgpu_avail_seq]
    mov     word [r8 + 2], ax
    mfence

    mov     rax, [rel vgpu_notify_mmio]
    test    rax, rax
    jz      .aguardar_used
    mov     word [rax], 0

.aguardar_used:
    mov     r9, [rel vgpu_used_ring]
    mov     rcx, VIRTIO_VQ_POLL_LIMIT
    mov     dx, [rel vgpu_last_used_idx]

.loop_used:
    cmp     word [r9 + 2], dx
    jne     .consumido_ok
    pause
    dec     rcx
    jnz     .loop_used

    xor     rax, rax
    jmp     .sub_fim

.consumido_ok:
    mov     ax, [r9 + 2]
    mov     [rel vgpu_last_used_idx], ax
    mov     rax, 1

.sub_fim:
    pop     r9
    pop     r8
    pop     rbx
    ret

; ==========================================
; 📊 STATUS DO DRIVER (Padrão Systray/Painel)
; Retorno: bit 0 = ativado, bit 1 = placa_ok
; ==========================================
virtio_esta_ativo:
    movzx   rax, byte [rel virtio_gpu_ativado]
    ret

virtio_ler_status:
    xor     rax, rax
    mov     al, [rel virtio_placa_ok]
    shl     al, 1
    or      al, [rel virtio_gpu_ativado]
    ret
