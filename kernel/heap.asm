; ==========================================
; HEAP.ASM — Buddy Allocator
; Alocação Dinâmica de Memória
; FydelisTech OS v2.0 · Salvador • Bahia 🇧🇷
; ==========================================
bits 64
default rel

; Configuração do Heap
HEAP_INICIO    equ 0xFFFF800000000000   ; Início do espaço de heap
HEAP_TAMANHO   equ 1024 * 1024 * 512     ; 512 MB
HEAP_MIN_BLCOK equ 4096                  ; Mínimo 4KB
HEAP_MAX_ORDER equ 17                    ; 2^17 × 4KB = 512MB

; Estrutura de nó da árvore
BITMAP_TAMANHO equ (1 << (HEAP_MAX_ORDER + 1)) / 8

section .bss
align 8
buddy_bitmap:       resb BITMAP_TAMANHO
heap_livre:         resq 1
heap_inicializado:  resb 1

section .text
global heap_inicializar
global heap_alocar
global heap_liberar
global heap_disponivel

; ==========================================
; INICIALIZAR O ALOCADOR
; ==========================================
heap_inicializar:
    mov al, [heap_inicializado]
    cmp al, 1
    je .feito

    lea rdi, [buddy_bitmap]
    mov rcx, BITMAP_TAMANHO
    xor al, al
    rep stosb

    mov qword [heap_livre], HEAP_TAMANHO
    mov byte [heap_inicializado], 1
.feito:
    ret

; ==========================================
; CALCULAR ORDEM
; Entrada: rdi = tamanho em bytes
; Saída:   rax = ordem (tamanho do bloco = 4KB << ordem)
; ==========================================
calcular_ordem:
    mov rax, HEAP_MIN_BLCOK
    xor rcx, rcx
.loop:
    cmp rax, rdi
    jae .pronto
    shl rax, 1
    inc rcx
    cmp rcx, HEAP_MAX_ORDER
    jbe .loop
.pronto:
    mov rax, rcx
    ret

; ==========================================
; ENCONTRAR BLOCO LIVRE
; Entrada: rdi = ordem desejada
; Saída:   rax = índice do bloco (0 se falhou)
; ==========================================
encontrar_bloco:
    push rbx
    push r12
    push r13
    push rsi

    mov r13, rdi                ; r13 = ordem
    mov rdx, 1
    mov rcx, r13
    shl rdx, cl                 ; rdx = 2^ordem (nº de blocos na camada)
    xor r12, r12

.procurar_loop:
    cmp r12, rdx
    jae .nao_encontrou

    ; índice na árvore: (2^ordem - 1) + i
    mov rax, 1
    mov rcx, r13
    shl rax, cl
    add rax, r12
    dec rax

    mov rbx, rax
    shr rax, 3                  ; byte offset no bitmap

    mov rcx, rbx
    and rcx, 7                  ; bit offset
    mov dl, 1
    shl dl, cl                  ; máscara do bit

    lea rsi, [buddy_bitmap]
    add rsi, rax
    mov al, [rsi]
    test al, dl
    jnz .proximo_bloco

    or al, dl
    mov [rsi], al               ; marca como ocupado
    mov rax, r12
    jmp .fim_encontrar

.proximo_bloco:
    inc r12
    jmp .procurar_loop

.nao_encontrou:
    xor rax, rax

.fim_encontrar:
    pop rsi
    pop r13
    pop r12
    pop rbx
    ret

; ==========================================
; ALOCAR
; Entrada: rdi = tamanho em bytes
; Saída:   rax = endereço virtual (0 se falhou)
; ==========================================
heap_alocar:
    push rbp
    push rbx
    push r12
    push r13

    cmp rdi, HEAP_MIN_BLCOK
    jae .tamanho_ok
    mov rdi, HEAP_MIN_BLCOK
.tamanho_ok:

    call calcular_ordem
    mov rbp, rax                ; rbp = ordem

    mov rdi, rbp
    call encontrar_bloco
    test rax, rax
    jz .falha

    mov r12, rax                ; r12 = índice do bloco

    ; endereço = HEAP_INICIO + indice * (4KB << ordem)
    mov rax, r12
    mov rcx, rbp
    add rcx, 12                 ; 12 = log2(4096)
    shl rax, cl
    mov rdx, HEAP_INICIO
    add rax, rdx
    mov r13, rax

    mov rdi, r12
    mov rsi, rbp
    call marcar_ocupado

    ; heap_livre -= (4KB << ordem)
    mov rax, 1
    mov rcx, rbp
    add rcx, 12
    shl rax, cl
    mov rdx, [heap_livre]
    sub rdx, rax
    mov [heap_livre], rdx

    mov rax, r13
    jmp .fim

