; ==================================================
; FydelisTechOS — syscall_handler.asm
; Núcleo: recebe SYSCALL → executa → retorna com segurança
; ==================================================
bits 64

; === Incluir todas as constantes ===
%include "user_syscalls.inc"
%include "virtual_syscalls.inc"
%include "disktools_syscalls.inc"
%include "rede_syscalls.inc"
%include "security_syscalls.inc"

; === Funções externas do núcleo ===
; Virtualização
extern vm_inicializar
extern vm_parar
extern vm_status
extern vm_mem_alocar
extern vm_disco_anexar
extern vm_listar

; Disco / Partições (Alinhado com disktools_syscalls.inc)
extern fs_montar
extern fs_desmontar
extern fs_abrir
extern fs_fechar
extern fs_ler
extern fs_escrever
extern fs_listar
extern fs_criar_dir
extern fs_remover

; Rede (implementação real do kernel, distinta do stub de usuário)
extern inicializar_nic_mmio
extern e1000_pci_inicializar
extern net_wifi_conectar
extern net_status
extern net_enviar
extern net_receber
extern net_meu_ip
extern net_desconectar

; Segurança
extern fw_habilitar
extern fw_desabilitar
extern fw_regra_adicionar
extern av_verificar
extern av_varrer
extern av_quarentena
extern cve_verificar
extern sec_listar_ameacas
extern sec_status

; E/S Básica
extern console_write
extern console_read
extern console_setcolor

; Processos
extern processo_exit
extern processo_spawn
extern processo_wait
extern processo_getpid

; Memória
extern mem_alocar_usuario
extern mem_liberar_usuario

section .text
global syscall_handler

; ══════════════════════════════════════════════════════════
; ENTRADA: SYSCALL
; rax = número da chamada
; rdi, rsi, rdx, r8, r9 = parâmetros
; rcx = RIP de retorno (colocado pela instrução syscall)
; r11 = RFLAGS salvo (colocado pela instrução syscall)
; SAÍDA: rax = resultado / código de erro
; ══════════════════════════════════════════════════════════
syscall_handler:
    ; Preserva endereço de retorno (rcx), flags (r11) e registradores callee-saved
    push rcx
    push r11
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Alinha a pilha em 16 bytes para chamadas System V ABI (8 pushes = 64 bytes)
    mov rbp, rsp
    and rsp, -16

    ; Distribuir conforme número da chamada — E/S e Processos
    cmp rax, SYS_IO_WRITE
    je .io_write
    cmp rax, SYS_IO_READ
    je .io_read
    cmp rax, SYS_IO_SETCOLOR
    je .io_setcolor

    cmp rax, SYS_PROCESS_EXIT
    je .proc_exit
    cmp rax, SYS_PROCESS_SPAWN
    je .proc_spawn
    cmp rax, SYS_PROCESS_GETPID
    je .proc_getpid

    cmp rax, SYS_MEM_ALLOC
    je .mem_alloc
    cmp rax, SYS_MEM_FREE
    je .mem_free

    ; Virtualização
    cmp rax, SYS_VM_INICIAR
    je .vm_iniciar
    cmp rax, SYS_VM_PARAR
    je .vm_parar
    cmp rax, SYS_VM_STATUS
    je .vm_status
    cmp rax, SYS_VM_MEM_ALOCAR
    je .vm_mem_alocar
    cmp rax, SYS_VM_DISCO_ANEXAR
    je .vm_disco_anexar
    cmp rax, SYS_VM_LISTAR
    je .vm_listar

    ; Disco e Ferramentas
    cmp rax, SYS_DISCO_LISTAR
    je .fs_listar
    cmp rax, SYS_PARTICAO_LISTAR
    je .fs_listar
    cmp rax, SYS_DISCO_LER_SETOR
    je .fs_ler
    cmp rax, SYS_DISCO_ESCREVER_SETOR
    je .fs_escrever

    ; Rede e Wi-Fi
    cmp rax, SYS_REDE_INICIALIZAR
    je .net_init
    cmp rax, SYS_WIFI_CONECTAR
    je .net_wifi
    cmp rax, SYS_REDE_STATUS
    je .net_status
    cmp rax, SYS_REDE_MEU_IP
    je .net_ip
    cmp rax, SYS_REDE_DESCONECTAR
    je .net_desc

    ; Segurança
    cmp rax, SYS_FW_HABILITAR
    je .fw_on
    cmp rax, SYS_FW_DESABILITAR
    je .fw_off
    cmp rax, SYS_AV_VERIFICAR
    je .av_check
    cmp rax, SYS_SEC_STATUS
    je .sec_status

    ; Chamada desconhecida
    mov rax, SYS_ERR_BADNO
    jmp .fim

