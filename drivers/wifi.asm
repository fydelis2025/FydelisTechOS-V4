; ==========================================
; DRIVER WIFI NATIVO & WPA2 — FYDELIS TECH OS v2.2
; Salvador • Bahia 🇧🇷
; NOTE: Cliente DHCP vive em dhcp_servidor.asm (extern aqui).
; ==========================================
BITS 64
default rel
%include "fydelterm.inc"

; ========== OFFSETS DA STRUCT DE REDE ESCANEADA (stride 64) ==========
%define WIFI_REDE_STRIDE    64
%define WifiRede.ssid       0
%define WifiRede.canal      33
%define WifiRede.potencia   34
%define WifiRede.seguranca  35
%define WifiRede.bssid      36
%define WifiRede.reservado  42

; Exporta explicitamente o tamanho para o linker
section .data
global WifiRede_size
WifiRede_size: dq 64

; ========== EXPORTAÇÕES GLOBAIS ==========
global wifi_detectar_placa
global wifi_inicializar
global sys_wifi_scan
global sys_wifi_conectar
global sys_wifi_desconectar
global bridge_wifi_scan
global bridge_wifi_conectar
global bridge_wifi_desconectar
global wifi_ler_status
global wifi_ler_ssid
global wifi_esta_conectado
global wifi_definir_senha
global wifi_conectar_completo
global wifi_comando_listar
global wifi_scan_lista

; ========== EXTERNAIS ==========
extern tx_pacote
extern rx_processa
extern wifi_tx_quadro
extern wifi_rx_quadro
extern print_num
extern memcpy
extern ip_para_string
extern dhcp_cliente_iniciar
extern dhcp_ip_atual

; --- Endereços/Comandos Wi-Fi ---
WIFI_BAR0_BASE     equ 0xF0000000
WIFI_CMD           equ 0x00
WIFI_DATA          equ 0x04
WIFI_STATUS        equ 0x08
WIFI_OCUPADO       equ 1 << 0
WIFI_PRONTO        equ 1 << 1
WIFI_CONECTADO     equ 1 << 2
CMD_RESET          equ 0x01
CMD_SCAN           equ 0x02
CMD_CONNECT        equ 0x03
CMD_DISCONNECT     equ 0x04
CMD_GET_RESULTS    equ 0x05
CMD_SET_KEY        equ 0x06
MAX_REDES          equ 32
SSID_TAMANHO       equ 32
WIFI_TIMEOUT       equ 5000000

; --- Constantes WPA2 ---
WPA2_KEY_LEN       equ 32
WPA2_IE_WPA2       equ 0x0F30
WPA2_CIPHER_CCMP   equ 0x00000004

; --- Tipos de Mensagem DHCP ---
DHCP_DISCOVER      equ 1
DHCP_OFFER         equ 2
DHCP_REQUEST       equ 3
DHCP_ACK           equ 5
DHCP_OPT_MSGTYPE   equ 53
DHCP_OPT_END       equ 255

section .bss
align 16
wifi_base:           resq 1
wifi_placa_ok:       resb 1
wifi_modo_virtual:   resb 1
wifi_inicializada:   resb 1
wifi_conectado:      resb 1
wifi_ssid_atual:     resb SSID_TAMANHO + 1
wifi_scan_count:     resd 1
wifi_scan_lista:     resb (WIFI_REDE_STRIDE * MAX_REDES)
wifi_tx_buffer:      resb 1536
wifi_rx_buffer:      resb 1536

; Buffers WPA2 e Criptografia
wpa2_psk:          resb 32
wpa2_ptk:          resb 48
wpa2_anonce:       resb 32
wpa2_snonce:       resb 32
wpa2_ap_mac:       resb 6
wpa2_estado:       resd 1
wifi_chave_senha:  resb 64
ip_buf:            resb 16

section .data
str_ieee:              db 'IEEE 802.11',0
str_prf_label:         db 'Pairwise key expansion',0
wifi_mac_local:        db 0x02,0x00,0x5E,0x00,0x53,0x01

