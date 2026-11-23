; ==========================================
; BLUETOOTH — Constantes para NASM APENAS
; ==========================================
BDADDR_TAMANHO      equ 6
NOME_BT_TAMANHO     equ 24
MAX_DEV_BT          equ 16

; Offsets na estrutura BtDispositivo
BTDEV_BDADDR        equ 0
BTDEV_NOME          equ 6
BTDEV_CLASSE        equ 32
BTDEV_SINAL         equ 36
BTDEV_CONECTADO     equ 38
BTDEV_PROXIMO       equ 40
BTDEV_TAMANHO       equ 48

; Números das syscalls
SYS_BT_DETECTAR     equ 0x80
SYS_BT_INICIALIZAR  equ 0x81
SYS_BT_ESCANEAR     equ 0x82
SYS_BT_CONECTAR     equ 0x83
SYS_BT_DESCONECTAR  equ 0x84