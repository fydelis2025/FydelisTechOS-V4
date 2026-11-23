; ==========================================
; STUBS DE SUPORTE PARA O KERNEL — FydelisTechOS
; Agrupa funções auxiliares e stubs pendentes
; ==========================================
bits 64

section .text
; E/S e Console
global console_write
global console_read
global console_setcolor
console_write:
console_read:
console_setcolor:
    mov rax, 1
    ret

; Processos
global processo_exit
global processo_spawn
global processo_getpid
processo_exit:
processo_spawn:
processo_getpid:
    xor rax, rax
    ret

; Memória de Usuário e Alocação
global mem_alocar_usuario
global mem_liberar_usuario
global gerenciador_alocar
mem_alocar_usuario:
mem_liberar_usuario:
gerenciador_alocar:
    xor rax, rax
    ret

; Virtualização e Estados
global vm_inicializar
global vmx_ativo
global svm_ativo
global vmx_launch
global vm_guest_stack
global vm_guest_cr3
global escrever_tela_vm
global tratar_falha_pagina
global pilha_usuario_top
global init_entry
vm_inicializar:
vmx_launch:
escrever_tela_vm:
tratar_falha_pagina:
    xor rax, rax
    ret

section .data
vmx_ativo:         db 0
svm_ativo:         db 0
vm_guest_stack:    dq 0
vm_guest_cr3:      dq 0
pilha_usuario_top: dq 0x7FFFFFFF0000
init_entry:        dq 0x400000

section .text
; Depuração e Utilitários
global print_hex
print_hex:
    ret
