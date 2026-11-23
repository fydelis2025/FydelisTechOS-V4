; ============================================================================
; SCHEDULER.ASM — Escalonador Preemptivo Round-Robin (x86_64)
; Alinhado com pcb.inc (PCB_RSP=56, PCB_ESTADO=152) · Sem Conflitos
; FydelisTech OS v4.2 · Salvador • Bahia
; ============================================================================
bits 64
default rel

; ============================================================================
; CONSTANTES & OFFSETS DO PCB (identicos ao pcb.inc)
; ============================================================================
PCB_ESTADO_PRONTO     equ 0
PCB_ESTADO_EXECUTANDO equ 1
PCB_ESTADO_BLOQUEADO  equ 2
PCB_ESTADO_ZOMBIE     equ 3

PCB_RAX               equ 0
PCB_RBX               equ 8
PCB_RCX               equ 16
PCB_RDX               equ 24
PCB_RSI               equ 32
PCB_RDI               equ 40
PCB_RBP               equ 48
PCB_RSP               equ 56
PCB_RIP               equ 64
PCB_RFLAGS            equ 72
PCB_R8                equ 80
PCB_R9                equ 88
PCB_R10               equ 96
PCB_R11               equ 104
PCB_R12               equ 112
PCB_R13               equ 120
PCB_R14               equ 128
PCB_R15               equ 136
PCB_ID                equ 144
PCB_ESTADO            equ 152
PCB_PRIORIDADE        equ 156
PCB_NOME              equ 160
PCB_TAMANHO           equ 256

MAX_PROCESSOS         equ 16
QUANTUM_PADRAO        equ 5

; ============================================================================
; EXTERNAIS & EXPORTACOES
; ============================================================================
extern trocar_contexto          ; rdi = pcb_atual, rsi = pcb_proximo

global scheduler_inicializar
global scheduler_adicionar
global scheduler_remover
global scheduler_bloquear_atual
global scheduler_desbloquear
global scheduler_trocar
global scheduler_tick
global scheduler_obter_atual
global processo_atual

section .bss
align 8
processo_atual:   resq 1         ; Ponteiro para PCB atualmente em execucao
fila_prontos:     resq MAX_PROCESSOS
indice_atual:     resd 1         ; Indice na fila do processo em execucao
contador_prontos: resd 1
quantum_ticks:    resd 1         ; Fatia de tempo por processo
ticks_restantes:  resd 1

section .text

; ============================================================================
; INICIALIZAR ESCALONADOR
; ============================================================================
scheduler_inicializar:
    push rdi
    push rcx

    lea rdi, [rel fila_prontos]
    mov rcx, MAX_PROCESSOS
    xor eax, eax
    rep stosq

    mov dword [rel contador_prontos], 0
    mov dword [rel indice_atual], 0
    mov dword [rel quantum_ticks], QUANTUM_PADRAO
    mov dword [rel ticks_restantes], QUANTUM_PADRAO
    mov qword [rel processo_atual], 0

    pop rcx
    pop rdi
    ret

; ============================================================================
; ADICIONAR PROCESSO NA FILA
; Entrada: rdi = ponteiro para PCB inicializado
; Saida:   rax = 1 sucesso, 0 fila cheia ou ponteiro nulo
; ============================================================================
scheduler_adicionar:
    test rdi, rdi
    jz .falha

    mov eax, [rel contador_prontos]
    cmp eax, MAX_PROCESSOS
    jae .falha

    lea rcx, [rel fila_prontos]
    mov [rcx + rax * 8], rdi
    inc dword [rel contador_prontos]

    ; Se nao ha processo ativo ainda, este assume imediatamente a CPU
    cmp qword [rel processo_atual], 0
    jnz .na_fila

    mov dword [rdi + PCB_ESTADO], PCB_ESTADO_EXECUTANDO
    mov [rel processo_atual], rdi
    mov [rel indice_atual], eax
    mov ecx, [rel quantum_ticks]
    mov [rel ticks_restantes], ecx
    jmp .ok

.na_fila:
    mov dword [rdi + PCB_ESTADO], PCB_ESTADO_PRONTO

.ok:
    mov rax, 1
    ret

.falha:
    xor rax, rax
    ret

; ============================================================================
; REMOVER PROCESSO DA FILA (marca como ZOMBIE e compacta fila)
; Entrada: rdi = ponteiro para PCB
; Saida:   rax = 1 removido, 0 nao encontrado
; ============================================================================
scheduler_remover:
    push rbx
    push rcx
    push rdx

    mov ecx, [rel contador_prontos]
    test ecx, ecx
    jz .nao_achou

    lea rbx, [rel fila_prontos]
    xor edx, edx
.busca:
    cmp [rbx + rdx * 8], rdi
    je .achou
    inc edx
    cmp edx, ecx
    jb .busca

.nao_achou:
    xor rax, rax
    pop rdx
    pop rcx
    pop rbx
    ret