msg_conectado:         db 'WiFi Conectado — Obtendo IP...',0
msg_falha_rede:        db 'Nao foi possivel conectar a rede',0
msg_falha_wpa2:        db 'Falha na autenticacao WPA2 — senha incorreta?',0
msg_wpa2_ok:           db 'Autenticacao WPA2 concluida.',0
msg_lista_titulo:      db 'Redes Wi-Fi encontradas:',0
msg_aberta:            db 'Aberta',0
msg_wpa2:              db 'WPA2',0
msg_nao_inicializado:  db 'Wi-Fi nao inicializado — digite "wifi on"',0
msg_nenhuma:           db 'Nenhuma rede encontrada.',0

; Redes virtuais para ambiente QEMU/VirtualBox sem placa PCI 802.11
v_ssid_1:              db 'FydelisTech_5G',0
v_ssid_2:              db 'Salvador_Free_WiFi',0
v_ssid_3:              db 'CyberLab_SecNet',0

section .text

; ==========================================
; 🔍 DETECTAR PLACA VIA PCI (COM FALLBACK VM)
; ==========================================
wifi_detectar_placa:
    push    rcx
    push    rdx
    xor     rcx, rcx
.pci_proximo:
    call    pci_ler_dispositivo
    cmp     rax, 0xFFFFFFFF
    je      .proximo
    call    pci_ler_classe
    cmp     eax, 0x02800000         ; Classe 02-80: Wireless Controller
    je      .encontrado
.proximo:
    inc     rcx
    cmp     rcx, 256
    jl      .pci_proximo

    ; Fallback automático para QEMU/VirtualBox sem hardware PCI Wi-Fi
    mov     byte [rel wifi_placa_ok], 1
    mov     byte [rel wifi_modo_virtual], 1
    mov     rax, 1
    jmp     .fim

.encontrado:
    call    pci_ler_bar0
    mov     [rel wifi_base], rax
    mov     byte [rel wifi_placa_ok], 1
    mov     byte [rel wifi_modo_virtual], 0
    mov     rax, 1
.fim:
    pop     rdx
    pop     rcx
    ret

; ==========================================
; ⚙️ INICIALIZAR HARDWARE
; ==========================================
wifi_inicializar:
    cmp     byte [rel wifi_placa_ok], 1
    jne     .sem_placa
    cmp     byte [rel wifi_modo_virtual], 1
    je      .ok_virtual

    mov     rax, [rel wifi_base]
    mov     dword [rax + WIFI_CMD], CMD_RESET
    call    wifi_espera_pronto
    test    rax, rax
    jz      .falha
    mov     rax, [rel wifi_base]
    mov     edx, [rax + WIFI_STATUS]
    test    edx, WIFI_PRONTO
    jz      .falha

.ok_virtual:
    mov     byte [rel wifi_inicializada], 1
    mov     rax, 1
    ret
.sem_placa:
.falha:
    xor     rax, rax
    ret

; ==========================================
; ⏳ ESPERAR PLACA FICAR LIVRE
; ==========================================
wifi_espera_pronto:
    push    rcx
    push    rdx
    mov     rax, [rel wifi_base]
    mov     ecx, WIFI_TIMEOUT
.loop:
    mov     edx, [rax + WIFI_STATUS]
    test    edx, WIFI_OCUPADO
    jz      .pronto
    pause
    dec     rcx
    jnz     .loop
    xor     eax, eax
    jmp     .fim
.pronto:
    mov     rax, 1
.fim:
    pop     rdx
    pop     rcx
    ret

; ==========================================
; 📡 ESCANEAR REDES
; ==========================================
sys_wifi_scan:
bridge_wifi_scan:
    cmp     byte [rel wifi_inicializada], 1
    jne     .nao_pronto
    cmp     byte [rel wifi_modo_virtual], 1
    je      .scan_virtual

    mov     dword [rel wifi_scan_count], 0
    mov     rax, [rel wifi_base]
    mov     dword [rax + WIFI_CMD], CMD_SCAN
    call    wifi_espera_pronto
    test    rax, rax
    jz      .nao_pronto
    mov     rax, [rel wifi_base]
    mov     dword [rax + WIFI_CMD], CMD_GET_RESULTS
    call    wifi_espera_pronto
    test    rax, rax
    jz      .nao_pronto
    call    wifi_parse_resultados
    mov     rax, [rel wifi_scan_count]
    test    rax, rax
    jz      .nao_pronto
    lea     rax, [rel wifi_scan_lista]
    ret

