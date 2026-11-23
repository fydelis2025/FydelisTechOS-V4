; ==========================================
; FYDELIS TECH OS — Constantes de Rede para Assembly
; SOMENTE valores/tamanhos — SEM funções!
; ==========================================

; --- Tamanhos das Estruturas ---
WifiRede_size     equ 80

; --- Offsets dentro de WifiRede ---
WIFIREDE_SSID     equ 0
WIFIREDE_BSSID    equ 33
WIFIREDE_SINAL    equ 40
WIFIREDE_SEG      equ 44
WIFIREDE_PROXIMO  equ 64

; --- Tipos de Interface ---
IFACE_CABO        equ 0
IFACE_WIFI        equ 1

; --- Rede ---
SYS_REDE_INICIALIZAR      equ 0x60
SYS_WIFI_CONECTAR         equ 0x61
SYS_REDE_STATUS           equ 0x62
SYS_REDE_MEU_IP           equ 0x63
SYS_REDE_DESCONECTAR      equ 0x64

SYS_REDE_ENVIAR           equ 0x73
SYS_REDE_RECEBER          equ 0x74

; ✅ FIM — NENHUMA linha com extern!
