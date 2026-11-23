; ==================================================
; FydelisTechOS — Tratador #VMEXIT (AMD-V / SVM)
; Complementa svm_init.asm
; ==================================================
bits 64

; Offsets VMCB (reutilizados)
VMCB_EXIT_REASON     equ 0x070
VMCB_EXIT_INFO1      equ 0x078
VMCB_EXIT_INFO2      equ 0x080
VMCB_GUEST_RAX       equ 0x400
VMCB_GUEST_RIP       equ 0x4F8
VMCB_GUEST_RSP       equ 0x420
VMCB_GUEST_RFLAGS    equ 0x500

; Códigos de saída AMD
SVM_EXIT_CPUID       equ 0x72
SVM_EXIT_VMMCALL     equ 0x81
SVM_EXIT_NMI         equ 0x02
SVM_EXIT_IO          equ 0x0B
SVM_EXIT_MSR         equ 0x0C
SVM_EXIT_PF          equ 0x1E

section .text
global svm_handle_exit

; ─────────────────────────────────────
; Processar saída da VM (AMD)
; Retorno: rax = 1 → continuar, 0 → encerrar
; ─────────────────────────────────────
svm_handle_exit:
    push rdi
    push rsi
    push rbx

    ; Ler motivo
    mov  rdx, [vmcb + VMCB_EXIT_REASON]

    cmp  rdx, SVM_EXIT_VMMCALL
    je   .chamada_sistema

    cmp  rdx, SVM_EXIT_CPUID
    je   .instrucao_cpuid

    cmp  rdx, SVM_EXIT_PF
    je   .falha_pagina

    cmp  rdx, SVM_EXIT_IO
    je   .acesso_io

    ; Padrão: continuar
    jmp  .continuar

; ═══ VMMCALL — Chamada do convidado ═══
.chamada_sistema:
    mov  rax, [vmcb + VMCB_GUEST_RAX]
    cmp  rax, 1
    je   .escrever_tela
    cmp  rax, 3
    je   .sair_vm
    jmp  .continuar

.escrever_tela:
    mov  rsi, [vmcb + 0x430]     ; RSI = mensagem
    mov  rdi, [vmcb + 0x438]     ; RDI = cor
    call escrever_tela_vm
    jmp  .continuar

.sair_vm:
    mov  rax, 0
    jmp  .fim

; ═══ CPUID ═══
.instrucao_cpuid:
    mov  eax, [vmcb + VMCB_GUEST_RAX]
    mov  ecx, [vmcb + 0x448]     ; RCX
    cpuid
    mov  [vmcb + VMCB_GUEST_RAX], rax
    mov  [vmcb + 0x410], rbx     ; RBX
    mov  [vmcb + 0x418], rcx     ; RCX
    mov  [vmcb + 0x420], rdx     ; RDX
    jmp  .avancar_rip

; ═══ Falha de Página ═══
.falha_pagina:
    mov  rsi, cr2
    mov  rdi, [vmcb + VMCB_EXIT_INFO1]
    call tratar_falha_pagina
    test rax, rax
    jnz  .continuar
    jmp  .erro

; ═══ Acesso a Porta de E/S ═══
.acesso_io:
    ; Porta de E/S — teclado, vídeo, disco...
    mov  rax, [vmcb + VMCB_EXIT_INFO1]
    ; Decodificar endereço e operação
    jmp  .continuar

.avancar_rip:
    ; Avançar ponteiro de instrução
    mov  rax, [vmcb + VMCB_GUEST_RIP]
    add  rax, 2
    mov  [vmcb + VMCB_GUEST_RIP], rax

.continuar:
    mov  rax, 1
    jmp  .fim

.erro:
    mov  rax, 0

.fim:
    pop  rbx
    pop  rsi
    pop  rdi
    ret

; Reutiliza as mesmas funções auxiliares do VT-x
extern escrever_tela_vm
extern tratar_falha_pagina
extern vmcb