.scan_virtual:
    push    rsi
    push    rdi
    push    rcx

    lea     rdi, [rel wifi_scan_lista]
    mov     rcx, (WIFI_REDE_STRIDE * MAX_REDES) / 8
    xor     rax, rax
    rep     stosq

    ; Rede 0: FydelisTech_5G (WPA2)
    lea     rdi, [rel wifi_scan_lista]
    lea     rsi, [rel v_ssid_1]
    mov     rcx, 15
    rep     movsb
    mov     byte [rel wifi_scan_lista + WifiRede.canal], 36
    mov     byte [rel wifi_scan_lista + WifiRede.potencia], 95
    mov     byte [rel wifi_scan_lista + WifiRede.seguranca], 1

    ; Rede 1: Salvador_Free_WiFi (Aberta)
    lea     rdi, [rel wifi_scan_lista + WIFI_REDE_STRIDE]
    lea     rsi, [rel v_ssid_2]
    mov     rcx, 19
    rep     movsb
    mov     byte [rel wifi_scan_lista + WIFI_REDE_STRIDE + WifiRede.canal], 6
    mov     byte [rel wifi_scan_lista + WIFI_REDE_STRIDE + WifiRede.potencia], 82
    mov     byte [rel wifi_scan_lista + WIFI_REDE_STRIDE + WifiRede.seguranca], 0

    ; Rede 2: CyberLab_SecNet (WPA2)
    lea     rdi, [rel wifi_scan_lista + (WIFI_REDE_STRIDE * 2)]
    lea     rsi, [rel v_ssid_3]
    mov     rcx, 16
    rep     movsb
    mov     byte [rel wifi_scan_lista + (WIFI_REDE_STRIDE * 2) + WifiRede.canal], 11
    mov     byte [rel wifi_scan_lista + (WIFI_REDE_STRIDE * 2) + WifiRede.potencia], 74
    mov     byte [rel wifi_scan_lista + (WIFI_REDE_STRIDE * 2) + WifiRede.seguranca], 1

    mov     dword [rel wifi_scan_count], 3
    pop     rcx
    pop     rdi
    pop     rsi
    lea     rax, [rel wifi_scan_lista]
    ret

.nao_pronto:
    xor     rax, rax
    ret

; ==========================================
; 🔌 CONECTAR À REDE
; ==========================================
sys_wifi_conectar:
bridge_wifi_conectar:
    push    rsi
    push    rdi
    test    rdi, rdi
    jz      .falha
    cmp     byte [rel wifi_inicializada], 1
    jne     .falha

    mov     rsi, rdi
    lea     rdi, [rel wifi_ssid_atual]
    mov     rcx, SSID_TAMANHO
.copia_ssid:
    lodsb
    mov     [rdi], al
    test    al, al
    je      .fim_copia
    inc     rdi
    dec     rcx
    jnz     .copia_ssid
.fim_copia:
    mov     byte [rdi], 0

    cmp     byte [rel wifi_modo_virtual], 1
    je      .conectar_ok

    mov     rax, [rel wifi_base]
    mov     dword [rax + WIFI_CMD], CMD_CONNECT
    lea     rcx, [rel wifi_ssid_atual]
    mov     qword [rax + WIFI_DATA], rcx
    call    wifi_espera_pronto
    test    rax, rax
    jz      .falha

    mov     rax, [rel wifi_base]
    mov     edx, [rax + WIFI_STATUS]
    test    edx, WIFI_CONECTADO
    jz      .falha

.conectar_ok:
    mov     byte [rel wifi_conectado], 1
    mov     rax, 1

    push    rax
    push    rdi
    push    rsi
    call    dhcp_cliente_iniciar
    pop     rsi
    pop     rdi
    pop     rax
    jmp     .fim

.falha:
    xor     rax, rax
