; ==========================================
; PAGING — FydelisTech OS v4.2 (x86_64)
; Mapeamento de Identidade (4 GB) + Recursiva
; Integrado com PMM (Gerenciador de Memoria Fisica)
; Salvador - Bahia
; ==========================================
BITS 64
default rel

PAGE_SIZE       equ 4096
PAGE_2MB        equ 0x200000

FLAG_PRESENT    equ 1 << 0
FLAG_RW         equ 1 << 1
FLAG_USER       equ 1 << 2
FLAG_PWT        equ 1 << 3
FLAG_PCD        equ 1 << 4      ; Cache Disable (obrigatorio para MMIO APIC)
FLAG_PS         equ 1 << 7

extern pmm_alocar
extern pmm_liberar

section .bss
align 4096
global pml4
global pdpt
global pdt0

pml4:   resb PAGE_SIZE
pdpt:   resb PAGE_SIZE
pdt0:   resb PAGE_SIZE          ; 0 GB .. 1 GB
pdt1:   resb PAGE_SIZE          ; 1 GB .. 2 GB
pdt2:   resb PAGE_SIZE          ; 2 GB .. 3 GB
pdt3:   resb PAGE_SIZE          ; 3 GB .. 4 GB (VRAM VESA + Local APIC + I/O APIC)

section .text
global paging_init
global paging_carregar
global paging_ativo
global paging_mapear
global paging_desmapear

paging_init:
    push    rbx
    push    rbp

    ; Limpar todas as 6 tabelas (6 * 512 qwords = 3072 qwords = 24 KB)
    lea     rdi, [rel pml4]
    mov     rcx, 512 * 6
    xor     rax, rax
    rep     stosq

    ; PML4[0] -> PDPT
    lea     rax, [rel pdpt]
    or      rax, FLAG_PRESENT | FLAG_RW
    lea     rbx, [rel pml4]
    mov     qword [rbx], rax

    ; PML4[511] -> Entrada recursiva
    lea     rax, [rel pml4]
    or      rax, FLAG_PRESENT | FLAG_RW
    mov     qword [rbx + 511 * 8], rax

    ; Conectar PDPT[0..3] -> pdt0..pdt3 (cobre 0 GB .. 4 GB)
    lea     rbx, [rel pdpt]

    lea     rax, [rel pdt0]
    or      rax, FLAG_PRESENT | FLAG_RW
    mov     qword [rbx + 0 * 8], rax

    lea     rax, [rel pdt1]
    or      rax, FLAG_PRESENT | FLAG_RW
    mov     qword [rbx + 1 * 8], rax

    lea     rax, [rel pdt2]
    or      rax, FLAG_PRESENT | FLAG_RW
    mov     qword [rbx + 2 * 8], rax

    lea     rax, [rel pdt3]
    or      rax, FLAG_PRESENT | FLAG_RW
    mov     qword [rbx + 3 * 8], rax

    ; Mapear 4 GB (2048 entradas de 2 MB = 16 KB contiguos em pdt0..pdt3)
    lea     rdi, [rel pdt0]
    mov     rcx, 2048
    mov     rax, FLAG_PRESENT | FLAG_RW | FLAG_PS

.map_2mb:
    mov     qword [rdi], rax
    add     rax, PAGE_2MB
    add     rdi, 8
    dec     rcx
    jnz     .map_2mb

    ; Marcar a pagina de 2 MB do APIC (0xFEC00000..0xFEDFFFFF e 0xFEE00000..0xFEFFFFFF)
    ; com Cache Disable (PCD | PWT) para evitar falha de coerencia MMIO
    ; Indice no pdt3: (0xFEC00000 - 0xC0000000) / 0x200000 = 502 e 503
    lea     rdi, [rel pdt3]
    or      qword [rdi + 502 * 8], FLAG_PCD | FLAG_PWT
    or      qword [rdi + 503 * 8], FLAG_PCD | FLAG_PWT

    ; Ativar paginacao x86_64
    lea     rax, [rel pml4]
    mov     cr3, rax

    mov     rax, cr4
    or      rax, 1 << 5             ; PAE
    mov     cr4, rax

    mov     rax, cr0
    or      rax, 1 << 31            ; PG
    mov     cr0, rax

    pop     rbp
    pop     rbx
    ret

