; ==========================================================
;  FYDB — NÚCLEO DO BANCO DE DADOS NATIVO DO FYDELISTECHOS
;  Extensão: .fydb
;  Depende de: fydperm.asm + fs_* (camada de arquivos)
;
;  Formato do arquivo .fydb:
;    [0..63]    cabeçalho (64 bytes)
;    [64..]     registros de tamanho fixo, um após o outro
;
;  Build (Linux):  nasm -f elf64 fydb.asm -o fydb.o
; ==========================================================

[BITS 64]
DEFAULT REL

; ── Exportar funções para linkagem com C ──────────────────
[GLOBAL fydb_init]
[GLOBAL fydb_ler]
[GLOBAL fydb_escrever]
[GLOBAL fydb_inserir]
[GLOBAL fydb_remover]
[GLOBAL fydb_buscar]
[GLOBAL fydb_contar]
[GLOBAL fydb_capacidade]
[GLOBAL fydb_proteger]

; ── Importar funções externas (syscalls + fydperm) ────────
EXTERN fydperm_verificar
EXTERN fydperm_bloquear_fydb
EXTERN fs_lseek                 ; long fs_lseek(int fd, long offset, int origem)
EXTERN fs_ler                   ; long fs_ler(int fd, void *buf, size_t tam)
EXTERN fs_escrever              ; long fs_escrever(int fd, const void *buf, size_t tam)
EXTERN fs_fechar                ; long fs_fechar(int fd)

; ── Constantes internas ──────────────────────────────────
FYDB_ASSINATURA   equ 0x42445946        ; "FYDB" little-endian
FYDB_VERSAO       equ 1
FYDB_CABECALHO    equ 64
INDICE_LIVRE      equ 0xFFFFFFFF        ; Marca: registro vago
FYDB_TAM_MAX_REG  equ 512

; Códigos de retorno
FYDB_OK             equ 0
FYDB_ERRO_IO        equ -1
FYDB_NAO_ENCONTRADO equ -2
FYDB_CHEIO          equ -3
FYDB_ERRO_PARAM     equ -4

; ── Offsets dentro do cabeçalho (64 bytes exatos) ─────────
CAB_ASSINATURA      equ 0       ; dd
CAB_VERSAO          equ 4       ; db
CAB_TAM_REGISTRO    equ 5       ; dw
CAB_MAX_REGISTROS   equ 8       ; dd
CAB_QTD_ATUAL       equ 12      ; dd
CAB_PROXIMO_LIVRE   equ 16      ; dd
CAB_CRIPTO_FLAG     equ 20      ; db
CAB_IV              equ 21      ; 16 bytes (21..36)
CAB_PERMISSOES      equ 37      ; 16 bytes FydPerm (37..52)
CAB_RESERVADO       equ 53      ; 11 bytes (53..63)

section .bss
align 16
    buf_cabecalho:  resb FYDB_CABECALHO
    buf_registro:   resb FYDB_TAM_MAX_REG
    fd_atual:       resd 1

section .text

; ═══════════════════════════════════════════════════════════
;  INTERNO: carregar_cabecalho(fd)
;  Retorna: 0 = ok, -1 = erro de IO
; ═══════════════════════════════════════════════════════════
carregar_cabecalho:
    push r12
    mov r12, rdi

    mov rsi, 0
    mov rdx, 0                      ; SEEK_SET
    call fs_lseek
    cmp rax, 0
    jl .erro

    mov rdi, r12
    lea rsi, [buf_cabecalho]
    mov rdx, FYDB_CABECALHO
    call fs_ler
    cmp rax, FYDB_CABECALHO
    jb .erro

    lea rax, [fd_atual]
    mov [rax], r12d
    xor eax, eax
    pop r12
    ret

.erro:
    mov eax, -1
    pop r12
    ret

; ═══════════════════════════════════════════════════════════
;  INTERNO: salvar_cabecalho(fd)
;  Retorna: 0 = ok, -1 = erro de IO
; ═══════════════════════════════════════════════════════════
salvar_cabecalho:
    push r12
    mov r12, rdi

    mov rsi, 0
    mov rdx, 0                      ; SEEK_SET
    call fs_lseek
    cmp rax, 0
    jl .erro

    mov rdi, r12
    lea rsi, [buf_cabecalho]
    mov rdx, FYDB_CABECALHO
    call fs_escrever
    cmp rax, FYDB_CABECALHO
    jb .erro

    lea rax, [fd_atual]
    mov [rax], r12d
    xor eax, eax
    pop r12
    ret