.fim:
    pop     rdi
    pop     rsi
    ret

; ==========================================
; 🔌 DESCONECTAR
; ==========================================
sys_wifi_desconectar:
bridge_wifi_desconectar:
    cmp     byte [rel wifi_inicializada], 1
    jne     .nao_pronto
    cmp     byte [rel wifi_modo_virtual], 1
    je      .desc_ok

    mov     rax, [rel wifi_base]
    mov     dword [rax + WIFI_CMD], CMD_DISCONNECT
    call    wifi_espera_pronto
    test    rax, rax
    jz      .nao_pronto

.desc_ok:
    mov     byte [rel wifi_conectado], 0
    mov     rax, 1
    ret
.nao_pronto:
    xor     rax, rax
    ret

; ==========================================
; 🔎 PARSE DOS RESULTADOS DO SCAN
; ==========================================
wifi_parse_resultados:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     dword [rel wifi_scan_count], 0
    lea     rdi, [rel wifi_scan_lista]
    mov     rbx, [rel wifi_base]

.proxima_rede:
    cmp     dword [rel wifi_scan_count], MAX_REDES
    jge     .fim

    mov     eax, [rel wifi_scan_count]
    mov     rdx, rax
    imul    rdx, rdx, 40
    add     rdx, WIFI_DATA

    lea     rsi, [rbx + rdx]

    cmp     byte [rsi], 0
    je      .proximo_indice

    mov     rcx, 33
    rep     movsb
    mov     byte [rdi - 1], 0

    sub     rdi, 33

    mov     al, [rsi + 0]
    mov     [rdi + WifiRede.canal], al
    mov     al, [rsi + 1]
    mov     [rdi + WifiRede.potencia], al
    mov     al, [rsi + 2]
    mov     [rdi + WifiRede.seguranca], al

    add     rsi, 3
    mov     rcx, 6
.copia_bssid:
    lodsb
    mov     [rdi + WifiRede.bssid], al
    inc     rdi
    loop    .copia_bssid

    inc     dword [rel wifi_scan_count]

.proximo_indice:
    mov     eax, [rel wifi_scan_count]
    imul    eax, eax, WIFI_REDE_STRIDE
    lea     rdi, [rel wifi_scan_lista]
    add     rdi, rax

    jmp     .proxima_rede

.fim:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ==========================================
; 🔑 SALVAR SENHA PARA WPA2
; ==========================================
wifi_definir_senha:
    push    rsi
    push    rdi
    test    rdi, rdi
    jz      .fim
    mov     rsi, rdi
    lea     rdi, [rel wifi_chave_senha]
    mov     rcx, 63
.copia:
    lodsb
    mov     [rdi], al
    test    al, al
    je      .nul
    inc     rdi
    dec     rcx
    jnz     .copia
.nul:
    mov     byte [rdi], 0
.fim:
    pop     rdi
    pop     rsi
    ret

; ==========================================
; 🔐 DERIVAR PSK — PBKDF2-HMAC-SHA1
; ==========================================
wifi_wpa2_derivar_chave:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 32

    lea     r12, [rel wifi_chave_senha]
    xor     r13, r13
.len_senha:
    cmp     byte [r12 + r13], 0
    je      .tem_len
    inc     r13
    cmp     r13, 64
    jb      .len_senha
.tem_len:
    test    r13, r13
    jz      .falha

    lea     rdi, [rsp]
    lea     rsi, [rel str_ieee]
    mov     rcx, 11
    rep     movsb
    mov     dword [rdi], 0x01000000

    lea     rdi, [rel wpa2_psk]
    lea     rsi, [rel wifi_chave_senha]
    mov     rdx, r13
    mov     rcx, rsp
    mov     r8, 15
    call    hmac_sha1

    mov     r14d, 4095
.iterar:
    sub     rsp, 32
    mov     rdi, rsp
    lea     rsi, [rel wifi_chave_senha]
    mov     rdx, r13
    lea     rcx, [rel wpa2_psk]
    mov     r8, 32
    call    hmac_sha1
    xor     rbx, rbx
