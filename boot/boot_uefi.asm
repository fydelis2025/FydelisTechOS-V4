BITS 64
ORG 0x100000

%define ALIGN_UP(val, align) (((val) + ((align) - 1)) & ~((align) - 1))

BOOTINFO_ADDR       equ 0x5000
KERNEL_LOAD_ADDR    equ 0x8000
KERNEL_START_LBA    equ 4096
KERNEL_READ_BYTES   equ 393216      ; 384 KB (768 setores de 512B)
MMAP_BUF_BYTES      equ 32768

; ============================================================================
; CABECALHO PE32+ (UEFI x86_64 EXECUTABLE)
; ============================================================================
dos_header:
    dw 0x5A4D
    times 58 db 0
    dd pe_header - dos_header

pe_header:
    dd 0x00004550
    dw 0x8664
    dw 2
    dd 0, 0, 0
    dw optional_header_end - optional_header
    dw 0x0206

optional_header:
    dw 0x020B
    db 1, 0
    dd text_end - text_start
    dd data_end - data_start
    dd 0
    dd efi_main - dos_header
    dd text_start - dos_header
    dq 0x100000
    dd 0x1000
    dd 0x200
    dw 0, 0, 0, 0, 0, 0
    dd 0
    dd ALIGN_UP(image_end - dos_header, 0x1000)
    dd ALIGN_UP(headers_end - dos_header, 0x200)
    dd 0
    dw 10
    dw 0
    dq 0x100000, 0x10000
    dq 0x100000, 0x10000
    dd 0
    dd 16
    times 16 dq 0
optional_header_end:

section_table:
    db '.text', 0, 0, 0
    dd ALIGN_UP(text_end - text_start, 0x200)
    dd ALIGN_UP(text_start - dos_header, 0x200)
    dd ALIGN_UP(text_end - text_start, 0x200)
    dd ALIGN_UP(text_start - dos_header, 0x200)
    dd 0, 0
    dw 0, 0
    dd 0x60000020

    db '.data', 0, 0, 0
    dd ALIGN_UP(data_end - data_start, 0x200)
    dd ALIGN_UP(data_start - dos_header, 0x200)
    dd ALIGN_UP(data_end - data_start, 0x200)
    dd ALIGN_UP(data_start - dos_header, 0x200)
    dd 0, 0
    dw 0, 0
    dd 0xC0000040

    align 0x200, db 0
headers_end:

; ============================================================================
; CODIGO UEFI (.text)
; ============================================================================
text_start:
efi_main:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 128

    mov     [rel efi_image_handle], rcx
    mov     [rel efi_system_table], rdx

    mov     rax, [rdx + 64]         ; ConOut
    mov     [rel efi_con_out], rax
    mov     rax, [rdx + 88]         ; RuntimeServices
    mov     [rel efi_runtime_srv], rax
    mov     rax, [rdx + 96]         ; BootServices
    mov     [rel efi_boot_srv], rax

    ; Zera BootInfo em 0x5000 (96 bytes)
    mov     rdi, BOOTINFO_ADDR
    xor     eax, eax
    mov     ecx, 24
.zera_bi:
    mov     [rdi], eax
    add     rdi, 4
    loop    .zera_bi

    mov     rdi, BOOTINFO_ADDR
    mov     dword [rdi + 0], 0x46594442 ; "FYDB"
    mov     dword [rdi + 4], 2          ; BOOT_MODE_UEFI

    lea     rdx, [rel ustr_banner]
    call    uefi_print

    ; 1. SecureBoot & SetupMode
    mov     qword [rel var_data_size], 1
    mov     byte  [rel var_secure_val], 0

    mov     rbx, [rel efi_runtime_srv]
    lea     rcx, [rel ustr_secure_boot]
    lea     rdx, [rel guid_global_var]
    xor     r8, r8
    lea     r9, [rel var_data_size]
    lea     rax, [rel var_secure_val]
    mov     [rsp + 32], rax
    call    [rbx + 72]

    test    rax, rax
    jnz     .sb_off
    cmp     byte [rel var_secure_val], 1
    jne     .sb_off

    mov     rdi, BOOTINFO_ADDR
    mov     dword [rdi + 8], 1
    lea     rdx, [rel ustr_sb_on]
    call    uefi_print
    jmp     .check_setup

.sb_off:
    mov     rdi, BOOTINFO_ADDR
    mov     dword [rdi + 8], 0
    lea     rdx, [rel ustr_sb_off]
    call    uefi_print

.check_setup:
    mov     qword [rel var_data_size], 1
    mov     byte  [rel var_setup_val], 0

    mov     rbx, [rel efi_runtime_srv]
    lea     rcx, [rel ustr_setup_mode]
    lea     rdx, [rel guid_global_var]
    xor     r8, r8
    lea     r9, [rel var_data_size]
    lea     rax, [rel var_setup_val]
    mov     [rsp + 32], rax
    call    [rbx + 72]

    test    rax, rax
    jnz     .etapa_gop
    movzx   eax, byte [rel var_setup_val]
    mov     rdi, BOOTINFO_ADDR
    mov     [rdi + 12], eax

    ; 2. GOP Framebuffer
