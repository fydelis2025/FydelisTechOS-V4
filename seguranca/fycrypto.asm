; ==========================================================
;  FYCRYPTO — Biblioteca criptográfica nativa do FYDELIS TECHOS
;  Alvo: x86-64 (System V ABI / elf64), NASM
;  Dependência: NENHUMA — freestanding, sem libc
;
;  Build (Linux): nasm -f elf64 fycrypto.asm -o fycrypto.o
;
;  Tamanhos das estruturas (para o header C):
;    SHA256_CTX     = 128 bytes
;    HMAC_SHA256_CTX= 384 bytes
;    AES256_CTX     = 240 bytes
;    AES256_GCM_CTX = 352 bytes
; ==========================================================

[BITS 64]
DEFAULT REL

; ── Exportar TODAS as funções para linkagem com C ─────────
; SHA-256
[GLOBAL sha256_inicia]
[GLOBAL sha256_adiciona]
[GLOBAL sha256_finaliza]
[GLOBAL sha256]

; HMAC-SHA256
[GLOBAL hmac_sha256_inicia]
[GLOBAL hmac_sha256_adiciona]
[GLOBAL hmac_sha256_finaliza]
[GLOBAL hmac_sha256]

; AES-256
[GLOBAL aes256_inicia]
[GLOBAL aes256_criptografa_bloco]
[GLOBAL aes256_descriptografa_bloco]
[GLOBAL aes256_cbc_criptografa]
[GLOBAL aes256_cbc_descriptografa]

; AES-256-GCM
[GLOBAL aes256_gcm_inicia]
[GLOBAL aes256_gcm_ad]
[GLOBAL aes256_gcm_criptografa]
[GLOBAL aes256_gcm_descriptografa]

; PBKDF2
[GLOBAL pbkdf2_sha256]

; Utilitários
[GLOBAL crypto_limpa_memoria]
[GLOBAL crypto_compara_constante_tempo]

; ── CONSTANTES SHA-256 (FIPS 180-4) ───────────────────────
section .rodata
align 16
sha256_constantes:
    dd 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    dd 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

align 16
sha256_k:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c20e73, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

; ── TABELAS AES (FIPS 197) ────────────────────────────────
align 16
aes_sbox:
    db 0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76
    db 0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0
    db 0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15
    db 0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75
    db 0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84
    db 0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf
    db 0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8
    db 0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2
    db 0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73
    db 0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb
    db 0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79
    db 0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08
    db 0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a
    db 0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e
    db 0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf
    db 0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16

align 16
aes_rcon:
    db 0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36,0x6c,0xd8,0xab,0x4d,0x9a,0x2f

align 16
shiftrows_perm:
    db 0,5,10,15, 4,9,14,3, 8,13,2,7, 12,1,6,11

align 16
invshiftrows_perm:
    db 0,13,10,7, 4,1,14,11, 8,5,2,15, 12,9,6,3

align 16
mixcoef:
    db 2,3,1,1,  1,2,3,1,  1,1,2,3,  3,1,1,2
    db 2,3,1,1,  1,2,3,1,  1,1,2,3,  3,1,1,2
    db 2,3,1,1,  1,2,3,1,  1,1,2,3,  3,1,1,2
    db 2,3,1,1,  1,2,3,1,  1,1,2,3,  3,1,1,2

align 16
invmix_coef:
    db 0x0e,0x0b,0x0d,0x09,  0x09,0x0e,0x0b,0x0d,  0x0d,0x09,0x0e,0x0b,  0x0b,0x0d,0x09,0x0e
    db 0x0e,0x0b,0x0d,0x09,  0x09,0x0e,0x0b,0x0d,  0x0d,0x09,0x0e,0x0b,  0x0b,0x0d,0x09,0x0e
    db 0x0e,0x0b,0x0d,0x09,  0x09,0x0e,0x0b,0x0d,  0x0d,0x09,0x0e,0x0b,  0x0b,0x0d,0x09,0x0e
    db 0x0e,0x0b,0x0d,0x09,  0x09,0x0e,0x0b,0x0d,  0x0d,0x09,0x0e,0x0b,  0x0b,0x0d,0x09,0x0e

section .bss
align 16
aes_inv_sbox: resb 256

; ── CÓDIGO ────────────────────────────────────────────────
section .text

; ═══════════════════════════════════════════════════════════
;  UTILITÁRIOS — SEGURANÇA
; ═══════════════════════════════════════════════════════════
; void crypto_limpa_memoria(void *ptr, size_t tam)
crypto_limpa_memoria:
    mov rcx, rsi
    xor eax, eax
    cld
    rep stosb
    mfence
    ret