.xor_u:
    mov     al, [rsp + rbx]
    xor     [rel wpa2_psk + rbx], al
    inc     rbx
    cmp     rbx, 32
    jb      .xor_u
    add     rsp, 32
    dec     r14d
    jnz     .iterar

    mov     rax, 1
    jmp     .fim
.falha:
    xor     rax, rax
.fim:
    add     rsp, 32
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ==========================================
; 🤝 HANDSHAKE DE 4 VIAS — WPA2
; ==========================================
wifi_wpa2_handshake:
    cmp     byte [rel wifi_conectado], 1
    jne     .falha
    lea     rdi, [rel wpa2_snonce]
    mov     rcx, 4
.gera_nonce:
    rdtsc
    rol     rax, 32
    xor     rax, rdx
    rol     rax, 13
    stosq
    dec     rcx
    jnz     .gera_nonce
    call    wifi_enviar_eapol_1
    test    rax, rax
    jz      .falha
    call    wifi_receber_eapol_2
    test    rax, rax
    jz      .falha
    lea     rdi, [rel wpa2_ptk]
    lea     rsi, [rel wpa2_psk]
    lea     rdx, [rel wpa2_ap_mac]
    lea     rcx, [rel wpa2_snonce]
    lea     r8, [rel wpa2_anonce]
    call    wpa2_prf
    call    wifi_instalar_chaves_ccmp
    mov     dword [rel wpa2_estado], 4
    mov     rax, 1
    ret
.falha:
    xor     rax, rax
    ret

; ==========================================
; PRF-512
; ==========================================
wpa2_prf:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 128

    mov     r14, rdi

    mov     rdi, rsp
    lea     rsi, [rel str_prf_label]
    mov     rcx, 22
    rep     movsb
    mov     byte [rdi], 0
    inc     rdi
    mov     rsi, rdx
    mov     rcx, 6
    rep     movsb
    lea     rsi, [rel wifi_mac_local]
    mov     rcx, 6
    rep     movsb
    mov     rsi, r8
    mov     rcx, 32
    rep     movsb
    lea     rsi, [rel wpa2_snonce]
    mov     rcx, 32
    rep     movsb

    xor     r13, r13
    mov     rbx, 48
.bloco:
    mov     byte [rsp + 99], r13b
    lea     rdi, [rsp + 110]
    lea     rsi, [rel wpa2_psk]
    mov     rdx, 32
    mov     rcx, rsp
    mov     r8, 100
    call    hmac_sha1
    mov     rcx, 20
    lea     rsi, [rsp + 110]
    mov     rdi, r14
    rep     movsb
    add     r14, 20
    sub     rbx, 20
    jz      .fim
    inc     r13
    jmp     .bloco
.fim:
    add     rsp, 128
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    mov     rax, 1
    ret

; ==========================================
; HMAC-SHA1
; ==========================================
hmac_sha1:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 256

    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx
    mov     [rsp + 120], r8

    mov     rcx, 64
    xor     eax, eax
    lea     rdi, [rsp]
.zera_k:
    mov     [rdi], al
    inc     rdi
    dec     rcx
    jnz     .zera_k

    cmp     r14, 64
    jbe     .copia_k
    lea     rdi, [rsp + 96]
    mov     rsi, r13
    mov     rdx, r14
    call    sha1_completo
    mov     rcx, 20
    lea     rsi, [rsp + 96]
    lea     rdi, [rsp]
    rep     movsb
    jmp     .k_pronto
.copia_k:
    mov     rcx, r14
    lea     rdi, [rsp]
    mov     rsi, r13
    rep     movsb
.k_pronto:

    xor     rbx, rbx
.ipad:
    xor     byte [rsp + rbx], 0x36
    inc     rbx
    cmp     rbx, 64
    jb      .ipad
    lea     rdi, [rsp + 128]
    lea     rsi, [rsp]
    mov     rcx, 64
    rep     movsb
    lea     rdi, [rsp + 192]
    mov     rsi, r15
    mov     rcx, [rsp + 120]
    rep     movsb
    lea     rdi, [rsp + 64]
    lea     rsi, [rsp + 128]
    mov     rdx, [rsp + 120]
    add     rdx, 64
    call    sha1_completo

    xor     rbx, rbx
.opad:
    xor     byte [rsp + rbx], 0x6A
    inc     rbx
    cmp     rbx, 64
    jb      .opad
    lea     rdi, [rsp + 128]
    lea     rsi, [rsp]
    mov     rcx, 64
    rep     movsb
    lea     rdi, [rsp + 192]
    lea     rsi, [rsp + 64]
    mov     rcx, 20
    rep     movsb
    lea     rdi, [rsp + 64]
    lea     rsi, [rsp + 128]
    mov     rdx, 84
    call    sha1_completo

    mov     rcx, 20
    lea     rsi, [rsp + 64]
    mov     rdi, r12
    rep     movsb

    add     rsp, 256
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ==========================================
; SHA1 COMPLETO
; ==========================================
sha1_completo:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 128

    mov     r15, rdi

    mov     dword [rsp],      0x67452301
    mov     dword [rsp + 4],  0xEFCDAB89
    mov     dword [rsp + 8],  0x98BADCFE
    mov     dword [rsp + 12], 0x10325476
    mov     dword [rsp + 16], 0xC3D2E1F0

    mov     rbx, rdx
    mov     rbp, rsi

.blocos:
    cmp     rbx, 64
    jb      .cauda
    mov     rcx, 16
    lea     rdi, [rsp + 32]
.copia_b:
    mov     eax, [rbp]
    bswap   eax
    mov     [rdi], eax
    add     rbp, 4
    add     rdi, 4
    dec     rcx
    jnz     .copia_b
    lea     rdi, [rsp]
    lea     rsi, [rsp + 32]
    call    sha1_bloco
    sub     rbx, 64
    jmp     .blocos

.cauda:
    lea     rdi, [rsp + 32]
    mov     rsi, rbp
    mov     rcx, rbx
    rep     movsb
    lea     rdi, [rsp + 32]
    add     rdi, rbx
    mov     byte [rdi], 0x80
    inc     rdi
    cmp     rbx, 56
    jae     .dois_bloco
    mov     rcx, 56
    sub     rcx, rbx
    dec     rcx
.zera1:
    mov     byte [rdi], 0
    inc     rdi
    dec     rcx
    jnz     .zera1
    mov     rax, rdx
    shl     rax, 3
    bswap   rax
    mov     [rsp + 32 + 56], rax
    lea     rdi, [rsp]
    lea     rsi, [rsp + 32]
    call    sha1_bloco
    jmp     .digest
.dois_bloco:
    mov     rcx, 64
    sub     rcx, rbx
    dec     rcx
.zera2:
    mov     byte [rdi], 0
    inc     rdi
    dec     rcx
    jnz     .zera2
    lea     rdi, [rsp]
    lea     rsi, [rsp + 32]
    call    sha1_bloco
    xor     rcx, rcx
.zera3:
    mov     byte [rsp + 32 + rcx], 0
    inc     rcx
    cmp     rcx, 56
    jb      .zera3
    mov     rax, rdx
    shl     rax, 3
    bswap   rax
    mov     [rsp + 32 + 56], rax
    lea     rdi, [rsp]
    lea     rsi, [rsp + 32]
    call    sha1_bloco

.digest:
    mov     rcx, 5
    mov     rsi, rsp
    mov     rdi, r15
.copia_d:
    lodsd
    bswap   eax
    stosd
    dec     rcx
    jnz     .copia_d

    add     rsp, 128
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ==========================================
; SHA1 — Bloco
; ==========================================
sha1_bloco:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 352

    xor     rcx, rcx
.carrega:
    mov     eax, [rsi + rcx*4]
    bswap   eax
    mov     [rsp + rcx*4], eax
    inc     rcx
    cmp     rcx, 16
    jb      .carrega
.expande:
    mov     eax, [rsp + rcx*4 - 12]
    xor     eax, [rsp + rcx*4 - 32]
    xor     eax, [rsp + rcx*4 - 56]
    xor     eax, [rsp + rcx*4 - 64]
    rol     eax, 1
    mov     [rsp + rcx*4], eax
    inc     rcx
    cmp     rcx, 80
    jb      .expande

    mov     r12d, [rdi]
    mov     r13d, [rdi + 4]
    mov     r14d, [rdi + 8]
    mov     r15d, [rdi + 12]
    mov     ebp,  [rdi + 16]
    xor     ebx, ebx

