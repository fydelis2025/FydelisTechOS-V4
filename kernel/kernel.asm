; ============================================================================
; Kernel FydelisTech OS - v4.2 COMPLETO (DUAL BOOT LEGACY/UEFI + SECURE BOOT)
; Transicao 16/32/64-bit + VESA/GOP + BSS Zero + GDT/IDT + SYSCALL MSRs + Rede
; Salvador - Bahia
; ============================================================================
DEFAULT REL
%include "fydelterm.inc"

extern __bss_start
extern __bss_end
extern gdt_init
extern idt_init
extern kernel_exec_bin
extern construir_estrutura_sistema
extern pmm_inicializar
extern mem_detect_e820
extern mem_total, mem_livre
extern fb_base, fb_largura, fb_altura, fb_pitch, fb_bpp
extern fb_inicializar
extern gpu_preencher_tela
extern gpu_preencher_retangulo
extern get_key
extern reset_buffer
extern set_input_base
extern add_char
extern parse_line
extern interpret_command

extern syscall_handler

extern detectar_disco
extern identificar_disco
extern disco_ler_setor
extern disco_escrever_setor
extern obter_tamanho_disco

extern audio_init
extern bt_detectar_placa
extern bt_inicializar
extern inicializar_nic_mmio
extern net_inicializar

extern e1000_pci_inicializar

extern hosts_inicializar
extern fydlog_inicializar

extern cve_guard_iniciar
extern cve_guard_adicionar_regra
extern cve_guard_inspecionar_comando

global bytes_para_gb
global _entry16
global _entry64_uefi
global start
global boot_modo_atual
global boot_secure_ativo

; ============================================================================
; CONSTANTES (Tabelas fora da faixa do kernel 0x8000..0x68020)
; ============================================================================
BOOTINFO_ADDR        equ 0x5000
BOOTINFO_MAGIC       equ 0x46594442     ; "FYDB"
BOOT_MODE_LEGACY     equ 1
BOOT_MODE_UEFI       equ 2

VBE_INFO_BUF         equ 0x6000         ; Buffer temporario VBE2
VBE_MODE_BUF         equ 0x6200

; Tabelas de pagina de apoio em 0x200000 (2 MB) para nao colidir com .text/.bss (0x8000..0x68020)
PT_PML4_BASE         equ 0x200000
PT_PDPT_BASE         equ 0x201000
PT_PD0_BASE          equ 0x202000       ; 0..1 GB
PT_PD1_BASE          equ 0x203000       ; 1..2 GB
PT_PD2_BASE          equ 0x204000       ; 2..3 GB
PT_PD3_BASE          equ 0x205000       ; 3..4 GB
FB_PD_POOL_BASE      equ 0x206000       ; 4 tabelas PD x 4 KB (0x206000..0x209FFF)
FB_PD_POOL_STRIDE    equ 0x1000

KERNEL_STACK_TOP     equ 0x90000
GB_MULT              equ 1073741824     ; Bytes -> GB

; MSRs de SYSCALL em x86_64 Long Mode
MSR_EFER             equ 0xC0000080
MSR_STAR             equ 0xC0000081
MSR_LSTAR            equ 0xC0000082
MSR_FMASK            equ 0xC0000084

STAR_EDX_VAL         equ 0x00100008
FMASK_IF_BIT         equ 0x00000200

; Portas PS/2 legadas para destravar/drenar fila caso necessario
PS2_DATA_PORT        equ 0x60
PS2_STATUS_PORT      equ 0x64
PS2_OBF_MASK         equ 0x01
PS2_POLL_LIMIT       equ 64

; PALETA
COR_FUNDO            equ 0xFF090611
COR_ROXO_ESCURO      equ 0xFF2A1050
COR_ROXO_NEON        equ 0xFF9D4EDD
COR_CIANO_NEON       equ 0xFF00FFFF
COR_CINZA_VIDRO      equ 0xFF3A2060
COR_TEXTO            equ 0xFFF0E6FF

