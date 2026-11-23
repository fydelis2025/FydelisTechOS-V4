; ==========================================
; 🖨️ IMPRESSORA.ASM — Driver de Impressora Unificado
; FydelisTech OS v4.2 · Salvador • Bahia 🇧🇷
; Suporta: Paralela (LPT1), USB (Class 07h) e Rede (Raw 9100)
; ==========================================
BITS 64
DEFAULT REL
%include "fydelterm.inc"

; ========== ESTADOS DA IMPRESSORA ==========
IMPRESSORA_DESCONECTADA  equ 0
IMPRESSORA_PRONTA        equ 1
IMPRESSORA_IMPRIMINDO    equ 2
IMPRESSORA_ERRO          equ -1

; ========== TIPOS DE CONEXÃO ==========
CONEXAO_NENHUMA          equ 0
CONEXAO_PARALELA         equ 1       ; Porta LPT1 (0x378)
CONEXAO_USB              equ 2       ; Interface USB Printer
CONEXAO_REDE             equ 3       ; Impressora IPP / JetDirect (9100)

; ========== REGISTRADORES LPT1 (IEEE 1284) ==========
LPT1_PORTA_DATA          equ 0x378
LPT1_PORTA_STATUS        equ 0x379
LPT1_PORTA_CTRL          equ 0x37A

LPT1_STAT_BUSY           equ 0x80    ; Bit 7 invertido: 1 = livre, 0 = ocupada
LPT1_STAT_ACK            equ 0x40
LPT1_STAT_PAPER_OUT      equ 0x20
LPT1_STAT_SELECT         equ 0x10
LPT1_STAT_ERROR          equ 0x08

LPT1_CTRL_STROBE         equ 0x01
LPT1_CTRL_INIT           equ 0x04
LPT1_CTRL_SELECT_IN      equ 0x08

LPT1_TIMEOUT             equ 500000

; ========== FUNÇÕES EXTERNAS ==========
extern print_string
extern print_newline
extern sys_usb_encontrar_dispositivo
extern sys_usb_enviar_dados
extern sys_rede_conectar
extern sys_rede_enviar
extern fila_criar
extern fila_adicionar
extern fila_processar
extern fila_limpar
extern arquivo_ler_todo

; ========== EXPORTAÇÕES GLOBAIS ==========
global impressora_inicializar
global impressora_listar
global impressora_imprimir_texto
global impressora_imprimir_arquivo
global impressora_status
global impressora_ler_status
global impressora_cancelar
global impressora_definir_padrao

section .data
msg_detectada:           db "  [OK] Impressora detectada: ", 0
msg_nao_encontrada:      db "  [!] Nenhuma impressora detectada", 0
msg_padrao:              db "  [OK] Impressora padrao atualizada", 0
msg_sem_imp:             db "  [!] Erro: Nenhuma impressora pronta", 0
msg_fila_vazia:          db "  [i] Fila de impressao limpa", 0

nome_lpt:                db "LPT1 - Paralela (0x378)", 0
nome_usb:                db "Impressora USB (0x03F0)", 0
nome_rede:               db "Impressora de Rede (9100)", 0
nome_nenhuma:            db "Nenhuma", 0

section .bss
align 8
status_impressora:       resd 1
tipo_conexao:            resd 1
porta_atual:             resq 1
impressora_padrao:       resq 1
fila_impressao:          resq 1
nome_impressora:         resb 64

section .text

; ==========================================
; 🔧 AUXILIAR: COPIAR STRING ZERO-TERMINADA
; Entrada: rsi = origem, rdi = destino, rcx = max bytes
; ==========================================
imp_copiar_nome:
    test    rcx, rcx
    jz      .fim
.loop:
    dec     rcx
    jz      .termina
    lodsb
    stosb
    test    al, al
    jnz     .loop
    ret
.termina:
    mov     byte [rdi], 0
.fim:
    ret

