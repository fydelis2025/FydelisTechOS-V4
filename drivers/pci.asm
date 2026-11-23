; ==========================================
; DRIVER PCI — FydelisTech OS (CORRIGIDO)
; ==========================================
BITS 64
%define BUILDING_PCI_DRIVER

%include "fydelterm.inc"

global pci_ler_dispositivo
global pci_ler_classe
global pci_ler_bar0

section .text

; ==========================================
; Lê configuração PCI básica (Vendor ID / Device ID)
; Entrada: RCX = Índice combinado (Bus: 8 bits | Dev: 5 bits | Func: 3 bits)
;          (Para Bus 0, dispositivos 0..31 e funções 0..7, basta iterar RCX de 0 a 255)
; Retorna: RAX = Vendor/Device ID (ou 0xFFFFFFFF se vazio)
; ==========================================
pci_ler_dispositivo:
    push    rdx

    ; Monta endereço CONFIG_ADDRESS:
    ; Bit 31 = 1 (Enable), Bits 23..8 = Bus/Dev/Func (RCX << 8), Offset = 0x00
    mov     rax, rcx
    and     eax, 0xFFFF
    shl     eax, 8
    or      eax, 0x80000000

    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax

    mov     dx, PCI_CONFIG_DATA
    in      eax, dx

    pop     rdx
    ret

; ==========================================
; Lê a classe do dispositivo PCI
; Entrada: RCX = Índice combinado (Bus/Dev/Func)
; Retorna: EAX = Class Code (31..24), Subclass (23..16), ProgIF (15..8), RevID (7..0)
; ==========================================
pci_ler_classe:
    push    rdx

    mov     rax, rcx
    and     eax, 0xFFFF
    shl     eax, 8
    or      eax, 0x80000008         ; Offset 0x08 = Revision ID / Class Code

    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax

    mov     dx, PCI_CONFIG_DATA
    in      eax, dx

    pop     rdx
    ret

; ==========================================
; Lê o BAR0 (Base Address Register 0)
; Entrada: RCX = Índice combinado (Bus/Dev/Func)
; Retorna: RAX = Endereço base limpo (MMIO 16-byte aligned ou I/O Port 4-byte aligned)
; ==========================================
pci_ler_bar0:
    push    rdx

    mov     rax, rcx
    and     eax, 0xFFFF
    shl     eax, 8
    or      eax, 0x80000010         ; Offset 0x10 = BAR0

    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax

    mov     dx, PCI_CONFIG_DATA
    in      eax, dx

    ; Verifica bit 0: 1 = Espaço de I/O (Áudio AC97), 0 = Espaço de Memória MMIO (E1000)
    test    eax, 1
    jnz     .bar_io

    and     eax, 0xFFFFFFF0         ; Limpa 4 bits de flags MMIO
    jmp     .fim

.bar_io:
    and     eax, 0xFFFFFFFC         ; Limpa 2 bits de flags I/O

.fim:
    mov     eax, eax                ; Zera os 32 bits superiores de RAX
    pop     rdx
    ret
