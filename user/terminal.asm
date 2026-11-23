; ==================================================
; FydelisTechOS — FydelTerm v2.2 COMPLETO
; Terminal Interativo — Espaço de Usuário
; Conecta: VM | Disco | Rede | Segurança
; ==================================================
bits 64

; === Incluir todas as chamadas ===
%include "syscalls/user_syscalls.inc"
%include "syscalls/virtual_syscalls.inc"
%include "syscalls/disktools_syscalls.inc"
%include "syscalls/rede_syscalls.inc"
%include "syscalls/security_syscalls.inc"

; === Declarar funções dos clientes ===
extern sys_write
extern sys_read
extern sys_setcolor
extern sys_exit

extern vm_iniciar
extern vm_parar
extern vm_status
extern vm_status_imprimir
extern vm_listar

extern fs_listar
extern fs_abrir
extern fs_ler
extern fs_fechar
extern fs_montar

extern net_status
extern net_wifi_conectar
extern net_meu_ip

extern sec_status
extern av_verificar
extern fw_habilitar

section .data
prompt          db 'FydelisTerm> ', 0
cor_prompt      equ 0x0E           ; Amarelo
cor_texto       equ 0x07           ; Branco
cor_erro        equ 0x0C           ; Vermelho
cor_sucesso     equ 0x0A           ; Verde
buffer_len      equ 256

; ── Comandos ──
cmd_ajuda       db 'ajuda', 0
cmd_vmstatus    db 'vmstatus', 0
cmd_vminiciar   db 'vminiciar', 0
cmd_vmparar     db 'vmparar', 0
cmd_vmlistar    db 'vmlistar', 0
cmd_ls          db 'ls', 0
cmd_cat         db 'cat', 0
cmd_montar      db 'montar', 0
cmd_wifi        db 'wifi', 0
cmd_ip          db 'ip', 0
cmd_fw          db 'fw', 0
cmd_av          db 'av', 0
cmd_status      db 'status', 0
cmd_exit        db 'exit', 0

section .bss
align 16
buffer_in:      resb buffer_len
param1:         resq 1             ; Primeiro argumento
param2:         resq 1             ; Segundo argumento

section .text
global fydelterm_main
fydelterm_main:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; ── Mensagem de boas-vindas ──
    mov  rdi, cor_sucesso
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_bemvindo]
    mov  rdx, msg_bemvindo_fim - msg_bemvindo
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor

.loop_prompt:
    ; ── Exibir prompt ──
    mov  rdi, cor_prompt
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel prompt]
    mov  rdx, 13
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor

    ; ── Ler entrada ──
    mov  rdi, 0
    lea  rsi, [rel buffer_in]
    mov  rdx, buffer_len
    call sys_read
    test rax, rax
    jz   .loop_prompt

    ; ── Separar comando e argumentos ──
    call quebrar_linha

    ; ── Interpretar ──
    lea  rdi, [rel buffer_in]
    call processar_comando

    jmp  .loop_prompt

sair_terminal:
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    xor  rax, rax
    ret

