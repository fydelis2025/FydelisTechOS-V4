; ============================================================================
; FydelisTech OS — Controle de Energia ACPI / APM / PS/2 (x86_64)
; Exporta apenas energia_reiniciar_agora e energia_desligar_agora para exec.c
; ============================================================================
[BITS 64]

section .text
global energia_reiniciar_agora
global energia_desligar_agora

; ----------------------------------------------------------------------------
; energia_reiniciar_agora: Reinicia a maquina via controlador PS/2 / Reset 0xCF9
; ----------------------------------------------------------------------------
energia_reiniciar_agora:
    cli

    ; 1. Tenta pulso de reset pelo controlador de teclado 8042 (porta 0x64)
    mov ecx, 0xFFFF
.espera_kbc:
    in al, 0x64
    test al, 0x02
    loopnz .espera_kbc
    mov al, 0xFE
    out 0x64, al

    ; 2. Fallback: Reset PCI System Control (porta 0xCF9)
    mov dx, 0x0CF9
    mov al, 0x02
    out dx, al
    mov al, 0x06
    out dx, al

.halt_reboot:
    hlt
    jmp .halt_reboot

; ----------------------------------------------------------------------------
; energia_desligar_agora: Desliga QEMU / Bochs / VirtualBox / ACPI
; ----------------------------------------------------------------------------
energia_desligar_agora:
    cli

    ; 1. QEMU moderno / Bochs (porta ACPI PM1a_CNT = 0x604, SLP_TYP=5 | SLP_EN)
    mov dx, 0x0604
    mov ax, 0x2000
    out dx, ax

    ; 2. QEMU antigo / Bochs legacy (porta 0xB004)
    mov dx, 0xB004
    mov ax, 0x2000
    out dx, ax

    ; 3. VirtualBox ACPI shutdown (porta 0x4004)
    mov dx, 0x4004
    mov ax, 0x3400
    out dx, ax

.halt_off:
    hlt
    jmp .halt_off
