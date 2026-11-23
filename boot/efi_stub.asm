; ==========================================
; FydelisTech - EFI Stub (BOOTX64.EFI)
; Cabeçalhos PE32+ estritamente compatíveis com UEFI
; ==========================================
BITS 64

%define KERNEL_LBA       4096
%define KERNEL_SIZE      0x8000
%define KERNEL_ADDR      0x8000
%define MAP_BUF          0x70000
%define MAP_SIZE         0x10000

; ---- Offsets EFI (x86_64) ----
%define ST_BootServices      0x58
%define ST_ConOut            0x38
%define BS_GetMemoryMap      0x38
%define BS_ExitBootServices  0xE8
%define BS_LocateHandleBuffer 0x138
%define BS_HandleProtocol    0x98
%define BIO_Media            32
%define BIO_ReadBlocks       48
%define MEDIA_MediaId        0
%define MEDIA_LogicalPartition 6
%define COUT_OutputString    0x20

; ==========================================
; Cabeçalhos PE32+
; ==========================================
PE_START:

; --- DOS Header ---
    db 'MZ'
    times 58 db 0
    dd PE_headers               ; e_lfanew aponta para o cabeçalho PE (offset 0x3C)

; --- PE signature + COFF Header ---
PE_headers:
    db 'PE', 0, 0
    dw 0x8664                   ; Machine: x86_64
    dw 1                        ; NumberOfSections (apenas .text)
    dd 0                        ; TimeDateStamp
    dd 0                        ; PointerToSymbolTable
    dd 0                        ; NumberOfSymbols
    dw opt_hdr_size             ; SizeOfOptionalHeader (geralmente 240 bytes)
    dw 0x0006                   ; Characteristics: EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE

; --- Optional Header (PE32+) ---
opt_start:
    dw 0x020B                   ; Magic: PE32+ (64-bit)
    db 0x02, 0x00               ; Linker Major/Minor version
    dd code_size                ; SizeOfCode
    dd 0                        ; SizeOfInitializedData
    dd 0                        ; SizeOfUninitializedData
    dd entry_rva                ; AddressOfEntryPoint (RVA 0x1000)
    dd 0x1000                   ; BaseOfCode
    dq 0x400000                 ; ImageBase
    dd 0x1000                   ; SectionAlignment (4 KB)
    dd 0x200                    ; FileAlignment (512 bytes)
    dw 0x0000, 0x0000           ; OperatingSystemVersion
    dw 0x0000, 0x0000           ; ImageVersion
    dw 0x0000, 0x0000           ; SubsystemVersion (0.0)
    dd 0                        ; Win32VersionValue
    dd image_size               ; SizeOfImage
    dd 0x200                    ; SizeOfHeaders
    dd 0                        ; Checksum
    dw 0x000A                   ; Subsystem: IMAGE_SUBSYSTEM_EFI_APPLICATION (10)
    dw 0x0000                   ; DllCharacteristics
    dq 0x100000                 ; SizeOfStackReserve
    dq 0x1000                   ; SizeOfStackCommit
    dq 0x100000                 ; SizeOfHeapReserve
    dq 0x1000                   ; SizeOfHeapCommit
    dd 0                        ; LoaderFlags
    dd 16                       ; NumberOfRvaAndSizes
    times 128 db 0              ; DataDirectories (16 diretórios zerados = 128 bytes)
opt_end equ ($ - opt_start)
opt_hdr_size equ opt_end

; --- Section Header: .text ---
    db '.text', 0, 0, 0
    dd 0x1000                   ; VirtualSize
    dd 0x1000                   ; VirtualAddress
    dd code_size                ; SizeOfRawData
    dd 0x200                    ; PointerToRawData
    dd 0                        ; PointerToRelocations
    dd 0                        ; PointerToLinenumbers
    dw 0                        ; NumberOfRelocations
    dw 0                        ; NumberOfLinenumbers
    dd 0x60000020               ; Characteristics: IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ

times (0x200 - ($-$$)) db 0     ; Preenche até o offset 0x200 onde o código binário começa

; ==========================================
; CÓDIGO EFI (RVA 0x1000)
; ==========================================
code_start:

