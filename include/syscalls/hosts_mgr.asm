; ==========================================
; HOSTS_MGR.ASM — Tabela Nome ↔ IP
; FydelisTechOS v2.2 · Sistema PRÓPRIO — Letras A:→Z:
; NÃO depende de Linux nem Windows!
; ==========================================
BITS 64
default rel
%include "fydelterm.inc"

; 📂 Arquivo fica na unidade do sistema, pasta Sistema
; Ex: C:\Sistema\hosts.fyd
HOSTS_ARQUIVO  equ "Sistema/hosts.fyd"

; 📦 Estrutura de memória
MAX_ENTRADAS   equ 64
TAM_IP         equ 16
TAM_NOME       equ 64

struc EntradaHost
    ip:        resb TAM_IP
    nome:      resb TAM_NOME
    proximo:   resq 1
endstruc

; 📤 Funções externas
extern arquivo_abrir
extern arquivo_ler_linha
extern arquivo_escrever_linha
extern arquivo_fechar
extern arquivo_existe
extern arquivo_criar
extern strcmp
extern strcpy
extern print_string
extern print_newline
extern obter_unidade_sistema   ; Retorna letra ex: 'C'

global hosts_inicializar
global hosts_listar
global hosts_adicionar
global hosts_remover
global hosts_resolver

section .data
mensagem_cabecalho:  db "=== Tabela de Nomes da Rede ===", 10, 0
mensagem_linha:      db "%-15s  %s", 10, 0
mensagem_naoencontr: db "Não encontrado: ", 0
mensagem_criado:     db "[OK] Arquivo de hosts criado em %c:\Sistema\hosts.fyd", 10, 0
formato_caminho:     db "%c:/Sistema/hosts.fyd", 0
buffer_caminho:      times 64 db 0

section .bss
ponteiro_arquivo:    resq 1
unidade_sistema:     resb 1
entradas_carregadas: resd 1

section .text

; ==========================================
; hosts_inicializar() — Carrega ou cria o arquivo
; ==========================================
hosts_inicializar:
    push rcx
    push rdx

    ; 📝 Descobrir letra da unidade do sistema
    call obter_unidade_sistema
    mov [unidade_sistema], al

    ; 📝 Montar caminho: "C:/Sistema/hosts.fyd"
    mov rdi, buffer_caminho
    mov rsi, formato_caminho
    movzx rdx, byte [unidade_sistema]
    xor rax, rax
    call sprintf  ; ou implementação própria de montagem de string

    ; 📝 Verificar se existe
    mov rdi, buffer_caminho
    call arquivo_existe
    test rax, rax
    jnz .carregar

    ; 🆕 Não existe → criar arquivo padrão
    mov rdi, buffer_caminho
    call arquivo_criar
    mov rsi, mensagem_criado
    movzx rdx, byte [unidade_sistema]
    call print_string_com_letra

.carregar:
    ; ✅ Carregar entradas para memória
    mov rdi, buffer_caminho
    mov rsi, 0        ; modo leitura
    call arquivo_abrir
    mov [ponteiro_arquivo], rax

    mov dword [entradas_carregadas], 0

.ler_linha:
    mov rdi, [ponteiro_arquivo]
    call arquivo_ler_linha
    test rax, rax
    jz .fim_carregamento

    ; Ignorar linhas vazias e comentários
    cmp byte [rax], ';'
    je .ler_linha
    cmp byte [rax], '#'
    je .ler_linha
    cmp byte [rax], 0
    je .ler_linha

    ; Analisar linha: IP + NOME
    call parsear_linha_hosts
    jmp .ler_linha

.fim_carregamento:
    mov rdi, [ponteiro_arquivo]
    call arquivo_fechar

    pop rdx
    pop rcx
    ret

; ==========================================
; hosts_listar() — Exibe todas as entradas
; ==========================================
hosts_listar:
    push rsi
    push rdi

    mov rsi, mensagem_cabecalho
    call print_string
    call print_newline

    ; Percorrer lista em memória
    mov rbx, 0
.listar_loop:
    cmp rbx, MAX_ENTRADAS
    jae .fim

    ; Se entrada usada → exibir
    cmp byte [rbx + EntradaHost.ip], 0
    jz .proximo

    mov rsi, mensagem_linha
    mov rdx, rbx + EntradaHost.ip
    mov rcx, rbx + EntradaHost.nome
    call print_formatado

.proximo:
    add rbx, EntradaHost_size
    jmp .listar_loop

.fim:
    pop rdi
    pop rsi
    ret

; ==========================================
; hosts_adicionar(ip, nome) — Adiciona entrada
; ==========================================
hosts_adicionar:
    ; rdi = IP, rsi = Nome
    push rdi
    push rsi

    ; Procurar entrada vazia ou mesmo nome para substituir
    mov rbx, 0
.procurar:
    cmp rbx, MAX_ENTRADAS
    jae .cheio

    cmp byte [rbx + EntradaHost.nome], 0
    jz .encontrado_livre

    mov rdx, rsi
    mov rcx, rbx + EntradaHost.nome
    call strcmp
    test rax, rax
    jz .substituir

    add rbx, EntradaHost_size
    jmp .procurar

.encontrado_livre:
    inc dword [entradas_carregadas]

.substituir:
    ; Copiar IP
    mov rdi, rbx + EntradaHost.ip
    call strcpy
    ; Copiar Nome
    mov rdi, rbx + EntradaHost.nome
    pop rsi
    call strcpy

    ; Salvar no disco
    call salvar_arquivo
    jmp .fim

.cheio:
    pop rsi
    pop rdi
    mov rax, -1   ; Sem espaço
    ret

.fim:
    pop rdi
    xor rax, rax
    ret

; ==========================================
; hosts_remover(nome) — Apaga entrada
; ==========================================
hosts_remover:
    ; rdi = Nome para remover
    push rbx
    push rdi

    mov rbx, 0
.procurar:
    cmp rbx, MAX_ENTRADAS
    jae .naoencontrado

    cmp byte [rbx + EntradaHost.nome], 0
    jz .proximo

    mov rsi, rdi
    mov rdi, rbx + EntradaHost.nome
    call strcmp
    test rax, rax
    jz .apagar

.proximo:
    add rbx, EntradaHost_size
    jmp .procurar

.apagar:
    mov byte [rbx + EntradaHost.ip], 0
    mov byte [rbx + EntradaHost.nome], 0
    dec dword [entradas_carregadas]
    call salvar_arquivo
    xor rax, rax
    jmp .fim

.naoencontrado:
    mov rax, -1

.fim:
    pop rdi
    pop rbx
    ret

; ==========================================
; hosts_resolver(nome) → ponteiro para IP ou 0
; ==========================================
hosts_resolver:
    ; rdi = Nome
    push rbx

    mov rbx, 0
.procurar:
    cmp rbx, MAX_ENTRADAS
    jae .naoencontrado

    cmp byte [rbx + EntradaHost.nome], 0
    jz .proximo

    mov rsi, rdi
    mov rdi, rbx + EntradaHost.nome
    call strcmp
    test rax, rax
    jz .encontrado

.proximo:
    add rbx, EntradaHost_size
    jmp .procurar

.encontrado:
    lea rax, [rbx + EntradaHost.ip]
    jmp .fim

.naoencontrado:
    xor rax, rax

.fim:
    pop rbx
    ret

; ==========================================
; Funções auxiliares internas
; ==========================================
salvar_arquivo:
    ; Reescreve todo o arquivo com dados da memória
    mov rdi, buffer_caminho
    mov rsi, 1   ; modo escrita
    call arquivo_abrir
    mov [ponteiro_arquivo], rax

    ; Cabeçalho
    mov rdi, [ponteiro_arquivo]
    mov rsi, "; Arquivo de Hosts — FydelisTechOS v2.2", 10
    call arquivo_escrever_linha

    ; Entradas
    mov rbx, 0
.escrever_loop:
    cmp rbx, MAX_ENTRADAS
    jae .fim

    cmp byte [rbx + EntradaHost.ip], 0
    jz .proximo

    ; Linha: IP + espaço + Nome
    mov rdi, [ponteiro_arquivo]
    mov rsi, rbx + EntradaHost.ip
    call arquivo_escrever_linha
    mov rsi, " "
    call arquivo_escrever_linha
    mov rsi, rbx + EntradaHost.nome
    call arquivo_escrever_linha
    mov rsi, 10
    call arquivo_escrever_linha

.proximo:
    add rbx, EntradaHost_size
    jmp .escrever_loop

.fim:
    mov rdi, [ponteiro_arquivo]
    call arquivo_fechar
    ret

parsear_linha_hosts:
    ; rdi = linha → separa IP e Nome
    ; Simplificado: IP até primeiro espaço, resto = nome
    ret