; ============================================================================
; VETOR DE ENTRADA DUAL NO TOPO DE .text._start (FIXADO EM 0x8000)
;   - 0x8000 (_entry16):      Entrada 16-bit Real Mode (MBR Legacy BIOS)
;   - 0x8010 (_entry64_uefi): Entrada 64-bit Long Mode (BOOTX64.EFI UEFI)
; ============================================================================
section .text._start
BITS 16
_entry16:
    jmp     short _legacy_16_start
    nop

times 16 - ($ - _entry16) db 0x90

BITS 64
_entry64_uefi:
    cli
    cld
    lgdt    [rel gdt64_boot_desc]
    push    0x18
    lea     rax, [rel .reload_cs64]
    push    rax
    retfq

.reload_cs64:
    mov     ax, 0x10
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax
    mov     rsp, KERNEL_STACK_TOP

    call    configurar_paginacao_64
    call    configurar_syscall_64

    mov     rbx, BOOTINFO_ADDR
    mov     rax, [rbx + 16]         ; BootInfo.fb_addr
    test    rax, rax
    jz      .ir_para_start
    mov     rdi, rax
    call    mapear_fb_regiao_64

.ir_para_start:
    jmp     start

; ============================================================================
; TRANSICAO LEGACY BIOS (16 -> 32 -> 64-BIT)
; ============================================================================
BITS 16
_legacy_16_start:
    cli
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7C00

    ; Garante estrutura BootInfo em 0x5000 para modo Legacy BIOS
    mov     di, BOOTINFO_ADDR
    mov     word [di + 0], 0x4442   ; "DB"
    mov     word [di + 2], 0x4659   ; "FY" -> "FYDB"
    mov     word [di + 4], BOOT_MODE_LEGACY
    mov     word [di + 6], 0
    mov     word [di + 8], 0        ; secure_boot = 0
    mov     word [di + 10], 0
    mov     word [di + 12], 0
    mov     word [di + 14], 0
    mov     dword [di + 16], 0      ; fb_addr = 0
    mov     dword [di + 20], 0

    ; 1. Detectar VESA (VBE2) usando buffer em 0x6000
    mov     dword [VBE_INFO_BUF], '2EBV'
    mov     di, VBE_INFO_BUF
    mov     ax, 0x4F00
    int     0x10
    cmp     ax, 0x004F
    jne     .sem_vesa

    ; 2. Tenta modo 0x145; se falhar, usa 0x118 (1024x768 32bpp)
    mov     bx, 0x0145
    mov     cx, bx
    mov     di, VBE_MODE_BUF
    mov     ax, 0x4F01
    int     0x10
    cmp     ax, 0x004F
    je      .vesa_ok

    mov     bx, 0x0118
    mov     cx, bx
    mov     di, VBE_MODE_BUF
    mov     ax, 0x4F01
    int     0x10
    cmp     ax, 0x004F
    jne     .sem_vesa

.vesa_ok:
    mov     si, BOOTINFO_ADDR
    mov     eax, [es:di + 0x28]     ; Endereco fisico do LFB
    mov     [si + 16], eax
    mov     dword [si + 20], 0

    movzx   eax, word [es:di + 0x12]
    mov     [si + 24], eax

    movzx   eax, word [es:di + 0x14]
    mov     [si + 28], eax

    movzx   eax, word [es:di + 0x10]
    mov     [si + 32], eax

    movzx   eax, byte [es:di + 0x19]
    mov     [si + 36], eax

    or      bx, 0x4000
    mov     ax, 0x4F02
    int     0x10

.sem_vesa:
    ; 3. Habilitar A20 e entrar em Modo Protegido (32-bit)
    in      al, 0x92
    or      al, 2
    out     0x92, al

    lgdt    [gdt_boot_desc]
    mov     eax, cr0
    or      eax, 1
    mov     cr0, eax
    jmp     0x08:_entry32

