; ==========================================
; DRIVER BLUETOOTH NATIVO - FYDELIS TECH OS
; De Salvador - Bahia
; Fala direto com o hardware - SEM Windows/Linux
; ==========================================
BITS 64
%include "../include/fydelterm.inc"

; --- Exporta para o sistema e GUI (exec.c) ---
global bt_detectar_placa
global bt_inicializar
global bt_ler_status
global sys_bt_scan
global sys_bt_conectar
global sys_bt_desconectar
global sys_bt_enviar_dados
global sys_bt_receber_dados

; --- Registros do Controlador HCI ---
BT_BASE_UNKNOWN  equ 0x00000000

; Registros HCI via MMIO
HCI_CMD          equ 0x00    ; Registro de Comando
HCI_DATA_TX      equ 0x04    ; Buffer de Transmissao
HCI_DATA_RX      equ 0x08    ; Buffer de Recepcao
HCI_STATUS       equ 0x0C    ; Status do controlador
  HCI_OCUPADO    equ 1 << 0
  HCI_PRONTO     equ 1 << 1
  HCI_CONECTADO  equ 1 << 2

; Comandos HCI padrao
HCI_RESET        equ 0x0C03
HCI_READ_BDADDR  equ 0x1009
HCI_SET_NAME     equ 0x0C13
HCI_INQUIRY      equ 0x0401
HCI_CREATE_CONN  equ 0x0405
HCI_DISCONNECT   equ 0x0406

; Limites
MAX_DISPOSITIVOS equ 16
NOME_TAMANHO     equ 24
BDADDR_TAMANHO   equ 6

; --- Estrutura: Dispositivo Bluetooth ---
struc BtDispositivo
    bdaddr:     resb BDADDR_TAMANHO    ; Endereco do dispositivo
    nome:       resb NOME_TAMANHO + 1  ; Nome amigavel
    classe:     resd 1                 ; Classe do dispositivo
    sinal:      resb 1                 ; Forca do sinal (0-100%)
    conectado:  resb 1                 ; 1 = conectado
    proximo:    resq 1                 ; Proximo da lista
endstruc

section .bss
align 16
bt_base:               resq 1          ; Endereco base MMIO do controlador
bt_placa_ok:           resb 1          ; 1 = placa detectada
bt_inicializada:       resb 1          ; 1 = driver pronto
bt_conectado:          resb 1          ; 1 = conectado a um dispositivo
bt_nome_local:         resb NOME_TAMANHO + 1
bt_endereco_alvo:      resb BDADDR_TAMANHO
bt_lista_dispositivos: resb (BtDispositivo_size * MAX_DISPOSITIVOS)
bt_contador:           resd 1

section .text

; ==========================================
; bt_ler_status - Consulta rapida para o Systray (exec.c)
; Saida: rax = 0 (ausente), 1 (placa pronta), 2 (conectado)
; ==========================================
bt_ler_status:
    cmp     byte [bt_conectado], 1
    je      .conectado
    cmp     byte [bt_placa_ok], 1
    je      .pronto
    xor     rax, rax
    ret
.pronto:
    mov     rax, 1
    ret
.conectado:
    mov     rax, 2
    ret

; ==========================================
; DETECTAR PLACA - Varre Bus 0, Slots 0..31, Funcoes 0..7
; Reconhece Bluetooth PCI (0x0D11 / 0x0280) e USB Host HCI (0x0C03)
; Retorna: rax = 1 se encontrou, 0 se nao
; ==========================================
bt_detectar_placa:
    push    rbx
    push    rcx
    push    rdx

    xor     ebx, ebx                ; EBX = indice combinado (Slot << 3) | Func (0..255)
.pci_proximo:
    ; Endereco PCI Config: (1 << 31) | (EBX << 8)
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000000
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    cmp     eax, 0xFFFFFFFF
    je      .proximo

    ; Ler Class Code / Subclass (offset 0x08)
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000008
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    shr     eax, 16                 ; AX = Base Class (alto) + Subclass (baixo)

    cmp     ax, 0x0D11              ; Wireless Controller -> Bluetooth
    je      .encontrada

    cmp     ax, 0x0280              ; Network -> Other Wireless
    je      .encontrada

    cmp     ax, 0x0C03              ; Serial Bus -> USB Controller (Transporta HCI Bluetooth)
    je      .encontrada

.proximo:
    inc     ebx
    cmp     ebx, 256
    jl      .pci_proximo

    mov     byte [bt_placa_ok], 0
    xor     rax, rax
    jmp     .fim

.encontrada:
    ; Ler BAR0 (offset 0x10) ou BAR4 (offset 0x20, usado pelo USB UHCI)
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000010
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    test    eax, eax
    jnz     .limpa_bar

    ; Fallback para BAR4 (offset 0x20) caso BAR0 seja zero
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000020
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx

.limpa_bar:
    and     eax, 0xFFFFFFF0
    mov     [bt_base], rax

    mov     byte [bt_placa_ok], 1
    mov     rax, 1

