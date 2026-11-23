; ==========================================
; 🎨 GRAPHICS.INC — CONSTANTES GRÁFICAS GLOBAIS
; Framebuffer VESA · UEFI GOP · Servidor de Janelas
; FydelisTech OS v2.2 · Salvador • Bahia 🇧🇷
; ==========================================
%ifndef GRAPHICS_INC
%define GRAPHICS_INC

; ========== MODOS DE VÍDEO ==========
VIDEO_MODO_TEXTO       equ 0   ; 80×25 VGA clássico
VIDEO_MODO_VESA        equ 1   ; VESA BIOS Extensions
VIDEO_MODO_GOP         equ 2   ; UEFI Graphics Output Protocol

; ========== PROFUNDIDADE DE COR ==========
BPP_8                  equ 8   ; 256 cores
BPP_16                 equ 16  ; 65.536 cores
BPP_24                 equ 24  ; 16M cores (packed)
BPP_32                 equ 32  ; 16M cores + alpha (True Color)

; ========== CORES PADRÃO — 0xAARRGGBB ==========
COR_PRETO              equ 0xFF000000
COR_BRANCO             equ 0xFFFFFFFF
COR_CINZA              equ 0xFF808080
COR_VERMELHO           equ 0xFFFF0000
COR_VERDE              equ 0xFF00FF00
COR_AZUL               equ 0xFF0000FF
COR_AMARELO            equ 0xFFFFFF00
COR_CIANO              equ 0xFF00FFFF
COR_MAGENTA            equ 0xFFFF00FF
COR_FUNDO_SISTEMA      equ 0xFF101020
COR_DESTAQUE           equ 0xFF00A0FF
COR_BORDA              equ 0xFF404060
COR_TEXTO              equ 0xFFFFFFFF
COR_TEXTO_SECUNDARIO   equ 0xFFC0C0C0

; ========== RESOLUÇÕES PADRÃO ==========
RES_640x480            equ 640
RES_800x600            equ 800
RES_1024x768           equ 1024
RES_1280x720           equ 1280
RES_1280x1024          equ 1280
RES_1366x768           equ 1366
RES_1600x900           equ 1600
RES_1920x1080          equ 1920
RES_1920x1200          equ 1920
RES_2560x1440          equ 2560
RES_3840x2160          equ 3840

; ========== ESTRUTURA FRAMEBUFFER ==========
; Preenchido pelo bootloader/modo de vídeo
struc FramebufferInfo
    .enderecoBase:     resq 1   ; Endereço físico do buffer
    .largura:          resd 1   ; Pixels por linha
    .altura:           resd 1   ; Linhas na tela
    .pitch:            resd 1   ; Bytes por linha
    .bpp:              resd 1   ; Bits por pixel
    .tamanho:          resd 1   ; Tamanho total em bytes
    .modo:             resd 1   ; VIDEO_MODO_*
    .redMask:          resd 1   ; Máscara canal vermelho
    .greenMask:        resd 1   ; Máscara canal verde
    .blueMask:         resd 1   ; Máscara canal azul
    .rsvMask:          resd 1   ; Máscara reservado/alpha
endstruc
FRAMEBUFFER_SIZE        equ 4 * 1024 * 1024  ; 4MB reserva inicial

; ========== SERVIDOR DE JANELAS ==========
MAX_JANELAS            equ 32
MAX_CAMADAS            equ 8
CURSOR_TAMANHO         equ 24
CURSOR_TAMANHO_MINIMO  equ 16
DOUBLE_BUFFER          equ 1   ; 1=ativado, 0=desativado

; ========== BOTÕES DO MOUSE PARA TELA ==========
MOUSE_BOTAO_ESQ        equ 0b001
MOUSE_BOTAO_DIR        equ 0b010
MOUSE_BOTAO_MEIO       equ 0b100
MOUSE_BOTAO_RODACIMA  equ 0b1000
MOUSE_BOTAO_RODABAIXO  equ 0b10000

; ========== UEFI GOP ESPECÍFICO ==========
GOP_SIGNATURE          equ 0x54464347  ; 'GCFB'
GOP_MODE_MAX           equ 16
GOP_PIXEL_FORMAT_RGB   equ 0x00000001
GOP_PIXEL_FORMAT_BGR   equ 0x00000002


; ========== FUNÇÕES EXPORTADAS ==========

extern ws_inicializar
extern ws_criar_janela
extern ws_desenhar
extern ws_atualizar_cursor

%endif ; GRAPHICS_INC