.erro:
    mov eax, -1
    pop r12
    ret

; ═══════════════════════════════════════════════════════════
;  INTERNO: garantir_cabecalho(fd)
;  Garante que buf_cabecalho pertence ao fd informado e tem
;  assinatura válida. Retorna 0 = ok, -1 = erro.
; ═══════════════════════════════════════════════════════════
garantir_cabecalho:
    push r12
    mov r12, rdi

    lea r8, [buf_cabecalho]
    cmp dword [r8 + CAB_ASSINATURA], FYDB_ASSINATURA
    jne .recarrega

    lea r9, [fd_atual]
    cmp [r9], r12d
    jne .recarrega

    xor eax, eax
    pop r12
    ret

.recarrega:
    mov rdi, r12
    call carregar_cabecalho
    test rax, rax
    jnz .erro

    lea r8, [buf_cabecalho]
    cmp dword [r8 + CAB_ASSINATURA], FYDB_ASSINATURA
    jne .erro

    xor eax, eax
    pop r12
    ret

.erro:
    mov eax, -1
    pop r12
    ret

; ═══════════════════════════════════════════════════════════
;  INTERNO: offset_registro(indice) -> rax = offset absoluto
; ═══════════════════════════════════════════════════════════
offset_registro:
    lea r8, [buf_cabecalho]
    movzx rax, word [r8 + CAB_TAM_REGISTRO]
    mov rdi, rdi
    imul rax, rdi
    add rax, FYDB_CABECALHO
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_init(fd, tam_registro, max_registros)
;  Retorna: 0 = ok, -1 = erro de IO, -4 = parâmetro inválido
; ═══════════════════════════════════════════════════════════
fydb_init:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi                    ; fd
    mov r13, rsi                    ; tam_registro
    mov r14, rdx                    ; max_registros

    test r13, r13
    jz .param_invalido
    cmp r13, FYDB_TAM_MAX_REG
    ja .param_invalido
    test r14, r14
    jz .param_invalido

    lea rax, [fd_atual]
    mov [rax], r12d

    mov rdi, r12
    call carregar_cabecalho
    test rax, rax
    jnz .criar_novo

    lea r8, [buf_cabecalho]
    cmp dword [r8 + CAB_ASSINATURA], FYDB_ASSINATURA
    jne .criar_novo
    cmp byte [r8 + CAB_VERSAO], FYDB_VERSAO
    jne .criar_novo

    movzx rax, word [r8 + CAB_TAM_REGISTRO]
    cmp rax, r13
    jne .param_invalido
    jmp .ok

.criar_novo:
    lea r8, [buf_cabecalho]
    xor ecx, ecx
.zera:
    movsxd rdx, ecx
    mov byte [r8 + rdx], 0
    inc ecx
    cmp ecx, FYDB_CABECALHO
    jb .zera

    mov dword [r8 + CAB_ASSINATURA], FYDB_ASSINATURA
    mov byte  [r8 + CAB_VERSAO], FYDB_VERSAO
    mov [r8 + CAB_TAM_REGISTRO], r13w
    mov [r8 + CAB_MAX_REGISTROS], r14d
    mov dword [r8 + CAB_QTD_ATUAL], 0
    mov dword [r8 + CAB_PROXIMO_LIVRE], 0
    mov byte  [r8 + CAB_CRIPTO_FLAG], 0

    mov rdi, r12
    call salvar_cabecalho
    test rax, rax
    jnz .erro_io

.ok:
    xor eax, eax
    jmp .fim_init

.param_invalido:
    mov eax, FYDB_ERRO_PARAM
    jmp .fim_init

.erro_io:
    mov eax, FYDB_ERRO_IO

