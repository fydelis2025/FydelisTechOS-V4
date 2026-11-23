; ============================================================================
; COMPAT_STUBS.ASM — Símbolos Auxiliares, Stubs Seguros & Conversões ABI x86_64
; FydelisTech OS v4.2 · Salvador • Bahia
; ============================================================================
BITS 64
default rel
[warning suppress reloc-rel-dword]
%include "fydelterm.inc"

; ============================================================================
; EXTERNAIS & GLOBAIS
; ============================================================================
extern print_string, print_num
extern dhcp_cliente_iniciar, dhcp_cliente_processar
extern dhcp_ip_atual, dhcp_estado
extern arquivo_abrir, arquivo_ler_linha, arquivo_escrever_linha
extern arquivo_existe, arquivo_criar

global strcmpi, strcmp, strcpy, strlen
global int_para_str, print_formatado
global rx_bytes_total, tx_bytes_total
global usb_listar_dispositivos, dhcp_exec
global arquivo_fechar, arquivo_ler_todo, obter_unidade_sistema
global fila_criar, fila_adicionar, fila_processar, fila_limpar
global sys_usb_listar, sys_usb_enviar_dados, sys_usb_encontrar_dispositivo
global sys_rede_enviar
global wifi_tx_quadro, wifi_rx_quadro
global fs_criar_arquivo, fs_lseek

; ============================================================================
; DADOS NÃO INICIALIZADOS (.bss)
; ============================================================================
section .bss
align 16
rx_bytes_total:   resq 1
tx_bytes_total:   resq 1

; Fila de impressão simples: 16 entradas x 128 bytes
fila_buf:         resb 16 * 128
fila_qtd:         resd 1

; Tabela de cursores de arquivo (64 descritores x 8 bytes)
fyd_fd_pos:       resq 64

; ============================================================================
; ROTINAS DE STRING & CONVERSÃO (.text)
; ============================================================================
section .text

; ---------- strcmpi(rdi, rsi) -> rax=0 se iguais ----------
strcmpi:
    push    r8
.loop:
    movzx   eax, byte [rdi]
    movzx   r8d, byte [rsi]
    cmp     al, 'A'
    jb      .ok1
    cmp     al, 'Z'
    ja      .ok1
    add     al, 32
.ok1:
    cmp     r8b, 'A'
    jb      .ok2
    cmp     r8b, 'Z'
    ja      .ok2
    add     r8b, 32
.ok2:
    cmp     al, r8b
    jne     .dif
    test    al, al
    jz      .igual
    inc     rdi
    inc     rsi
    jmp     .loop
.dif:
    movzx   eax, byte [rdi]
    movzx   r8d, byte [rsi]
    sub     eax, r8d
    pop     r8
    ret
.igual:
    xor     eax, eax
    pop     r8
    ret

; ---------- strcmp(rdi, rsi) -> rax=0 se iguais ----------
strcmp:
    push    r8
.loop:
    movzx   eax, byte [rdi]
    movzx   r8d, byte [rsi]
    cmp     al, r8b
    jne     .dif
    test    al, al
    jz      .igual
    inc     rdi
    inc     rsi
    jmp     .loop
.dif:
    sub     eax, r8d
    pop     r8
    ret
.igual:
    xor     eax, eax
    pop     r8
    ret

; ---------- strcpy(rdi=dst, rsi=src) ----------
strcpy:
    push    rdi
    push    rsi
.loop:
    lodsb
    stosb
    test    al, al
    jnz     .loop
    pop     rsi
    pop     rdi
    ret

; ---------- strlen(rdi) -> rax ----------
strlen:
    xor     eax, eax
.loop:
    cmp     byte [rdi + rax], 0
    je      .fim
    inc     rax
    jmp     .loop
.fim:
    ret

; ---------- int_para_str(rdi=buffer, rax=valor) decimal ----------
int_para_str:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rbp
    mov     rsi, rdi
    mov     rbp, rdi
    mov     rbx, 10
    add     rsi, 31
    mov     byte [rsi], 0
