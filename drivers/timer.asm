; ==========================================
; TIMER.ASM — PIT / APIC Timer
; Fonte de Tempo para Escalonador Preemptivo
; FydelisTech OS v2.0 · Salvador • Bahia 🇧🇷
; ==========================================
bits 64

; Portas do PIT 8253/8254
PIT_CH0_DATA   equ 0x40
PIT_CH1_DATA   equ 0x41
PIT_CH2_DATA   equ 0x42
PIT_CMD        equ 0x43

; Frequência base do PIT
PIT_FREQ_BASE  equ 1193182

; Registradores do APIC Timer
APIC_TIMER_INIT   equ 0x380
APIC_TIMER_CURR   equ 0x390
APIC_TIMER_DIV    equ 0x3E0
APIC_LVT_TIMER    equ 0x320

section .bss
align 8
ticks_contador: resq 1
ticks_por_segundo: resd 1
usar_apic_timer:   resd 1
apic_base_virtual: resq 1

extern apic_is_disponivel
extern scheduler_tick

section .text
global timer_inicializar
global timer_ler_ticks
global timer_esperar_ms
global timer_por_segundo

; ==========================================
; ⏱️ DETECTAR E INICIALIZAR MELHOR TIMER
; ==========================================
timer_inicializar:
    mov dword [ticks_por_segundo], 100   ; Padrão: 100 Hz = 10ms por tick
    mov qword [ticks_contador], 0

    call apic_is_disponivel
    test rax, rax
    jz .usar_pit

    ; ✅ APIC Timer disponível — mais preciso
    mov dword [usar_apic_timer], 1
    mov rax, 0xFEE00000                   ; Endereço físico do APIC
    mov [apic_base_virtual], rax

    ; Configurar divisor (16 = /16)
    mov rdi, [apic_base_virtual]
    mov dword [rdi + APIC_TIMER_DIV], 2

    ; Calcular contagem para 100Hz
    ; Frequência APIC = Ônibus / 2 → definimos valor inicial
    mov dword [rdi + APIC_LVT_TIMER], (32 << 16) | 32   ; Vetor 32, Periódico
    mov dword [rdi + APIC_TIMER_INIT], 100000            ; Ajustar conforme hardware

    jmp .pronto

.usar_pit:
    ; ⏱️ Fallback — PIT legado
    mov dword [usar_apic_timer], 0

    ; Configurar PIT Canal 0 — Modo 2 (Periódico)
    mov al, 00110100b
    out PIT_CMD, al

    ; Calcular divisor para ~100 Hz
    mov eax, PIT_FREQ_BASE / 100
    out PIT_CH0_DATA, al
    mov al, ah
    out PIT_CH0_DATA, al

.pronto:
    ret

; ==========================================
; 🔔 CHAMADO A CADA INTERRUPÇÃO DO TEMPORIZADOR
; ==========================================
global timer_isr
timer_isr:
    push rax

    inc qword [ticks_contador]

    ; Notificar escalonador para possível troca
    call scheduler_tick

    ; Reconhecer interrupção
    cmp dword [usar_apic_timer], 0
    je .eoi_pit
    extern apic_eoi
    call apic_eoi
    jmp .fim
.eoi_pit:
    mov al, 0x20
    out 0x20, al
.fim:
    pop rax
    iretq

; ==========================================
; 📄 LER CONTADOR DE TICKS
; ==========================================
timer_ler_ticks:
    mov rax, [ticks_contador]
    ret

; ==========================================
; ⏳ ESPERAR N MILISSEGUNDOS
; ==========================================
timer_esperar_ms:
    ; rdi = milissegundos
    push rbx
    mov rbx, rdi
    mov rax, [ticks_contador]
    mov rdx, rbx
    shr rdx, 4                  ; ms → ticks (10ms = 1 tick)
    add rdx, rax
.esperar:
    cmp [ticks_contador], rdx
    jb .esperar
    pop rbx
    ret

; ==========================================
; RETORNAR FREQUÊNCIA CONFIGURADA
; ==========================================
timer_por_segundo:
    mov eax, [ticks_por_segundo]
    ret