; ==========================================
;  FYDPERM — SISTEMA DE PERMISSOES NATIVO
;  Arquivo: kernel/fydperm.asm
;  Depende de: NADA — freestanding
;
;  Chamadas:
;    fydperm_inicializar(uid_sistema, gid_sistema)
;    fydperm_verificar(uid, gid, perm_ptr, acesso_solicitado) -> 0=permitido
;    fydperm_definir(perm_ptr, modo, dono_uid, grupo_gid)
;    fydperm_bloquear_fydb(perm_ptr) -> marca como SOMENTE_KERNEL
;
;  Build (Linux):  nasm -f elf64 kernel/fydperm.asm -o build/obj/fydperm.o
; ==========================================

[BITS 64]
DEFAULT REL

[GLOBAL fydperm_inicializar]
[GLOBAL fydperm_verificar]
[GLOBAL fydperm_definir]
[GLOBAL fydperm_bloquear_fydb]

; === ESTRUTURA FydPerm (16 bytes — cabe no cabecalho .fydb) ===
%define FydPerm.modo        0
%define FydPerm.dono_uid    4
%define FydPerm.grupo_gid   8
%define FydPerm.reservado  12
FYDPERM_TAM_STRUC equ 16

; === BITS DE ACESSO (estilo POSIX) ===
PERM_EXEC     equ 0x01
PERM_ESCRITA  equ 0x02
PERM_LEITURA  equ 0x04

PERM_DONO_SHIFT   equ 6
PERM_GRUPO_SHIFT  equ 3
PERM_OUTROS_SHIFT equ 0

PERM_FYD_ONLY equ 0x00008000

FYDPERM_OK     equ 0
FYDPERM_NEGADO equ -1

section .bss
perm_sistema_dono_uid:   resd 1
perm_sistema_gid:        resd 1
perm_inicializado:       resb 1

section .text

fydperm_inicializar:
    mov [perm_sistema_dono_uid], edi
    mov [perm_sistema_gid], esi
    mov byte [perm_inicializado], 1
    xor eax, eax
    ret

fydperm_verificar:
    push rbx
    push r10
    push r11

    cmp byte [perm_inicializado], 0
    je .negado

    test rdx, rdx
    jz .negado

    mov r11d, ecx
    and r11d, 0x07
    jz .negado

    mov r10d, [rdx + FydPerm.modo]

    test r10d, PERM_FYD_ONLY
    jz .verificar_usuario

    cmp edi, [perm_sistema_dono_uid]
    je .permitido
    jmp .negado

.verificar_usuario:
    cmp edi, [perm_sistema_dono_uid]
    je .permitido

    mov ebx, [rdx + FydPerm.dono_uid]
    cmp edi, ebx
    je .checar_modo_dono

    mov ebx, [rdx + FydPerm.grupo_gid]
    cmp esi, ebx
    je .checar_modo_grupo

    jmp .checar_modo_outros

.checar_modo_dono:
    mov ebx, r10d
    shr ebx, PERM_DONO_SHIFT
    and ebx, 0b111
    jmp .comparar

.checar_modo_grupo:
    mov ebx, r10d
    shr ebx, PERM_GRUPO_SHIFT
    and ebx, 0b111
    jmp .comparar

.checar_modo_outros:
    mov ebx, r10d
    and ebx, 0b111

.comparar:
    mov eax, r11d
    and eax, ebx
    cmp eax, r11d
    je .permitido

.negado:
    mov eax, FYDPERM_NEGADO
    pop r11
    pop r10
    pop rbx
    ret

.permitido:
    xor eax, eax
    pop r11
    pop r10
    pop rbx
    ret

fydperm_definir:
    test rdi, rdi
    jz .nulo
    mov [rdi + FydPerm.modo], esi
    mov [rdi + FydPerm.dono_uid], edx
    mov [rdi + FydPerm.grupo_gid], ecx
    mov dword [rdi + FydPerm.reservado], 0
    xor eax, eax
    ret
.nulo:
    mov eax, FYDPERM_NEGADO
    ret

fydperm_bloquear_fydb:
    test rdi, rdi
    jz .nulo
    or dword [rdi + FydPerm.modo], PERM_FYD_ONLY
    xor eax, eax
    ret
.nulo:
    mov eax, FYDPERM_NEGADO
    ret
