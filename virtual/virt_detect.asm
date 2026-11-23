; ==================================================
; FydelisTechOS — Detecção de Virtualização v2.2
; ==================================================
bits 64

global detect_vmx_support
global detect_svm_support

; Retorna 1 se CPU tem VT-x (Intel)
detect_vmx_support:
    mov  eax, 1
    cpuid
    mov  eax, ecx
    shr  eax, 5
    and  eax, 1
    ret

; Retorna 1 se CPU tem AMD-V (AMD)
detect_svm_support:
    mov  eax, 0x80000001
    cpuid
    mov  eax, ecx
    shr  eax, 2
    and  eax, 1
    ret