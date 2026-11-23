; ==================================================
; FydelisTechOS — net_client.asm
; Interface de usuário para rede e WiFi
; ==================================================
bits 64
%include "syscalls/rede_syscalls.inc"
%include "syscalls/user_syscalls.inc"

section .text

; ══════════════════════════════════════════════════
; Inicializar Interface de Rede
; Saída: rax = 0 pronto / <0 erro
; ══════════════════════════════════════════════════
global net_inicializar
net_inicializar:
    mov  rax, SYS_REDE_INICIALIZAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Conectar WiFi
; Entrada: rdi = SSID, rsi = senha
; Saída: rax = 0 conectado / <0 erro
; ══════════════════════════════════════════════════
global net_wifi_conectar
net_wifi_conectar:
    mov  rax, SYS_WIFI_CONECTAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Obter Status da Conexão
; Saída: rax = flags de status
; ══════════════════════════════════════════════════
global net_status
net_status:
    mov  rax, SYS_REDE_STATUS
    syscall
    ret

; ══════════════════════════════════════════════════
; Enviar Pacote
; Entrada: rdi = IP destino, rsi = porta, rdx = dados, rcx = tamanho
; ══════════════════════════════════════════════════
global net_enviar
net_enviar:
    mov  rax, SYS_REDE_ENVIAR
    syscall
    ret

; ══════════════════════════════════════════════════
; Receber Pacote
; Entrada: rdi = buffer, rsi = capacidade
; Saída: rax = bytes recebidos / <0 erro
; ══════════════════════════════════════════════════
global net_receber
net_receber:
    mov  rax, SYS_REDE_RECEBER
    syscall
    ret

; ══════════════════════════════════════════════════
; Obter Endereço IP Local
; Saída: rax = IP (formato 0xHHHHHHHH)
; ══════════════════════════════════════════════════
global net_meu_ip
net_meu_ip:
    mov  rax, SYS_REDE_MEU_IP
    syscall
    ret

; ══════════════════════════════════════════════════
; Desconectar
; ══════════════════════════════════════════════════
global net_desconectar
net_desconectar:
    mov  rax, SYS_REDE_DESCONECTAR
    syscall
    ret