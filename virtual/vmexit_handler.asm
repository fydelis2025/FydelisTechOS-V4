; ==================================================
; FydelisTechOS — Tratador #VMEXIT (Intel VT-x)
; Processa eventos da VM e decide o que fazer
; ==================================================
bits 64

; Offsets VMCS (reutilizados)
VMCS_EXIT_REASON        equ 0x00004402
VMCS_EXIT_QUALIFICATION equ 0x00006400
VMCS_GUEST_RIP          equ 0x00006818
VMCS_GUEST_RSP          equ 0x0000681c
VMCS_GUEST_RFLAGS       equ 0x00006820
VMCS_IDT_VECTORING      equ 0x00004404

; Índices dos registradores convidados no VMCS
VMCS_GUEST_RAX          equ 0x6800
VMCS_GUEST_RBX          equ 0x6801
VMCS_GUEST_RCX          equ 0x6802
VMCS_GUEST_RDX          equ 0x6803
VMCS_GUEST_RSI          equ 0x6806
VMCS_GUEST_RDI          equ 0x6807

; Códigos de saída mais comuns
EXIT_EXCECAO_NMI        equ  2
EXIT_EXCECAO_INTERRUPCAO equ 3
EXIT_INSTRUCAO_CPUID    equ 10
EXIT_INSTRUCAO_RDTSC    equ 16
EXIT_ERRO_PAGINACAO     equ 28
EXIT_INSTRUCAO_VMCALL   equ 18
EXIT_INSTRUCAO_UD2      equ 46

; Funções externas do kernel / sistema de arquivos
extern fs_criar_arquivo
extern fs_ler_arquivo

section .text
global vmx_handle_exit

; ─────────────────────────────────────
; Processar saída da VM (Intel)
; Entrada: rdx = código do motivo de saída
; Retorno: rax = 1 → continuar VM, 0 → encerrar
; ─────────────────────────────────────
vmx_handle_exit:
    push rdi
    push rsi
    push rbx

    ; Ler motivo da saída com VMREAD seguro
    mov  rcx, VMCS_EXIT_REASON
    vmread rdx, rcx

    ; ── Analisar motivo ──
    cmp  rdx, EXIT_INSTRUCAO_UD2
    je   .solicitou_parada

    cmp  rdx, EXIT_INSTRUCAO_VMCALL
    je   .chamada_sistema

    cmp  rdx, EXIT_INSTRUCAO_CPUID
    je   .instrucao_cpuid

    cmp  rdx, EXIT_ERRO_PAGINACAO
    je   .falha_pagina

    cmp  rdx, EXIT_EXCECAO_INTERRUPCAO
    je   .interrupcao

    jmp  .erro_desconhecido

; ═══ Caso 1: Convidado pediu para parar ═══
.solicitou_parada:
    mov  rax, 0                  
    jmp  .fim

; ═══ Caso 2: Chamada do convidado para o hospedeiro ═══
.chamada_sistema:
    ; Ler RAX do convidado armazenado no VMCS
    mov  rcx, VMCS_GUEST_RAX
    vmread rax, rcx

    cmp  rax, 1
    je   .vmcall_escrever_tela
    cmp  rax, 10
    je   .disco_criar
    cmp  rax, 11
    je   .disco_ler
    cmp  rax, 3
    je   .vmcall_sair

    jmp  .continuar

.vmcall_escrever_tela:
    mov  rcx, VMCS_GUEST_RSI
    vmread rsi, rcx              
    mov  rcx, VMCS_GUEST_RDI
    vmread rdi, rcx              
    call escrever_tela_vm
    jmp  .continuar

.disco_criar:
    mov  rcx, VMCS_GUEST_RBX
    vmread rbx, rcx              
    mov  rcx, VMCS_GUEST_RCX
    vmread rcx, rcx              
    mov  rcx, VMCS_GUEST_RDX
    vmread rdx, rcx              
    call fs_criar_arquivo
    jmp  .continuar

.disco_ler:
    mov  rcx, VMCS_GUEST_RBX
    vmread rbx, rcx              
    mov  rcx, VMCS_GUEST_RCX
    vmread rcx, rcx              
    call fs_ler_arquivo
    mov  rcx, VMCS_GUEST_RAX
    vmwrite rcx, rax             
    jmp  .continuar

.vmcall_sair:
    mov  rax, 0
    jmp  .fim

; ═══ Caso 3: CPUID — emular instrução ═══
.instrucao_cpuid:
    mov  rcx, VMCS_GUEST_RAX
    vmread r8, rcx               
    mov  rcx, VMCS_GUEST_RBX
    vmread r9, rcx               
    mov  rcx, VMCS_GUEST_RSI
    vmread rsi, rcx              
    mov  rcx, VMCS_GUEST_RDI
    vmread rdi, rcx              

    mov  eax, r8d
    mov  ecx, edx
    cpuid

    mov  rcx, VMCS_GUEST_RAX
    vmwrite rcx, rax         
    mov  rcx, VMCS_GUEST_RBX
    vmwrite rcx, rbx         
    mov  rcx, VMCS_GUEST_RCX
    vmwrite rcx, rcx         
    mov  rcx, VMCS_GUEST_RDX
    vmwrite rcx, rdx         

    ; Avançar RIP
    mov  rcx, VMCS_GUEST_RIP
    vmread rax, rcx
    add  rax, 2                  
    vmwrite rcx, rax
    jmp  .continuar

; ═══ Caso 4: Falha de página ═══
.falha_pagina:
    mov  rcx, VMCS_EXIT_QUALIFICATION
    vmread rdi, rcx
    mov  rsi, cr2                
    call tratar_falha_pagina
    test rax, rax
    jz   .erro_mapeamento
    jmp  .continuar

; ═══ Caso 5: Interrupção ═══
.interrupcao:
    jmp  .continuar

.continuar:
    mov  rax, 1                  
    jmp  .fim

.erro_mapeamento:
.erro_desconhecido:
    mov  rax, 0                  

.fim:
    pop  rbx
    pop  rsi
    pop  rdi
    ret

; ── Funções auxiliares ──
escrever_tela_vm:
    mov  rcx, 80*25*2
    mov  rbx, 0xB8000
.loop:
    lodsb
    test al, al
    jz   .escrito
    mov  [rbx], al
    mov  [rbx+1], dil
    add  rbx, 2
    dec  rcx
    jnz  .loop
.escrito:
    ret

tratar_falha_pagina:
    mov  rax, 1
    ret
