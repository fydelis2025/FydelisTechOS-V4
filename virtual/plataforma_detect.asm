; ==================================================
; FydelisTechOS — Detecção Automática da Plataforma
; Escolhe Intel VT-x OU AMD-V conforme a CPU
; ==================================================
bits 64

; Funções externas
extern detect_vmx_support
extern detect_svm_support
extern vmx_enter
extern vmx_exit
extern vmcs_init
extern vm_launch
extern svm_initialize
extern svm_exit
extern vmcb_setup
extern svm_launch
extern vm_load_guest
extern vm_test_guest_code
extern vm_test_guest_len

; Tipos de CPU detectada
CPU_INTEL_VMX  equ 1
CPU_AMD_SVM    equ 2
CPU_NONE       equ 0

section .data
global cpu_vendor
cpu_vendor:     dd 0
vmx_ativo:      db 0
svm_ativo:      db 0

section .text
global detectar_plataforma
global executar_vm

; ─────────────────────────────────────
; Detectar fabricante e suporte
; Retorna: rax = CPU_*
; ─────────────────────────────────────
detectar_plataforma:
    ; Ler vendor da CPU
    mov  eax, 0
    cpuid
    mov  [cpu_vendor], ebx
    mov  [cpu_vendor+4], edx
    mov  [cpu_vendor+8], ecx

    ; Testar Intel
    call detect_vmx_support
    test rax, rax
    jnz  .intel_vmx

    ; Testar AMD
    call detect_svm_support
    test rax, rax
    jnz  .amd_svm

    ; Nenhum suporte
    mov  rax, CPU_NONE
    ret

.intel_vmx:
    mov  byte [vmx_ativo], 1
    mov  rax, CPU_INTEL_VMX
    ret

.amd_svm:
    mov  byte [svm_ativo], 1
    mov  rax, CPU_AMD_SVM
    ret

; ─────────────────────────────────────
; Inicializar plataforma escolhida
; ─────────────────────────────────────
global inicializar_plataforma
inicializar_plataforma:
    mov  rax, [cpu_vendor]

    cmp  byte [vmx_ativo], 1
    je   .init_vmx

    cmp  byte [svm_ativo], 1
    je   .init_svm

    mov  rax, 0
    ret

.init_vmx:
    call vmx_enter
    test rax, rax
    jz   .falha
    call vmcs_init
    ret

.init_svm:
    call svm_initialize
    test rax, rax
    jz   .falha
    call vmcb_setup
    ret

.falha:
    xor  rax, rax
    ret

; ─────────────────────────────────────
; Executar VM na plataforma ativa
; ─────────────────────────────────────
executar_vm:
    cmp  byte [vmx_ativo], 1
    je   .rodar_vmx

    cmp  byte [svm_ativo], 1
    je   .rodar_svm

    mov  rax, 0
    ret

.rodar_vmx:
    call vm_launch
    ret

.rodar_svm:
    call svm_launch
    ret

; ─────────────────────────────────────
; Desligar plataforma
; ─────────────────────────────────────
global desligar_plataforma
desligar_plataforma:
    cmp  byte [vmx_ativo], 1
    je   .sair_vmx

    cmp  byte [svm_ativo], 1
    je   .sair_svm
    ret

.sair_vmx:
    call vmx_exit
    ret
.sair_svm:
    call svm_exit
    ret