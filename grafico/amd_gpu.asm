; ==========================================
; ⚡ AMD_GPU.ASM — DRIVER RADEON GFX8+
; FydelisTech OS v2.2 · Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
default rel
%include "fydelterm.inc"

section .bss
amd_ativado: resb 1

section .text
global amd_detectar
global amd_inicializar
global amd_preencher_retangulo
global amd_esta_ativo

amd_detectar:
    ; Retorna 0 por padrão para usar o fallback genérico VESA, 
    ; ou 1 se quiser forçar a detecção da Radeon.
    xor rax, rax
    ret

amd_inicializar:
    mov byte [rel amd_ativado], 1
    mov rax, 1
    ret

amd_preencher_retangulo:
    extern fb_preencher_retangulo
    jmp fb_preencher_retangulo

amd_esta_ativo:
    movzx rax, byte [rel amd_ativado]
    ret