; int crypto_compara_constante_tempo(const void *a, const void *b, size_t tam)
crypto_compara_constante_tempo:
    xor eax, eax
    xor r8d, r8d
    mov rcx, rdx
.compara_loop:
    test rcx, rcx
    jz .fim
    dec rcx
    mov r9b, [rdi + rcx]
    xor r9b, [rsi + rcx]
    or r8b, r9b
    jmp .compara_loop
.fim:
    test r8b, r8b
    sete al
    movzx eax, al
    ret

; ═══════════════════════════════════════════════════════════
;  SHA-256 — FIPS 180-4
; ═══════════════════════════════════════════════════════════
; void sha256_inicia(SHA256_CTX *ctx)
sha256_inicia:
    lea rax, [sha256_constantes]
    mov rcx, 8
.copia:
    mov rdx, rcx
    dec rdx
    mov r8d, [rax + rdx*4]
    mov [rdi + rdx*4], r8d
    dec rcx
    jnz .copia
    mov qword [rdi + 32], 0
    mov dword [rdi + 48], 0
    ret

; void sha256_adiciona(SHA256_CTX *ctx, const void *dados, size_t tam)
sha256_adiciona:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi
    mov r13, rdx
    mov r14d, [rdi + 48]
    mov rbx, rdi

.loop:
    test r13, r13
    jz .fim
    mov al, [r12]
    mov r15d, r14d
    mov [rbx + r15 + 48], al
    inc r12
    dec r13
    inc r14d
    add qword [rbx + 32], 8
    cmp r14d, 64
    jb .loop

    mov rdi, rbx
    lea rsi, [rbx + 48]
    call bloco_compress
    xor r14d, r14d
    jmp .loop

.fim:
    mov dword [rbx + 48], r14d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; void bloco_compress(SHA256_CTX *ctx, const uint8_t bloco[64])
bloco_compress:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r10, rsi

    mov rcx, 16
.carrega_w:
    mov rdx, rcx
    dec rdx
    mov eax, [r10 + rdx*4]
    bswap eax
    mov [rbx + rdx*4 + 112], eax
    dec rcx
    jnz .carrega_w

    mov r12d, [rbx]
    mov r13d, [rbx + 4]
    mov r14d, [rbx + 8]
    mov r15d, [rbx + 12]
    mov ebp,  [rbx + 16]
    mov r8d,  [rbx + 20]
    mov r9d,  [rbx + 24]
    mov r11d, [rbx + 28]

    xor ecx, ecx
.roundos:
    cmp ecx, 16
    jb .w_pronto

    ; s0 = rotr(W[i-15], 7) ^ rotr(W[i-15], 18) ^ (W[i-15] >> 3)
    lea rax, [rbx + rcx*4]
    mov eax, [rax + 112 - 60]
    mov edx, eax
    mov esi, eax
    ror eax, 7
    ror edx, 18
    shr esi, 3
    xor eax, edx
    xor eax, esi

    lea rdx, [rbx + rcx*4]
    add eax, [rdx + 112 - 28]
    add eax, [rdx + 112 - 64]

    ; s1 = rotr(W[i-2], 17) ^ rotr(W[i-2], 19) ^ (W[i-2] >> 10)
    mov edx, [rdx + 112 - 8]
    mov esi, edx
    mov r10d, edx
    ror edx, 17
    ror esi, 19
    shr r10d, 10
    xor edx, esi
    xor edx, r10d

    add eax, edx
    lea rdx, [rbx + rcx*4]
    mov [rdx + 112], eax

