; ==========================================================
;  FYDELIS-CIPHER — Cifra de Bloco do FydelisTechOS
;  Base: Feistel Generalizado (4 ramos, tipo 2) + ARX
;  Bloco: 128 bits | Chave: 256 bits | Rodadas: 24
;  Modo de disco: XTS (tweak por setor, GF(2^128), poly 0x87)
;
;  Layout do ctx (208 bytes):
;    [0..15]   W0..W3  (whitening, 4 words)
;    [16..207] k[r][0], k[r][1] — 48 subkeys (24 rodadas x 2)
;
;  Build: nasm -f elf64 fydcipher.asm -o fydcipher.o
; ==========================================================

[BITS 64]
DEFAULT REL

[GLOBAL fydcipher_inicia]
[GLOBAL fydcipher_criptografa]
[GLOBAL fydcipher_descriptografa]
[GLOBAL fydcipher_xts_criptografa]
[GLOBAL fydcipher_xts_descriptografa]

FYCIPHER_RODADAS equ 24

section .text

; -----------------------------------------------------
;  Funcao F v2 — ARX endurecido, 6 operacoes
;  eax = valor, edx = subchave -> eax = F(valor, chave)
;  Clobber: eax, r9d, flags
; -----------------------------------------------------
FuncaoF:
    add eax, edx
    ror eax, 13
    xor eax, edx
    rol eax, 7
    mov r9d, edx
    ror r9d, 17
    add eax, r9d
    rol eax, 1
    ret

; -----------------------------------------------------
;  INTERNO: chacha_qr — quarter-round ARX
;  rdi = ponteiro para 4 words
; -----------------------------------------------------
chacha_qr:
    mov eax, [rdi]
    mov ecx, [rdi+4]
    mov edx, [rdi+8]
    mov esi, [rdi+12]

    add eax, ecx
    xor esi, eax
    rol esi, 16

    add edx, esi
    xor ecx, edx
    rol ecx, 12

    add eax, ecx
    xor esi, eax
    rol esi, 8

    add edx, esi
    xor ecx, edx
    rol ecx, 7

    mov [rdi], eax
    mov [rdi+4], ecx
    mov [rdi+8], edx
    mov [rdi+12], esi
    ret

; -----------------------------------------------------
;  fydcipher_inicia(ctx, chave[32])
; -----------------------------------------------------
fydcipher_inicia:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24

    mov rbx, rdi
    mov r12, rsi

    ; W0..W3 (bytes 16..31 da chave de 256 bits) -> ctx[0..15]
    mov ecx, 4
.cp_w:
    mov r8d, ecx
    dec r8d
    mov eax, [r12 + r8*4 + 16]
    mov [rbx + r8*4], eax
    dec ecx
    jnz .cp_w

    ; Estado inicial do schedule em [rsp..rsp+15] (bytes 0..15 da chave)
    mov eax, [r12]
    mov [rsp], eax
    mov eax, [r12+4]
    mov [rsp+4], eax
    mov eax, [r12+8]
    mov [rsp+8], eax
    mov eax, [r12+12]
    mov [rsp+12], eax

    lea r14, [rbx + 16]
    xor r13d, r13d

.agenda:
    mov eax, r13d
    imul eax, eax, 0x9e3779b9
    mov edx, [rsp]
    add edx, eax
    mov [rsp], edx

    mov eax, r13d
    shl eax, 3
    mov edx, [rsp+4]
    xor edx, eax
    mov [rsp+4], edx

    mov edx, [rsp+8]
    or  edx, 0x00010000
    mov [rsp+8], edx

    mov edx, [rsp+12]
    bswap edx
    mov [rsp+12], edx

    mov rdi, rsp
    call chacha_qr
    mov rdi, rsp
    call chacha_qr
    mov rdi, rsp
    call chacha_qr

    movsxd rax, r13d
    mov edx, [rsp]
    mov [r14 + rax*8], edx
    mov edx, [rsp+4]
    mov [r14 + rax*8 + 4], edx

    inc r13d
    cmp r13d, FYCIPHER_RODADAS
    jb .agenda

    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------
;  Rodadas internas
;  rbx = ctx, r10d..r13d = A,B,C,D, r8d = rodada, r15d = tmp
; -----------------------------------------------------
rodada_enc:
    lea r14, [rbx + 16]
    movsxd rax, r8d

    mov eax, r11d
    movsxd rcx, r8d
    mov edx, [r14 + rcx*8]
    call FuncaoF
    xor r10d, eax

    mov eax, r13d
    movsxd rcx, r8d
    mov edx, [r14 + rcx*8 + 4]
    call FuncaoF
    xor r12d, eax

    mov r15d, r10d
    mov r10d, r11d
    mov r11d, r12d
    mov r12d, r13d
    mov r13d, r15d
    ret

rodada_dec:
    lea r14, [rbx + 16]

    mov r15d, r13d
    mov r13d, r12d
    mov r12d, r11d
    mov r11d, r10d
    mov r10d, r15d

    mov eax, r13d
    movsxd rcx, r8d
    mov edx, [r14 + rcx*8 + 4]
    call FuncaoF
    xor r12d, eax

    mov eax, r11d
    movsxd rcx, r8d
    mov edx, [r14 + rcx*8]
    call FuncaoF
    xor r10d, eax
    ret

