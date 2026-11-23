; ==================================================
; FydelisTechOS — Interface Disco para Convidado
; Permite que a VM acesse arquivos por VMCALL/VMMCALL
; ==================================================
bits 64

; Funções externas do sistema de arquivos
extern fs_criar_arquivo
extern fs_ler_arquivo
extern fs_buscar_arquivo

; Códigos de chamada
VMCALL_DISCO_CRIAR   equ 10
VMCALL_DISCO_LER     equ 11
VMCALL_DISCO_LISTAR   equ 12

section .text
global vm_disco_tratar_chamada

; ─────────────────────────────────────
; Tratar solicitação de acesso a disco da VM
; Entrada: registradores do convidado
; Saída: resultado devolvido para a VM
; ─────────────────────────────────────
vm_disco_tratar_chamada:
    ; rbx = código da chamada
    ; rcx = nome do arquivo
    ; rdx = buffer/dados
    ; rsi = tamanho

    cmp  rbx, VMCALL_DISCO_CRIAR
    je   .criar

    cmp  rbx, VMCALL_DISCO_LER
    je   .ler

    cmp  rbx, VMCALL_DISCO_LISTAR
    je   .listar

    xor  rax, rax
    ret

.criar:
    mov  rsi, rcx                  ; Nome
    mov  rdi, rdx                  ; Dados
    mov  rdx, rsi                  ; Tamanho
    call fs_criar_arquivo
    ret

.ler:
    mov  rsi, rcx                  ; Nome
    mov  rdi, rdx                  ; Buffer
    call fs_ler_arquivo
    ret

.listar:
    ; Implementar lista de arquivos
    mov  rax, 1
    ret