.w_pronto:
    ; Σ1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
    mov eax, ebp
    mov esi, ebp
    mov edx, ebp
    ror eax, 6
    ror esi, 11
    ror edx, 25
    xor eax, esi
    xor eax, edx

    ; ch = (e & f) ^ (~e & g)
    mov esi, ebp
    and esi, r8d
    mov edx, ebp
    not edx
    and edx, r9d
    xor esi, edx

    ; t1 = h + Σ1 + ch + K[i] + W[i]
    add eax, r11d
    add eax, esi
    lea r10, [sha256_k]
    add eax, [r10 + rcx*4]
    lea r10, [rbx + rcx*4]
    add eax, [r10 + 112]
    mov r10d, eax

    ; Σ0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
    mov eax, r12d
    mov esi, r12d
    mov edx, r12d
    ror eax, 2
    ror esi, 13
    ror edx, 22
    xor eax, esi
    xor eax, edx

    ; maj = (a&b) ^ (a&c) ^ (b&c)
    mov esi, r12d
    and esi, r13d
    mov edx, r12d
    and edx, r14d
    xor esi, edx
    mov edx, r13d
    and edx, r14d
    xor esi, edx
    add eax, esi

    mov r11d, r9d
    mov r9d,  r8d
    mov r8d,  ebp
    add r10d, eax
    mov ebp,  r15d
    add ebp,  r10d
    mov r15d, r14d
    mov r14d, r13d
    mov r13d, r12d
    mov r12d, r10d

    inc ecx
    cmp ecx, 64
    jb .roundos

    add [rbx],      r12d
    add [rbx + 4],  r13d
    add [rbx + 8],  r14d
    add [rbx + 12], r15d
    add [rbx + 16], ebp
    add [rbx + 20], r8d
    add [rbx + 24], r9d
    add [rbx + 28], r11d

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; void sha256_finaliza(SHA256_CTX *ctx, uint8_t digest[32])
sha256_finaliza:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi

    mov eax, [rbx + 48]
    mov byte [rbx + rax + 48], 0x80
    inc eax
    cmp eax, 57
    jbe .escreve_len

.zera1:
    cmp eax, 64
    jae .fecha1
    mov byte [rbx + rax + 48], 0
    inc eax
    jmp .zera1

.fecha1:
    mov rdi, rbx
    lea rsi, [rbx + 48]
    call bloco_compress
    xor eax, eax

.escreve_len:
.zera2:
    cmp eax, 56
    jae .len
    mov byte [rbx + rax + 48], 0
    inc eax
    jmp .zera2

.len:
    mov rax, [rbx + 32]
    bswap rax
    mov [rbx + 104], rax
    mov rdi, rbx
    lea rsi, [rbx + 48]
    call bloco_compress

    mov ecx, 8
.copia_be:
    mov rdx, rcx
    dec rdx
    mov eax, [rbx + rdx*4]
    bswap eax
    mov [r12 + rdx*4], eax
    dec rcx
    jnz .copia_be

    pop r12
    pop rbx
    ret

; void sha256(void *saida, const void *dados, size_t tam)
sha256:
    push rbp
    push rbx
    push r12
    sub rsp, 128

    mov r12, rdi
    mov rbx, rsi
    mov rbp, rdx

    mov rdi, rsp
    call sha256_inicia
    mov rdi, rsp
    mov rsi, rbx
    mov rdx, rbp
    call sha256_adiciona
    mov rdi, rsp
    mov rsi, r12
    call sha256_finaliza

    add rsp, 128
    pop r12
    pop rbx
    pop rbp
    ret

; ═══════════════════════════════════════════════════════════
;  HMAC-SHA256
; ═══════════════════════════════════════════════════════════
; void hmac_sha256_inicia(HMAC_CTX *ctx, const void *chave, size_t tam_chave)
hmac_sha256_inicia:
    push rbp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    sub rsp, 128
    mov rbp, rsp

    mov rcx, 16
    xor eax, eax
.zera:
    mov rdx, rcx
    dec rdx
    mov [rbp + rdx*4], eax
    mov [rbp + rdx*4 + 64], eax
    dec rcx
    jnz .zera

    cmp r13, 64
    jbe .copia_chave
    mov rdi, rbp
    mov rsi, r12
    mov rdx, r13
    call sha256
    mov r13d, 32
    mov rsi, rbp
    jmp .copia_loop

.copia_chave:
    mov rsi, r12

.copia_loop:
    mov rcx, r13
.cp_bytes:
    test rcx, rcx
    jz .fim_copia
    dec rcx
    mov al, [rsi + rcx]
    mov [rbp + rcx], al
    mov [rbp + rcx + 64], al
    jmp .cp_bytes

.fim_copia:
    mov rcx, 64
.xors:
    dec rcx
    mov al, [rbp + rcx]
    xor al, 0x36
    mov [rbp + rcx], al

    mov al, [rbp + rcx + 64]
    xor al, 0x5C
    mov [rbp + rcx + 64], al
    mov [rbx + rcx + 128], al

    test rcx, rcx
    jnz .xors

    mov rdi, rbx
    call sha256_inicia
    mov rdi, rbx
    mov rsi, rbp
    mov edx, 64
    call sha256_adiciona

    add rsp, 128
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; void hmac_sha256_adiciona(HMAC_CTX *ctx, const void *dados, size_t tam)
hmac_sha256_adiciona:
    jmp sha256_adiciona

