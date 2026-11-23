; ============================================================================
; HOSTS_MGR.ASM — Tabela Nome <-> IP (/fyd/rede/cfg/hosts.fcfg)
; FydelisTech OS v4.2 — Integrado ao estrutura.asm (Sem letras C:/D:)
; Salvador - Bahia
; ============================================================================
BITS 64
default rel
%include "fydelterm.inc"

; Estrutura de memoria
MAX_ENTRADAS   equ 64
TAM_IP         equ 16
TAM_NOME       equ 64

struc EntradaHost
    .ip:      resb TAM_IP
    .nome:    resb TAM_NOME
    .proximo: resq 1
endstruc

; Funcoes exportadas pelo kernel/estrutura.asm e kernel/strings
extern fs_caminho_existe
extern fs_criar_diretorio
extern strcmp
extern strcpy
extern strlen
extern print_string
extern print_newline

; Exportacao publica
global hosts_inicializar
global hosts_listar
global hosts_adicionar
global hosts_remover
global hosts_resolver
global hosts_obter_arquivo_fcfg

section .data
caminho_hosts_fcfg:  db "/fyd/rede/cfg/hosts.fcfg", 0

ip_localhost:        db "127.0.0.1", 0
nome_localhost:      db "localhost", 0
ip_gateway:          db "10.0.2.2", 0
nome_gateway:        db "gateway.fydelis", 0

mensagem_cabecalho:  db "=== Tabela de Nomes (/fyd/rede/cfg/hosts.fcfg) ===", 10, 0
mensagem_cheio:      db "Tabela de hosts cheia!", 10, 0
mensagem_criado:     db "[OK] Tabela /fyd/rede/cfg/hosts.fcfg inicializada", 10, 0
cabecalho_fcfg:      db "#!FYDCFG v1", 10, "# Tabela de Hosts FydelisTech OS", 10, 0
espaco_str:          db " ", 0

section .bss
entradas_carregadas: resd 1
entradas:            resb MAX_ENTRADAS * EntradaHost_size
buffer_export_fcfg:  resb 2048

section .text

; ============================================================================
; hosts_inicializar() — Registra /fyd/rede/cfg/hosts.fcfg e popula base
; ============================================================================
hosts_inicializar:
    push rbx
    push rsi
    push rdi

    ; Verifica se /fyd/rede/cfg/hosts.fcfg ja esta na tabela do estrutura.asm
    lea rdi, [rel caminho_hosts_fcfg]
    call fs_caminho_existe
    test rax, rax
    jnz .popular_padrao

    lea rdi, [rel caminho_hosts_fcfg]
    call fs_criar_diretorio

.popular_padrao:
    ; Limpa tabela em memoria
    lea rdi, [rel entradas]
    xor eax, eax
    mov rcx, MAX_ENTRADAS * EntradaHost_size
    rep stosb
    mov dword [rel entradas_carregadas], 0

    ; Adiciona entradas padrao da rede FydelisTech OS
    lea rdi, [rel ip_localhost]
    lea rsi, [rel nome_localhost]
    call hosts_adicionar

    lea rdi, [rel ip_gateway]
    lea rsi, [rel nome_gateway]
    call hosts_adicionar

    lea rsi, [rel mensagem_criado]
    call print_string

    pop rdi
    pop rsi
    pop rbx
    ret

; ============================================================================
; hosts_listar() — Exibe todas as entradas no terminal
; ============================================================================
hosts_listar:
    push rbx
    push rsi
    push rdi

    lea rsi, [rel mensagem_cabecalho]
    call print_string

    lea rbx, [rel entradas]
.listar_loop:
    lea rax, [rel entradas + MAX_ENTRADAS * EntradaHost_size]
    cmp rbx, rax
    jae .fim

    cmp byte [rbx + EntradaHost.ip], 0
    jz .proximo

    lea rsi, [rbx + EntradaHost.ip]
    call print_string
    lea rdi, [rbx + EntradaHost.ip]
    call strlen
    mov rcx, 16
    sub rcx, rax
    jg .preencher
    xor rcx, rcx
.preencher:
    test rcx, rcx
    jz .nome
    push rcx
    lea rsi, [rel espaco_str]
    call print_string
    pop rcx
    dec rcx
    jmp .preencher
.nome:
    lea rsi, [rbx + EntradaHost.nome]
    call print_string
    call print_newline

.proximo:
    add rbx, EntradaHost_size
    jmp .listar_loop

.fim:
    pop rdi
    pop rsi
    pop rbx
    ret

; ============================================================================
; hosts_adicionar(ip, nome) — Adiciona ou atualiza entrada em RAM e .fcfg
; rdi = ponteiro IP | rsi = ponteiro Nome -> rax = 0 OK, -1 cheia
; ============================================================================
hosts_adicionar:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi

    lea rbx, [rel entradas]
    xor r14d, r14d
