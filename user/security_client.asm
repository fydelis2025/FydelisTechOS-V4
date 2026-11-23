; ==================================================
; FydelisTechOS — security_client.asm
; Interface de usuário para firewall, antivírus e CVE Shield
; ==================================================
bits 64
%include "syscalls/security_syscalls.inc"
%include "syscalls/user_syscalls.inc"

section .text

; ══════════════════════════════════════════════════
; Firewall — Habilitar/Desabilitar
; ══════════════════════════════════════════════════
global fw_habilitar
fw_habilitar:
    mov  rax, SYS_FW_HABILITAR
    syscall
    ret

global fw_desabilitar
fw_desabilitar:
    mov  rax, SYS_FW_DESABILITAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Adicionar Regra de Firewall
; Entrada: rdi = porta, rsi = protocolo, rdx = permissão
; ══════════════════════════════════════════════════
global fw_regra_adicionar
fw_regra_adicionar:
    mov  rax, SYS_FW_REGRA_ADICIONAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Antivírus — Verificar Arquivo
; Entrada: rdi = caminho
; Saída: rax = 0 limpo / <0 ameaça detectada
; ══════════════════════════════════════════════════
global av_verificar
av_verificar:
    mov  rax, SYS_AV_VERIFICAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Verificar Diretório Completo
; Entrada: rdi = caminho raiz
; ══════════════════════════════════════════════════
global av_varrer
av_varrer:
    mov  rax, SYS_AV_VARRER
    syscall
    ret

; ══════════════════════════════════════════════════
; Quarentena
; Entrada: rdi = caminho do arquivo suspeito
; ══════════════════════════════════════════════════
global av_quarentena
av_quarentena:
    mov  rax, SYS_AV_QUARENTENA
    syscall
    ret

; ══════════════════════════════════════════════════
; CVE Shield — Verificar Sistema
; Saída: rax = número de vulnerabilidades encontradas
; ══════════════════════════════════════════════════
global cve_verificar
cve_verificar:
    mov  rax, SYS_CVE_VERIFICAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Listar Log de Ameaças
; Entrada: rdi = buffer, rsi = máximo de entradas
; ══════════════════════════════════════════════════
global sec_listar_ameacas
sec_listar_ameacas:
    mov  rax, SYS_SEC_LISTAR_AMEACAS
    syscall
    ret

; ══════════════════════════════════════════════════
; Obter Status Geral de Segurança
; Saída: rax = bitmask (ver constantes)
; ══════════════════════════════════════════════════
global sec_status
sec_status:
    mov  rax, SYS_SEC_STATUS
    syscall
    ret