; void hmac_sha256_finaliza(HMAC_CTX *ctx, uint8_t tag[32])
hmac_sha256_finaliza:
    push rbp
    push rbx
    push r12
    sub rsp, 32

    mov rbx, rdi
    mov r12, rsi

    mov rdi, rbx
    mov rsi, rsp
    call sha256_finaliza

    mov rdi, rbx
    call sha256_inicia
    mov rdi, rbx
    lea rsi, [rbx + 128]
    mov edx, 64
    call sha256_adiciona
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 32
    call sha256_adiciona
    mov rdi, rbx
    mov rsi, r12
    call sha256_finaliza

    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

; void hmac_sha256(uint8_t tag[32], const void *chave, size_t tam_chave,
;                  const void *dados, size_t tam)
hmac_sha256:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 384

    mov r12, rdi
    mov r13, rcx
    mov r14, r8

    mov rdi, rsp
    call hmac_sha256_inicia
    mov rdi, rsp
    mov rsi, r13
    mov rdx, r14
    call hmac_sha256_adiciona
    mov rdi, rsp
    mov rsi, r12
    call hmac_sha256_finaliza

    add rsp, 384
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ═══════════════════════════════════════════════════════════
;  AES-256 — FIPS 197 (Nk=8, Nr=14, 15 round keys)
; ═══════════════════════════════════════════════════════════
; void aes256_inicia(AES256_CTX *ctx, const uint8_t chave[32])
aes256_inicia:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16

    mov rbx, rdi
    mov r12, rsi

    lea r13, [aes_sbox]
    lea r8,  [aes_inv_sbox]
    xor ecx, ecx
.build_inv:
    movzx eax, byte [r13 + rcx]
    mov [r8 + rax], cl
    inc ecx
    cmp ecx, 256
    jb .build_inv

    mov ecx, 8
.copy_key:
    mov rdx, rcx
    dec rdx
    mov eax, [r12 + rdx*4]
    mov [rbx + rdx*4], eax
    dec rcx
    jnz .copy_key

    mov r14d, 8
.exp:
    mov eax, r14d
    dec eax
    shl eax, 2
    mov r15, rbx
    add r15, rax
    mov eax, [r15]
    mov [rsp], eax

    mov ecx, r14d
    and ecx, 7
    test ecx, ecx
    jnz .chk4

    mov al, [rsp]
    mov dl, [rsp+1]
    mov [rsp], dl
    mov dl, [rsp+2]
    mov [rsp+1], dl
    mov dl, [rsp+3]
    mov [rsp+2], dl
    mov [rsp+3], al

    xor ecx, ecx
.sw0:
    movzx eax, byte [rsp + rcx]
    mov al, [r13 + rax]
    mov [rsp + rcx], al
    inc ecx
    cmp ecx, 4
    jb .sw0

    mov ecx, r14d
    shr ecx, 3
    lea rdx, [aes_rcon]
    movzx eax, byte [rdx + rcx - 1]
    mov dl, [rsp]
    xor dl, al
    mov [rsp], dl
    jmp .xorw

.chk4:
    cmp ecx, 4
    jne .xorw
    xor ecx, ecx
.sw4:
    movzx eax, byte [rsp + rcx]
    mov al, [r13 + rax]
    mov [rsp + rcx], al
    inc ecx
    cmp ecx, 4
    jb .sw4

.xorw:
    mov eax, r14d
    sub eax, 8
    shl eax, 2
    mov r15, rbx
    add r15, rax

    mov r8, r14
    shl r8, 2
    add r8, rbx

    mov ecx, 4
.xw:
    mov rdx, rcx
    dec rdx
    mov al, [r15 + rdx]
    xor al, [rsp + rdx]
    mov [r8 + rdx], al
    dec ecx
    jnz .xw

    inc r14d
    cmp r14d, 60
    jb .exp

    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

aes_mul:
    xor ecx, ecx
    movzx r8d, al
.mul_loop:
    test r10d, 1
    jz .mul_skip
    xor ecx, r8d
.mul_skip:
    mov eax, r8d
    add r8d, r8d
    mov edx, eax
    shr edx, 7
    imul edx, edx, 0x1b
    xor r8d, edx
    and r8d, 0xff
    shr r10d, 1
    jnz .mul_loop
    mov eax, ecx
    ret