.converter:
    xor     edx, edx
    div     rbx
    add     dl, '0'
    dec     rsi
    mov     [rsi], dl
    test    rax, rax
    jnz     .converter
    mov     rdi, rbp
.copiar:
    lodsb
    stosb
    test    al, al
    jnz     .copiar
    pop     rbp
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ---------- print_formatado(rdi=string) ----------
print_formatado:
    push    rsi
    mov     rsi, rdi
    call    print_string
    pop     rsi
    ret

; ============================================================================
; USB & REDE STUBS
; ============================================================================

usb_listar_dispositivos:
    xor     eax, eax
    ret

dhcp_exec:
    push    r12
    call    dhcp_cliente_iniciar
    xor     r12, r12
.aguardar:
    mov     eax, [rel dhcp_estado]
    cmp     eax, 3
    je      .ok
    call    dhcp_cliente_processar
    inc     r12
    cmp     r12, 1000000
    jb      .aguardar
    xor     eax, eax
    pop     r12
    ret
.ok:
    mov     eax, [rel dhcp_ip_atual]
    test    eax, eax
    jz      .falhou
    mov     eax, 1
    pop     r12
    ret
.falhou:
    xor     eax, eax
    pop     r12
    ret

sys_rede_enviar:
    xor     eax, eax
    ret

wifi_tx_quadro:
    xor     eax, eax
    ret

wifi_rx_quadro:
    xor     eax, eax
    ret

sys_usb_listar:
    xor     eax, eax
    ret

sys_usb_enviar_dados:
    xor     eax, eax
    ret

sys_usb_encontrar_dispositivo:
    xor     eax, eax
    ret

; ============================================================================
; FILA DE IMPRESSÃO
; ============================================================================

fila_criar:
    mov     dword [rel fila_qtd], 0
    mov     eax, 1
    ret

fila_adicionar:
    mov     eax, [rel fila_qtd]
    cmp     eax, 16
    jae     .cheia
    imul    rax, rax, 128
    lea     rcx, [rel fila_buf]
    add     rcx, rax
    push    rsi
    mov     rsi, rdi
    mov     rdi, rcx
    call    strcpy
    pop     rsi
    inc     dword [rel fila_qtd]
    mov     eax, 1
    ret
.cheia:
    xor     eax, eax
    ret

fila_processar:
    mov     dword [rel fila_qtd], 0
    mov     eax, 1
    ret

fila_limpar:
    mov     dword [rel fila_qtd], 0
    mov     eax, 1
    ret

; ============================================================================
; STUBS DE ARQUIVO & UNIDADE
; ============================================================================

arquivo_fechar:
    xor     eax, eax
    ret

arquivo_ler_todo:
    xor     eax, eax
    ret

fs_criar_arquivo:
    xor     eax, eax
    ret

; ---------- fs_lseek(rdi=fd, rsi=offset, rdx=origem) -> rax ----------
; origem: 0 = SEEK_SET, 1 = SEEK_CUR, 2 = SEEK_END
fs_lseek:
    cmp     rdi, 0
    jl      .erro
    cmp     rdi, 64
    jae     .erro

    lea     rcx, [rel fyd_fd_pos]
    mov     r8, [rcx + rdi * 8]

    cmp     rdx, 0
    je      .seek_set
    cmp     rdx, 1
    je      .seek_cur
    cmp     rdx, 2
    je      .seek_end
    jmp     .erro

.seek_set:
    mov     rax, rsi
    jmp     .valida_pos

.seek_cur:
    mov     rax, r8
    add     rax, rsi
    jmp     .valida_pos

.seek_end:
    mov     rax, rsi
    jmp     .valida_pos

.valida_pos:
    test    rax, rax
    js      .erro
    mov     [rcx + rdi * 8], rax
    ret

.erro:
    mov     rax, -1
    ret

obter_unidade_sistema:
    mov     al, 'C'
    ret