.procurar:
    cmp r14d, MAX_ENTRADAS
    jae .cheio

    cmp byte [rbx + EntradaHost.nome], 0
    jz .encontrado_livre

    mov rdi, r13
    lea rsi, [rbx + EntradaHost.nome]
    call strcmp
    test rax, rax
    jz .substituir

    add rbx, EntradaHost_size
    inc r14d
    jmp .procurar

.encontrado_livre:
    inc dword [rel entradas_carregadas]

.substituir:
    lea rdi, [rbx + EntradaHost.ip]
    mov rsi, r12
    call strcpy

    lea rdi, [rbx + EntradaHost.nome]
    mov rsi, r13
    call strcpy

    call sincronizar_buffer_fcfg
    xor eax, eax
    jmp .fim

.cheio:
    lea rsi, [rel mensagem_cheio]
    call print_string
    mov rax, -1

.fim:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; hosts_remover(nome) — Remove entrada pelo nome
; rdi = nome -> rax = 0 OK, -1 nao encontrado
; ============================================================================
hosts_remover:
    push rbx
    push r12

    mov r12, rdi
    lea rbx, [rel entradas]
    xor ecx, ecx
.procurar:
    cmp ecx, MAX_ENTRADAS
    jae .naoencontrado

    cmp byte [rbx + EntradaHost.nome], 0
    jz .proximo

    mov rdi, r12
    lea rsi, [rbx + EntradaHost.nome]
    call strcmp
    test rax, rax
    jz .apagar

.proximo:
    add rbx, EntradaHost_size
    inc ecx
    jmp .procurar

.apagar:
    mov byte [rbx + EntradaHost.ip], 0
    mov byte [rbx + EntradaHost.nome], 0
    dec dword [rel entradas_carregadas]
    call sincronizar_buffer_fcfg
    xor eax, eax
    jmp .fim

.naoencontrado:
    mov rax, -1

.fim:
    pop r12
    pop rbx
    ret

; ============================================================================
; hosts_resolver(nome) -> rax = ponteiro para IP ou 0
; ============================================================================
hosts_resolver:
    push rbx
    push r12

    mov r12, rdi
    lea rbx, [rel entradas]
    xor ecx, ecx
.procurar:
    cmp ecx, MAX_ENTRADAS
    jae .naoencontrado

    cmp byte [rbx + EntradaHost.nome], 0
    jz .proximo

    mov rdi, r12
    lea rsi, [rbx + EntradaHost.nome]
    call strcmp
    test rax, rax
    jz .encontrado

.proximo:
    add rbx, EntradaHost_size
    inc ecx
    jmp .procurar

.encontrado:
    lea rax, [rbx + EntradaHost.ip]
    jmp .fim

.naoencontrado:
    xor eax, eax

.fim:
    pop r12
    pop rbx
    ret

; ============================================================================
; sincronizar_buffer_fcfg — Serializa a tabela no formato "#!FYDCFG v1" (nome=ip)
; ============================================================================
sincronizar_buffer_fcfg:
    push rbx
    push rsi
    push rdi

    lea rdi, [rel buffer_export_fcfg]
    lea rsi, [rel cabecalho_fcfg]
.copia_hdr:
    lodsb
    test al, al
    jz .loop_itens
    stosb
    jmp .copia_hdr

.loop_itens:
    lea rbx, [rel entradas]
.item:
    lea rax, [rel entradas + MAX_ENTRADAS * EntradaHost_size]
    cmp rbx, rax
    jae .terminar

    cmp byte [rbx + EntradaHost.nome], 0
    jz .prox_item

    ; Escreve "nome=ip\n" (compativel com fyd_cfg_ler_chave!)
    lea rsi, [rbx + EntradaHost.nome]
.copia_nome:
    lodsb
    test al, al
    jz .poe_igual
    stosb
    jmp .copia_nome

.poe_igual:
    mov byte [rdi], '='
    inc rdi

    lea rsi, [rbx + EntradaHost.ip]
.copia_ip:
    lodsb
    test al, al
    jz .poe_nl
    stosb
    jmp .copia_ip

.poe_nl:
    mov byte [rdi], 10
    inc rdi

.prox_item:
    add rbx, EntradaHost_size
    jmp .item

.terminar:
    mov byte [rdi], 0
    pop rdi
    pop rsi
    pop rbx
    ret

; Exporta ponteiro do conteudo .fcfg para C (exec.c / fyd_formatos.c)
hosts_obter_arquivo_fcfg:
    lea rax, [rel buffer_export_fcfg]
    ret
