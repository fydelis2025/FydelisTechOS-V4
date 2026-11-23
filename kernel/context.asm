; ============================================================================
; CONTEXT.ASM — Troca de Contexto x86_64 (Salvar, Restaurar & Inicializar Pilha)
; Alinhado com pcb.inc e scheduler.asm (PCB_RSP = 56)
; FydelisTech OS v4.2 · Salvador • Bahia
; ============================================================================
bits 64
default rel

; ============================================================================
; OFFSETS DO PCB (identicos ao pcb.inc)
; ============================================================================
PCB_RAX       equ 0
PCB_RBX       equ 8
PCB_RCX       equ 16
PCB_RDX       equ 24
PCB_RSI       equ 32
PCB_RDI       equ 40
PCB_RBP       equ 48
PCB_RSP       equ 56
PCB_RIP       equ 64
PCB_RFLAGS    equ 72
PCB_R8        equ 80
PCB_R9        equ 88
PCB_R10       equ 96
PCB_R11       equ 104
PCB_R12       equ 112
PCB_R13       equ 120
PCB_R14       equ 128
PCB_R15       equ 136

; Tamanho do frame empilhado na pilha do processo:
; 15 registradores + RFLAGS = 16 quadwords = 128 bytes (+ 8 bytes RIP do call = 136 bytes)
FRAME_CONTEXTO_BYTES equ 128

section .text
global contexto_salvar
global contexto_restaurar
global trocar_contexto
global contexto_preparar_pilha

; ============================================================================
; CONTEXTO_PREPARAR_PILHA — Monta frame inicial na pilha de um novo processo
; Entrada:
;   rdi = ponteiro para struct PCB
;   rsi = topo da pilha alocada (ex: pilha_base + 8192, alinhado em 16 bytes)
;   rdx = ponto de entrada (RIP inicial da funcao do processo)
;   rcx = argumento inicial passado em RDI ao iniciar o processo
; Saida:
;   rax = novo RSP salvo em [rdi + PCB_RSP]
; ============================================================================
contexto_preparar_pilha:
    ; Garante alinhamento de 16 bytes no topo da pilha
    and rsi, ~0x0F

    ; Salva metadados na struct PCB
    mov [rdi + PCB_RIP], rdx
    mov [rdi + PCB_RDI], rcx
    mov qword [rdi + PCB_RFLAGS], 0x202     ; IF=1 (interrupcoes habilitadas) + bit 1 reservado

    ; Empilha endereco de retorno inicial (RIP que o 'ret' de trocar_contexto usara)
    sub rsi, 8
    mov [rsi], rdx

    ; Monta os 16 quadwords na exata ordem inversa dos 'pop' de trocar_contexto:
    ; Ordem de pop: r15, r14, r13, r12, r11, r10, r9, r8, rbp, rdi, rsi, rdx, rcx, rbx, rax, rflags
    sub rsi, FRAME_CONTEXTO_BYTES
    mov qword [rsi + 0],   0                ; r15
    mov qword [rsi + 8],   0                ; r14
    mov qword [rsi + 16],  0                ; r13
    mov qword [rsi + 24],  0                ; r12
    mov qword [rsi + 32],  0                ; r11
    mov qword [rsi + 40],  0                ; r10
    mov qword [rsi + 48],  0                ; r9
    mov qword [rsi + 56],  0                ; r8
    mov qword [rsi + 64],  0                ; rbp
    mov [rsi + 72],        rcx              ; rdi (1o argumento ABI System V para o processo)
    mov qword [rsi + 80],  0                ; rsi
    mov qword [rsi + 88],  0                ; rdx
    mov qword [rsi + 96],  0                ; rcx
    mov qword [rsi + 104], 0                ; rbx
    mov qword [rsi + 112], 0                ; rax
    mov qword [rsi + 120], 0x202            ; rflags (IF = 1)

    ; Registra o RSP pronto no PCB
    mov [rdi + PCB_RSP], rsi
    mov rax, rsi
    ret

; ============================================================================
; SALVAR CONTEXTO NA PILHA DO PROCESSO
; Entrada: rdi = ponteiro para struct PCB
; ============================================================================
contexto_salvar:
    ; Retira temporariamente o endereco de retorno para ficar acima do frame
    pop r11

    pushfq
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov [rdi + PCB_RSP], rsp
    jmp r11

; ============================================================================
; RESTAURAR CONTEXTO DA PILHA DO PROCESSO
; Entrada: rdi = ponteiro para struct PCB
; ============================================================================
contexto_restaurar:
    mov rsp, [rdi + PCB_RSP]

    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    popfq
    ret

; ============================================================================
; TROCAR DE UM PROCESSO PARA OUTRO (Preemptivo ou Cooperativo)
; Entrada:
;   rdi = PCB do processo atual (onde salvar RSP)
;   rsi = PCB do proximo processo (de onde carregar RSP)
; ============================================================================
trocar_contexto:
    ; 1. Empilha estado completo da CPU na pilha do processo atual
    pushfq
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    ; 2. Salva RSP do processo atual no campo PCB_RSP (offset 56)
    mov [rdi + PCB_RSP], rsp

    ; 3. Alterna para a pilha do proximo processo (offset 56)
    mov rsp, [rsi + PCB_RSP]

    ; 4. Restaura estado completo da CPU do proximo processo (sem sujar RAX!)
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    popfq

    ; 5. Retorna para o RIP empilhado no topo da pilha do proximo processo
    ret
