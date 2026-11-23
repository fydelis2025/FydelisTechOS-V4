; ==================================================
; Código Convidado — Acessa Disco Virtual
; Roda DENTRO da VM e pede serviços ao hospedeiro
; ==================================================
bits 64

; Chamadas de sistema
VMCALL_ESCREVER_TELA  equ 1
VMCALL_DISCO_CRIAR    equ 10
VMCALL_DISCO_LER       equ 11
VMCALL_SAIR            equ 3

section .data
arquivo_nome    db 'teste.txt', 0
arquivo_conteudo db 'Olá do FydelisVM!', 0
arquivo_lido    times 64 db 0

section .text
global _start_convidado

_start_convidado:
    ; ── 1. Criar arquivo no disco ──
    mov  rax, VMCALL_DISCO_CRIAR
    mov  rbx, arquivo_nome       ; Nome
    mov  rcx, arquivo_conteudo    ; Dados
    mov  rdx, 20                  ; Tamanho
    vmmcall                       ; ou VMCALL

    ; ── 2. Confirmar na tela ──
    mov  rax, VMCALL_ESCREVER_TELA
    mov  rsi, arquivo_nome
    mov  rdi, 0x0A                ; Verde
    vmmcall

    ; ── 3. Ler arquivo de volta ──
    mov  rax, VMCALL_DISCO_LER
    mov  rbx, arquivo_nome
    mov  rcx, arquivo_lido
    vmmcall

    ; ── 4. Exibir conteúdo lido ──
    mov  rax, VMCALL_ESCREVER_TELA
    mov  rsi, arquivo_lido
    mov  rdi, 0x0E                ; Amarelo
    vmmcall

    ; ── 5. Encerrar ──
    mov  rax, VMCALL_SAIR
    vmmcall