.roundo:
    cmp     ebx, 20
    jae     .faixa2
    mov     eax, r13d
    and     eax, r14d
    mov     ecx, r13d
    not     ecx
    and     ecx, r15d
    or      eax, ecx
    mov     ecx, 0x5A827999
    jmp     .tem_f
.faixa2:
    cmp     ebx, 40
    jae     .faixa3
    mov     eax, r13d
    xor     eax, r14d
    xor     eax, r15d
    mov     ecx, 0x6ED9EBA1
    jmp     .tem_f
.faixa3:
    cmp     ebx, 60
    jae     .faixa4
    mov     eax, r13d
    and     eax, r14d
    mov     ecx, r13d
    and     ecx, r15d
    or      eax, ecx
    mov     ecx, r14d
    and     ecx, r15d
    or      eax, ecx
    mov     ecx, 0x8F1BBCDC
    jmp     .tem_f
.faixa4:
    mov     eax, r13d
    xor     eax, r14d
    xor     eax, r15d
    mov     ecx, 0xC3D2E1F0
.tem_f:
    mov     edx, r12d
    rol     edx, 5
    add     edx, eax
    add     edx, ebp
    add     edx, ecx
    add     edx, [rsp + rbx*4]
    mov     ebp, r15d
    mov     r15d, r14d
    mov     r14d, r13d
    mov     r13d, r12d
    mov     r12d, edx
    inc     ebx
    cmp     ebx, 80
    jb      .roundo

    add     [rdi], r12d
    add     [rdi + 4], r13d
    add     [rdi + 8], r14d
    add     [rdi + 12], r15d
    add     [rdi + 16], ebp

    add     rsp, 352
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ==========================================
; 📨 EAPOL
; ==========================================
wifi_enviar_eapol_1:
    push    rsi
    push    rdi
    lea     rdi, [rel wifi_tx_buffer]
    mov     rcx, 128
    xor     eax, eax
    rep     stosb
    mov     word [rel wifi_tx_buffer + 12], 0x888E
    mov     byte [rel wifi_tx_buffer + 14], 3
    mov     byte [rel wifi_tx_buffer + 15], 1
    mov     dword [rel wifi_tx_buffer + 16], 0x01000000
    lea     rsi, [rel wpa2_snonce]
    lea     rdi, [rel wifi_tx_buffer + 24]
    mov     rcx, 32
    rep     movsb
    lea     rsi, [rel wpa2_ap_mac]
    lea     rdi, [rel wifi_tx_buffer + 6]
    mov     rcx, 6
    rep     movsb

    lea     rdi, [rel wifi_tx_buffer]
    mov     rsi, 128
    call    wifi_tx_quadro
    mov     rax, 1
    pop     rdi
    pop     rsi
    ret

wifi_receber_eapol_2:
    push    rsi
    push    rdi
    lea     rdi, [rel wifi_rx_buffer]
    call    wifi_rx_quadro
    test    rax, rax
    jz      .falha
    cmp     word [rel wifi_rx_buffer + 12], 0x888E
    jne     .falha
    lea     rsi, [rel wifi_rx_buffer + 24]
    lea     rdi, [rel wpa2_anonce]
    mov     rcx, 32
    rep     movsb
    lea     rsi, [rel wifi_rx_buffer + 6]
    lea     rdi, [rel wpa2_ap_mac]
    mov     rcx, 6
    rep     movsb
    mov     rax, 1
    pop     rdi
    pop     rsi
    ret
.falha:
    xor     rax, rax
    pop     rdi
    pop     rsi
    ret

wifi_instalar_chaves_ccmp:
    mov     rax, [rel wifi_base]
    mov     dword [rax + WIFI_CMD], CMD_SET_KEY
    lea     rcx, [rel wpa2_ptk]
    mov     qword [rax + WIFI_DATA], rcx
    call    wifi_espera_pronto
    ret

