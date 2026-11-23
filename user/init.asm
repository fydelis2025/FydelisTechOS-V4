; ==================================================
; FydelisTechOS — Processo Inicial do Usuário
; Primeiro processo carregado pelo kernel
; ==================================================
bits 64
extern _user_start

section .text
global _start_init
_start_init:
    ; rdi = estrutura de boot passada pelo kernel
    ; Configurar ambiente
    mov rsp, pilha_top

    ; Chamar o ponto de entrada principal
    call _user_start

    ; Nunca deve retornar
.hang:
    hlt
    jmp .hang

section .bss
align 16
pilha:
resb 8192
pilha_top: