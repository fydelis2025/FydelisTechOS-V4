; ==================================================
; FydelisTechOS — fs_client.asm
; Interface de usuário para disco e arquivos
; ==================================================
bits 64
%include "syscalls/disktools_syscalls.inc"
%include "syscalls/user_syscalls.inc"

section .text

; ══════════════════════════════════════════════════
; Montar Disco / Partição
; Entrada: rdi = caminho_origem, rsi = letra (ex: 'C')
; Saída: rax = 0 sucesso / <0 erro
; ══════════════════════════════════════════════════
global fs_montar
fs_montar:
    mov  rax, SYS_DISCO_MONTAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Desmontar
; Entrada: rdi = letra
; Saída: rax = 0 sucesso / <0 erro
; ══════════════════════════════════════════════════
global fs_desmontar
fs_desmontar:
    mov  rax, SYS_DISCO_DESMONTAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Abrir Arquivo
; Entrada: rdi = caminho, rsi = modo (leitura/escrita)
; Saída: rax = descritor / <0 erro
; ══════════════════════════════════════════════════
global fs_abrir
fs_abrir:
    mov  rax, SYS_ARQUIVO_ABRIR
    syscall
    ret

; ══════════════════════════════════════════════════
; Fechar Arquivo
; Entrada: rdi = descritor
; ══════════════════════════════════════════════════
global fs_fechar
fs_fechar:
    mov  rax, SYS_ARQUIVO_FECHAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Ler do Arquivo
; Entrada: rdi = descritor, rsi = buffer, rdx = tamanho
; Saída: rax = bytes lidos / <0 erro
; ══════════════════════════════════════════════════
global fs_ler
fs_ler:
    mov  rax, SYS_ARQUIVO_LER
    syscall
    ret

; ══════════════════════════════════════════════════
; Escrever no Arquivo
; Entrada: rdi = descritor, rsi = dados, rdx = tamanho
; Saída: rax = bytes escritos / <0 erro
; ══════════════════════════════════════════════════
global fs_escrever
fs_escrever:
    mov  rax, SYS_ARQUIVO_ESCREVER
    syscall
    ret

; ══════════════════════════════════════════════════
; Listar Diretório
; Entrada: rdi = caminho, rsi = buffer_saída, rdx = capacidade
; Saída: rax = número de entradas / <0 erro
; ══════════════════════════════════════════════════
global fs_listar
fs_listar:
    mov  rax, SYS_DIRETORIO_LISTAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Criar Diretório
; Entrada: rdi = caminho
; ══════════════════════════════════════════════════
global fs_criar_dir
fs_criar_dir:
    mov  rax, SYS_DIRETORIO_CRIAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Remover Arquivo (syscall user-space)
; Entrada: rdi = caminho
; ══════════════════════════════════════════════════
global fs_user_remover
fs_user_remover:
    mov  rax, SYS_ARQUIVO_REMOVER
    syscall
    ret