aes_mix_generic:
    push rbx
    push r12
    push r13
    sub rsp, 16

    mov rbx, rdi
    mov r13, rsi
    xor r12d, r12d
.ob:
    xor r11d, r11d
    mov r9d, 4
.jloop:
    dec r9d
    mov eax, r12d
    shr eax, 2
    shl eax, 2
    add eax, r9d
    movzx eax, byte [rbx + rax]

    mov r10d, r12d
    shl r10d, 2
    add r10d, r9d
    movzx r10d, byte [r13 + r10]

    call aes_mul
    xor r11d, eax
    test r9d, r9d
    jnz .jloop

    mov r8d, r12d
    mov [rsp + r8], r11b
    inc r12d
    cmp r12d, 16
    jb .ob

    mov ecx, 16
.cp:
    mov rdx, rcx
    dec rdx
    mov al, [rsp + rdx]
    mov [rbx + rdx], al
    dec ecx
    jnz .cp

    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

aes_sub_generic:
    xor ecx, ecx
.l:
    movzx eax, byte [rdi + rcx]
    mov al, [rsi + rax]
    mov [rdi + rcx], al
    inc ecx
    cmp ecx, 16
    jb .l
    ret

aes_shift_generic:
    sub rsp, 16
    mov rcx, 16
.cp:
    mov rdx, rcx
    dec rdx
    mov al, [rdi + rdx]
    mov [rsp + rdx], al
    dec rcx
    jnz .cp

    xor ecx, ecx
.l:
    movzx eax, byte [rsi + rcx]
    mov al, [rsp + rax]
    mov [rdi + rcx], al
    inc ecx
    cmp ecx, 16
    jb .l

    add rsp, 16
    ret

aes_addroundkey:
    mov r8, rsi
    mov eax, edx
    shl eax, 4
    add r8, rax
    xor ecx, ecx
.l:
    mov al, [r8 + rcx]
    mov dl, [rdi + rcx]
    xor dl, al
    mov [rdi + rcx], dl
    inc ecx
    cmp ecx, 16
    jb .l
    ret

aes_subbytes:
    lea rsi, [aes_sbox]
    jmp aes_sub_generic
aes_invsubbytes:
    lea rsi, [aes_inv_sbox]
    jmp aes_sub_generic
aes_shiftrows:
    lea rsi, [shiftrows_perm]
    jmp aes_shift_generic
aes_invshiftrows:
    lea rsi, [invshiftrows_perm]
    jmp aes_shift_generic
aes_mixcolumns:
    lea rsi, [mixcoef]
    jmp aes_mix_generic
aes_invmixcolumns:
    lea rsi, [invmix_coef]
    jmp aes_mix_generic

aes_enc_state:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi

    mov rdi, r12
    mov rsi, rbx
    xor edx, edx
    call aes_addroundkey

    mov r13d, 1
.rounds:
    mov rdi, r12
    call aes_subbytes
    mov rdi, r12
    call aes_shiftrows
    mov rdi, r12
    call aes_mixcolumns
    mov rdi, r12
    mov rsi, rbx
    mov edx, r13d
    call aes_addroundkey
    inc r13d
    cmp r13d, 14
    jb .rounds

    mov rdi, r12
    call aes_subbytes
    mov rdi, r12
    call aes_shiftrows
    mov rdi, r12
    mov rsi, rbx
    mov edx, 14
    call aes_addroundkey

    pop r13
    pop r12
    pop rbx
    ret

aes_dec_state:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi

    mov rdi, r12
    mov rsi, rbx
    mov edx, 14
    call aes_addroundkey

    mov r13d, 13
.rounds:
    mov rdi, r12
    call aes_invshiftrows
    mov rdi, r12
    call aes_invsubbytes
    mov rdi, r12
    mov rsi, rbx
    mov edx, r13d
    call aes_addroundkey
    mov rdi, r12
    call aes_invmixcolumns
    dec r13d
    jnz .rounds

    mov rdi, r12
    call aes_invshiftrows
    mov rdi, r12
    call aes_invsubbytes
    mov rdi, r12
    mov rsi, rbx
    xor edx, edx
    call aes_addroundkey

    pop r13
    pop r12
    pop rbx
    ret

aes256_criptografa_bloco:
    push rbx
    sub rsp, 16
    mov rbx, rdx
    mov rax, [rsi]
    mov [rsp], rax
    mov rax, [rsi+8]
    mov [rsp+8], rax
    mov rsi, rsp
    call aes_enc_state
    mov rax, [rsp]
    mov [rbx], rax
    mov rax, [rsp+8]
    mov [rbx+8], rax
    add rsp, 16
    pop rbx
    ret

