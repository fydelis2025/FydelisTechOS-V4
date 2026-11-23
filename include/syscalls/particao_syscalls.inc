; ==========================================
; 📞 CHAMADAS DE SISTEMA — PARTIÇÕES
; Ponte entre C++/Qt e Assembly Nativo
; ==========================================
%ifndef PARTICAO_SYSCALLS_INC
%define PARTICAO_SYSCALLS_INC

; Syscall numbers
SYS_DISCO_LER          equ 100
SYS_DISCO_ESCREVER     equ 101
SYS_LISTAR_PARTICOES   equ 102
SYS_CRIAR_PARTICAO     equ 103
SYS_EXCLUIR_PARTICAO   equ 104
SYS_FORMATAR_PARTICAO  equ 105
SYS_TAMANHO_DISCO      equ 106

; Estrutura — Particao (igual ao C++)
struc Particao
    .dispositivo:   resb 16
    .nome:          resb 32
    .sistemaArq:    resb 16
    .tamanhoTotal:  resq 1
    .tamanhoUsado:  resq 1
    .montagem:      resb 32
    .ativo:         resb 1
    .align:         resb 7
endstruc

%endif