BITS 32
_entry32:
    mov     ax, 0x10
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax
    mov     esp, KERNEL_STACK_TOP

    ; 4. Configura Paginacao Identity Map de 4 GB em 0x200000..0x205FFF
    mov     edi, PT_PML4_BASE
    xor     eax, eax
    mov     ecx, 6144               ; 24 KB (6 paginas de 4 KB) / 4 bytes = 6144 dwords
    rep     stosd

    mov     dword [PT_PML4_BASE + 0],  PT_PDPT_BASE + 3
    mov     dword [PT_PDPT_BASE + 0],  PT_PD0_BASE  + 3
    mov     dword [PT_PDPT_BASE + 8],  PT_PD1_BASE  + 3
    mov     dword [PT_PDPT_BASE + 16], PT_PD2_BASE  + 3
    mov     dword [PT_PDPT_BASE + 24], PT_PD3_BASE  + 3

    mov     edi, PT_PD0_BASE
    mov     eax, 0x00000083         ; Present + RW + 2MB
    mov     ecx, 1024               ; 0..2 GB (PD0 + PD1 sao contiguos)
.map_2gb_lo:
    mov     [edi], eax
    add     eax, 0x00200000
    add     edi, 8
    dec     ecx
    jnz     .map_2gb_lo

    mov     edi, PT_PD2_BASE
    mov     ecx, 512                ; 2..3 GB
.map_gb2:
    mov     [edi], eax
    add     eax, 0x00200000
    add     edi, 8
    dec     ecx
    jnz     .map_gb2

    mov     edi, PT_PD3_BASE
    mov     ecx, 512                ; 3..4 GB (cobre 0xFD000000)
.map_gb3:
    mov     [edi], eax
    add     eax, 0x00200000
    add     edi, 8
    dec     ecx
    jnz     .map_gb3

    mov     eax, PT_PML4_BASE
    mov     cr3, eax

    mov     eax, cr4
    or      eax, 1 << 5             ; PAE
    mov     cr4, eax

    mov     ecx, MSR_EFER
    rdmsr
    or      eax, 1 << 8             ; LME
    or      eax, 1 << 0             ; SCE (System Call Extensions)
    wrmsr

    mov     eax, cr0
    or      eax, 1 << 31            ; PG
    mov     cr0, eax

    lgdt    [dword gdt64_boot_desc]
    jmp     dword 0x18:start

; ============================================================================
; AUXILIARES DE PAGINACAO, SYSCALL E PS/2 64-BIT (LEGACY E UEFI)
; ============================================================================
BITS 64
configurar_paginacao_64:
    mov     rdi, PT_PML4_BASE
    xor     eax, eax
    mov     rcx, 3072               ; 24 KB / 8 bytes = 3072 qwords
    rep     stosq

    mov     qword [PT_PML4_BASE + 0],  PT_PDPT_BASE + 3
    mov     qword [PT_PDPT_BASE + 0],  PT_PD0_BASE  + 3
    mov     qword [PT_PDPT_BASE + 8],  PT_PD1_BASE  + 3
    mov     qword [PT_PDPT_BASE + 16], PT_PD2_BASE  + 3
    mov     qword [PT_PDPT_BASE + 24], PT_PD3_BASE  + 3

    mov     rdi, PT_PD0_BASE
    mov     rax, 0x00000083
    mov     rcx, 1024
.u_lo:
    mov     [rdi], rax
    add     rax, 0x00200000
    add     rdi, 8
    dec     rcx
    jnz     .u_lo

    mov     rdi, PT_PD2_BASE
    mov     rcx, 512
.u_gb2:
    mov     [rdi], rax
    add     rax, 0x00200000
    add     rdi, 8
    dec     rcx
    jnz     .u_gb2

    mov     rdi, PT_PD3_BASE
    mov     rcx, 512
.u_gb3:
    mov     [rdi], rax
    add     rax, 0x00200000
    add     rdi, 8
    dec     rcx
    jnz     .u_gb3

    mov     rax, PT_PML4_BASE
    mov     cr3, rax
    ret

