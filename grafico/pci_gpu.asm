; ==========================================
; 📡 PCI_GPU.ASM — DETECÇÃO E MAPEAMENTO MMIO
; Intel · AMD · NVIDIA · Virtio · QEMU / VirtualBox
; FydelisTech OS v4.2 · Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
DEFAULT REL
%include "fydelterm.inc"
%include "graphics.inc"

; ========== REGISTRADORES PCI ==========
PCI_CONFIG_ADDR        equ 0xCF8
PCI_CONFIG_DATA        equ 0xCFC
PCI_CLASS_VIDEO        equ 0x03
PCI_CMD_REG            equ 0x04
PCI_CLASS_REG          equ 0x08
PCI_BAR0_OFFSET        equ 0x10
PCI_BAR1_OFFSET        equ 0x14

PCI_CMD_MEM_SPACE      equ 0x0002
PCI_CMD_BUS_MASTER     equ 0x0004

; ========== IDs de Fabricantes ==========
VENDOR_INTEL           equ 0x8086
VENDOR_AMD             equ 0x1002
VENDOR_NVIDIA          equ 0x10DE
VENDOR_VIRTIO          equ 0x1AF4
VENDOR_QEMU_STD        equ 0x1234
VENDOR_VBOX_VGA        equ 0x80EE

; ========== ESTRUTURA INTERNA DE DETECÇÃO ==========
struc GPUInfo
    .presente:         resb 1
    .bus:              resb 1
    .dev:              resb 1
    .func:             resb 1
    .vendedor:         resw 1
    .dispositivo:      resw 1
    .classe:           resd 1
    .bar0_fisico:      resq 1       ; Endereço físico MMIO / LFB
    .bar0_tamanho:     resq 1
    .framebuffer:      resq 1       ; VRAM linear
    .tipo:             resd 1       ; INTEL / AMD / NVIDIA / VESA
endstruc

; Tipos de GPU
GPU_TIPO_DESCONHECIDO  equ 0
GPU_TIPO_INTEL         equ 1
GPU_TIPO_AMD           equ 2
GPU_TIPO_NVIDIA        equ 3
GPU_TIPO_VIRTIO        equ 4
GPU_TIPO_VESA_GEN      equ 5

; ========== EXPORTAÇÕES GLOBAIS ==========
global pci_gpu_varrer_barramento
global pci_gpu_mapear_barramentos
global pci_gpu_obter_info
global pci_gpu_ativar_mmio
global pci_gpu_ler_status

section .bss
align 8
gpu_info:              resb GPUInfo_size
pci_mmio_mapeado:      resb 1

section .text

; ==========================================
; 🔧 AUXILIAR: LER DWORD DO ESPAÇO DE CONFIGURAÇÃO PCI
; Entrada: rdx = bus, rsi = dev, rdi = func, ecx = offset (alinhado em 4B)
; Saída:   eax = valor de 32 bits lido de 0xCFC
; ==========================================
pci_ler_config32:
    mov     eax, edx
    and     eax, 0xFF
    shl     eax, 16

    mov     r8d, esi
    and     r8d, 0x1F
    shl     r8d, 11
    or      eax, r8d

    mov     r8d, edi
    and     r8d, 0x07
    shl     r8d, 8
    or      eax, r8d

    and     ecx, 0xFC
    or      eax, ecx
    or      eax, 0x80000000

    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    ret

; ==========================================
; 🔧 AUXILIAR: ESCREVER DWORD NO ESPAÇO DE CONFIGURAÇÃO PCI
; Entrada: rdx = bus, rsi = dev, rdi = func, ecx = offset, r9d = valor
; ==========================================
pci_escrever_config32:
    mov     eax, edx
    and     eax, 0xFF
    shl     eax, 16

    mov     r8d, esi
    and     r8d, 0x1F
    shl     r8d, 11
    or      eax, r8d

    mov     r8d, edi
    and     r8d, 0x07
    shl     r8d, 8
    or      eax, r8d

    and     ecx, 0xFC
    or      eax, ecx
    or      eax, 0x80000000

    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    mov     eax, r9d
    out     dx, eax
    ret