; ==========================================
; 🔌 CONECTAR + WPA2 + DHCP AUTOMÁTICO
; ==========================================
wifi_conectar_completo:
    push    rbx
    push    rdi
    push    rsi
    test    rsi, rsi
    jz      .sem_senha
    mov     rdi, rsi
    call    wifi_definir_senha
.sem_senha:
    mov     rdi, [rsp + 16]
    call    sys_wifi_conectar
    test    rax, rax
    jz      .falha_conexao
    cmp     byte [rel wifi_conectado], 1
    jne     .falha_conexao
    cmp     byte [rel wifi_chave_senha], 0
    je      .sem_wpa2
    call    wifi_wpa2_derivar_chave
    test    rax, rax
    jz      .falha_wpa2
    call    wifi_wpa2_handshake
    test    rax, rax
    jz      .falha_wpa2
    lea     rsi, [rel msg_wpa2_ok]
    call    print_string
    call    print_newline
.sem_wpa2:
    lea     rsi, [rel msg_conectado]
    call    print_string
    call    print_newline
    call    dhcp_cliente_iniciar
    pop     rsi
    pop     rdi
    pop     rbx
    mov     rax, 1
    ret
.falha_conexao:
    lea     rsi, [rel msg_falha_rede]
    call    print_string
    call    print_newline
    xor     eax, eax
    jmp     .fim
.falha_wpa2:
    lea     rsi, [rel msg_falha_wpa2]
    call    print_string
    call    print_newline
    call    sys_wifi_desconectar
    xor     eax, eax
.fim:
    pop     rsi
    pop     rdi
    pop     rbx
    ret

; ==========================================
; 🌐 FUNÇÕES DE STATUS E LISTAGEM CLI
; ==========================================
wifi_esta_conectado:
    xor     rax, rax
    mov     al, [rel wifi_conectado]
    ret

wifi_ler_ssid:
    cmp     byte [rel wifi_conectado], 1
    jne     .sem_conexao
    lea     rax, [rel wifi_ssid_atual]
    ret
.sem_conexao:
    xor     rax, rax
    ret

wifi_ler_status:
    xor     rax, rax
    mov     al, [rel wifi_placa_ok]
    shl     al, 1
    or      al, [rel wifi_inicializada]
    shl     al, 1
    or      al, [rel wifi_conectado]
    ret

wifi_comando_listar:
    cmp     byte [rel wifi_inicializada], 1
    jne     .nao_inicializado

    call    sys_wifi_scan
    test    rax, rax
    jz      .nenhuma_rede

    lea     rsi, [rel msg_lista_titulo]
    call    print_string
    call    print_newline

    xor     rcx, rcx
.exibir_loop:
    cmp     ecx, [rel wifi_scan_count]
    jge     .fim_exibicao

    mov     rax, rcx
    imul    rax, WIFI_REDE_STRIDE
    lea     rsi, [rel wifi_scan_lista]
    add     rsi, rax

    push    rcx
    push    rsi
    mov     rdi, rcx
    call    print_num
    mov     al, ':'
    call    print_char
    mov     al, ' '
    call    print_char

    pop     rsi
    push    rsi
    lea     rsi, [rsi + WifiRede.ssid]
    call    print_string

    pop     rsi
    push    rsi
    mov     al, ' '
    call    print_char
    mov     al, '-'
    call    print_char
    mov     al, ' '
    call    print_char
    lea     rdi, [rsi + WifiRede.seguranca]
    cmp     byte [rdi], 0
    je      .aberta
    lea     rsi, [rel msg_wpa2]
    jmp     .imprimir_seg
.aberta:
    lea     rsi, [rel msg_aberta]
.imprimir_seg:
    call    print_string
    call    print_newline

    pop     rsi
    pop     rcx
    inc     ecx
    jmp     .exibir_loop

.fim_exibicao:
    ret

.nao_inicializado:
    lea     rsi, [rel msg_nao_inicializado]
    call    print_string
    call    print_newline
    ret

.nenhuma_rede:
    lea     rsi, [rel msg_nenhuma]
    call    print_string
    call    print_newline
    ret