.falha:
    xor rax, rax

.fim:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ==========================================
; LIBERAR BLOCO
; Entrada: rdi = endereço do bloco
; ==========================================
heap_liberar:
    push rbp
    push rbx
    push r12

    mov rax, HEAP_INICIO
    cmp rdi, rax
    jb .invalido
    mov rax, HEAP_INICIO + HEAP_TAMANHO
    cmp rdi, rax
    jae .invalido

    ; índice do bloco de 4KB = (addr - HEAP_INICIO) / 4096
    mov rax, rdi
    mov rdx, HEAP_INICIO
    sub rax, rdx
    xor rdx, rdx
    mov rcx, HEAP_MIN_BLCOK
    div rcx
    mov r12, rax                ; r12 = índice

    ; descobrir ordem: posição do primeiro bit 1 do índice
    xor rbp, rbp
.ordem_loop:
    mov cl, bpl                 ; shl em x86-64 só aceita cl como contador
    mov rcx, 1
    shl rcx, cl
    mov rdx, r12
    and rdx, rcx
    jz .achou
    inc rbp
    cmp rbp, HEAP_MAX_ORDER
    jbe .ordem_loop
.achou:

    mov rdi, r12
    mov rsi, rbp
    call marcar_livre_e_fundir

    ; heap_livre += (4KB << ordem)
    mov rax, 1
    mov rcx, rbp
    add rcx, 12
    shl rax, cl
    mov rdx, [heap_livre]
    add rdx, rax
    mov [heap_livre], rdx

.invalido:
    pop r12
    pop rbx
    pop rbp
    ret

; ==========================================
; MARCAR OCUPADO
; Entrada: rdi = índice do bloco, rsi = ordem
; ==========================================
marcar_ocupado:
    push rbx
    push rdx
    push rsi

    mov rcx, rsi
    mov rax, rdi
    mov rdx, 1
    shl rdx, cl
    add rax, rdx
    dec rax                     ; índice na árvore

    mov rbx, rax
    shr rax, 3                  ; byte offset

    mov rcx, rbx
    and rcx, 7                  ; bit offset
    mov dl, 1
    shl dl, cl

    lea rsi, [buddy_bitmap]
    add rsi, rax
    mov al, [rsi]
    or al, dl
    mov [rsi], al

    pop rsi
    pop rdx
    pop rbx
    ret

; ==========================================
; MARCAR LIVRE E FUNDIR (coalescing)
; Entrada: rdi = índice do bloco, rsi = ordem
; ==========================================
marcar_livre_e_fundir:
    push rbx
    push rbp
    push rsi
    push rdx
    push r8

    mov rbp, rsi                ; rbp = ordem atual (persiste entre iterações)
.fundir_loop:
    mov rcx, rbp

    ; --- limpar o bit do nó atual: índice = rdi + 2^ordem - 1 ---
    mov rax, rdi
    mov r8, 1
    shl r8, cl
    add rax, r8
    dec rax
    mov rbx, rax
    shr rax, 3                  ; byte offset
    mov rcx, rbx
    and rcx, 7                  ; bit offset
    mov r8b, 1
    shl r8b, cl                 ; máscara
    not r8b
    lea rsi, [buddy_bitmap]
    add rsi, rax
    mov al, [rsi]
    and al, r8b
    mov [rsi], al

    ; --- testar o buddy: (rdi ^ 1) + 2^ordem - 1 ---
    mov rdx, rdi
    xor rdx, 1
    mov rax, rdx
    mov rcx, rbp                ; restaura a ordem (cl foi sobrescrito)
    mov r8, 1
    shl r8, cl
    add rax, r8
    dec rax

    mov rbx, rax
    shr rax, 3
    lea rsi, [buddy_bitmap]
    add rsi, rax

    mov rcx, rbx
    and rcx, 7
    mov r8b, 1
    shl r8b, cl
    mov al, [rsi]
    test al, r8b
    jnz .nao_livre

    ; --- buddy livre: sobe para o pai ---
    mov rax, rdi
    and rax, -2
    mov rdi, rax
    inc rbp                     ; próxima ordem
    cmp rbp, HEAP_MAX_ORDER
    jbe .fundir_loop

.nao_livre:
    pop r8
    pop rdx
    pop rsi
    pop rbp
    pop rbx
    ret

; ==========================================
; RETORNAR ESPAÇO LIVRE
; Saída: rax = bytes livres
; ==========================================
heap_disponivel:
    mov rax, [heap_livre]
    ret