.fim_init:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_ler(fd, indice, buffer)
; ═══════════════════════════════════════════════════════════
fydb_ler:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx

    mov rdi, r12
    call garantir_cabecalho
    test rax, rax
    jnz .erro_ler

    cmp r13, 0
    jl .erro_param

    lea r8, [buf_cabecalho]
    mov eax, [r8 + CAB_MAX_REGISTROS]
    mov rax, rax
    cmp r13, rax
    jae .erro_param

    mov rdi, r13
    call offset_registro

    mov rsi, rax
    mov rdx, 0
    mov rdi, r12
    call fs_lseek
    cmp rax, 0
    jl .erro_ler

    lea r8, [buf_cabecalho]
    movzx rdx, word [r8 + CAB_TAM_REGISTRO]
    mov rdi, r12
    mov rsi, r14
    call fs_ler

    lea r8, [buf_cabecalho]
    movzx rcx, word [r8 + CAB_TAM_REGISTRO]
    cmp rax, rcx
    jne .erro_ler

    mov eax, FYDB_OK
    jmp .fim_ler

.erro_param:
    mov eax, FYDB_ERRO_PARAM
    jmp .fim_ler

.erro_ler:
    mov eax, FYDB_ERRO_IO

.fim_ler:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_escrever(fd, indice, registro)
; ═══════════════════════════════════════════════════════════
fydb_escrever:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx

    mov rdi, r12
    call garantir_cabecalho
    test rax, rax
    jnz .erro_esc

    cmp r13, 0
    jl .erro_param

    lea r8, [buf_cabecalho]
    mov eax, [r8 + CAB_MAX_REGISTROS]
    cmp r13, rax
    jae .erro_param

    mov rdi, r13
    call offset_registro

    mov rsi, rax
    mov rdx, 0
    mov rdi, r12
    call fs_lseek
    cmp rax, 0
    jl .erro_esc

    lea r8, [buf_cabecalho]
    movzx rdx, word [r8 + CAB_TAM_REGISTRO]
    mov rdi, r12
    mov rsi, r14
    call fs_escrever

    lea r8, [buf_cabecalho]
    movzx rcx, word [r8 + CAB_TAM_REGISTRO]
    cmp rax, rcx
    jne .erro_esc

    mov eax, FYDB_OK
    jmp .fim_esc

.erro_param:
    mov eax, FYDB_ERRO_PARAM
    jmp .fim_esc

.erro_esc:
    mov eax, FYDB_ERRO_IO

.fim_esc:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_inserir(fd, registro) -> retorna índice ou erro
; ═══════════════════════════════════════════════════════════
fydb_inserir:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi

    mov rdi, r12
    call garantir_cabecalho
    test rax, rax
    jnz .erro_inserir

    lea r8, [buf_cabecalho]
    mov eax, [r8 + CAB_QTD_ATUAL]
    mov ebx, [r8 + CAB_MAX_REGISTROS]
    cmp eax, ebx
    jae .banco_cheio

    mov r14d, [r8 + CAB_PROXIMO_LIVRE]
    cmp r14d, ebx
    jae .banco_cheio

    mov rdi, r12
    mov rsi, r14
    mov rdx, r13
    call fydb_escrever
    cmp rax, FYDB_OK
    jne .erro_inserir

    lea r8, [buf_cabecalho]
    mov eax, [r8 + CAB_QTD_ATUAL]
    inc eax
    mov [r8 + CAB_QTD_ATUAL], eax

    mov eax, [r8 + CAB_PROXIMO_LIVRE]
    inc eax
    mov [r8 + CAB_PROXIMO_LIVRE], eax

    mov rdi, r12
    call salvar_cabecalho
    test rax, rax
    jnz .erro_inserir

    mov eax, r14d
    jmp .fim_inserir

.banco_cheio:
    mov eax, FYDB_CHEIO
    jmp .fim_inserir

.erro_inserir:
    mov eax, FYDB_ERRO_IO

.fim_inserir:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_remover(fd, indice)
; ═══════════════════════════════════════════════════════════
fydb_remover:
    push r12
    push r13
    sub rsp, FYDB_TAM_MAX_REG

    mov r12, rdi
    mov r13, rsi

    mov rdi, r12
    call garantir_cabecalho
    test rax, rax
    jnz .erro_io_rem

    cmp r13, 0
    jl .nao_existe

    lea r8, [buf_cabecalho]
    mov eax, [r8 + CAB_MAX_REGISTROS]
    cmp r13, rax
    jae .nao_existe

    mov rdi, r12
    mov rsi, r13
    mov rdx, rsp
    call fydb_ler
    cmp rax, FYDB_OK
    jne .nao_existe

    lea r8, [buf_cabecalho]
    movzx ecx, word [r8 + CAB_TAM_REGISTRO]
    test ecx, ecx
    jz .escreve_zerado

