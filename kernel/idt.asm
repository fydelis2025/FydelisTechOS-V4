; ============================================================================
; IDT.ASM — Tabela Completa de 32 Excecoes + IRQ0 (Timer) + IRQ1 (Teclado) + IRQ12 (Mouse)
; FydelisTech OS v4.2 — Conectado ao APIC, Kernel Panic & FydLog
; Salvador - Bahia
; ============================================================================
bits 64
default rel

IDT_ENTRIES equ 256
CODE_SEG_64 equ 0x08            ; Seletor Kernel Code 64-bit conforme gdt.asm (indice 1 * 8)

section .data
align 8
idt_ptr:
    dw IDT_ENTRIES * 16 - 1     ; Limite
    dq 0                        ; Endereco base (preenchido no idt_init)

section .bss
align 16
idt_table:
    resb IDT_ENTRIES * 16

section .text
global idt_init
extern kernel_panic_handler     ; Handler visual e de log em kernel/panic.c
extern apic_eoi                 ; EOI do Local APIC em kernel/apic.asm

; ============================================================================
; STUBS DE IRQ DO APIC (Preservam todos os registradores volateis System V)
; ============================================================================
%macro IRQ_APIC_STUB 1
%1:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    call apic_eoi

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    iretq
%endmacro

; Stub de Timer (IRQ0 / GSI 2 - Vetor 32): acorda o HLT e envia EOI ao APIC
IRQ_APIC_STUB irq0_timer_stub

; Stub de Teclado PS/2 (IRQ1 - Vetor 33): acorda o HLT sem consumir porta 0x60
IRQ_APIC_STUB keyboard_stub

; Stub de Mouse PS/2 (IRQ12 - Vetor 44): acorda o HLT e envia EOI ao APIC
IRQ_APIC_STUB irq12_mouse_stub

; Stub para interrupcao espuria do APIC (Vetor 0xFF - NAO envia EOI)
irq_espuria_stub:
    iretq

; ============================================================================
; MACROS — Gerar Stubs de Excecao x86_64
; ============================================================================
%macro ISR_SEM_ERRO 1
global isr%1
isr%1:
    push qword 0                ; Codigo de erro ficticio
    push qword %1               ; Numero do vetor
    jmp isr_comum
%endmacro

%macro ISR_COM_ERRO 1
global isr%1
isr%1:
    ; CPU ja empilhou o codigo de erro
    push qword %1               ; Numero do vetor
    jmp isr_comum
%endmacro

; ============================================================================
; 32 EXCECOES DA CPU (Conforme Manual Intel/AMD x86_64)
; ============================================================================
ISR_SEM_ERRO 0   ; #DE — Divisao por Zero
ISR_SEM_ERRO 1   ; #DB — Depuracao
ISR_SEM_ERRO 2   ; — Interrupcao NMI
ISR_SEM_ERRO 3   ; #BP — Ponto de Parada
ISR_SEM_ERRO 4   ; #OF — Estouro
ISR_SEM_ERRO 5   ; #BR — Limite Excedido
ISR_SEM_ERRO 6   ; #UD — Instrucao Invalida
ISR_SEM_ERRO 7   ; #NM — Coprocessador Indisponivel
ISR_COM_ERRO 8   ; #DF — Falha Dupla
ISR_SEM_ERRO 9   ; — Reservado
ISR_COM_ERRO 10  ; #TS — Seletor Invalido
ISR_COM_ERRO 11  ; #NP — Segmento Nao Presente
ISR_COM_ERRO 12  ; #SS — Falha de Pilha
ISR_COM_ERRO 13  ; #GP — Protecao Geral
ISR_COM_ERRO 14  ; #PF — Falha de Pagina
ISR_SEM_ERRO 15  ; — Reservado
ISR_SEM_ERRO 16  ; #MF — Erro de Matematica
ISR_COM_ERRO 17  ; #AC — Verificacao de Alinhamento
ISR_SEM_ERRO 18  ; #MC — Erro de Maquina
ISR_SEM_ERRO 19  ; #XF — Excecao SIMD
ISR_SEM_ERRO 20
ISR_SEM_ERRO 21
ISR_SEM_ERRO 22
ISR_SEM_ERRO 23
ISR_SEM_ERRO 24
ISR_SEM_ERRO 25
ISR_SEM_ERRO 26
ISR_SEM_ERRO 27
ISR_SEM_ERRO 28
ISR_SEM_ERRO 29
ISR_SEM_ERRO 30
ISR_SEM_ERRO 31

