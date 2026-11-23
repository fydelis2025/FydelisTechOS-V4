; ==================================================
; Código Convidado — Roda ISOLADO dentro da VM
; Usa VMCALL/VMMCALL para pedir serviços ao hospedeiro
; ==================================================
bits 64

; Números das chamadas
VMCALL_ESCREVER_TELA  equ 1
VMCALL_SAIR           equ 3

section .data
mensagem db 'FydelisVM rodando!', 0

section .text
global _start_convidado

_start_convidado:
    ; ── Escrever mensagem na tela ──
    mov  rax, VMCALL_ESCREVER_TELA
    mov  rsi, mensagem        ; Ponteiro para texto
    mov  rdi, 0x0F            ; Cor: branco/preto
    vmmcall                    ; Ou VMCALL para Intel

    ; ── Fazer algo ──
    mov  rcx, 100000000
.delay:
    pause
    dec  rcx
    jnz  .delay

    ; ── Sair da VM ──
    mov  rax, VMCALL_SAIR
    vmmcall

    ; Nunca chega aqui
    hlt