configurar_syscall_64:
    push    rax
    push    rcx
    push    rdx

    mov     ecx, MSR_EFER
    rdmsr
    or      eax, (1 << 0) | (1 << 8)
    wrmsr

    mov     ecx, MSR_STAR
    xor     eax, eax
    mov     edx, STAR_EDX_VAL
    wrmsr

    lea     rax, [rel syscall_handler]
    mov     rdx, rax
    shr     rdx, 32
    mov     ecx, MSR_LSTAR
    wrmsr

    mov     ecx, MSR_FMASK
    mov     eax, FMASK_IF_BIT
    xor     edx, edx
    wrmsr

    pop     rdx
    pop     rcx
    pop     rax
    ret

; Drena bytes residuais do buffer de saida PS/2 sem travar se vazio
drenar_ps2_residua:
    push    rax
    push    rcx
    mov     ecx, PS2_POLL_LIMIT
.drain_loop:
    in      al, PS2_STATUS_PORT
    test    al, PS2_OBF_MASK
    jz      .drain_done
    in      al, PS2_DATA_PORT
    dec     ecx
    jnz     .drain_loop
.drain_done:
    pop     rcx
    pop     rax
    ret

; Garante que a regiao do framebuffer em RDI (64 MB = 32 paginas de 2 MB)
; esteja identity-mapped na tabela de paginas atual (CR3) com RW + Present + 2MB.
mapear_fb_regiao_64:
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    r8
    push    r9

    test    rdi, rdi
    jz      .fim_map_fb

    mov     rax, rdi
    and     rax, ~0x1FFFFF          ; Base alinhada em 2 MB

    mov     qword [PT_PML4_BASE + 0], PT_PDPT_BASE + 3

    mov     rcx, 32                 ; Mapeia 64 MB (32 x 2 MB)
.loop_2mb:
    mov     r8, rax
    shr     r8, 30
    and     r8, 0x1FF               ; Indice PDPT (0..511)

    mov     r9, [PT_PDPT_BASE + r8 * 8]
    test    r9, 1
    jnz     .pd_pronta

    mov     rbx, r8
    and     rbx, 3
    imul    rbx, FB_PD_POOL_STRIDE
    add     rbx, FB_PD_POOL_BASE

    push    rax
    push    rcx
    push    rdi
    mov     rdi, rbx
    xor     eax, eax
    mov     rcx, 512
    rep     stosq
    pop     rdi
    pop     rcx
    pop     rax

    lea     r9, [rbx + 3]           ; Present + RW
    mov     [PT_PDPT_BASE + r8 * 8], r9
    jmp     .preenche_pd

.pd_pronta:
    mov     rbx, r9
    and     rbx, ~0xFFF

.preenche_pd:
    mov     r9, rax
    shr     r9, 21
    and     r9, 0x1FF               ; Indice PD (0..511)

    mov     rdx, rax
    or      rdx, 0x00000083         ; Present + RW + Page Size (2MB)
    mov     [rbx + r9 * 8], rdx

    add     rax, 0x00200000
    dec     rcx
    jnz     .loop_2mb

    mov     rax, cr3
    mov     cr3, rax

.fim_map_fb:
    pop     r9
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

align 8
gdt_boot_start:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF           ; 0x08: Codigo 32-bit
    dq 0x00CF92000000FFFF           ; 0x10: Dados 32-bit
    dq 0x00AF9A000000FFFF           ; 0x18: Codigo 64-bit
gdt_boot_end:

gdt_boot_desc:
    dw gdt_boot_end - gdt_boot_start - 1
    dd gdt_boot_start

gdt64_boot_desc:
    dw gdt_boot_end - gdt_boot_start - 1
    dq gdt_boot_start