; ==========================================
; 🔍 VARRER BARRAMENTO → ENCONTRAR GPU (CLASSE 0x03)
; ==========================================
pci_gpu_varrer_barramento:
    push    rbx
    push    r12
    push    r13
    push    r14

    xor     r12, r12                ; r12 = Bus 0..255
.bus:
    xor     r13, r13                ; r13 = Device 0..31
.dev:
    xor     r14, r14                ; r14 = Function 0..7
.funct:
    ; 1. Verifica Vendor ID primeiro (0xFFFF = slot vazio)
    mov     rdx, r12
    mov     rsi, r13
    mov     rdi, r14
    xor     ecx, ecx                ; Offset 0x00 (Vendor/Device ID)
    call    pci_ler_config32
    cmp     ax, 0xFFFF
    je      .proxima_func
    mov     ebx, eax                ; Salva Vendor/Device ID em EBX

    ; 2. Lê Class Code / Subclass / ProgIF (Offset 0x08)
    mov     rdx, r12
    mov     rsi, r13
    mov     rdi, r14
    mov     ecx, PCI_CLASS_REG
    call    pci_ler_config32
    mov     r10d, eax               ; Salva registro de classe
    shr     eax, 24
    cmp     al, PCI_CLASS_VIDEO
    je      .encontrado

.proxima_func:
    inc     r14
    cmp     r14, 8
    jl      .funct

    inc     r13
    cmp     r13, 32
    jl      .dev

    inc     r12
    cmp     r12, 256
    jl      .bus

    ; Nenhuma GPU PCI encontrada → usa VESA genérico
    mov     byte [rel gpu_info + GPUInfo.presente], 0
    mov     dword [rel gpu_info + GPUInfo.tipo], GPU_TIPO_VESA_GEN
    xor     rax, rax
    jmp     .fim

.encontrado:
    mov     byte [rel gpu_info + GPUInfo.presente], 1
    mov     [rel gpu_info + GPUInfo.bus], r12b
    mov     [rel gpu_info + GPUInfo.dev], r13b
    mov     [rel gpu_info + GPUInfo.func], r14b
    mov     [rel gpu_info + GPUInfo.vendedor], bx
    ror     ebx, 16
    mov     [rel gpu_info + GPUInfo.dispositivo], bx
    mov     [rel gpu_info + GPUInfo.classe], r10d

    ; Identificar fabricante
    mov     ax, [rel gpu_info + GPUInfo.vendedor]
    cmp     ax, VENDOR_INTEL
    je      .tipo_intel
    cmp     ax, VENDOR_AMD
    je      .tipo_amd
    cmp     ax, VENDOR_NVIDIA
    je      .tipo_nvidia
    cmp     ax, VENDOR_VIRTIO
    je      .tipo_virtio
    cmp     ax, VENDOR_QEMU_STD
    je      .tipo_vesa
    cmp     ax, VENDOR_VBOX_VGA
    je      .tipo_vesa
    mov     dword [rel gpu_info + GPUInfo.tipo], GPU_TIPO_DESCONHECIDO
    jmp     .ler_bar0

.tipo_intel:
    mov     dword [rel gpu_info + GPUInfo.tipo], GPU_TIPO_INTEL
    jmp     .ler_bar0
.tipo_amd:
    mov     dword [rel gpu_info + GPUInfo.tipo], GPU_TIPO_AMD
    jmp     .ler_bar0
.tipo_nvidia:
    mov     dword [rel gpu_info + GPUInfo.tipo], GPU_TIPO_NVIDIA
    jmp     .ler_bar0
.tipo_virtio:
    mov     dword [rel gpu_info + GPUInfo.tipo], GPU_TIPO_VIRTIO
    jmp     .ler_bar0
.tipo_vesa:
    mov     dword [rel gpu_info + GPUInfo.tipo], GPU_TIPO_VESA_GEN