aes256_descriptografa_bloco:
    push rbx
    sub rsp, 16
    mov rbx, rdx
    mov rax, [rsi]
    mov [rsp], rax
    mov rax, [rsi+8]
    mov [rsp+8], rax
    mov rsi, rsp
    call aes_dec_state
    mov rax, [rsp]
    mov [rbx], rax
    mov rax, [rsp+8]
    mov [rbx+8], rax
    add rsp, 16
    pop rbx
    ret

aes256_cbc_criptografa:
    push rbx
    push r12
    push r13
    push r14
    push r15
    test r8, 15
    jnz .erro
    sub rsp, 16

    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, rsi

    mov rax, [r15]
    mov [rsp], rax
    mov rax, [r15+8]
    mov [rsp+8], rax
    xor r15d, r15d

.blk:
    mov ecx, 16
.x:
    mov rdx, rcx
    dec rdx
    lea r8, [r12 + r15]
    mov al, [r8 + rdx]
    xor al, [rsp + rdx]
    mov [rsp + rdx], al
    dec ecx
    jnz .x

    mov rdi, rbx
    mov rsi, rsp
    call aes_enc_state

    mov ecx, 16
.cp:
    mov rdx, rcx
    dec rdx
    lea r8, [r13 + r15]
    mov al, [rsp + rdx]
    mov [r8 + rdx], al
    dec ecx
    jnz .cp

    add r15, 16
    sub r14, 16
    jnz .blk

    xor eax, eax
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.erro:
    mov eax, -1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

aes256_cbc_descriptografa:
    push rbx
    push r12
    push r13
    push r14
    push r15
    test r8, 15
    jnz .erro
    sub rsp, 32

    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8

    mov rax, [rsi]
    mov [rsp+16], rax
    mov rax, [rsi+8]
    mov [rsp+24], rax
    xor r15d, r15d

.blk:
    mov rax, [r12]
    mov [rsp], rax
    mov r8, [rsp+16]
    mov [rsp+16], rax

    mov rax, [r12+8]
    mov [rsp+8], rax
    mov r9, [rsp+24]
    mov [rsp+24], rax

    mov rdi, rbx
    mov rsi, rsp
    call aes_dec_state

    mov ecx, 16
.x:
    mov rdx, rcx
    dec rdx
    mov al, [rsp + rdx]
    xor al, r8b
    lea r10, [r13 + r15]
    mov [r10 + rdx], al
    dec ecx
    jnz .x

    mov [rsp+16], rax
    mov rax, [r12+8]
    mov [rsp+24], rax

    add r15, 16
    add r12, 16
    sub r14, 16
    jnz .blk

    xor eax, eax
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.erro:
    mov eax, -1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
;  AES-256-GCM
; ═══════════════════════════════════════════════════════════
gcm_gmul:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov rbx, rdi
    mov rax, [rsi]
    mov [rsp], rax
    mov rax, [rsi+8]
    mov [rsp+8], rax
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0

    xor r14d, r14d
.byte_loop:
    mov r15d, 8
    mov r8d, r14d
    mov al, [rbx + r8]
.bit_loop:
    mov edx, eax
    and edx, 0x80
    jz .no_xor
    mov r9, [rsp]
    xor r9, [rsp+16]
    mov [rsp+16], r9
    mov r9, [rsp+8]
    xor r9, [rsp+24]
    mov [rsp+24], r9
.no_xor:
    shl eax, 1
    mov dl, [rsp+15]
    and dl, 1
    mov rcx, 15
.shr_v:
    mov r8b, [rsp + rcx]
    shr r8b, 1
    mov r9b, [rsp + rcx - 1]
    and r9b, 1
    shl r9b, 7
    or r8b, r9b
    mov [rsp + rcx], r8b
    dec rcx
    jnz .shr_v

    mov r8b, [rsp]
    shr r8b, 1
    mov [rsp], r8b
    test dl, dl
    jz .no_reduce
    mov r8b, [rsp]
    xor r8b, 0xe1
    mov [rsp], r8b
.no_reduce:
    dec r15d
    jnz .bit_loop
    inc r14d
    cmp r14d, 16
    jb .byte_loop

    mov rax, [rsp+16]
    mov [rbx], rax
    mov rax, [rsp+24]
    mov [rbx+8], rax

    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ghash_block:
    push rbx
    mov rbx, rdi
    mov rcx, 16