; ============================================================================
; ENTRADA PRINCIPAL UNIFICADA DO KERNEL (64-BIT)
; ============================================================================
BITS 64
start:
    cli
    cld
    mov     ax, 0x10
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax
    mov     rsp, KERNEL_STACK_TOP

    ; 0a. Zera toda a secao .bss (__bss_start ate __bss_end)
    lea     rdi, [rel __bss_start]
    lea     rcx, [rel __bss_end]
    sub     rcx, rdi
    jbe     .bss_limpo
    xor     eax, eax
    rep     stosb
.bss_limpo:

    ; 0b. Instala GDT definitiva e IDT 64-bit
    call    gdt_init
    call    idt_init

    ; Configura MSRs de SYSCALL apos GDT/IDT
    call    configurar_syscall_64

    mov     rax, cr3
    cmp     rax, PT_PML4_BASE
    je      .cr3_ok
    call    configurar_paginacao_64
.cr3_ok:

    ; 0c. Silencia IRQs do PIC 8259A legado e drena lixo residual do PS/2
    mov     al, 0xFF
    out     0x21, al
    out     0xA1, al
    call    drenar_ps2_residua

    ; 0d. Sincroniza BootInfo (0x5000)
    mov     rbx, BOOTINFO_ADDR
    cmp     dword [rbx + 0], BOOTINFO_MAGIC
    jne     .bootinfo_fallback

    mov     eax, [rbx + 4]
    mov     [rel boot_modo_atual], eax
    mov     eax, [rbx + 8]
    mov     [rel boot_secure_ativo], eax

    mov     rax, [rbx + 16]
    mov     [rel fb_base], rax
    mov     eax, [rbx + 24]
    mov     [rel fb_largura], eax
    mov     eax, [rbx + 28]
    mov     [rel fb_altura], eax
    mov     eax, [rbx + 32]
    mov     [rel fb_pitch], eax
    mov     eax, [rbx + 36]
    mov     [rel fb_bpp], eax
    jmp     .init_video

.bootinfo_fallback:
    mov     dword [rel boot_modo_atual], BOOT_MODE_LEGACY
    mov     dword [rel boot_secure_ativo], 0

.init_video:
    mov     rdi, [rel fb_base]
    test    rdi, rdi
    jz      .pula_fb

    call    mapear_fb_regiao_64
    call    fb_inicializar

    mov     rdi, [rel fb_base]
    test    rdi, rdi
    jz      .pula_fb
    call    mapear_fb_regiao_64

    mov     rdi, COR_FUNDO
    call    gpu_preencher_tela
.pula_fb:

    ; [CHECKPOINT 1 - Faixa Azul]
    mov     rdi, 10
    mov     rsi, 10
    mov     rdx, 120
    mov     rcx, 20
    mov     r8d, 0xFF0066FF
    call    gpu_preencher_retangulo

    lea     rsi, [rel msg_cabecalho]
    call    print_string

    lea     rsi, [rel msg_fw_label]
    call    print_string
    cmp     dword [rel boot_modo_atual], BOOT_MODE_UEFI
    je      .print_uefi
    lea     rsi, [rel msg_fw_legacy]
    call    print_string
    jmp     .print_sb_status

.print_uefi:
    lea     rsi, [rel msg_fw_uefi]
    call    print_string

.print_sb_status:
    cmp     dword [rel boot_secure_ativo], 1
    je      .print_sb_on
    lea     rsi, [rel msg_sb_off]
    call    print_string
    jmp     .fase_cpu

.print_sb_on:
    lea     rsi, [rel msg_sb_on]
    call    print_string

    ; ========================================================================
    ; FASE 1 - CPU
    ; ========================================================================
.fase_cpu:
    lea     rsi, [rel msg_fase_cpu]
    call    print_string
    call    cpu_verificar
    cmp     rax, 1
    jne     .cpu_erro

    lea     rsi, [rel msg_cpu_info]
    call    print_string
    lea     rsi, [rel cpu_vendor]
    call    print_string
    call    print_newline

    ; [CHECKPOINT 2 - Faixa Verde]
    mov     rdi, 140
    mov     rsi, 10
    mov     rdx, 250
    mov     rcx, 20
    mov     r8d, 0xFF00CC66
    call    gpu_preencher_retangulo

    ; ========================================================================
    ; FASE 2 - MEMORIA REAL
    ; ========================================================================
