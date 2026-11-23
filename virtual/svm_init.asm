; ==================================================
; FydelisTechOS — Suporte AMD-V / SVM v2.2
; Arquitetura: x86_64 | Sintaxe: NASM
; ==================================================
bits 64
align 4096

; ========== Offsets VMCB — Manual AMD Volume 2 ==========
VMCB_CTRL            equ 0x000   ; Área de controle
VMCB_STATE           equ 0x400   ; Área de salvamento

; Controle — Interceptações
VMCB_INTCPT_CR_READ  equ 0x000
VMCB_INTCPT_CR_WRITE equ 0x002
VMCB_INTCPT_EXCEPT   equ 0x008
VMCB_EXIT_REASON     equ 0x070
VMCB_EXIT_INFO1      equ 0x078
VMCB_EXIT_INFO2      equ 0x080
VMCB_N_CR3           equ 0x110
VMCB_NP_ENABLE       equ 0x120   ; Tabelas aninhadas ativadas

; Estado do convidado (Save Area)
VMCB_GUEST_RAX       equ 0x400
VMCB_GUEST_RCX       equ 0x408
VMCB_GUEST_RDX       equ 0x410
VMCB_GUEST_RBX       equ 0x418
VMCB_GUEST_RSP       equ 0x420
VMCB_GUEST_RBP       equ 0x428
VMCB_GUEST_RSI       equ 0x430
VMCB_GUEST_RDI       equ 0x438
VMCB_GUEST_R8        equ 0x440
VMCB_GUEST_R9        equ 0x448
VMCB_GUEST_R10       equ 0x450
VMCB_GUEST_R11       equ 0x458
VMCB_GUEST_R12       equ 0x460
VMCB_GUEST_R13       equ 0x468
VMCB_GUEST_R14       equ 0x470
VMCB_GUEST_R15       equ 0x478
VMCB_GUEST_RIP       equ 0x4F8
VMCB_GUEST_RFLAGS    equ 0x500
VMCB_GUEST_CR0       equ 0x508
VMCB_GUEST_CR3       equ 0x518
VMCB_GUEST_CR4       equ 0x520

; MSRs importantes
MSR_EFER             equ 0xC0000080
MSR_VM_HSAVE_PA      equ 0xC0010117
EFER_SVME            equ 0x00001000  ; Bit de ativação SVM

; ========== Dados ==========
section .bss
align 4096
global vmcb
global host_save_area

vmcb:               resb 4096   ; Bloco de Controle de Máquina Virtual
host_save_area:    resb 4096   ; Área de salvamento do hospedeiro
svm_active:         resq 1      ; Flag: SVM ligado?

section .text

; ==================================================
; Passo 1 — Ativar SVM no processador
; ==================================================
global svm_initialize
svm_initialize:
    ; 1. Verificar suporte da CPU (já confirmado com detect_svm_support)

    ; 2. Ativar SVM no EFER (MSR)
    mov  ecx, MSR_EFER
    rdmsr
    or   eax, EFER_SVME
    wrmsr

    ; 3. Apontar área de salvamento do hospedeiro
    ; O CPU salva o estado aqui ao entrar/ sair da VM
    mov  rax, host_save_area
    mov  ecx, MSR_VM_HSAVE_PA
    wrmsr

    mov  qword [svm_active], 1
    mov  rax, 1        ; ✅ SVM ativado
    ret

; ==================================================
; Passo 2 — Inicializar VMCB
; ==================================================
global vmcb_setup
vmcb_setup:
    ; Limpar todo o VMCB
    mov  rdi, vmcb
    mov  rcx, 512
    xor  rax, rax
    rep stosq

    ; ── Configurar interceptações ──
    ; Por padrão, NÃO interceptar nada (convidado roda livre)
    mov  word [vmcb + VMCB_INTCPT_CR_READ], 0
    mov  word [vmcb + VMCB_INTCPT_CR_WRITE], 0
    mov  dword [vmcb + VMCB_INTCPT_EXCEPT], 0

    ; ── Estado do convidado ──
    ; CR0: modo protegido + paginação
    mov  qword [vmcb + VMCB_GUEST_CR0], 0x80000011  ; PG + PE
    ; CR4: PAE obrigatório para modo longo
    mov  qword [vmcb + VMCB_GUEST_CR4], 0x00000200
    ; RFLAGS: padrão
    mov  qword [vmcb + VMCB_GUEST_RFLAGS], 0x00000002

    ; Pilha do convidado
    mov  rax, vm_guest_stack + 8192
    mov  qword [vmcb + VMCB_GUEST_RSP], rax

    ret

; ==================================================
; Passo 3 — Executar a VM (VMRUN)
; ==================================================
global svm_launch
svm_launch:
    ; Salvar contexto do hospedeiro
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Carregar endereço de entrada do convidado no RIP
    mov  rax, [vm_guest_rip]
    mov  qword [vmcb + VMCB_GUEST_RIP], rax

    ; Carregar CR3 do convidado
    mov  rax, [vm_guest_cr3]
    test rax, rax
    jnz  .usar_cr3
    mov  rax, pml4_table         ; Reutiliza do kernel
.usar_cr3:
    mov  qword [vmcb + VMCB_GUEST_CR3], rax

    ; ⚡ VMRUN — Salta para o convidado!
    mov  rax, vmcb
    vmrun

    ; ─────────────────────────────────────────────
    ; Volta aqui após #VMEXIT
    ; ─────────────────────────────────────────────
    ; Ler motivo da saída
    mov  rax, [vmcb + VMCB_EXIT_REASON]
    mov  rdx, rax                ; Código em rdx

    ; Códigos comuns:
    ; 0 = inválido | 1 = instrução interceptada | 2 = NMI | ...
    ; 0x81 = VMMCALL (chamada do convidado)

    cmp  rax, 0
    je   .falha

    mov  rax, 1                  ; ✅ Sucesso (saiu controladamente)
    jmp  .fim

.falha:
    xor  rax, rax

.fim:
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    ret

; ==================================================
; Passo 4 — Desativar SVM
; ==================================================
global svm_exit
svm_exit:
    mov  ecx, MSR_EFER
    rdmsr
    and  eax, ~EFER_SVME
    wrmsr
    mov  qword [svm_active], 0
    ret

; ========== Reutilizar funções de memória ==========
; vm_load_guest permanece igual — só copia código
extern vm_load_guest
extern vm_guest_rip
extern vm_guest_cr3
extern vm_guest_stack
extern pml4_table