; ============================================================================
; TRATADOR COMUM — Captura contexto da CPU e chama kernel_panic_handler
; ============================================================================
isr_comum:
    cli

    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    push rbp
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    push rax

    mov rdi, [rsp + 120]        ; RDI = vetor_id
    mov rsi, [rsp + 128]        ; RSI = error_code
    mov rdx, [rsp + 136]        ; RDX = rip
    mov rcx, cr2                ; RCX = cr2
    mov r8,  [rsp + 160]        ; R8  = rsp_original
    mov r9,  rsp                ; R9  = ponteiro para dump de registradores (antes do alinhamento)

    ; Garante RSP alinhado a 16 bytes antes do CALL (System V ABI)
    sub rsp, 8
    and rsp, -16
    call kernel_panic_handler

.halt_eterno:
    cli
    hlt
    jmp .halt_eterno

; ============================================================================
; INICIALIZACAO DA IDT
; ============================================================================
idt_init:
    push rbx
    push rsi
    push r12

    xor rcx, rcx
.loop:
    cmp rcx, 32
    jl .carrega_excecao

    cmp rcx, 32
    je .carrega_timer

    cmp rcx, 33
    je .carrega_teclado

    cmp rcx, 44
    je .carrega_mouse

    cmp rcx, 255
    je .carrega_espuria

    xor rdx, rdx
    jmp .escreve_entrada

.carrega_excecao:
    lea rsi, [rel isr_vetor]
    mov rdx, [rsi + rcx * 8]
    jmp .escreve_entrada

.carrega_timer:
    lea rdx, [rel irq0_timer_stub]
    jmp .escreve_entrada

.carrega_teclado:
    lea rdx, [rel keyboard_stub]
    jmp .escreve_entrada

.carrega_mouse:
    lea rdx, [rel irq12_mouse_stub]
    jmp .escreve_entrada

.carrega_espuria:
    lea rdx, [rel irq_espuria_stub]
    jmp .escreve_entrada

.escreve_entrada:
    lea rax, [rel idt_table]
    mov rbx, rcx
    shl rbx, 4
    add rax, rbx

    test rdx, rdx
    jz .entrada_nula

    mov word [rax], dx
    mov word [rax + 2], CODE_SEG_64
    mov byte [rax + 4], 0
    mov byte [rax + 5], 0x8E    ; Presente, Ring 0, Interrupt Gate 64-bit

    shr rdx, 16
    mov word [rax + 6], dx

    shr rdx, 16
    mov dword [rax + 8], edx
    mov dword [rax + 12], 0
    jmp .proximo

.entrada_nula:
    mov qword [rax], 0
    mov qword [rax + 8], 0

.proximo:
    inc rcx
    cmp rcx, IDT_ENTRIES
    jl .loop

    lea rax, [rel idt_table]
    mov qword [rel idt_ptr + 2], rax
    lidt [rel idt_ptr]

    pop r12
    pop rsi
    pop rbx
    ret

section .rodata
align 8
isr_vetor:
    dq isr0,  isr1,  isr2,  isr3,  isr4,  isr5,  isr6,  isr7
    dq isr8,  isr9,  isr10, isr11, isr12, isr13, isr14, isr15
    dq isr16, isr17, isr18, isr19, isr20, isr21, isr22, isr23
    dq isr24, isr25, isr26, isr27, isr28, isr29, isr30, isr31