entry:
    ; RCX = ImageHandle, RDX = SystemTable
    mov [rel gImageHandle], rcx
    mov [rel gSystemTable], rdx

    ; ── RASTREIO VISUAL UEFI (Seguindo Windows x64 ABI) ──
    ; 1º Argumento (This): ConOut em RCX
    mov rcx, [rdx + ST_ConOut]
    ; 2º Argumento (String): debug_msg em RDX
    lea rdx, [rel debug_msg]
    
    ; Salva os registradores voláteis e aloca o Shadow Space (32 bytes obrigatórios na UEFI ABI)
    sub rsp, 0x28
    mov rax, [rcx + COUT_OutputString]
    call rax
    add rsp, 0x28

    ; Restaura rbx para os BootServices
    mov rdx, [rel gSystemTable]
    mov rbx, [rdx + ST_BootServices]

    ; Localiza handles com BlockIo: LocateHandleBuffer(ByProtocol, &guid, NULL, &n, &buf)
    mov rcx, 2                    ; ByProtocol (1º arg)
    lea rdx, [rel BlockIoGuid]    ; Guid (2º arg)
    xor r8d, r8d                  ; SearchType = NULL (3º arg)
    lea r9, [rel n_handles]       ; NoHandles (4º arg)
    sub rsp, 0x28                 ; Shadow space
    lea rax, [rel handle_buf]
    mov [rsp+0x20], rax           ; Buffer (5º arg na pilha)
    call [rbx + BS_LocateHandleBuffer]
    add rsp, 0x28
    test eax, eax
    js fail

    ; Loop pelos handles: acha o BlockIo do DISCO INTEIRO (LogicalPartition == 0)
    xor r14d, r14d                ; índice
    
.procura:
    cmp r14d, [rel n_handles]
    jae fail
    lea rax, [rel handle_buf]
    mov rcx, [rax]              ; handles[0] (buffer é um ponteiro para array)
    mov rcx, [rcx + r14*8]
    mov r15, rcx                ; handle atual

    ; HandleProtocol(handle, &guid, &bio)
    mov rcx, r15
    lea rdx, [rel BlockIoGuid]
    lea r8, [rel gBlockIo]
    call [rbx + BS_HandleProtocol]
    test eax, eax
    js .proximo

    mov rax, [rel gBlockIo]
    mov rax, [rax + BIO_Media]  ; Media
    cmp byte [rax + MEDIA_LogicalPartition], 0
    je .achou                   ; é o disco inteiro
.proximo:
    inc r14
    jmp .procura

.achou:
    ; ReadBlocks(This, MediaId, LBA, Size, Buffer)
    mov rcx, [rel gBlockIo]
    mov rax, [rcx + BIO_Media]
    mov edx, [rax + MEDIA_MediaId]
    mov r8, KERNEL_LBA
    mov r9, KERNEL_SIZE
    sub rsp, 0x28
    mov qword [rsp+0x20], KERNEL_ADDR   ; 5º argumento = buffer destino
    mov rax, [rcx + BIO_ReadBlocks]
    call rax
    add rsp, 0x28
    test eax, eax
    js fail

    ; GetMemoryMap(&Size, &Map, &Key, &DescSize, &DescVer)
    mov qword [rel map_size], MAP_SIZE
    lea rcx, [rel map_size]
    mov rdx, MAP_BUF
    lea r8, [rel map_key]
    lea r9, [rel desc_size]
    sub rsp, 0x28
    lea rax, [rel desc_version]
    mov [rsp+0x20], rax
    call [rbx + BS_GetMemoryMap]
    add rsp, 0x28
    test eax, eax
    jnz fail

    ; ExitBootServices(ImageHandle, MapKey)
    mov rcx, [rel gImageHandle]
    mov rdx, [rel map_key]
    call [rbx + BS_ExitBootServices]
    test eax, eax
    jnz fail                    ; se falhar, não podemos mais usar BootServices

    ; Kernel já está em 0x8000, identity-mapped pelo próprio UEFI
    cli
    jmp KERNEL_ADDR

fail:
    ; ConOut->OutputString(ConOut, L"EFI boot fail\n")
    mov rdx, [rel gSystemTable]
    mov rcx, [rdx + ST_ConOut]  ; This
    lea rdx, [rel err_msg]      ; string UCS-2
    call [rcx + COUT_OutputString]
    cli
.hlt:   hlt
    jmp .hlt



; ==========================================
; DADOS & VARIÁVEIS (Seguras em binário plano)
; ==========================================
align 8
BlockIoGuid:
    dd 0x964e5b21
    dw 0x6459, 0x11d2
    db 0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b

debug_msg: dw 'E','F','I',' ','S','t','a','r','t',13,10,0

err_msg:        dw 'E','F','I',' ','f','a','i','l',13,10,0

gImageHandle:   dq 0
gSystemTable:   dq 0
gBlockIo:       dq 0
n_handles:      dd 0
                dd 0
handle_buf:     dq 0
map_size:       dq 0
map_key:        dq 0
desc_size:      dq 0
desc_version:   dd 0
                dd 0

code_end:
code_size   equ (code_end - code_start + 0x1FF) & ~0x1FF
image_size  equ 0x3000
entry_rva   equ 0x1000