.x:
    mov rdx, rcx
    dec rdx
    mov al, [rsi + rdx]
    mov r8b, [rbx + rdx + 256]
    xor r8b, al
    mov [rbx + rdx + 256], r8b
    dec rcx
    jnz .x

    mov rdi, rbx
    lea rsi, [rbx + 240]
    call gcm_gmul
    pop rbx
    ret

ctr_block:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx+272]
    mov [r12], rax
    mov rax, [rbx+280]
    mov [r12+8], rax
    mov eax, edx
    bswap eax
    mov [r12+12], eax
    mov rdi, rbx
    mov rsi, r12
    call aes_enc_state
    pop r12
    pop rbx
    ret

aes256_gcm_inicia:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16

    mov rbx, rdi
    call aes256_inicia

    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov rdi, rbx
    mov rsi, rsp
    call aes_enc_state

    mov rcx, 16
.cpH:
    mov r8, rcx
    dec r8
    mov al, [rsp + r8]
    mov [rbx + r8 + 240], al
    dec rcx
    jnz .cpH

    mov rcx, 12
.cpiv:
    mov r8, rcx
    dec r8
    mov al, [rdx + r8]
    mov [rbx + r8 + 272], al
    dec rcx
    jnz .cpiv

    mov dword [rbx+284], 0x01000000
    mov qword [rbx+256], 0
    mov qword [rbx+264], 0
    mov qword [rbx+304], 0
    mov qword [rbx+312], 0

    mov rcx, 16
.cpj:
    mov r8, rcx
    dec r8
    mov al, [rbx + r8 + 272]
    mov [rsp + r8], al
    dec rcx
    jnz .cpj

    mov rdi, rbx
    mov rsi, rsp
    call aes_enc_state

    mov rcx, 16
.cpe:
    mov r8, rcx
    dec r8
    mov al, [rsp + r8]
    mov [rbx + r8 + 288], al
    dec rcx
    jnz .cpe

    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

aes256_gcm_ad:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 16

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    add [rbx+304], r13

.full:
    cmp r13, 16
    jb .resto
    mov rdi, rbx
    mov rsi, r12
    call ghash_block
    add r12, 16
    sub r13, 16
    jmp .full

.resto:
    test r13, r13
    jz .fim
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov rcx, r13
.p:
    mov r8, rcx
    dec r8
    mov al, [r12 + r8]
    mov [rsp + r8], al
    dec rcx
    jnz .p

    mov rdi, rbx
    mov rsi, rsp
    call ghash_block

.fim:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

aes256_gcm_criptografa:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov rbx, rdi
    mov rbp, r8
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    add [rbx+312], r14
    mov r15d, 1

.blk:
    test r14, r14
    jz .ghash_len
    mov rdi, rbx
    mov rsi, rsp
    mov edx, r15d
    call ctr_block

    mov ecx, 16
    cmp r14, 16
    jae .n_ok
    mov ecx, r14d
.n_ok:
    xor r10d, r10d
.x:
    mov r8d, r10d
    mov al, [r12 + r8]
    xor al, [rsp + r8]
    mov [r13 + r8], al
    inc r10d
    dec ecx
    jnz .x

    cmp r10d, 16
    jne .pad_ghash
    mov rdi, rbx
    mov rsi, r13
    call ghash_block
    jmp .next

.pad_ghash:
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov ecx, r10d
.pd:
    mov r8, rcx
    dec r8
    mov al, [r13 + r8]
    mov [rsp + r8 + 16], al
    dec ecx
    jnz .pd

    mov rdi, rbx
    lea rsi, [rsp+16]
    call ghash_block

.next:
    add r12, r10
    add r13, r10
    sub r14, r10
    inc r15d
    jmp .blk

.ghash_len:
    mov rax, [rbx+304]
    bswap rax
    mov [rsp+16], rax
    mov rax, [rbx+312]
    bswap rax
    mov [rsp+24], rax
    mov rdi, rbx
    lea rsi, [rsp+16]
    call ghash_block

    mov rcx, 16
.tg:
    mov r8, rcx
    dec r8
    mov al, [rbx + r8 + 288]
    xor al, [rbx + r8 + 256]
    mov [rbp + r8], al
    dec rcx
    jnz .tg

    xor eax, eax
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

aes256_gcm_descriptografa:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov rbx, rdi
    mov rbp, r8
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    add [rbx+312], r14
    mov r15d, 1