.fim:
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ==========================================
; INICIALIZAR - Reset e configuracao HCI segura
; ==========================================
bt_inicializar:
    cmp     byte [bt_placa_ok], 1
    jne     .sem_placa

    ; Definir nome do dispositivo local na memoria
    mov     rsi, nome_fydelis
    mov     rdi, bt_nome_local
    mov     rcx, NOME_TAMANHO
    rep     movsb
    mov     byte [rdi], 0

    ; Se bt_base for MMIO valido (> 0x100000), envia comandos HCI
    mov     rax, [bt_base]
    cmp     rax, 0x100000
    jb      .pronto_usb

    mov     dword [rax + HCI_CMD], HCI_RESET
    call    bt_espera_pronto

    mov     rax, [bt_base]
    mov     dword [rax + HCI_CMD], HCI_READ_BDADDR
    call    bt_espera_pronto

.pronto_usb:
    mov     byte [bt_inicializada], 1
    mov     dword [bt_contador], 0
    mov     rax, 1
    ret

.sem_placa:
    xor     rax, rax
    ret

; ==========================================
; sys_bt_scan - Escanear dispositivos proximos
; Retorna: rax = ponteiro para lista BtDispositivo
; ==========================================
sys_bt_scan:
    cmp     byte [bt_inicializada], 1
    jne     .nao_pronto

    mov     dword [bt_contador], 0

    mov     rax, [bt_base]
    mov     dword [rax + HCI_CMD], HCI_INQUIRY
    call    bt_espera_pronto

    call    bt_parse_resultados

    mov     rax, bt_lista_dispositivos
    ret

.nao_pronto:
    xor     rax, rax
    ret

; ==========================================
; sys_bt_conectar - Conectar a dispositivo
; Entrada: rdi = ponteiro para BD_ADDR (6 bytes)
; Retorna: rax = 1 sucesso, 0 falha
; ==========================================
sys_bt_conectar:
    push    rsi
    push    rdi

    cmp     byte [bt_inicializada], 1
    jne     .falha

    mov     rsi, rdi
    mov     rdi, bt_endereco_alvo
    mov     rcx, BDADDR_TAMANHO
    rep     movsb

    mov     rax, [bt_base]
    mov     dword [rax + HCI_CMD], HCI_CREATE_CONN
    call    bt_espera_pronto

    mov     rax, [bt_base]
    mov     edx, [rax + HCI_STATUS]
    test    edx, HCI_CONECTADO
    jz      .falha

    mov     byte [bt_conectado], 1
    mov     rax, 1
    jmp     .fim

.falha:
    xor     rax, rax
.fim:
    pop     rdi
    pop     rsi
    ret

; ==========================================
; sys_bt_desconectar - Encerrar conexao
; ==========================================
sys_bt_desconectar:
    cmp     byte [bt_inicializada], 1
    jne     .nao_pronto

    mov     rax, [bt_base]
    mov     dword [rax + HCI_CMD], HCI_DISCONNECT
    call    bt_espera_pronto

    mov     byte [bt_conectado], 0
    mov     rax, 1
    ret

.nao_pronto:
    xor     rax, rax
    ret

; ==========================================
; sys_bt_enviar_dados - Transmitir dados
; Entrada: rsi=dados, rdx=tamanho
; ==========================================
sys_bt_enviar_dados:
    cmp     byte [bt_conectado], 1
    jne     .nao_conectado

    mov     rax, [bt_base]
    mov     rcx, rdx
    lea     rdi, [rax + HCI_DATA_TX]
    rep     movsb

    mov     dword [rax + HCI_STATUS], 0
    call    bt_espera_pronto
    mov     rax, 1
    ret

.nao_conectado:
    xor     rax, rax
    ret

; ==========================================
; sys_bt_receber_dados - Ler dados recebidos
; ==========================================
sys_bt_receber_dados:
    cmp     byte [bt_conectado], 1
    jne     .sem_dados

    mov     rax, [bt_base]
    lea     rsi, [rax + HCI_DATA_RX]
    mov     rax, 1
    ret

.sem_dados:
    xor     rax, rax
    ret

; ==========================================
; AUXILIARES
; ==========================================
bt_espera_pronto:
    push    rax
    push    rcx
    push    rdx
    mov     rax, [bt_base]
    mov     rcx, 100000             ; Timeout de seguranca para evitar loop infinito
.loop:
    mov     edx, [rax + HCI_STATUS]
    test    edx, HCI_OCUPADO
    jz      .pronto
    pause
    dec     rcx
    jnz     .loop
.pronto:
    pop     rdx
    pop     rcx
    pop     rax
    ret

bt_parse_resultados:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     rax, [bt_base]
    lea     rsi, [rax + HCI_DATA_RX]
    mov     rdi, bt_lista_dispositivos
    xor     rbx, rbx

.proximo:
    cmp     rbx, MAX_DISPOSITIVOS
    jge     .fim

    cmp     byte [rsi], 0
    jz      .fim

    mov     rdx, rdi
    mov     rcx, BDADDR_TAMANHO
    rep     movsb

    mov     rcx, NOME_TAMANHO
    rep     movsb
    mov     byte [rdi], 0

    inc     dword [bt_contador]
    lea     rdi, [rdx + BtDispositivo_size]
    inc     rbx
    jmp     .proximo

.fim:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; --- Dados Constantes ---
section .data
nome_fydelis: db "FydelisTech-Device", 0
