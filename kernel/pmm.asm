; ==========================================
; 🧠 PMM — Gerenciador de Memória Física
; Bitmap de páginas · 4 KiB por página
; FydelisTech OS v4.2 · Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
DEFAULT REL

; Configuração
PAGE_SIZE           equ 4096                            ; 4 KiB
ENTRADAS_POR_BYTE   equ 8                               ; bits por byte do bitmap
MAX_PAGINAS         equ 262144                          ; 1 GiB = 262.144 páginas de 4K
BITMAP_SIZE         equ MAX_PAGINAS / ENTRADAS_POR_BYTE ; 32 KB
PAGINAS_RESERVADAS  equ 512                             ; Primeiros 2 MiB (0x000000..0x1FFFFF) reservados

section .bss
align 4096
bitmap_base:        resb BITMAP_SIZE                    ; Bitmap principal
paginas_livres:     resd 1                              ; Contador de páginas livres

section .data
align 8
global mem_total
global mem_livre
mem_total:          dq 0
mem_livre:          dq 0

section .text
global pmm_inicializar
global pmm_alocar
global pmm_liberar
global pmm_contar_livres
global pmm_marcar_ocupada

; ==========================================
; ✅ INICIALIZAR — Zera bitmap e reserva área baixa
; ==========================================
pmm_inicializar:
    push    rbx
    push    rcx
    push    rdi

    ; Zera o bitmap → todas as páginas LIVRES inicialmente
    lea     rdi, [rel bitmap_base]
    mov     rcx, BITMAP_SIZE
    xor     eax, eax
    rep     stosb

    mov     dword [rel paginas_livres], MAX_PAGINAS

    ; Reserva os primeiros 2 MiB (0x000000..0x1FFFFF) para BIOS/IVT/BootInfo/PageTables/Kernel
    xor     rbx, rbx
.reservar_loop:
    cmp     rbx, PAGINAS_RESERVADAS
    jae     .atualiza_stats
    mov     rdi, rbx
    shl     rdi, 12
    call    pmm_marcar_ocupada
    inc     rbx
    jmp     .reservar_loop

.atualiza_stats:
    mov     rax, MAX_PAGINAS
    shl     rax, 12
    mov     [rel mem_total], rax

    mov     eax, [rel paginas_livres]
    shl     rax, 12
    mov     [rel mem_livre], rax

    pop     rdi
    pop     rcx
    pop     rbx
    ret

; ==========================================
; AUXILIAR — Marca página física em RDI como OCUPADA
; ==========================================
pmm_marcar_ocupada:
    push    rax
    push    rdx

    mov     rax, rdi
    shr     rax, 12                     ; índice da página
    cmp     rax, MAX_PAGINAS
    jae     .fim_ocupada

    mov     rdx, rax
    and     rdx, 7                      ; bit dentro do byte
    shr     rax, 3                      ; índice do byte

    lea     rcx, [rel bitmap_base]
    add     rax, rcx

    bt      [rax], rdx
    jc      .fim_ocupada                ; já estava ocupada

    bts     [rax], rdx
    dec     dword [rel paginas_livres]

    mov     eax, [rel paginas_livres]
    shl     rax, 12
    mov     [rel mem_livre], rax

.fim_ocupada:
    pop     rdx
    pop     rax
    ret

; ==========================================
; ✅ ALOCAR PÁGINA FÍSICA
; Saída: rax = endereço físico (alinhado a 4K) ou 0 = sem memória
; ==========================================
pmm_alocar:
    push    rcx
    push    rdx
    push    rdi
    push    r8

    mov     rcx, BITMAP_SIZE
    lea     rdi, [rel bitmap_base]
    mov     r8, rdi

.procurar_byte:
    test    rcx, rcx
    jz      .sem_memoria

    cmp     byte [rdi], 0xFF
    jne     .encontrado

    inc     rdi
    dec     rcx
    jmp     .procurar_byte

.encontrado:
    movzx   rax, byte [rdi]
    not     rax                         ; 1 = livre
    bsf     rdx, rax                    ; rdx = primeiro bit livre (0..7)

    bts     [rdi], rdx                  ; marca como ocupado

    ; índice da página = ((rdi - bitmap_base) * 8) + rdx
    mov     rax, rdi
    sub     rax, r8
    shl     rax, 3
    add     rax, rdx

    ; endereço físico = índice * 4096
    shl     rax, 12

    dec     dword [rel paginas_livres]
    push    rax
    mov     eax, [rel paginas_livres]
    shl     rax, 12
    mov     [rel mem_livre], rax
    pop     rax

    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    ret

.sem_memoria:
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    xor     rax, rax
    ret

; ==========================================
; ✅ LIBERAR PÁGINA
; Entrada: rdi = endereço físico da página
; ==========================================
pmm_liberar:
    push    rax
    push    rcx
    push    rdx

    test    rdi, rdi
    jz      .fim_invalido

    mov     rax, rdi
    test    rax, PAGE_SIZE - 1
    jnz     .fim_invalido

    shr     rax, 12                     ; índice da página
    cmp     rax, PAGINAS_RESERVADAS
    jb      .fim_invalido               ; protege área reservada inicial

    cmp     rax, MAX_PAGINAS
    jae     .fim_invalido

    mov     rdx, rax
    and     rdx, 7
    shr     rax, 3

    lea     rcx, [rel bitmap_base]
    add     rax, rcx

    btr     [rax], rdx
    jnc     .fim_invalido               ; já estava livre

    inc     dword [rel paginas_livres]
    mov     eax, [rel paginas_livres]
    shl     rax, 12
    mov     [rel mem_livre], rax

.fim_invalido:
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ==========================================
; ✅ RETORNAR QUANTIDADE DE PÁGINAS LIVRES
; Saída: eax = número de páginas livres
; ==========================================
pmm_contar_livres:
    mov     eax, [rel paginas_livres]
    ret
