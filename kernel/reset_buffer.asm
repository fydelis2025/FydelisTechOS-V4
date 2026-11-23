; ======================================
; reset_buffer — Prepara para nova linha
; ======================================
BITS 64
%include "fydelterm.inc"

extern buf_head, buf_tail, buffer
global reset_buffer

section .text
reset_buffer:
    push rdi
    push rcx

    mov qword [buf_head], 0
    mov qword [buf_tail], 0

    mov rdi, buffer
    mov rcx, BUFFER_SIZE
    xor rax, rax
    rep stosb

    pop rcx
    pop rdi
    ret