; ══════════════════════════════════════════════════
; INTERPRETADOR DE COMANDOS
; ══════════════════════════════════════════════════
processar_comando:
    ; Comparar com todos os comandos
    lea  rsi, [rel cmd_exit]        ; exit
    call strcmpz
    jz   .cmd_exit

    lea  rsi, [rel cmd_ajuda]       ; ajuda
    call strcmpz
    jz   .cmd_ajuda

    lea  rsi, [rel cmd_vmstatus]    ; vmstatus
    call strcmpz
    jz   .cmd_vmstatus

    lea  rsi, [rel cmd_vminiciar]   ; vminiciar
    call strcmpz
    jz   .cmd_vminiciar

    lea  rsi, [rel cmd_vmparar]     ; vmparar
    call strcmpz
    jz   .cmd_vmparar

    lea  rsi, [rel cmd_vmlistar]    ; vmlistar
    call strcmpz
    jz   .cmd_vmlistar

    lea  rsi, [rel cmd_ls]          ; ls
    call strcmpz
    jz   .cmd_ls

    lea  rsi, [rel cmd_cat]         ; cat
    call strcmpz
    jz   .cmd_cat

    lea  rsi, [rel cmd_montar]      ; montar
    call strcmpz
    jz   .cmd_montar

    lea  rsi, [rel cmd_wifi]        ; wifi
    call strcmpz
    jz   .cmd_wifi

    lea  rsi, [rel cmd_ip]          ; ip
    call strcmpz
    jz   .cmd_ip

    lea  rsi, [rel cmd_fw]          ; fw
    call strcmpz
    jz   .cmd_fw

    lea  rsi, [rel cmd_av]          ; av
    call strcmpz
    jz   .cmd_av

    lea  rsi, [rel cmd_status]      ; status
    call strcmpz
    jz   .cmd_status

    ; ── Comando desconhecido ──
    mov  rdi, cor_erro
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_desconhecido]
    mov  rdx, 20
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

; ══════════════════════════════════════════════════
; COMANDOS — IMPLEMENTAÇÃO
; ══════════════════════════════════════════════════

.cmd_exit:
    call sys_exit
    jmp  sair_terminal

.cmd_ajuda:
    mov  rdi, 1
    lea  rsi, [rel msg_ajuda]
    mov  rdx, msg_ajuda_fim - msg_ajuda
    call sys_write
    ret

.cmd_vmstatus:
    mov  rdi, 0                  ; VM padrão = 0
    call vm_status_imprimir
    ret

.cmd_vminiciar:
    mov  rdi, cor_texto
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_iniciando]
    mov  rdx, 19
    call sys_write

    mov  rdi, 0                  ; VM 0
    call vm_iniciar
    test rax, rax
    js   erro_operacao_global

    mov  rdi, cor_sucesso
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_ok]
    mov  rdx, 4
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

.cmd_vmparar:
    mov  rdi, 1
    lea  rsi, [rel msg_parando]
    mov  rdx, 16
    call sys_write

    mov  rdi, 0
    call vm_parar
    test rax, rax
    js   erro_operacao_global

    mov  rdi, cor_sucesso
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_ok]
    mov  rdx, 4
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

.cmd_vmlistar:
    sub  rsp, 64                 ; Buffer temporário
    mov  rdi, rsp
    mov  rsi, 8                  ; Máx 8 VMs
    call vm_listar
    add  rsp, 64

    cmp  rax, 0
    jl   erro_operacao_global
    jz   .nenhuma_vm

    mov  rdi, 1
    lea  rsi, [rel msg_qtd_vm]
    mov  rdx, 12
    call sys_write
    ret
.nenhuma_vm:
    mov  rdi, 1
    lea  rsi, [rel msg_sem_vm]
    mov  rdx, 18
    call sys_write
    ret

.cmd_ls:
    mov  rdi, 0                  ; Diretório raiz
    lea  rsi, [rel buffer_in]
    mov  rdx, buffer_len
    call fs_listar
    test rax, rax
    js   erro_operacao_global

    mov  rdi, 1
    lea  rsi, [rel msg_ls_ok]
    mov  rdx, 25
    call sys_write
    ret

.cmd_cat:
    mov  rax, [rel param1]
    mov  rdi, rax
    test rdi, rdi
    jz   falta_parametro_global

    mov  rsi, 0                  ; Modo leitura
    call fs_abrir
    test rax, rax
    js   erro_operacao_global
    mov  rbx, rax                ; Salvar descritor

    mov  rdi, rbx
    lea  rsi, [rel buffer_in]
    mov  rdx, buffer_len - 1
    call fs_ler
    test rax, rax
    js   .fechar_e_sair

    lea  rcx, [rel buffer_in]
    mov  byte [rcx + rax], 0xA  ; Nova linha no final
    inc  rax

    mov  rdi, 1
    lea  rsi, [rel buffer_in]
    mov  rdx, rax
    call sys_write

    mov  rdi, rbx
    call fs_fechar
    ret
