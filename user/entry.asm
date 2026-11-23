; ==================================================
; FydelisTechOS — Módulo Usuário: Ponto de Entrada
; Roda em nível 3 (usuário), sem privilégios diretos
; ==================================================
bits 64
section .text
extern fydelterm_main

global _user_start
_user_start:
    ; rdi = argumento do kernel (se houver)
    ; rsi = ponteiro para tabela de chamadas
    ; Inicializar tabela de syscalls
    mov [rel syscall_table_ptr], rsi

    ; Chamar o terminal principal
    call fydelterm_main

    ; Se retornar, encerrar
    mov rdi, rax
    call usuario_exit

; ── Encerramento limpo ──
global usuario_exit
usuario_exit:
    mov rax, SYS_PROCESS_EXIT
    syscall
.hang:
    hlt
    jmp .hang

section .data
align 8
syscall_table_ptr: dq 0

%include "syscalls/user_syscalls.inc"
