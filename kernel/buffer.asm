; ============================================================================
; BUFFER_CMD.ASM — Buffer de Comandos Circular, Seguro & Parser argc/argv
; FydelisTech OS v4.2 · Salvador • Bahia
; ============================================================================
BITS 64
default rel
%include "fydelterm.inc"

section .bss
align 8
buffer:     resb BUFFER_SIZE        ; Ring buffer de entrada de teclado
linha_cmd:  resb BUFFER_SIZE        ; Linha linearizada extraida para parsing seguro
buf_head:   resq 1
buf_tail:   resq 1
argc:       resq 1
argv:       resq MAX_ARGS

section .text
global add_char, read_command, reset_buffer, parse_line
global argc, argv, buffer, linha_cmd, buf_head, buf_tail

; ============================================================================
; ADD_CHAR — Adiciona caractere AL ao ring buffer (trata Backspace e wrap)
; Preserva todos os registradores usados
; ============================================================================
add_char:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi

    mov     rbx, [rel buf_head]
    mov     rcx, [rel buf_tail]
    lea     rsi, [rel buffer]

    cmp     al, KEY_BACKSPACE
    je      .faz_backspace
    cmp     al, 0x7F                ; DEL (alguns terminais/teclados enviam 127)
    je      .faz_backspace

    ; Calcula proximo indice circular: (head + 1) % BUFFER_SIZE
    mov     rdx, rbx
    inc     rdx
    cmp     rdx, BUFFER_SIZE
    jb      .ok_wrap
    xor     rdx, rdx
.ok_wrap:
    cmp     rdx, rcx
    je      .fim                    ; Buffer cheio (evita sobrescrever tail)

    mov     [rsi + rbx], al
    mov     [rel buf_head], rdx
    jmp     .fim

.faz_backspace:
    cmp     rbx, rcx
    je      .fim                    ; Nada para apagar antes de tail
    dec     rbx
    jns     .atualiza
    mov     rbx, BUFFER_SIZE - 1
.atualiza:
    mov     byte [rsi + rbx], 0
    mov     [rel buf_head], rbx

.fim:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ============================================================================
; READ_COMMAND — Verifica se ha linha completa ate ENTER e extrai para linha_cmd
; Saida:
;   rax = 1 se uma linha completa foi extraida para linha_cmd (pronta p/ parse_line)
;   rax = 0 se ainda nao houve ENTER no buffer
; ============================================================================
read_command:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     rbx, [rel buf_tail]
    mov     rcx, [rel buf_head]
    lea     rsi, [rel buffer]

    ; 1. Procura KEY_ENTER (0x0D) ou LF (0x0A) entre tail e head
.procurar_enter:
    cmp     rbx, rcx
    je      .sem_comando

    mov     al, [rsi + rbx]
    cmp     al, KEY_ENTER
    je      .achou_enter
    cmp     al, 0x0A
    je      .achou_enter

    inc     rbx
    cmp     rbx, BUFFER_SIZE
    jb      .procurar_enter
    xor     rbx, rbx
    jmp     .procurar_enter

.achou_enter:
    ; 2. Copia linearmente de buf_tail ate rbx para linha_cmd (resolve wrap-around)
    mov     rdx, [rel buf_tail]
    lea     rdi, [rel linha_cmd]
    xor     ecx, ecx                ; contador de bytes copiados

.copiar_linha:
    cmp     rdx, rbx
    je      .finalizar_copia

    mov     al, [rsi + rdx]
    mov     byte [rsi + rdx], 0     ; limpa byte consumido do ring buffer
    cmp     ecx, BUFFER_SIZE - 1
    jae     .avanca_tail
    mov     [rdi + rcx], al
    inc     ecx

.avanca_tail:
    inc     rdx
    cmp     rdx, BUFFER_SIZE
    jb      .copiar_linha
    xor     rdx, rdx
    jmp     .copiar_linha

.finalizar_copia:
    mov     byte [rdi + rcx], 0     ; termina string linear com NUL
    mov     byte [rsi + rbx], 0     ; limpa o proprio ENTER no ring buffer

    ; Avanca buf_tail para logo apos o ENTER
    inc     rbx
    cmp     rbx, BUFFER_SIZE
    jb      .salvar_tail
    xor     rbx, rbx
.salvar_tail:
    mov     [rel buf_tail], rbx

    mov     rax, 1
    jmp     .fim

.sem_comando:
    xor     rax, rax

.fim:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================================
; RESET_BUFFER — Zera ring buffer, linha linear, head/tail e argc/argv
; ============================================================================
reset_buffer:
    push    rax
    push    rcx
    push    rdi

    lea     rdi, [rel buffer]
    mov     rcx, BUFFER_SIZE
    xor     eax, eax
    rep     stosb

    lea     rdi, [rel linha_cmd]
    mov     rcx, BUFFER_SIZE
    rep     stosb

    mov     qword [rel buf_head], 0
    mov     qword [rel buf_tail], 0
    mov     qword [rel argc], 0

    mov     rcx, MAX_ARGS
    lea     rdi, [rel argv]
    rep     stosq

    pop     rdi
    pop     rcx
    pop     rax
    ret

; ============================================================================
; PARSE_LINE — Tokeniza linha_cmd em argc / argv (com suporte a aspas "...")
; ============================================================================
parse_line:
    push    rax
    push    rbx
    push    rcx
    push    rsi
    push    rdi

    ; Zera ponteiros anteriores de argv
    lea     rdi, [rel argv]
    mov     rcx, MAX_ARGS
    xor     eax, eax
    rep     stosq

    lea     rsi, [rel linha_cmd]

    ; Corta no primeiro CR ou LF residual
.limpa_fim:
    mov     al, [rsi]
    test    al, al
    jz      .inicia_parse
    cmp     al, 0x0D
    je      .anula_fim
    cmp     al, 0x0A
    je      .anula_fim
    inc     rsi
    jmp     .limpa_fim
.anula_fim:
    mov     byte [rsi], 0

.inicia_parse:
    lea     rsi, [rel linha_cmd]
    lea     rdi, [rel argv]
    xor     ecx, ecx                ; argc = 0

.pula_espacos:
    mov     al, [rsi]
    test    al, al
    jz      .fim_parse
    cmp     al, ' '
    je      .avanca_espaco
    cmp     al, 9                   ; TAB
    je      .avanca_espaco
    jmp     .verifica_aspas

.avanca_espaco:
    inc     rsi
    jmp     .pula_espacos

.verifica_aspas:
    cmp     ecx, MAX_ARGS
    jge     .fim_parse

    cmp     al, '"'
    je      .arg_com_aspas

    ; Argumento normal (sem aspas)
    mov     [rdi + rcx * 8], rsi
    inc     ecx

.proxima_letra:
    mov     al, [rsi]
    test    al, al
    jz      .fim_parse
    cmp     al, ' '
    je      .termina_arg
    cmp     al, 9
    je      .termina_arg
    inc     rsi
    jmp     .proxima_letra

.arg_com_aspas:
    inc     rsi                     ; pula a aspa de abertura
    mov     [rdi + rcx * 8], rsi
    inc     ecx

.proxima_letra_aspas:
    mov     al, [rsi]
    test    al, al
    jz      .fim_parse              ; aspa nao fechada: termina no NUL
    cmp     al, '"'
    je      .termina_arg
    inc     rsi
    jmp     .proxima_letra_aspas

.termina_arg:
    mov     byte [rsi], 0
    inc     rsi
    jmp     .pula_espacos

.fim_parse:
    mov     [rel argc], rcx

    pop     rdi
    pop     rsi
    pop     rcx
    pop     rbx
    pop     rax
    ret