; -----------------------------------------------------
;  fydcipher_criptografa(ctx, entrada[16], saida[16])
; -----------------------------------------------------
fydcipher_criptografa:
    push rbx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi

    mov r10d, [rsi]
    mov r11d, [rsi+4]
    mov r12d, [rsi+8]
    mov r13d, [rsi+12]

    xor r10d, [rbx]
    xor r11d, [rbx+4]
    xor r12d, [rbx+8]
    xor r13d, [rbx+12]

    xor r8d, r8d
.enc_loop:
    call rodada_enc
    inc r8d
    cmp r8d, FYCIPHER_RODADAS
    jb .enc_loop

    xor r10d, [rbx+12]
    xor r11d, [rbx+8]
    xor r12d, [rbx+4]
    xor r13d, [rbx]

    mov [rdx], r10d
    mov [rdx+4], r11d
    mov [rdx+8], r12d
    mov [rdx+12], r13d

    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbx
    ret

; -----------------------------------------------------
;  fydcipher_descriptografa(ctx, entrada[16], saida[16])
; -----------------------------------------------------
fydcipher_descriptografa:
    push rbx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi

    mov r10d, [rsi]
    mov r11d, [rsi+4]
    mov r12d, [rsi+8]
    mov r13d, [rsi+12]

    xor r10d, [rbx+12]
    xor r11d, [rbx+8]
    xor r12d, [rbx+4]
    xor r13d, [rbx]

    mov r8d, FYCIPHER_RODADAS - 1
.dec_loop:
    call rodada_dec
    dec r8d
    jns .dec_loop

    xor r10d, [rbx]
    xor r11d, [rbx+4]
    xor r12d, [rbx+8]
    xor r13d, [rbx+12]

    mov [rdx], r10d
    mov [rdx+4], r11d
    mov [rdx+8], r12d
    mov [rdx+12], r13d

    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbx
    ret

; -----------------------------------------------------
;  INTERNO: gf_dobrar(uint8 T[16])
;  T = T * x em GF(2^128), poly 0x87 (little-endian, XTS)
; -----------------------------------------------------
gf_dobrar:
    xor edx, edx
    xor ecx, ecx
.gf_loop:
    mov al, [rdi + rcx]
    mov r8b, dl
    shl al, 1
    setc dl
    or  al, r8b
    mov [rdi + rcx], al
    inc ecx
    cmp ecx, 16
    jb .gf_loop

    test dl, dl
    jz .gf_fim
    mov al, [rdi]
    xor al, 0x87
    mov [rdi], al
.gf_fim:
    ret

; -----------------------------------------------------
;  INTERNO: xts_tweak(ctx, numero_setor, T[16])
;  T = E_K(le64(setor) || le64(0))
; -----------------------------------------------------
xts_tweak:
    push rbx
    push r12
    sub rsp, 24

    mov r12, rdi
    mov rbx, rdx
    mov [rsp], rsi
    mov qword [rsp+8], 0

    mov rdi, r12
    mov rsi, rsp
    mov rdx, rbx
    call fydcipher_criptografa

    add rsp, 24
    pop r12
    pop rbx
    ret

; -----------------------------------------------------
;  fydcipher_xts_criptografa(ctx, setor, dados, tam) — in-place
;  Retorna: 0 = ok, -1 = tam nao multiplo de 16
; -----------------------------------------------------
fydcipher_xts_criptografa:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32

    test rcx, 15
    jnz .erro
    test rcx, rcx
    jz .ok

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx

    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rsp]
    call xts_tweak

.blk:
    mov rax, [r13]
    xor rax, [rsp]
    mov [rsp+16], rax

    mov rax, [r13+8]
    xor rax, [rsp+8]
    mov [rsp+24], rax

    mov rdi, rbx
    lea rsi, [rsp+16]
    mov rdx, r13
    call fydcipher_criptografa

    mov rax, [r13]
    xor rax, [rsp]
    mov [r13], rax

    mov rax, [r13+8]
    xor rax, [rsp+8]
    mov [r13+8], rax

    lea rdi, [rsp]
    call gf_dobrar

    add r13, 16
    sub r14, 16
    jnz .blk

.ok:
    xor eax, eax
    jmp .fim

.erro:
    mov eax, -1

.fim:
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------
;  fydcipher_xts_descriptografa(ctx, setor, dados, tam)
;  Retorna: 0 = ok, -1 = tam nao multiplo de 16
; -----------------------------------------------------
fydcipher_xts_descriptografa:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32

    test rcx, 15
    jnz .erro
    test rcx, rcx
    jz .ok

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx

    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rsp]
    call xts_tweak

.blk:
    mov rax, [r13]
    xor rax, [rsp]
    mov [rsp+16], rax

    mov rax, [r13+8]
    xor rax, [rsp+8]
    mov [rsp+24], rax

    mov rdi, rbx
    lea rsi, [rsp+16]
    mov rdx, r13
    call fydcipher_descriptografa

    mov rax, [r13]
    xor rax, [rsp]
    mov [r13], rax

    mov rax, [r13+8]
    xor rax, [rsp+8]
    mov [r13+8], rax

    lea rdi, [rsp]
    call gf_dobrar

    add r13, 16
    sub r14, 16
    jnz .blk

.ok:
    xor eax, eax
    jmp .fim

.erro:
    mov eax, -1

.fim:
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
