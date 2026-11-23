; ==========================================
; FYDELIS — RENDERIZAÇÃO DE TEXTO EM ASSEMBLY
; v1.0 | Fonte 8x8 | Direto no Framebuffer
; Sem C, sem X11, sem Wayland ainda — só bits
; ==========================================

%ifndef TEXTO_INC
%define TEXTO_INC

; === DADOS DO FRAMEBUFFER (vindos de vesafb.asm) ===
extern fb_largura       ; Largura em pixels
extern fb_altura         ; Altura em pixels
extern fb_bpp            ; Bytes por pixel (4 = 32-bit)
extern fb_base           ; Endereço base do framebuffer
extern fb_linhasize      ; Bytes por linha

; === CORES — Formato 0xRRGGBB (compatível com teu fb) ===
%define COR_FUNDO      0x23192D   ; Roxo escuro
%define COR_TEXTO      0xDCDCDC   ; Branco suave
%define COR_DESTAQUE   0x78C8FF   ; Azul claro
%define COR_BORDA      0x5AA0FF   ; Azul Fydelis

; === FONTE 8x8 — 128 caracteres × 8 bytes = 1024 bytes TOTAL ===
; Cada linha: bit 7 = esquerda, bit 0 = direita
extern fonte_8x8

; === ROTINAS PÚBLICAS ===
global texto_iniciar       ; Inicializar (verificar fb)
global texto_limpar_tela   ; Preencher com cor de fundo
global texto_char          ; Desenhar 1 caractere: x, y, char, cor
global texto_string        ; Desenhar string: x, y, ptr, cor
global texto_centralizado  ; Centralizar na linha y
global texto_barra_superior; Desenhar barra de título

%endif