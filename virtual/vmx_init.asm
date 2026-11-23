; ==================================================
; FydelisTechOS — Inicialização VT-x v2.2
; ==================================================
bits 64
align 4096

section .bss
global vmxon_region
vmxon_region: resb 4096   ; Área de controle VMXON

section .text
global vmx_enter
global vmx_exit

; Entrar em modo de virtualização (VMXON)
vmx_enter:
    ; Ativar VMX no CR4
    mov  rax, cr4
    or   rax, 1 << 13
    mov  cr4, rax

    ; Executar VMXON — exige um ponteiro de memória de 64 bits
    lea  rax, [rel vmxon_region]
    vmxon [rel vmxon_region]   ; vmxon opera diretamente com apontamento de memória
    jc   .falha
    jz   .falha

    mov  rax, 1    ; Sucesso!
    ret

.falha:
    xor  rax, rax
    ret

; Sair do modo de virtualização
vmx_exit:
    vmxoff
    mov  rax, cr4
    and  rax, ~(1 << 13)
    mov  cr4, rax
    ret