.achou:
    mov dword [rdi + PCB_ESTADO], PCB_ESTADO_ZOMBIE
    dec ecx
    mov [rel contador_prontos], ecx

    ; Desloca elementos seguintes para fechar o buraco
.compacta:
    cmp edx, ecx
    jae .limpa_ultimo
    mov rax, [rbx + rdx * 8 + 8]
    mov [rbx + rdx * 8], rax
    inc edx
    jmp .compacta

.limpa_ultimo:
    mov qword [rbx + rcx * 8], 0
    mov rax, 1
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================================
; OBTER PCB DO PROCESSO ATUAL
; Saida: rax = ponteiro para PCB em execucao
; ============================================================================
scheduler_obter_atual:
    mov rax, [rel processo_atual]
    ret

; ============================================================================
; ESCOLHER PROXIMO PROCESSO PRONTO (Round-Robin com filtro de estado)
; Entrada: rdi = PCB atual
; Saida:   rax = proximo PCB pronto (ou mesmo PCB se nenhum outro pronto)
; ============================================================================
escolher_proximo:
    push rbx
    push rcx
    push rdx
    push r8

    mov ecx, [rel contador_prontos]
    cmp ecx, 1
    jbe .manter_atual

    lea rbx, [rel fila_prontos]
    mov edx, [rel indice_atual]
    xor r8d, r8d                    ; tentativas = 0

.proxima_tentativa:
    inc edx
    cmp edx, ecx
    jb .idx_ok
    xor edx, edx                    ; wrap-around circular
.idx_ok:
    mov rax, [rbx + rdx * 8]
    test rax, rax
    jz .avanca_tentativa

    mov r9d, [rax + PCB_ESTADO]
    cmp r9d, PCB_ESTADO_PRONTO
    je .selecionado

.avanca_tentativa:
    inc r8d
    cmp r8d, ecx
    jb .proxima_tentativa

.manter_atual:
    mov rax, rdi
    jmp .fim

.selecionado:
    mov [rel indice_atual], edx

.fim:
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================================
; TICK DO TIMER — Preempcao por fatia de tempo (PIT / APIC Timer IRQ)
; ============================================================================
scheduler_tick:
    mov rdi, [rel processo_atual]
    test rdi, rdi
    jz .sem_troca

    cmp dword [rel ticks_restantes], 0
    je .avaliar_troca
    dec dword [rel ticks_restantes]
    jnz .sem_troca

.avaliar_troca:
    mov eax, [rel quantum_ticks]
    mov [rel ticks_restantes], eax

    call escolher_proximo
    cmp rax, rdi
    je .sem_troca                   ; So existe 1 processo pronto: evita overhead

    ; Atualiza estados: atual volta para PRONTO, proximo vira EXECUTANDO
    mov rsi, rax
    cmp dword [rdi + PCB_ESTADO], PCB_ESTADO_EXECUTANDO
    jne .ativa_proximo
    mov dword [rdi + PCB_ESTADO], PCB_ESTADO_PRONTO

.ativa_proximo:
    mov dword [rsi + PCB_ESTADO], PCB_ESTADO_EXECUTANDO
    mov [rel processo_atual], rsi

    ; Salva contexto de RDI e restaura contexto de RSI
    jmp trocar_contexto

.sem_troca:
    ret

; ============================================================================
; FORCAR TROCA COOPERATIVA (yield / sono / espera de I/O)
; ============================================================================
scheduler_trocar:
    mov rdi, [rel processo_atual]
    test rdi, rdi
    jz .retornar

    mov eax, [rel quantum_ticks]
    mov [rel ticks_restantes], eax

    call escolher_proximo
    cmp rax, rdi
    je .retornar

    mov rsi, rax
    cmp dword [rdi + PCB_ESTADO], PCB_ESTADO_EXECUTANDO
    jne .ativa_novo
    mov dword [rdi + PCB_ESTADO], PCB_ESTADO_PRONTO

.ativa_novo:
    mov dword [rsi + PCB_ESTADO], PCB_ESTADO_EXECUTANDO
    mov [rel processo_atual], rsi
    jmp trocar_contexto

.retornar:
    ret

; ============================================================================
; BLOQUEAR PROCESSO ATUAL E CEDER CPU IMEDIATAMENTE
; ============================================================================
scheduler_bloquear_atual:
    mov rdi, [rel processo_atual]
    test rdi, rdi
    jz .fim
    mov dword [rdi + PCB_ESTADO], PCB_ESTADO_BLOQUEADO
    jmp scheduler_trocar
.fim:
    ret

; ============================================================================
; DESBLOQUEAR PROCESSO (volta para PCB_ESTADO_PRONTO)
; Entrada: rdi = ponteiro para PCB
; ============================================================================
scheduler_desbloquear:
    test rdi, rdi
    jz .fim
    cmp dword [rdi + PCB_ESTADO], PCB_ESTADO_BLOQUEADO
    jne .fim
    mov dword [rdi + PCB_ESTADO], PCB_ESTADO_PRONTO
.fim:
    ret