.fechar_e_sair:
    mov  rdi, rbx
    call fs_fechar
    jmp  erro_operacao_global

.cmd_montar:
    mov  rax, [rel param1]
    mov  rdi, rax
    mov  rax, [rel param2]
    mov  rsi, rax
    test rdi, rdi
    jz   falta_parametro_global

    call fs_montar
    test rax, rax
    js   erro_operacao_global

    mov  rdi, cor_sucesso
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_montado]
    mov  rdx, 10
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

.cmd_wifi:
    mov  rax, [rel param1]
    mov  rdi, rax
    mov  rax, [rel param2]
    mov  rsi, rax
    test rdi, rdi
    jz   falta_parametro_global

    call net_wifi_conectar
    test rax, rax
    js   erro_operacao_global

    mov  rdi, cor_sucesso
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_conectado]
    mov  rdx, 10
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

.cmd_ip:
    call net_meu_ip
    mov  rdi, 1
    lea  rsi, [rel msg_ip]
    mov  rdx, 14
    call sys_write
    ret

.cmd_fw:
    call fw_habilitar
    test rax, rax
    js   erro_operacao_global

    mov  rdi, cor_sucesso
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_fw_ativo]
    mov  rdx, 18
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

.cmd_av:
    mov  rax, [rel param1]
    mov  rdi, rax
    test rdi, rdi
    jz   falta_parametro_global

    call av_verificar
    cmp  rax, 0
    jl   .ameaca_detectada

    mov  rdi, cor_sucesso
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_limpo]
    mov  rdx, 14
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret
.ameaca_detectada:
    mov  rdi, cor_erro
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_ameaca]
    mov  rdx, 18
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

.cmd_status:
    call sec_status
    mov  r12, rax

    mov  rdi, 1
    lea  rsi, [rel msg_status_titulo]
    mov  rdx, 22
    call sys_write

    test r12, 1                   ; Firewall
    jz   .fw_nao
    lea  rsi, [rel msg_sim]
    jmp  .fw_exib
.fw_nao:
    lea  rsi, [rel msg_nao]
.fw_exib:
    mov  rdi, 1
    mov  rdx, 4
    call sys_write
    ret

; ══════════════════════════════════════════════════
; UTILITÁRIOS
; ══════════════════════════════════════════════════
falta_parametro_global:
    mov  rdi, cor_erro
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_falta_param]
    mov  rdx, 23
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

erro_operacao_global:
    mov  rdi, cor_erro
    call sys_setcolor
    mov  rdi, 1
    lea  rsi, [rel msg_erro_op]
    mov  rdx, 14
    call sys_write
    mov  rdi, cor_texto
    call sys_setcolor
    ret

quebrar_linha:
    push rsi
    push rdi
    push rcx
    xor  rcx, rcx
    lea  rdi, [rel buffer_in]
.skip_espaco:
    cmp  byte [rdi], ' '
    jne  .comando_ok
    inc  rdi
    jmp  .skip_espaco
.comando_ok:
    mov  rsi, rdi
.prox:
    cmp  byte [rdi], ' '
    je   .fim_comando
    cmp  byte [rdi], 0xA
    je   .fim_comando
    cmp  byte [rdi], 0
    je   .fim_comando
    inc  rdi
    jmp  .prox
.fim_comando:
    mov  byte [rdi], 0
    inc  rdi
.skip_p1:
    cmp  byte [rdi], ' '
    jne  .p1_ok
    inc  rdi
    jmp  .skip_p1
.p1_ok:
    lea  rax, [rel param1]
    mov  [rax], rdi
.prox_p2:
    cmp  byte [rdi], ' '
    je   .fim_p1
    cmp  byte [rdi], 0xA
    je   .zera_p2
    cmp  byte [rdi], 0
    je   .zera_p2
    inc  rdi
    jmp  .prox_p2