.fase_mem:
    lea     rsi, [rel msg_fase_mem]
    call    print_string
    call    pmm_inicializar
    call    mem_detect_e820

    mov     rax, [rel mem_total]
    mov     [rel mem_total_bytes], rax
    lea     rsi, [rel msg_mem_total]
    call    print_string
    mov     rdi, rax
    call    bytes_para_gb
    call    print_num
    lea     rsi, [rel msg_gb_sufixo]
    call    print_string

    mov     rax, [rel mem_livre]
    mov     [rel mem_livre_bytes], rax
    lea     rsi, [rel msg_mem_livre]
    call    print_string
    mov     rdi, rax
    call    bytes_para_gb
    call    print_num
    lea     rsi, [rel msg_gb_sufixo]
    call    print_string

    ; [CHECKPOINT 3 - Faixa Amarela]
    mov     rdi, 270
    mov     rsi, 10
    mov     rdx, 380
    mov     rcx, 20
    mov     r8d, 0xFFFFCC00
    call    gpu_preencher_retangulo

    ; ========================================================================
    ; FASE 3 - DISCO REAL
    ; ========================================================================
    lea     rsi, [rel msg_fase_disco]
    call    print_string

    xor     rdi, rdi
    call    detectar_disco
    cmp     rax, 1
    jne     .sem_disco

    xor     rdi, rdi
    lea     rsi, [rel info_disco]
    call    identificar_disco

    call    obter_tamanho_disco
    mov     rdi, rax
    call    bytes_para_gb
    mov     [rel disco_tam_gb], eax

    lea     rsi, [rel msg_disco_tam]
    call    print_string
    mov     rdi, rax
    call    print_num
    lea     rsi, [rel msg_gb_sufixo]
    call    print_string

    jmp     .montar_estrutura

.sem_disco:
    lea     rsi, [rel msg_sem_disco]
    call    print_string

.montar_estrutura:
    ; ========================================================================
    ; FASE 4 - ESTRUTURA DE DIRETORIOS (/fyd) & SEGURANCA
    ; ========================================================================
    call    construir_estrutura_sistema
    call    hosts_inicializar
    call    fydlog_inicializar

    push    rbp
    mov     rbp, rsp
    and     rsp, -16

    call    cve_guard_iniciar

    lea     rdi, [rel cve_id_1]
    lea     rsi, [rel cve_pad_1]
    lea     rdx, [rel cve_msg_1]
    call    cve_guard_adicionar_regra

    lea     rdi, [rel cve_id_2]
    lea     rsi, [rel cve_pad_2]
    lea     rdx, [rel cve_msg_2]
    call    cve_guard_adicionar_regra

    lea     rdi, [rel cve_id_3]
    lea     rsi, [rel cve_pad_3]
    lea     rdx, [rel cve_msg_3]
    call    cve_guard_adicionar_regra

    lea     rdi, [rel cve_id_4]
    lea     rsi, [rel cve_pad_4]
    lea     rdx, [rel cve_msg_4]
    call    cve_guard_adicionar_regra

    mov     rsp, rbp
    pop     rbp

    ; ========================================================================
    ; FASE 5 - PERIFERICOS & REDE REAL (AUDIO, BLUETOOTH, E1000 PCI)
    ; ========================================================================
    lea     rsi, [rel msg_fase_hw]
    call    print_string

    push    rbp
    mov     rbp, rsp
    and     rsp, -16

    call    audio_init

    call    bt_detectar_placa
    test    rax, rax
    jz      .sem_bt
    call    bt_inicializar