.ler_bar0:
    ; Lê BAR0 (Offset 0x10) e trata BAR 64-bit se bit [2:1] == 10b
    mov     rdx, r12
    mov     rsi, r13
    mov     rdi, r14
    mov     ecx, PCI_BAR0_OFFSET
    call    pci_ler_config32

    mov     r11d, eax
    and     r11d, 0xFFFFFFF0        ; Limpa flags inferiores do BAR0
    mov     [rel gpu_info + GPUInfo.bar0_fisico], r11

    and     eax, 0x06
    cmp     eax, 0x04               ; BAR de 64 bits?
    jne     .ativar

    mov     rdx, r12
    mov     rsi, r13
    mov     rdi, r14
    mov     ecx, PCI_BAR1_OFFSET
    call    pci_ler_config32
    shl     rax, 32
    or      [rel gpu_info + GPUInfo.bar0_fisico], rax

.ativar:
    call    pci_gpu_ativar_mmio
    mov     rax, 1

.fim:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ==========================================
; ✅ ATIVAR MMIO + BUS MASTER NO PCI COMMAND
; ==========================================
pci_gpu_ativar_mmio:
    cmp     byte [rel gpu_info + GPUInfo.presente], 0
    je      .sem_gpu

    movzx   rdx, byte [rel gpu_info + GPUInfo.bus]
    movzx   rsi, byte [rel gpu_info + GPUInfo.dev]
    movzx   rdi, byte [rel gpu_info + GPUInfo.func]
    mov     ecx, PCI_CMD_REG
    call    pci_ler_config32

    or      eax, PCI_CMD_MEM_SPACE | PCI_CMD_BUS_MASTER
    mov     r9d, eax

    movzx   rdx, byte [rel gpu_info + GPUInfo.bus]
    movzx   rsi, byte [rel gpu_info + GPUInfo.dev]
    movzx   rdi, byte [rel gpu_info + GPUInfo.func]
    mov     ecx, PCI_CMD_REG
    call    pci_escrever_config32

    mov     byte [rel pci_mmio_mapeado], 1
    mov     rax, 1
    ret

.sem_gpu:
    mov     byte [rel pci_mmio_mapeado], 0
    xor     rax, rax
    ret

; ==========================================
; 🗺️ MAPEAR BARRAMENTOS (COMPATIBILIDADE)
; ==========================================
pci_gpu_mapear_barramentos:
    call    pci_gpu_varrer_barramento
    ret

; ==========================================
; 📤 RETORNAR DADOS PARA DRIVERS / C
; Layout da struct de saída (24 bytes):
;   [rdi + 0]  = presente (uint8_t) + padding
;   [rdi + 4]  = tipo (uint32_t: INTEL=1, AMD=2, NVIDIA=3, VIRTIO=4, VESA=5)
;   [rdi + 8]  = bar0_fisico (uint64_t)
;   [rdi + 16] = vendedor (uint16_t)
;   [rdi + 18] = dispositivo (uint16_t)
; ==========================================
pci_gpu_obter_info:
    movzx   eax, byte [rel gpu_info + GPUInfo.presente]
    mov     [rdi + 0], eax
    mov     eax, [rel gpu_info + GPUInfo.tipo]
    mov     [rdi + 4], eax
    mov     rax, [rel gpu_info + GPUInfo.bar0_fisico]
    mov     [rdi + 8], rax
    mov     ax,  [rel gpu_info + GPUInfo.vendedor]
    mov     [rdi + 16], ax
    mov     ax,  [rel gpu_info + GPUInfo.dispositivo]
    mov     [rdi + 18], ax
    ret

; ==========================================
; 📊 STATUS DO BARRAMENTO GPU
; Retorno: bit 0 = gpu_presente, bit 1 = mmio_ativo
; ==========================================
pci_gpu_ler_status:
    xor     rax, rax
    mov     al, [rel pci_mmio_mapeado]
    shl     al, 1
    or      al, [rel gpu_info + GPUInfo.presente]
    ret
