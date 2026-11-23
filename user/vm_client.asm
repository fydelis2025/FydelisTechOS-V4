; ==================================================
; FydelisTechOS — vm_client.asm
; Interface de usuário para gerenciar VMs
; ==================================================
bits 64
%include "syscalls/virtual_syscalls.inc"
%include "syscalls/user_syscalls.inc"

section .text

; ══════════════════════════════════════════════════
; Iniciar Máquina Virtual
; Entrada: rdi = ID da VM (0 = padrão)
; Saída: rax = 0 sucesso / <0 erro
; ══════════════════════════════════════════════════
global vm_iniciar
vm_iniciar:
    mov  rax, SYS_VM_INICIAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Parar Máquina Virtual
; Entrada: rdi = ID da VM
; Saída: rax = 0 sucesso / <0 erro
; ══════════════════════════════════════════════════
global vm_parar
vm_parar:
    mov  rax, SYS_VM_PARAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Consultar Status da VM
; Entrada: rdi = ID da VM
; Saída: rax = status (VM_STATUS_*)
; ══════════════════════════════════════════════════
global vm_status
vm_status:
    mov  rax, SYS_VM_STATUS
    syscall
    ret

; ══════════════════════════════════════════════════
; Alocar Memória para VM
; Entrada: rdi = ID da VM, rsi = tamanho em bytes
; Saída: rax = endereço atribuído / 0 erro
; ══════════════════════════════════════════════════
global vm_mem_alocar
vm_mem_alocar:
    mov  rax, SYS_VM_MEM_ALOCAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Anexar Disco à VM
; Entrada: rdi = ID da VM, rsi = tipo, rdx = ponteiro descritor
; Saída: rax = 0 sucesso / <0 erro
; ══════════════════════════════════════════════════
global vm_disco_anexar
vm_disco_anexar:
    mov  rax, SYS_VM_DISCO_ANEXAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Listar Todas as VMs
; Entrada: rdi = buffer de saída, rsi = capacidade
; Saída: rax = número de VMs / <0 erro
; ══════════════════════════════════════════════════
global vm_listar
vm_listar:
    mov  rax, SYS_VM_LISTAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Exibir Status Formatado no Terminal
; ══════════════════════════════════════════════════
global vm_status_imprimir
vm_status_imprimir:
    push rbx
    mov  rbx, rdi               ; Salvar ID

    call vm_status
    cmp  rax, VM_STATUS_EXECUTANDO
    je   .msg_rodando
    cmp  rax, VM_STATUS_PAUSADO
    je   .msg_pausado
    cmp  rax, VM_STATUS_DESLIGADO
    je   .msg_desligado

    ; Erro
    mov  rsi, str_erro
    mov  rdx, 13
    jmp  .escrever

.msg_rodando:
    mov  rsi, str_rodando
    mov  rdx, 16
    jmp  .escrever
.msg_pausado:
    mov  rsi, str_pausado
    mov  rdx, 13
    jmp  .escrever
.msg_desligado:
    mov  rsi, str_desligado
    mov  rdx, 16

.escrever:
    mov  rdi, 1
    call sys_write
    pop  rbx
    ret

section .rodata
str_rodando:   db ' → Executando', 0xA
str_pausado:   db ' → Pausada', 0xA
str_desligado: db ' → Desligada', 0xA
str_erro:      db ' → Erro', 0xA

extern sys_write