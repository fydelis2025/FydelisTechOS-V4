; ============================================================================
; FYDLOG.ASM — Sistema de Logs Nativo (/fyd/dados/logs/sistema.flog)
; FydelisTech OS v4.2 — Integrado ao estrutura.asm & C Freestanding
; Salvador - Bahia
; ============================================================================
BITS 64
default rel

; Tipos de Eventos (compativeis com C: fydlog_escrever(int tipo, const char *msg))
%define LOG_INFO        0
%define LOG_AVISO       1
%define LOG_ERRO        2
%define LOG_CRITICO     3
%define LOG_BUFFER_MAX  4096

; Funcoes externas do Kernel (print & estrutura.asm)
extern print_string
extern print_newline
extern fs_caminho_existe
extern fs_criar_diretorio

; Exportacao publica (Assembly e C)
global fydlog_inicializar
global fydlog_escrever
global fydlog_ler_todos
global fydlog_obter_buffer
global fydlog_obter_tamanho
global fydlog_fechar

section .data
    caminho_log_flog: db "/fyd/dados/logs/sistema.flog", 0
    cabecalho_flog:   db "#!FYDLOG v1", 10, "# Log Nativo do Kernel FydelisTech OS", 10, 0
    msg_inicio:       db "[SISTEMA] Modulo FydLog v1.2 ativo -> /fyd/dados/logs/sistema.flog", 0

    ; Etiquetas ASCII puras (compativeis com VGA e VESA)
    etiqueta_info:    db "[INFO] ", 0
    etiqueta_aviso:   db "[AVISO] ", 0
    etiqueta_erro:    db "[ERRO] ", 0
    etiqueta_critico: db "[CRITICO] ", 0

section .bss
    inicializado:     resb 1                ; 0 = nao, 1 = sim
    lock_log:         resb 1                ; Spinlock de concorrencia
    buffer_logs:      resb LOG_BUFFER_MAX   ; Buffer de 4KB em RAM (.flog)
    cursor_log:       resq 1                ; Offset atual de escrita no buffer

section .text

; ============================================================================
; fydlog_inicializar() — Registra /fyd/dados/logs/sistema.flog e inicia buffer
; Retorno: rax = 1 (sucesso)
; ============================================================================
fydlog_inicializar:
    push rbx
    push rcx
    push rsi
    push rdi

    cmp byte [rel inicializado], 1
    je .ja_inicializado

    ; Registra /fyd/dados/logs/sistema.flog na arvore do estrutura.asm
    lea rdi, [rel caminho_log_flog]
    call fs_caminho_existe
    test rax, rax
    jnz .preparar_buffer

    lea rdi, [rel caminho_log_flog]
    call fs_criar_diretorio

.preparar_buffer:
    ; Limpa buffer_logs e grava cabecalho #!FYDLOG v1
    lea rdi, [rel buffer_logs]
    xor eax, eax
    mov rcx, LOG_BUFFER_MAX
    rep stosb

    mov qword [rel cursor_log], 0
    lea rsi, [rel cabecalho_flog]
    call anexar_str_buffer

    mov byte [rel lock_log], 0
    mov byte [rel inicializado], 1

    ; Exibe confirmacao no console de boot (antes do modo grafico)
    lea rsi, [rel msg_inicio]
    call print_string
    call print_newline

    mov rdi, LOG_INFO
    lea rsi, [rel msg_inicio]
    call fydlog_escrever

.ja_inicializado:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    mov rax, 1
    ret

; ============================================================================
; fydlog_escrever(rdi = tipo, rsi = ponteiro_mensagem)
; Grava apenas no buffer .flog em RAM (seguro para VGA e VESA)
; ============================================================================
fydlog_escrever:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    cmp byte [rel inicializado], 1
    je .tentar_travar
    call fydlog_inicializar

.tentar_travar:
    mov al, 1
    xchg [rel lock_log], al
    test al, al
    jz .secao_critica
    pause
    jmp .tentar_travar

.secao_critica:
    mov rbx, rdi                ; rbx = tipo do log
    mov rdx, rsi                ; rdx = ponteiro da mensagem

    ; Seleciona etiqueta conforme o nivel
    cmp rbx, LOG_INFO
    je .etq_info
    cmp rbx, LOG_AVISO
    je .etq_aviso
    cmp rbx, LOG_ERRO
    je .etq_erro
    jmp .etq_critico

.etq_info:
    lea r8, [rel etiqueta_info]
    jmp .gravar_buffer
.etq_aviso:
    lea r8, [rel etiqueta_aviso]
    jmp .gravar_buffer
.etq_erro:
    lea r8, [rel etiqueta_erro]
    jmp .gravar_buffer
.etq_critico:
    lea r8, [rel etiqueta_critico]

.gravar_buffer:
    ; Grava etiqueta + mensagem + '\n' no buffer_logs (.flog)
    mov rsi, r8
    call anexar_str_buffer

    mov rsi, rdx
    call anexar_str_buffer

    call anexar_nl_buffer

    ; Libera spinlock sem tocar no console VGA/VESA
    mov byte [rel lock_log], 0

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================================
; fydlog_ler_todos() — Imprime todo o historico de logs gravados no terminal
; ============================================================================
fydlog_ler_todos:
    push rsi
    cmp byte [rel inicializado], 1
    jne .fim
    lea rsi, [rel buffer_logs]
    call print_string
    call print_newline
.fim:
    pop rsi
    ret

; ============================================================================
; ACESSORES PARA C (exec.c / visualizador de logs / fyd_formatos.c)
; ============================================================================
fydlog_obter_buffer:
    lea rax, [rel buffer_logs]
    ret

fydlog_obter_tamanho:
    mov rax, [rel cursor_log]
    ret

; ============================================================================
; fydlog_fechar() — Encerra o subsistema de logs
; ============================================================================
fydlog_fechar:
    mov byte [rel inicializado], 0
    ret

; ============================================================================
; ROTINAS INTERNAS DE APPEND NO BUFFER DE 4KB (Com rotacao se lotar)
; ============================================================================
anexar_str_buffer:
    push rax
    push rcx
    push rdi

    mov rcx, [rel cursor_log]
    lea rdi, [rel buffer_logs]

.loop_char:
    lodsb
    test al, al
    jz .fim_str

    ; Se atingir o limite (LOG_BUFFER_MAX - 2), reinicia cursor para nao estourar
    cmp rcx, LOG_BUFFER_MAX - 2
    jb .gravar_byte
    xor ecx, ecx

.gravar_byte:
    mov [rdi + rcx], al
    inc rcx
    jmp .loop_char

.fim_str:
    mov byte [rdi + rcx], 0
    mov [rel cursor_log], rcx

    pop rdi
    pop rcx
    pop rax
    ret

anexar_nl_buffer:
    push rax
    push rcx
    push rdi

    mov rcx, [rel cursor_log]
    lea rdi, [rel buffer_logs]

    cmp rcx, LOG_BUFFER_MAX - 2
    jb .gravar_nl
    xor ecx, ecx

.gravar_nl:
    mov byte [rdi + rcx], 10
    inc rcx
    mov byte [rdi + rcx], 0
    mov [rel cursor_log], rcx

    pop rdi
    pop rcx
    pop rax
    ret
