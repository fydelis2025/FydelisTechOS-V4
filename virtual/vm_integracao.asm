; ==================================================
; Exemplo de uso completo no FydelisTechOS
; ==================================================
bits 64

; Importar todas as funções dos outros arquivos
extern init_virtual_memory
extern load_page_tables
extern detect_vmx_support
extern vmx_enter
extern vmx_exit
extern vmcs_init
extern vm_load_guest
extern vm_launch
extern vm_test_guest_code
extern vm_test_guest_len

global _start

_start:
    ; ── FASE 1: Preparar sistema ──
    call init_virtual_memory
    call load_page_tables

    ; ── FASE 2: Verificar virtualização ──
    call detect_vmx_support
    test rax, rax
    jz   .sem_vmx

    ; Ativar modo VMX
    call vmx_enter
    test rax, rax
    jz   .falha_vmx

    ; ── FASE 3: Preparar VM ──
    ; Carregar código de teste do convidado em 0x200000
    mov  rsi, vm_test_guest_code
    mov  rdi, 0x200000           ; Endereço de carga do convidado
    mov  rcx, vm_test_guest_len
    call vm_load_guest

    ; Inicializar VMCS com o código carregado
    call vmcs_init
    test rax, rax
    jz   .falha_vmcs

    ; ── FASE 4: Executar a VM! 🚀 ──
    call vm_launch
    test rax, rax
    jnz  .vm_sucesso

    ; Falha — rdx tem o código do motivo
    jmp  .fim

.vm_sucesso:
    ; A VM rodou e saiu com sucesso!
    ; O código de teste escreveu 'V' na tela
    call vmx_exit
    jmp  .fim

.sem_vmx:
    ; CPU não suporta VT-x — segue sem VM
    hlt

.falha_vmx:
    ; Ative VT-x na BIOS/UEFI
    hlt

.falha_vmcs:
    ; Configuração VMCS incorreta
    hlt

.fim:
    ; Ponto de parada — expanda daqui
    hlt