.sem_bt:

    call    inicializar_nic_mmio
    call    e1000_pci_inicializar
    call    net_inicializar

    mov     rsp, rbp
    pop     rbp

    call    drenar_ps2_residua

    lea     rsi, [rel msg_hw_ok]
    call    print_string

.menu:
    ; ========================================================================
    ; MENU PRINCIPAL
    ; ========================================================================
    lea     rsi, [rel msg_opcoes]
    call    print_string

.escolha:
    call    get_key
    cmp     al, '1'
    je      .modo_terminal
    cmp     al, '2'
    je      .modo_grafico
    pause
    jmp     .escolha

.cpu_erro:
    lea     rsi, [rel msg_cpu_erro]
    call    print_string
    cli
    hlt

; ============================================================================
; MODO GRAFICO
; ============================================================================
.modo_grafico:
    call    clear_screen
    mov     rdi, COR_FUNDO
    call    gpu_preencher_tela

    push    rbp
    mov     rbp, rsp
    and     rsp, -16

    call    kernel_exec_bin

    mov     rsp, rbp
    pop     rbp

    call    clear_screen
    lea     rsi, [rel msg_encerrado]
    call    print_string
    call    print_newline
    jmp     .modo_terminal

; ============================================================================
; MODO TERMINAL
; ============================================================================
.modo_terminal:
    call    clear_screen
    mov     rdi, COR_FUNDO
    call    gpu_preencher_tela
    lea     rsi, [rel msg_cabecalho]
    call    print_string

main_loop:
    call    reset_buffer
    lea     rsi, [rel msg_prompt]
    call    print_string
    call    set_input_base
.le_tecla:
    call    get_key
    cmp     al, KEY_NULL
    jne     .processa_tecla
    pause
    jmp     .le_tecla
.processa_tecla:
    cmp     al, KEY_ENTER
    je      .executa
    cmp     al, KEY_BACKSPACE
    je      .trata_bs
    cmp     al, 0x20
    jb      .le_tecla
    cmp     al, 0x7E
    ja      .le_tecla
    push    rax
    call    add_char
    pop     rax
    call    print_char
    jmp     .le_tecla
.trata_bs:
    cmp     dword [rel buf_head], 0
    je      .le_tecla
    mov     al, KEY_BACKSPACE
    call    print_char
    mov     al, ' '
    call    print_char
    call    print_char
    dec     dword [rel buf_head]
    mov     eax, [rel buf_head]
    lea     rcx, [rel buffer]
    mov     byte [rcx + rax], 0
    jmp     .le_tecla
.executa:
    call    print_newline
    mov     eax, [rel buf_head]
    lea     rcx, [rel buffer]
    mov     byte [rcx + rax], 0
    cmp     dword [rel buf_head], 0
    je      main_loop

    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    lea     rdi, [rel buffer]
    call    cve_guard_inspecionar_comando
    mov     rsp, rbp
    pop     rbp

    cmp     rax, 1
    je      .comando_bloqueado

    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    call    parse_line
    call    interpret_command
    mov     rsp, rbp
    pop     rbp
    jmp     main_loop

.comando_bloqueado:
    lea     rsi, [rel msg_cve_bloqueado]
    call    print_string
    jmp     main_loop

; ============================================================================
; CONVERSAO DE UNIDADES & CPU
; ============================================================================
section .text
bytes_para_gb:
    mov     rax, rdi
    mov     rcx, GB_MULT
    xor     rdx, rdx
    div     rcx
    ret

print_num:
    push    rbx
    push    rcx
    push    rdx
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    and     rsp, -16

    mov     rax, rdi
    mov     rcx, 10
    lea     rbx, [rsp + 31]
    mov     byte [rbx], 0
    dec     rbx

.converte:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    mov     [rbx], dl
    dec     rbx
    test    rax, rax
    jnz     .converte

    inc     rbx
    mov     rsi, rbx
    call    print_string

    mov     rsp, rbp
    pop     rbp
    pop     rdx
    pop     rcx
    pop     rbx
    ret