; ══════════════════════════════════════════════════════════
; E/S — CONSOLE
; ══════════════════════════════════════════════════════════
.io_write:
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    call console_write
    jmp .fim

.io_read:
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    call console_read
    jmp .fim

.io_setcolor:
    call console_setcolor
    xor rax, rax
    jmp .fim

; ══════════════════════════════════════════════════════════
; PROCESSOS
; ══════════════════════════════════════════════════════════
.proc_exit:
    call processo_exit
    jmp .fim

.proc_spawn:
    mov rdx, rsi
    mov rsi, rdi
    call processo_spawn
    jmp .fim

.proc_getpid:
    call processo_getpid
    jmp .fim

; ══════════════════════════════════════════════════════════
; MEMÓRIA
; ══════════════════════════════════════════════════════════
.mem_alloc:
    mov rdx, rsi
    mov rsi, rdi
    call mem_alocar_usuario
    jmp .fim

.mem_free:
    call mem_liberar_usuario
    jmp .fim

; ══════════════════════════════════════════════════════════
; VIRTUALIZAÇÃO
; ══════════════════════════════════════════════════════════
.vm_iniciar:
    call vm_inicializar
    jmp .fim

.vm_parar:
    call vm_parar
    jmp .fim

.vm_status:
    call vm_status
    jmp .fim

.vm_mem_alocar:
    mov rdx, rsi
    mov rsi, rdi
    call vm_mem_alocar
    jmp .fim

.vm_disco_anexar:
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    call vm_disco_anexar
    jmp .fim

.vm_listar:
    mov rdx, rsi
    mov rsi, rdi
    call vm_listar
    jmp .fim

; ══════════════════════════════════════════════════════════
; SISTEMA DE ARQUIVOS / DISCO
; ══════════════════════════════════════════════════════════
.fs_ler:
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    call fs_ler
    jmp .fim

.fs_escrever:
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    call fs_escrever
    jmp .fim

.fs_listar:
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    call fs_listar
    jmp .fim

; ══════════════════════════════════════════════════════════
; REDE (sem recursão para o stub net_inicializar)
; ══════════════════════════════════════════════════════════
.net_init:
    call inicializar_nic_mmio
    call e1000_pci_inicializar
    xor rax, rax
    jmp .fim

.net_wifi:
    mov rdx, rsi
    mov rsi, rdi
    call net_wifi_conectar
    jmp .fim

.net_status:
    call net_status
    jmp .fim

.net_ip:
    call net_meu_ip
    jmp .fim

.net_desc:
    call net_desconectar
    jmp .fim

; ══════════════════════════════════════════════════════════
; SEGURANÇA
; ══════════════════════════════════════════════════════════
.fw_on:
    call fw_habilitar
    jmp .fim

.fw_off:
    call fw_desabilitar
    jmp .fim

.av_check:
    call av_verificar
    jmp .fim

.sec_status:
    call sec_status
    jmp .fim

; ══════════════════════════════════════════════════════════
; SAÍDA PADRÃO (restaura pilha, RFLAGS e retorna para RCX)
; ══════════════════════════════════════════════════════════
.fim:
    mov rsp, rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    pop r11
    pop rcx
    jmp rcx