; ==========================================
; 🚀 impressora_inicializar() — Detecta e prepara
; ==========================================
impressora_inicializar:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16

    mov     dword [rel status_impressora], IMPRESSORA_DESCONECTADA
    mov     dword [rel tipo_conexao], CONEXAO_NENHUMA
    mov     qword [rel porta_atual], 0

    lea     rsi, [rel nome_nenhuma]
    lea     rdi, [rel nome_impressora]
    mov     rcx, 64
    call    imp_copiar_nome

    ; 1. Criar fila de impressão (até 32 trabalhos)
    mov     rdi, 32
    call    fila_criar
    mov     [rel fila_impressao], rax

    ; 2. Detecção automática em cascata (LPT1 -> USB -> Rede)
    call    detectar_lpt
    cmp     rax, 1
    je      .encontrada

    call    detectar_usb
    cmp     rax, 1
    je      .encontrada

    call    detectar_rede
    cmp     rax, 1
    je      .encontrada

    ; Nenhuma impressora presente
    lea     rsi, [rel msg_nao_encontrada]
    call    print_string
    call    print_newline
    xor     rax, rax
    jmp     .fim

.encontrada:
    mov     dword [rel status_impressora], IMPRESSORA_PRONTA
    lea     rsi, [rel msg_detectada]
    call    print_string
    lea     rsi, [rel nome_impressora]
    call    print_string
    call    print_newline
    mov     rax, 1

.fim:
    mov     rsp, rbp
    pop     rbp
    ret

; ==========================================
; 📋 impressora_listar() — Exibe impressora ativa
; ==========================================
impressora_listar:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16

    cmp     dword [rel status_impressora], IMPRESSORA_DESCONECTADA
    je      .nenhuma

    lea     rsi, [rel msg_detectada]
    call    print_string
    lea     rsi, [rel nome_impressora]
    call    print_string
    call    print_newline
    mov     rax, 1
    jmp     .fim

.nenhuma:
    lea     rsi, [rel msg_nao_encontrada]
    call    print_string
    call    print_newline
    xor     rax, rax

.fim:
    mov     rsp, rbp
    pop     rbp
    ret

; ==========================================
; 🖨️ impressora_imprimir_texto(texto, tamanho)
; Entrada: rdi = ponteiro texto, rsi = tamanho em bytes
; Saída:   rax = 0 (sucesso), -1 (erro)
; ==========================================
impressora_imprimir_texto:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    and     rsp, -16

    test    rdi, rdi
    jz      .erro
    test    rsi, rsi
    jle     .erro

    mov     r12, rdi                ; Preserva ponteiro do buffer
    mov     r13, rsi                ; Preserva tamanho em bytes

    mov     eax, [rel status_impressora]
    cmp     eax, IMPRESSORA_PRONTA
    jne     .erro

    mov     dword [rel status_impressora], IMPRESSORA_IMPRIMINDO

    ; 1. Enfileira trabalho de impressão se a fila existir
    mov     rdi, [rel fila_impressao]
    test    rdi, rdi
    jz      .despachar
    mov     rsi, r12
    mov     rdx, r13
    xor     rcx, rcx
    xor     r8, r8
    xor     r9, r9
    call    fila_adicionar

    mov     rdi, [rel fila_impressao]
    call    fila_processar

.despachar:
    mov     eax, [rel tipo_conexao]
    cmp     eax, CONEXAO_PARALELA
    je      .enviar_lpt
    cmp     eax, CONEXAO_USB
    je      .enviar_usb
    cmp     eax, CONEXAO_REDE
    je      .enviar_rede
    jmp     .erro

.enviar_lpt:
    mov     rsi, r12                ; Origem para lodsb
    mov     rcx, r13                ; Quantidade de bytes
.lpt_byte:
    ; Aguarda impressora ficar livre (bit BUSY == 1) com timeout seguro
    mov     ebx, LPT1_TIMEOUT
    mov     dx, LPT1_PORTA_STATUS
.lpt_espera_livre:
    in      al, dx
    test    al, LPT1_STAT_BUSY
    jnz     .lpt_pronta
    pause
    dec     ebx
    jnz     .lpt_espera_livre
    jmp     .erro_hw

.lpt_pronta:
    lodsb
    mov     dx, LPT1_PORTA_DATA
    out     dx, al

    ; Pulso STROBE na porta de controle (0x37A)
    mov     dx, LPT1_PORTA_CTRL
    mov     al, LPT1_CTRL_INIT | LPT1_CTRL_SELECT_IN | LPT1_CTRL_STROBE
    out     dx, al
    nop
    nop
    mov     al, LPT1_CTRL_INIT | LPT1_CTRL_SELECT_IN
    out     dx, al

    dec     rcx
    jnz     .lpt_byte
    jmp     .concluido

.enviar_usb:
    mov     rdi, [rel porta_atual]
    mov     rsi, r12
    mov     rdx, r13
    call    sys_usb_enviar_dados
    cmp     rax, -1
    je      .erro_hw
    jmp     .concluido

