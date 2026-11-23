; ==================================================
; FydelisTechOS — Disco Virtual v2.2
; Emula HD de 64MB com acesso por setores
; ==================================================
bits 64

; Configurações do disco
DISCO_TAMANHO     equ 67108864   ; 64 MB
SETOR_TAMANHO     equ 512        ; 512 bytes por setor
TOTAL_SETORES     equ DISCO_TAMANHO / SETOR_TAMANHO

section .bss
align 4096
global disco_buffer
global disco_tamanho

disco_buffer:     resb DISCO_TAMANHO   ; Espaço do disco inteiro
disco_tamanho:   resq 1               ; Tamanho em bytes

section .text
global disco_inicializar
global disco_ler_setor
global disco_escrever_setor

; ─────────────────────────────────────
; Inicializar disco virtual
; ─────────────────────────────────────
disco_inicializar:
    mov  qword [disco_tamanho], DISCO_TAMANHO
    ; Limpar todo o disco
    mov  rdi, disco_buffer
    mov  rcx, DISCO_TAMANHO / 8
    xor  rax, rax
    rep stosq
    ret

; ─────────────────────────────────────
; Ler setor do disco
; Entrada: rdi = número do setor, rsi = buffer de destino
; Saída: rax = 1 sucesso, 0 erro
; ─────────────────────────────────────
disco_ler_setor:
    cmp  rdi, TOTAL_SETORES
    jae  .erro                    ; Setor inválido

    ; Calcular offset = setor × 512
    mov  rax, rdi
    mov  rdx, SETOR_TAMANHO
    mul  rdx

    ; Copiar dados
    lea  rcx, [disco_buffer + rax]
    mov  rdi, rsi
    mov  rsi, rcx
    mov  rcx, SETOR_TAMANHO
    rep movsb

    mov  rax, 1
    ret

.erro:
    xor  rax, rax
    ret

; ─────────────────────────────────────
; Escrever setor no disco
; Entrada: rdi = número do setor, rsi = buffer de origem
; Saída: rax = 1 sucesso, 0 erro
; ─────────────────────────────────────
disco_escrever_setor:
    cmp  rdi, TOTAL_SETORES
    jae  .erro

    mov  rax, rdi
    mov  rdx, SETOR_TAMANHO
    mul  rdx

    lea  rdi, [disco_buffer + rax]
    mov  rcx, SETOR_TAMANHO
    rep movsb

    mov  rax, 1
    ret

.erro:
    xor  rax, rax
    ret