.blk:
    test r14, r14
    jz .ghash_len
    mov rdi, rbx
    mov rsi, rsp
    mov edx, r15d
    call ctr_block

    mov ecx, 16
    cmp r14, 16
    jae .n_ok
    mov ecx, r14d
.n_ok:
    xor r10d, r10d
.x:
    mov r8d, r10d
    mov al, [r12 + r8]
    xor al, [rsp + r8]
    mov [r13 + r8], al
    inc r10d
    dec ecx
    jnz .x

    cmp r10d, 16
    jne .pad_ghash
    mov rdi, rbx
    mov rsi, r12
    call ghash_block
    jmp .next

.pad_ghash:
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov ecx, r10d
.pd:
    mov r8, rcx
    dec r8
    mov al, [r12 + r8]
    mov [rsp + r8 + 16], al
    dec ecx
    jnz .pd

    mov rdi, rbx
    lea rsi, [rsp+16]
    call ghash_block

.next:
    add r12, r10
    add r13, r10
    sub r14, r10
    inc r15d
    jmp .blk

.ghash_len:
    mov rax, [rbx+304]
    bswap rax
    mov [rsp+16], rax
    mov rax, [rbx+312]
    bswap rax
    mov [rsp+24], rax
    mov rdi, rbx
    lea rsi, [rsp+16]
    call ghash_block

    mov rdi, rbp
    lea rsi, [rbx+256]
    mov edx, 16
    call crypto_compara_constante_tempo
    test eax, eax
    jz .falha
    xor eax, eax
    jmp .sair

.falha:
    mov eax, -3

.sair:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
;  PBKDF2-HMAC-SHA256
; ═══════════════════════════════════════════════════════════
; void pbkdf2_sha256(uint8_t *dk, const void *senha, size_t tam_senha,
;                    const void *sal, size_t tam_sal, uint64_t iteracoes,
;                    size_t dk_len)
pbkdf2_sha256:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, [rsp + 56]             ; dk_len (5o argumento na pilha na System V ABI)
    sub rsp, 512

    mov r13, rdi                    ; dk
    mov rbp, rsi                    ; senha
    mov r14, rdx                    ; tam_senha
    mov r15, rcx                    ; sal
    mov [rsp + 456], r9             ; iteracoes
    mov [rsp + 464], r8             ; tam_sal
    mov dword [rsp + 452], 1        ; índice do bloco (1-based)

.blk_loop:
    test r12, r12
    jz .fim

    mov eax, [rsp + 452]
    bswap eax
    mov [rsp + 448], eax

    mov rdi, rsp
    mov rsi, rbp
    mov rdx, r14
    call hmac_sha256_inicia

    mov rdi, rsp
    mov rsi, r15
    mov rdx, [rsp + 464]
    call hmac_sha256_adiciona

    mov rdi, rsp
    lea rsi, [rsp + 448]
    mov edx, 4
    call hmac_sha256_adiciona

    mov rdi, rsp
    lea rsi, [rsp + 384]
    call hmac_sha256_finaliza

    mov ecx, 32
.cp_t:
    mov r8, rcx
    dec r8
    mov al, [rsp + r8 + 384]
    mov [rsp + r8 + 416], al
    dec ecx
    jnz .cp_t

    mov rax, [rsp + 456]
    mov [rsp + 472], rax

.it_loop:
    dec qword [rsp + 472]
    jz .store

    mov rdi, rsp
    mov rsi, rbp
    mov rdx, r14
    call hmac_sha256_inicia

    mov rdi, rsp
    lea rsi, [rsp + 384]
    mov edx, 32
    call hmac_sha256_adiciona

    mov rdi, rsp
    lea rsi, [rsp + 384]
    call hmac_sha256_finaliza

    mov ecx, 32
.xor_t:
    mov r8, rcx
    dec r8
    mov al, [rsp + r8 + 384]
    xor al, [rsp + r8 + 416]
    mov [rsp + r8 + 416], al
    dec ecx
    jnz .xor_t

    jmp .it_loop

.store:
    mov r10d, 32
    cmp r12, 32
    jae .st_n
    mov r10d, r12d
.st_n:
    xor ecx, ecx
.st:
    mov r8d, ecx
    mov al, [rsp + r8 + 416]
    mov [r13 + r8], al
    inc ecx
    cmp ecx, r10d
    jb .st

    add r13, r10
    sub r12, r10
    inc dword [rsp + 452]
    jmp .blk_loop

.fim:
    add rsp, 512
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