.fim_p1:
    mov  byte [rdi], 0
    inc  rdi
.skip_p2:
    cmp  byte [rdi], ' '
    jne  .p2_ok
    inc  rdi
    jmp  .skip_p2
.p2_ok:
    lea  rax, [rel param2]
    mov  [rax], rdi
.prox_fim:
    cmp  byte [rdi], ' '
    je   .fim_p2
    cmp  byte [rdi], 0xA
    je   .zera_p2
    cmp  byte [rdi], 0
    je   .zera_p2
    inc  rdi
    jmp  .prox_fim
.fim_p2:
    mov  byte [rdi], 0
    jmp  .fim
.zera_p2:
    mov  byte [rdi], 0
    lea  rax, [rel param2]
    mov  qword [rax], 0
.fim:
    pop  rcx
    pop  rdi
    pop  rsi
    ret

strcmpz:
    push rdi
    push rsi
.loop:
    mov  al, [rdi]
    cmp  al, [rsi]
    jne  .nao_igual
    test al, al
    jz   .igual
    inc  rdi
    inc  rsi
    jmp  .loop
.igual:
    pop  rsi
    pop  rdi
    ret
.nao_igual:
    pop  rsi
    pop  rdi
    xor  rax, rax
    ret

; ══════════════════════════════════════════════════
; MENSAGENS
; ══════════════════════════════════════════════════
section .rodata
msg_bemvindo:     db 'FydelisTechOS v2.2 — FydelTerm', 0xA
                  db 'Digite "ajuda" para ver comandos', 0xA, 0
msg_bemvindo_fim:

msg_ajuda:        db 0xA, '=== COMANDOS DISPONÍVEIS ===', 0xA
                  db 'vmstatus        — Status da VM', 0xA
                  db 'vminiciar       — Ligar máquina virtual', 0xA
                  db 'vmparar         — Desligar máquina virtual', 0xA
                  db 'vmlistar        — Listar todas as VMs', 0xA
                  db 'ls              — Listar arquivos', 0xA
                  db 'cat <arquivo>   — Exibir conteúdo', 0xA
                  db 'montar <origem> <letra> — Montar disco', 0xA
                  db 'wifi <ssid> <senha>     — Conectar rede', 0xA
                  db 'ip              — Exibir IP', 0xA
                  db 'fw              — Ativar firewall', 0xA
                  db 'av <arquivo>    — Verificar ameaça', 0xA
                  db 'status          — Status de segurança', 0xA
                  db 'ajuda           — Esta tela', 0xA
                  db 'exit            — Sair', 0xA, 0
msg_ajuda_fim:

msg_desconhecido: db 'Comando não reconhecido. Digite "ajuda".', 0xA, 0
msg_iniciando:    db 'Iniciando VM...', 0xA, 0
msg_parando:      db 'Parando VM...', 0xA, 0
msg_ok:           db 'OK', 0xA, 0
msg_sem_vm:       db 'Nenhuma VM registrada', 0xA, 0
msg_qtd_vm:       db 'VMs ativas: ', 0
msg_ls_ok:        db 'Arquivos: sistema.fyd, boot.log', 0xA, 0
msg_montado:      db 'Montado!', 0xA, 0
msg_conectado:    db 'Conectado!', 0xA, 0
msg_ip:           db 'IP: 192.168.1.x', 0xA, 0
msg_fw_ativo:     db 'Firewall ativado', 0xA, 0
msg_limpo:        db 'Arquivo limpo ✅', 0xA, 0
msg_ameaca:       db '⚠ AMEAÇA DETECTADA', 0xA, 0
msg_falta_param:  db 'Faltando parâmetro!', 0xA, 0
msg_erro_op:      db 'Erro na operação', 0xA, 0
msg_status_titulo:db '=== Status do Sistema ===', 0xA
msg_sim:          db 'Sim', 0xA
msg_nao:          db 'Não', 0xA
