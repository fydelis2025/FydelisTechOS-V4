; ==================================================
; FydelisTechOS — Wrappers de Chamada de Sistema
; Espaço de Usuário → Núcleo via instrução SYSCALL
; ==================================================
bits 64
%include "syscalls/user_syscalls.inc"
%include "syscalls/disktools_syscalls.inc"
%include "syscalls/virtual_syscalls.inc"
%include "syscalls/rede_syscalls.inc"
%include "syscalls/security_syscalls.inc"

section .text

; ══════════════════════════════════════════════════
; E/S — Tela e Console
; ══════════════════════════════════════════════════
global sys_write
sys_write:
    ; rdi = descritor, rsi = buffer, rdx = tamanho
    mov rax, SYS_IO_WRITE
    syscall
    ret

global sys_read
sys_read:
    mov rax, SYS_IO_READ
    syscall
    ret

global sys_setcolor
sys_setcolor:
    ; rdi = cor (0xFR)
    mov rax, SYS_IO_SETCOLOR
    syscall
    ret

; ══════════════════════════════════════════════════
; Processos
; ══════════════════════════════════════════════════
global sys_exit
sys_exit:
    mov rax, SYS_PROCESS_EXIT
    syscall
    ret

global sys_spawn
sys_spawn:
    ; rdi = ponteiro para código, rsi = tamanho
    mov rax, SYS_PROCESS_SPAWN
    syscall
    ret

; ══════════════════════════════════════════════════
; Memória
; ══════════════════════════════════════════════════
global sys_alloc
sys_alloc:
    ; rdi = tamanho, rsi = flags
    mov rax, SYS_MEM_ALLOC
    syscall
    ret

global sys_free
sys_free:
    ; rdi = endereço
    mov rax, SYS_MEM_FREE
    syscall
    ret

; ══════════════════════════════════════════════════
; Virtualização
; ══════════════════════════════════════════════════
global sys_vm_iniciar
sys_vm_iniciar:
    ; rdi = id da VM
    mov rax, SYS_VM_INICIAR
    syscall
    ret

global sys_vm_parar
sys_vm_parar:
    mov rax, SYS_VM_PARAR
    syscall
    ret

global sys_vm_status
sys_vm_status:
    mov rax, SYS_VM_STATUS
    syscall
    ret

; ══════════════════════════════════════════════════
; Sistema de Arquivos / Disco
; ══════════════════════════════════════════════════
global sys_disk_mount
sys_disk_mount:
    ; rdi = caminho, rsi = letra
    mov rax, SYS_DISCO_MONTAR
    syscall
    ret

global sys_file_open
sys_file_open:
    mov rax, SYS_ARQUIVO_ABRIR
    syscall
    ret

global sys_file_read
sys_file_read:
    mov rax, SYS_ARQUIVO_LER
    syscall
    ret

global sys_file_write
sys_file_write:
    mov rax, SYS_ARQUIVO_ESCREVER
    syscall
    ret