; ==========================================
; 🖥️ GOP.ASM — UEFI GRAPHICS OUTPUT PROTOCOL
; Boot Nativo EFI · Framebuffer Linear
; FydelisTech OS v2.2 · Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
%include "fydelterm.inc"
%include "graphics.inc"

; ========== ESTRUTURAS UEFI GOP ==========
struc EFI_GOP_MODE_INFORMATION
    .versao:              resd 1
    .largura:             resd 1
    .altura:              resd 1
    .formatoPixel:        resd 1   ; 1=RGB, 2=BGR, etc
    .informacaoPixel:     resd 4   ; máscaras R/G/B/Reservado
    .linhaTamanho:        resd 1   ; pixels por linha
endstruc

struc EFI_GRAPHICS_OUTPUT_PROTOCOL
    .QueryMode:           resq 1
    .SetMode:             resq 1
    .Blt:                 resq 1
    .ModoInfo:            resq 1   ; → EFI_GOP_MODE_INFORMATION
    .TamanhoModoInfo:     resq 1
    .ModoAtual:           resd 1
    .MaxModo:             resd 1
    .FrameBufferBase:     resq 1   ; ← ENDEREÇO FÍSICO
    .FrameBufferSize:     resq 1
endstruc

; ========== DADOS ==========
section .bss
align 4096
gop_protocol_ptr:     resq 1
gop_fb_endereco:      resq 1
gop_largura:          resd 1
gop_altura:           resd 1
gop_pitch:            resd 1
gop_bpp:              resd 1
gop_ativo:            resb 1
gop_sem_gop:          resb 1   ; Fallback para VESA

section .text
; ========== EXPORTAÇÃO ==========
global gop_detectar
global gop_inicializar
global gop_obter_framebuffer
global gop_esta_ativo

; ==========================================
; 🔍 DETECTAR DISPONIBILIDADE DE GOP
; Chamado pelo bootloader EFI — passa ponteiro
; ==========================================
gop_detectar:
    ; Entrada: rdi = ponteiro para EFI_GRAPHICS_OUTPUT_PROTOCOL
    ; passado pelo bootloader (stivale2/limine/efi)
    
    cmp     rdi, 0
    jz      .nao_detectado

    ; Valida assinatura/estrutura
    mov     rax, [rdi + EFI_GRAPHICS_OUTPUT_PROTOCOL.FrameBufferBase]
    cmp     rax, 0
    jz      .nao_detectado

    mov     [gop_protocol_ptr], rdi
    mov     rax, 1
    ret

.nao_detectado:
    mov     byte [gop_sem_gop], 1
    xor     rax, rax
    ret

; ==========================================
;  INICIALIZAR GOP — Extrair parâmetros
; ==========================================
gop_inicializar:
    cmp     byte [gop_sem_gop], 1
    je      .fallback_vesa

    mov      rdi, [gop_protocol_ptr]
    mov      rsi, [rdi + EFI_GRAPHICS_OUTPUT_PROTOCOL.ModoInfo]

    ; Resolução
    mov      eax, [rsi + EFI_GOP_MODE_INFORMATION.largura]
    mov      [gop_largura], eax
    mov      eax, [rsi + EFI_GOP_MODE_INFORMATION.altura]
    mov      [gop_altura], eax

    ; Formato de pixel → sempre 32bpp no GOP moderno
    mov      dword [gop_bpp], 32

    ; Pitch = largura * 4 bytes (32bpp)
    mov      eax, [gop_largura]
    shl      eax, 2
    mov      [gop_pitch], eax

    ; Endereço do framebuffer
    mov      rax, [rdi + EFI_GRAPHICS_OUTPUT_PROTOCOL.FrameBufferBase]
    mov      [gop_fb_endereco], rax

    ; Validação mínima
    cmp      dword [gop_largura], 640
    jl       .resolucao_baixa
    cmp      dword [gop_altura], 480
    jl       .resolucao_baixa

    mov      byte [gop_ativo], 1
    mov      rax, 1  ; Sucesso
    ret

.resolucao_baixa:
    xor      rax, rax
    ret

.fallback_vesa:
    ; Sem GOP → sistema deve usar VESA
    xor      rax, rax
    ret

; ==========================================
; 📤 RETORNAR DADOS DO FRAMEBUFFER
; Saída: rdi=endereco, rsi=larg, rdx=alt, rcx=pitch, r8=bpp
; ==========================================
gop_obter_framebuffer:
    cmp     byte [gop_ativo], 1
    jne     .indisponivel

    mov     rdi, [gop_fb_endereco]
    mov     esi, [gop_largura]
    mov     edx, [gop_altura]
    mov     ecx, [gop_pitch]
    mov     r8d, [gop_bpp]
    mov     rax, 1
    ret

.indisponivel:
    xor     rax, rax
    ret

; ==========================================
; ✅ VERIFICAR SE GOP ESTÁ EM USO
; ==========================================
gop_esta_ativo:
    movzx   rax, byte [gop_ativo]
    ret