cpu_verificar:
    push    rbx
    pushfq
    pushfq
    xor     qword [rsp], 1 << 21
    popfq
    pushfq
    pop     rax
    xor     rax, [rsp]
    jz      .sem_cpuid
    popfq

    xor     rax, rax
    cpuid
    cmp     rax, 1
    jb      .erro

    xor     rax, rax
    cpuid
    mov     [rel cpu_vendor], ebx
    mov     [rel cpu_vendor + 4], edx
    mov     [rel cpu_vendor + 8], ecx
    mov     byte [rel cpu_vendor + 12], 0

    mov     rax, 1
    cpuid
    pop     rbx
    mov     rax, 1
    ret

.sem_cpuid:
    popfq
.erro:
    popfq
    pop     rbx
    xor     rax, rax
    ret

; ============================================================================
; MENSAGENS (.rodata)
; ============================================================================
section .rodata
msg_cabecalho:     db '+------------------------------------------------------------+',10
                   db '|          FYDELISTECH OS - Sistema Operacional do Zero      |',10
                   db '|                    v4.2 - Salvador - Bahia                 |',10
                   db '+------------------------------------------------------------+',10,10,0

msg_fw_label:      db '  [FW] Firmware: ', 0
msg_fw_legacy:     db 'Legacy BIOS (MBR)', 0
msg_fw_uefi:       db 'UEFI 64-bit (GPT)', 0
msg_sb_on:         db ' | Secure Boot: HABILITADO', 10, 0
msg_sb_off:        db ' | Secure Boot: DESABILITADO', 10, 0

msg_fase_cpu:      db '  [*] Verificando processador...',0
msg_fase_mem:      db '  [*] Inicializando memoria...',0
msg_fase_disco:    db '  [*] Detectando armazenamento...',0
msg_fase_hw:       db '  [*] Inicializando Audio, Bluetooth e Rede E1000...',0
msg_hw_ok:         db ' OK',10,0

msg_cpu_info:      db '  [OK] Processador: ',0
msg_mem_total:     db '  [OK] Memoria Total: ',0
msg_mem_livre:     db '  [OK] Memoria Livre: ',0
msg_disco_tam:     db '  [OK] Tamanho Total: ',0
msg_gb_sufixo:     db ' GB',10,0

msg_opcoes:        db 10,'  Escolha:',10
                   db '    [1] Terminal FydelTerm',10
                   db '    [2] Area de Trabalho Grafica',10,10,'  -> ',0
msg_prompt:        db 'fydelterm> ',0
msg_sem_disco:     db '  [!] Disco nao detectado',10,0
msg_cpu_erro:      db '  [X] CPU incompativel',10,0
msg_encerrado:     db 'Sessao grafica encerrada.',10,0

msg_cve_bloqueado: db '  [CVE-GUARD] Execucao bloqueada: assinatura maliciosa detectada!',10,0

cve_id_1:          db 'CVE-2024-3094',0
cve_pad_1:         db '*xz-backdoor*',0
cve_msg_1:         db 'Payload backdoor XZ comprometido',0

cve_id_2:          db 'CVE-2021-44228',0
cve_pad_2:         db '*jndi:ldap*',0
cve_msg_2:         db 'Tentativa de exploracao Log4Shell',0

cve_id_3:          db 'FYD-MEM-001',0
cve_pad_3:         db '*0x90909090*',0
cve_msg_3:         db 'Deteccao de NOP sled em memoria',0

cve_id_4:          db 'FYD-SYS-002',0
cve_pad_4:         db '*rm -rf /*',0
cve_msg_4:         db 'Comando destrutivo bloqueado',0

; ============================================================================
; DADOS (.bss)
; ============================================================================
section .bss
align 4
boot_modo_atual:   resd 1
boot_secure_ativo: resd 1
cpu_vendor:        resb 16
mem_total_bytes:   resq 1
mem_livre_bytes:   resq 1
disco_tam_gb:      resd 1

align 16
info_disco:        resw 256