paging_carregar:
    mov     cr3, rdi
    ret

; ==========================================
; MAPEAR PAGINA 4 KB — Dinamico (usando PMM)
; Entrada: rdi = endereco virtual
;          rsi = endereco fisico
;          rdx = flags
; ==========================================
paging_mapear:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; Virt
    mov     r13, rsi                ; Phys
    mov     r14, rdx                ; Flags

    ; Flags intermediarias: propaga FLAG_USER somente se solicitado em r14
    mov     r15, FLAG_PRESENT | FLAG_RW
    test    r14, FLAG_USER
    jz      .sem_user
    or      r15, FLAG_USER
.sem_user:

    ; --- 1. PML4 -> PDPT ---
    mov     rax, r12
    shr     rax, 39
    and     rax, 0x1FF              ; indice PML4
    lea     rdx, [rel pml4]
    lea     rcx, [rdx + rax * 8]
    mov     rbx, qword [rcx]
    test    rbx, FLAG_PRESENT
    jnz     .tem_pdpt

    push    rcx
    call    pmm_alocar
    pop     rcx
    test    rax, rax
    jz      .erro
    ; Zera nova tabela alocada
    mov     rdi, rax
    push    rax
    push    rcx
    mov     rcx, 512
    xor     eax, eax
    rep     stosq
    pop     rcx
    pop     rax

    mov     rbx, rax
    or      rbx, r15
    mov     qword [rcx], rbx

.tem_pdpt:
    and     rbx, -4096

    ; --- 2. PDPT -> PDT ---
    mov     rax, r12
    shr     rax, 30
    and     rax, 0x1FF              ; indice PDPT
    lea     rcx, [rbx + rax * 8]
    mov     rbx, qword [rcx]
    test    rbx, FLAG_PRESENT
    jnz     .tem_pdt

    push    rcx
    call    pmm_alocar
    pop     rcx
    test    rax, rax
    jz      .erro
    mov     rdi, rax
    push    rax
    push    rcx
    mov     rcx, 512
    xor     eax, eax
    rep     stosq
    pop     rcx
    pop     rax

    mov     rbx, rax
    or      rbx, r15
    mov     qword [rcx], rbx

.tem_pdt:
    and     rbx, -4096

    ; --- 3. PDT -> PTE ---
    mov     rax, r12
    shr     rax, 21
    and     rax, 0x1FF              ; indice PDT
    lea     rcx, [rbx + rax * 8]
    mov     rbx, qword [rcx]
    test    rbx, FLAG_PRESENT
    jnz     .tem_pte

    push    rcx
    call    pmm_alocar
    pop     rcx
    test    rax, rax
    jz      .erro
    mov     rdi, rax
    push    rax
    push    rcx
    mov     rcx, 512
    xor     eax, eax
    rep     stosq
    pop     rcx
    pop     rax

    mov     rbx, rax
    or      rbx, r15
    mov     qword [rcx], rbx

.tem_pte:
    and     rbx, -4096

    ; --- 4. PTE -> Pagina Fisica ---
    mov     rax, r12
    shr     rax, 12
    and     rax, 0x1FF              ; indice PTE
    lea     rcx, [rbx + rax * 8]

    mov     rax, r13
    and     rax, -4096
    or      rax, r14
    mov     qword [rcx], rax

    invlpg  [r12]

    mov     rax, 1
    jmp     .fim

.erro:
    xor     rax, rax

.fim:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

paging_desmapear:
    invlpg  [rdi]
    ret

paging_ativo:
    mov     rax, cr0
    test    rax, 1 << 31
    jz      .nao
    mov     rax, 1
    ret
.nao:
    xor     rax, rax
    ret
