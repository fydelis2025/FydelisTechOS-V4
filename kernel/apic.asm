; ==========================================
; APIC — Local APIC + I/O APIC (x86_64)
; Substitui o PIC 8259A herdado (Unificado em kernel/apic.asm)
; FydelisTech OS • Salvador - Bahia
; ==========================================
bits 64
default rel

; Registros MMIO do Local APIC (Base 0xFEE00000)
APIC_ID      equ 0x020
APIC_VERSION equ 0x030
APIC_TPR     equ 0x080
APIC_EOI     equ 0x0B0
APIC_SVR     equ 0x0F0
APIC_ICR_LOW equ 0x300
APIC_ICR_HI  equ 0x310

APIC_BASE    equ 0xFEE00000
IOAPIC_BASE  equ 0xFEC00000

; Registros indiretos do I/O APIC
IOAPIC_REGSEL equ 0x00
IOAPIC_WIN    equ 0x10
IOAPIC_REDTBL equ 0x10

section .bss
align 4
apic_ok: resd 1

section .text
global apic_detect
global apic_is_disponivel
global apic_get_ok
global apic_inicializar
global interrupts_init
global apic_eoi
global apic_enviar_eoi
global ioapic_redirecionar_irq

; ==========================================
; DETECTAR SE LOCAL APIC EXISTE (CPUID + MSR)
; Retorno: RAX = 1 (suportado), 0 (ausente)
; ==========================================
apic_is_disponivel:
apic_detect:
    push rbx

    mov eax, 1
    cpuid
    bt edx, 9                   ; Bit 9 de EDX = CPU suporta APIC on-chip
    jnc .nao_existe

    mov ecx, 0x1B               ; MSR IA32_APIC_BASE
    rdmsr
    bt eax, 11                  ; Bit 11 de EAX = APIC Global Enable
    jnc .nao_existe

    mov rax, 1
    pop rbx
    ret

.nao_existe:
    xor rax, rax
    pop rbx
    ret

; ==========================================
; RETORNA STATUS DO APIC (1 = ativo, 0 = inativo)
; ==========================================
apic_get_ok:
    mov eax, [rel apic_ok]
    ret

; ==========================================
; ROTEAMENTO DE IRQ NO I/O APIC
; EDI = numero da IRQ/GSI (ex: 1=teclado, 2=PIT timer, 12=mouse)
; ESI = vetor na IDT (ex: 32, 33, 44)
; ==========================================
ioapic_redirecionar_irq:
ioapic_mapear_irq:
    mov r8, IOAPIC_BASE

    ; Calcula indice da tabela de redirecionamento: 0x10 + (irq * 2)
    mov eax, edi
    shl eax, 1
    add eax, IOAPIC_REDTBL

    ; Parte baixa (32 bits): vetor IDT, Fixed Delivery, Active High, Edge, Unmasked
    mov dword [r8 + IOAPIC_REGSEL], eax
    mov dword [r8 + IOAPIC_WIN], esi

    ; Parte alta (32 bits): APIC ID destino = 0 (BSP / CPU 0)
    inc eax
    mov dword [r8 + IOAPIC_REGSEL], eax
    mov dword [r8 + IOAPIC_WIN], 0

    mov rax, 1
    ret

; ==========================================
; INICIALIZAR — Desligar PIC 8259A, Ligar Local APIC + I/O APIC
; ==========================================
interrupts_init:
apic_inicializar:
    ; 1 — Remapear e mascarar completamente o PIC 8259A herdado
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al

    mov al, 0xFF                ; Mascara todas as IRQs no PIC legado
    out 0xA1, al
    out 0x21, al

    ; 2 — Garantir Local APIC ativado no MSR 0x1B (Base 0xFEE00000 + Bit 11)
    mov ecx, 0x1B
    rdmsr
    and eax, 0x00000FFF         ; Preserva flags inferiores (BSP bit 8, etc.)
    or  eax, APIC_BASE | (1 << 11)
    xor edx, edx
    wrmsr

    ; 3 — Configurar Local APIC via MMIO real (0xFEE00000)
    mov r8, APIC_BASE
    mov dword [r8 + APIC_TPR], 0            ; Prioridade 0: aceita todas as IRQs
    mov dword [r8 + APIC_SVR], 0x100 | 0xFF ; Bit 8 (0x100) = Enable + Vetor Espurio 0xFF

    ; 4 — Configurar I/O APIC para dispositivos PS/2 e Timer PIT
    ; Nota: No I/O APIC padrao PC/QEMU, o PIT IRQ0 chega no pino GSI 2
    mov edi, 2                  ; GSI 2 (Timer PIT)
    mov esi, 32                 ; Vetor 32 da IDT
    call ioapic_mapear_irq

    mov edi, 1                  ; GSI 1 (Teclado PS/2)
    mov esi, 33                 ; Vetor 33 da IDT
    call ioapic_mapear_irq

    mov edi, 12                 ; GSI 12 (Mouse PS/2)
    mov esi, 44                 ; Vetor 44 da IDT
    call ioapic_mapear_irq

    mov dword [rel apic_ok], 1

    ; Limpa qualquer EOI pendente
    call apic_eoi
    ret

; ==========================================
; FIM DE INTERRUPCAO — Avisar Local APIC
; ==========================================
apic_enviar_eoi:
apic_eoi:
    mov r8, APIC_BASE
    mov dword [r8 + APIC_EOI], 0
    ret