.enviar_rede:
    mov     rdi, [rel porta_atual]
    mov     rsi, r12
    mov     rdx, r13
    call    sys_rede_enviar
    cmp     rax, -1
    je      .erro_hw

.concluido:
    mov     dword [rel status_impressora], IMPRESSORA_PRONTA
    xor     rax, rax
    jmp     .fim

.erro_hw:
    mov     dword [rel status_impressora], IMPRESSORA_ERRO
.erro:
    mov     rax, -1

.fim:
    lea     rsp, [rbp - 24]
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ==========================================
; 📄 impressora_imprimir_arquivo(caminho)
; Entrada: rdi = ponteiro para string do caminho
; ==========================================
impressora_imprimir_arquivo:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16

    test    rdi, rdi
    jz      .erro

    call    arquivo_ler_todo        ; Retorna RAX = buffer, RDX = tamanho
    test    rax, rax
    jz      .erro

    mov     rdi, rax
    mov     rsi, rdx
    call    impressora_imprimir_texto
    jmp     .fim

.erro:
    mov     rax, -1

.fim:
    mov     rsp, rbp
    pop     rbp
    ret

; ==========================================
; 📊 STATUS DO DRIVER (Padrão Systray / Painel)
; ==========================================
impressora_status:
    mov     eax, [rel status_impressora]
    ret

impressora_ler_status:
    xor     rax, rax
    cmp     dword [rel status_impressora], IMPRESSORA_PRONTA
    jne     .verifica_conectada
    mov     al, 3                   ; bit 0 = conectada, bit 1 = pronta
    ret
.verifica_conectada:
    cmp     dword [rel status_impressora], IMPRESSORA_IMPRIMINDO
    jne     .off
    mov     al, 1
.off:
    ret

; ==========================================
; 🛑 impressora_cancelar() — Limpa fila e restaura estado
; ==========================================
impressora_cancelar:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16

    mov     rdi, [rel fila_impressao]
    test    rdi, rdi
    jz      .restaura
    call    fila_limpar

.restaura:
    cmp     dword [rel tipo_conexao], CONEXAO_NENHUMA
    je      .fim
    mov     dword [rel status_impressora], IMPRESSORA_PRONTA

.fim:
    mov     rsp, rbp
    pop     rbp
    ret

; ==========================================
; ⭐ impressora_definir_padrao(indice)
; ==========================================
impressora_definir_padrao:
    mov     [rel impressora_padrao], rdi
    ret

; ==========================================
; 🔍 ROTINAS INTERNAS DE DETECÇÃO DE HARDWARE
; ==========================================
detectar_lpt:
    ; Teste real de presença LPT1: escreve 0x55/0xAA na porta DATA e lê de volta
    mov     dx, LPT1_PORTA_DATA
    mov     al, 0x55
    out     dx, al
    nop
    in      al, dx
    cmp     al, 0x55
    jne     .nao

    mov     al, 0xAA
    out     dx, al
    nop
    in      al, dx
    cmp     al, 0xAA
    jne     .nao

    ; Restaura 0x00 e envia pulso INIT na porta de controle
    xor     al, al
    out     dx, al
    mov     dx, LPT1_PORTA_CTRL
    mov     al, LPT1_CTRL_INIT | LPT1_CTRL_SELECT_IN
    out     dx, al

    lea     rsi, [rel nome_lpt]
    lea     rdi, [rel nome_impressora]
    mov     rcx, 64
    call    imp_copiar_nome

    mov     dword [rel tipo_conexao], CONEXAO_PARALELA
    mov     qword [rel porta_atual], LPT1_PORTA_DATA
    mov     rax, 1
    ret

.nao:
    xor     rax, rax
    ret

detectar_usb:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16

    mov     rdi, 0x03F0             ; Vendor HP / Classe Impressora USB
    xor     rsi, rsi
    call    sys_usb_encontrar_dispositivo
    test    rax, rax
    jz      .nao

    mov     [rel porta_atual], rax
    lea     rsi, [rel nome_usb]
    lea     rdi, [rel nome_impressora]
    mov     rcx, 64
    call    imp_copiar_nome

    mov     dword [rel tipo_conexao], CONEXAO_USB
    mov     rax, 1
    jmp     .fim

.nao:
    xor     rax, rax
.fim:
    mov     rsp, rbp
    pop     rbp
    ret

detectar_rede:
    xor     rax, rax
    ret