.etapa_gop:
    mov     rbx, [rel efi_boot_srv]
    lea     rcx, [rel guid_gop]
    xor     rdx, rdx
    lea     r8, [rel gop_proto]
    call    [rbx + 320]
    test    rax, rax
    jnz     .erro_gop

    mov     rsi, [rel gop_proto]
    mov     rsi, [rsi + 24]         ; EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE*
    mov     rdx, [rsi + 8]          ; EFI_GRAPHICS_OUTPUT_MODE_INFORMATION*

    mov     rdi, BOOTINFO_ADDR
    mov     rax, [rsi + 24]         ; FrameBufferBase
    mov     [rdi + 16], rax

    mov     eax, [rdx + 4]          ; HorizontalResolution
    mov     [rdi + 24], eax

    mov     eax, [rdx + 8]          ; VerticalResolution
    mov     [rdi + 28], eax

    mov     eax, [rdx + 36]         ; PixelsPerScanLine
    shl     eax, 2
    mov     [rdi + 32], eax
    mov     dword [rdi + 36], 32

    lea     rdx, [rel ustr_gop_ok]
    call    uefi_print

    ; 3. Ler kernel.bin do LBA 4096 (384 KB -> 0x8000)
    mov     rbx, [rel efi_boot_srv]
    mov     rcx, 2
    lea     rdx, [rel guid_block_io]
    xor     r8, r8
    lea     r9, [rel blk_handle_cnt]
    lea     rax, [rel blk_handle_buf]
    mov     [rsp + 32], rax
    call    [rbx + 312]
    test    rax, rax
    jnz     .erro_disco

    xor     r12, r12

.loop_handles:
    cmp     r12, [rel blk_handle_cnt]
    jae     .erro_disco

    mov     rsi, [rel blk_handle_buf]
    mov     rcx, [rsi + r12 * 8]
    lea     rdx, [rel guid_block_io]
    lea     r8, [rel blk_proto]
    mov     rbx, [rel efi_boot_srv]
    call    [rbx + 152]
    test    rax, rax
    jnz     .prox_handle

    mov     rsi, [rel blk_proto]
    mov     rdx, [rsi + 8]          ; Media
    mov     [rel last_media_ptr], rdx

    cmp     byte [rdx + 8], 1       ; MediaPresent
    jne     .prox_handle

    cmp     byte [rdx + 10], 0      ; LogicalPartition == 0 (disco bruto)
    jne     .prox_handle

    cmp     qword [rdx + 24], KERNEL_START_LBA + 768
    jb      .prox_handle

    mov     rcx, rsi
    mov     edx, [rdx + 0]          ; MediaId
    mov     r8, KERNEL_START_LBA
    mov     r9, KERNEL_READ_BYTES
    mov     qword [rsp + 32], KERNEL_LOAD_ADDR
    call    [rsi + 24]              ; ReadBlocks

    mov     [rel last_read_status], rax
    mov     [rel last_handle_idx], r12

    test    rax, rax
    jz      .kernel_carregado

    lea     rdx, [rel ustr_dbg_h]
    call    uefi_print
    mov     rcx, r12
    call    uefi_print_hex64
    lea     rdx, [rel ustr_dbg_st]
    call    uefi_print
    mov     rcx, [rel last_read_status]
    call    uefi_print_hex64
    lea     rdx, [rel ustr_crlf]
    call    uefi_print

.prox_handle:
    inc     r12
    jmp     .loop_handles

.kernel_carregado:
    lea     rdx, [rel ustr_kern_ok]
    call    uefi_print

    ; 4. GetMemoryMap + ExitBootServices + salto para 0x8000
    mov     qword [rel mmap_size], MMAP_BUF_BYTES
    mov     rbx, [rel efi_boot_srv]
    lea     rcx, [rel mmap_size]
    lea     rdx, [rel mmap_buffer]
    lea     r8, [rel mmap_key]
    lea     r9, [rel mmap_desc_size]
    lea     rax, [rel mmap_desc_ver]
    mov     [rsp + 32], rax
    call    [rbx + 56]

    mov     rdi, BOOTINFO_ADDR
    lea     rax, [rel mmap_buffer]
    mov     [rdi + 48], rax

    mov     rax, [rel mmap_size]
    mov     rdx, [rel mmap_desc_size]
    test    rdx, rdx
    jz      .sem_entries
    xor     edx, edx
    div     qword [rel mmap_desc_size]
    mov     [rdi + 56], eax
.sem_entries:

    mov     rbx, [rel efi_boot_srv]
    mov     rcx, [rel efi_image_handle]
    mov     rdx, [rel mmap_key]
    call    [rbx + 232]
    test    rax, rax
    jz      .entrar_kernel

    mov     qword [rel mmap_size], MMAP_BUF_BYTES
    mov     rbx, [rel efi_boot_srv]
    lea     rcx, [rel mmap_size]
    lea     rdx, [rel mmap_buffer]
    lea     r8, [rel mmap_key]
    lea     r9, [rel mmap_desc_size]
    lea     rax, [rel mmap_desc_ver]
    mov     [rsp + 32], rax
    call    [rbx + 56]

    mov     rbx, [rel efi_boot_srv]
    mov     rcx, [rel efi_image_handle]
    mov     rdx, [rel mmap_key]
    call    [rbx + 232]