.zera_reg:
    dec ecx
    movsxd rdx, ecx
    mov byte [rsp + rdx], 0
    test ecx, ecx
    jnz .zera_reg

.escreve_zerado:
    mov rdi, r12
    mov rsi, r13
    mov rdx, rsp
    call fydb_escrever
    cmp rax, FYDB_OK
    jne .erro_io_rem

    lea r8, [buf_cabecalho]
    mov eax, [r8 + CAB_QTD_ATUAL]
    test eax, eax
    jz .salva_rem
    dec eax
    mov [r8 + CAB_QTD_ATUAL], eax

.salva_rem:
    mov rdi, r12
    call salvar_cabecalho
    test rax, rax
    jnz .erro_io_rem

    mov eax, FYDB_OK
    jmp .fim_rem

.nao_existe:
    mov eax, FYDB_NAO_ENCONTRADO
    jmp .fim_rem

.erro_io_rem:
    mov eax, FYDB_ERRO_IO

.fim_rem:
    add rsp, FYDB_TAM_MAX_REG
    pop r13
    pop r12
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_buscar(fd, chave, offset_campo, tam_campo)
; ═══════════════════════════════════════════════════════════
fydb_buscar:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 520                    ; 56 + 520 = 576 (múltiplo de 16)

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx

    mov rdi, r12
    call garantir_cabecalho
    test rax, rax
    jnz .erro_io_busca

    test r15, r15
    jz .erro_param_busca

    lea r8, [buf_cabecalho]
    movzx eax, word [r8 + CAB_TAM_REGISTRO]
    mov rcx, r14
    add rcx, r15
    cmp rcx, rax
    ja .erro_param_busca

    xor ebx, ebx

.busca_loop:
    lea r8, [buf_cabecalho]
    cmp ebx, [r8 + CAB_MAX_REGISTROS]
    jae .nao_encontrado

    mov rdi, r12
    mov rsi, rbx
    mov rdx, rsp
    call fydb_ler
    cmp rax, FYDB_OK
    jne .proximo

    lea rdi, [rsp]
    add rdi, r14
    mov rsi, r13
    mov rcx, r15
    repe cmpsb
    je .encontrado

.proximo:
    inc ebx
    jmp .busca_loop

.encontrado:
    mov eax, ebx
    jmp .fim_busca

.nao_encontrado:
    mov eax, FYDB_NAO_ENCONTRADO
    jmp .fim_busca

.erro_param_busca:
    mov eax, FYDB_ERRO_PARAM
    jmp .fim_busca

.erro_io_busca:
    mov eax, FYDB_ERRO_IO

.fim_busca:
    add rsp, 520
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_contar(fd) -> retorna qtd_atual ou erro negativo
; ═══════════════════════════════════════════════════════════
fydb_contar:
    push r12
    mov r12, rdi

    call garantir_cabecalho
    test rax, rax
    jnz .erro_c

    lea r8, [buf_cabecalho]
    mov eax, [r8 + CAB_QTD_ATUAL]
    pop r12
    ret

.erro_c:
    mov eax, FYDB_ERRO_IO
    pop r12
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_capacidade(fd) -> retorna max_registros ou erro negativo
; ═══════════════════════════════════════════════════════════
fydb_capacidade:
    push r12
    mov r12, rdi

    call garantir_cabecalho
    test rax, rax
    jnz .erro_k

    lea r8, [buf_cabecalho]
    mov eax, [r8 + CAB_MAX_REGISTROS]
    pop r12
    ret

.erro_k:
    mov eax, FYDB_ERRO_IO
    pop r12
    ret

; ═══════════════════════════════════════════════════════════
;  fydb_proteger(fd) -> ativa bloqueio via FydPerm e persiste
; ═══════════════════════════════════════════════════════════
fydb_proteger:
    push r12
    mov r12, rdi

    call garantir_cabecalho
    test rax, rax
    jnz .erro_p

    lea rdi, [buf_cabecalho + CAB_PERMISSOES]
    call fydperm_bloquear_fydb

    mov rdi, r12
    call salvar_cabecalho
    test rax, rax
    jnz .erro_p

    xor eax, eax
    pop r12
    ret

.erro_p:
    mov eax, -1
    pop r12
    ret