.entrar_kernel:
    cli
    mov     rdi, BOOTINFO_ADDR
    mov     rax, KERNEL_LOAD_ADDR
    jmp     rax

.erro_gop:
    lea     rdx, [rel ustr_err_gop]
    call    uefi_print
    jmp     .halt

.erro_disco:
    lea     rdx, [rel ustr_err_disk]
    call    uefi_print

.halt:
    cli
    hlt
    jmp     .halt

uefi_print:
    push    rcx
    sub     rsp, 32
    mov     rcx, [rel efi_con_out]
    call    [rcx + 8]
    add     rsp, 32
    pop     rcx
    ret

uefi_print_hex64:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9

    mov     r8, rcx
    lea     rdx, [rel hex_utf16_buf]
    mov     rcx, 16
    xor     rbx, rbx

.next_nibble:
    mov     rax, r8
    mov     r9, 15
    sub     r9, rbx
    shl     r9, 2
    push    rcx
    mov     cl, r9b
    shr     rax, cl
    pop     rcx
    and     rax, 0x0F

    cmp     al, 10
    jb      .digito_0_9
    add     al, 'A' - 10
    jmp     .gravar_char
.digito_0_9:
    add     al, '0'
.gravar_char:
    mov     word [rdx + rbx * 2], ax
    inc     rbx
    loop    .next_nibble

    mov     word [rdx + 32], 0
    call    uefi_print

    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret

    align 0x200, db 0
text_end:

; ============================================================================
; DADOS UEFI (.data)
; ============================================================================
data_start:
efi_image_handle: dq 0
efi_system_table: dq 0
efi_con_out:      dq 0
efi_runtime_srv:  dq 0
efi_boot_srv:     dq 0

var_data_size:    dq 1
var_secure_val:   db 0
var_setup_val:    db 0

last_read_status: dq 0
last_handle_idx:  dq 0
last_media_ptr:   dq 0

align 8
gop_proto:        dq 0
blk_handle_cnt:   dq 0
blk_handle_buf:   dq 0
blk_proto:        dq 0

mmap_size:        dq MMAP_BUF_BYTES
mmap_key:         dq 0
mmap_desc_size:   dq 0
mmap_desc_ver:    dd 0

align 8
guid_global_var:
    dd 0x8BE4DF61
    dw 0x93CA, 0x11D2
    db 0xAA, 0x0D, 0x00, 0xE0, 0x98, 0x03, 0x2B, 0x8C

guid_gop:
    dd 0x9042A9DE
    dw 0x23DC, 0x4A38
    db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A

guid_block_io:
    dd 0x964E5B21
    dw 0x6459, 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

ustr_secure_boot: dw 'S','e','c','u','r','e','B','o','o','t', 0
ustr_setup_mode:  dw 'S','e','t','u','p','M','o','d','e', 0
ustr_banner:      dw 'F','y','d','e','l','i','s','T','e','c','h',' ','O','S',' ','[','U','E','F','I',' ','x','6','4',']', 13, 10, 0
ustr_sb_on:       dw '[','O','K',']',' ','S','e','c','u','r','e',' ','B','o','o','t',':',' ','H','A','B','I','L','I','T','A','D','O', 13, 10, 0
ustr_sb_off:      dw '[','!',']',' ','S','e','c','u','r','e',' ','B','o','o','t',':',' ','D','E','S','A','B','I','L','I','T','A','D','O', 13, 10, 0
ustr_gop_ok:      dw '[','O','K',']',' ','U','E','F','I',' ','G','O','P',' ','F','r','a','m','e','b','u','f','f','e','r',' ','c','a','p','t','u','r','a','d','o', 13, 10, 0
ustr_kern_ok:     dw '[','O','K',']',' ','K','e','r','n','e','l',' ','c','a','r','r','e','g','a','d','o',' ','d','o',' ','L','B','A',' ','4','0','9','6', 13, 10, 0
ustr_err_gop:     dw '[','E','R','R',']',' ','F','a','l','h','a',' ','a','o',' ','o','b','t','e','r',' ','G','O','P', 13, 10, 0
ustr_err_disk:    dw '[','E','R','R',']',' ','F','a','l','h','a',' ','a','o',' ','l','e','r',' ','L','B','A',' ','4','0','9','6', 13, 10, 0
ustr_dbg_h:       dw '[','D','B','G',']',' ','H','a','n','d','l','e',' ', 0
ustr_dbg_st:      dw ' ','S','T','A','T','U','S','=','0','x', 0
ustr_crlf:        dw 13, 10, 0

hex_utf16_buf:    times 18 dw 0

align 16
mmap_buffer:      times MMAP_BUF_BYTES db 0

    align 0x200, db 0
data_end:
image_end:
