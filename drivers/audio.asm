; ======================================
; FydelisTech OS - Driver de Audio Nativo (AC97 & Intel HDA)
; De Salvador - Bahia
; Fala direto com o hardware via PCI (sem int 0x10)
; ======================================
BITS 64
%include "../include/fydelterm.inc"

extern print_string, print_newline, print_char
extern argc, argv

; --- Registros AC97 (I/O Port BAR0 / BAR1) ---
AC97_RESET          equ 0x00
AC97_MASTER_VOL     equ 0x02
AC97_PCM_OUT_VOL    equ 0x18
AC97_POWERDOWN      equ 0x26

; --- Registros Intel HDA (MMIO BAR0) ---
HDA_GCTL            equ 0x08
HDA_CORBCTL         equ 0x4C
HDA_RIRBCTL         equ 0x5C

AUDIO_VOLUME_MAX    equ 31
AUDIO_VOLUME_DEF    equ 20

section .data
align 16
msg_audio_ok:   db 'Controlador de audio: ', 0
msg_audio_no:   db 'Controlador de audio nao detectado', 0
msg_vol_ok:     db 'Volume definido: ', 0
msg_mute_on:    db 'Audio: MUDO', 0
msg_mute_off:   db 'Audio: Ativo', 0
msg_ac97:       db 'AC97 (PCI Multimedia)', 0
msg_hda:        db 'Intel HDA (HD Audio)', 0
msg_playing:    db 'Emitindo pulso de teste PCM/Speaker...', 0
msg_tone_ok:    db 'Teste de audio concluido.', 0
ajuda_vol:      db 'Uso: vol [0-31] - Ajusta volume', 0

audio_type:     dd 0            ; 0 = nenhum, 1 = AC97, 2 = Intel HDA
audio_base:     dq 0            ; BAR0 / BAR1 do controlador detectado
audio_volume:   db AUDIO_VOLUME_DEF
audio_muted:    db 0

section .text
global audio_init, audio_status, audio_set_volume, audio_mute_toggle, audio_ler_status
global do_audio, do_vol, do_mute, do_sound
global print_dec, str_to_int

; --------------------------------------
; Consulta rapida para o Systray (exec.c)
; Saida: rax = 0 (sem placa), 1 (ativo), 2 (mudo)
; --------------------------------------
audio_ler_status:
    cmp     dword [audio_type], 0
    je      .sem_audio
    cmp     byte [audio_muted], 1
    je      .mudo
    mov     rax, 1
    ret
.mudo:
    mov     rax, 2
    ret
.sem_audio:
    xor     rax, rax
    ret

; --------------------------------------
; Inicializacao via Barramento PCI (Bus 0, Slots 0..31, Funcoes 0..7)
; --------------------------------------
audio_init:
    push    rbx
    push    rcx
    push    rdx

    xor     ebx, ebx                ; EBX = (Slot << 3) | Func (0..255)
.pci_loop:
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000000
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    cmp     eax, 0xFFFFFFFF
    je      .proximo

    ; Ler Class Code / Subclass (offset 0x08)
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000008
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    shr     eax, 16                 ; AX = Class (alto) + Subclass (baixo)

    cmp     ax, 0x0401              ; Multimedia Audio Controller (AC97)
    je      .init_ac97

    cmp     ax, 0x0403              ; High Definition Audio (Intel HDA)
    je      .init_hda

.proximo:
    inc     ebx
    cmp     ebx, 256
    jl      .pci_loop

    mov     dword [audio_type], 0
    jmp     .fim

.init_ac97:
    ; Habilitar I/O Space (bit 0) e Bus Master (bit 2) no PCI Command (offset 0x04)
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000004
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    or      eax, 0x05
    mov     ecx, eax

    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000004
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    mov     eax, ecx
    out     dx, eax

    ; Ler BAR0 (Mixer I/O Base - NAMBAR, offset 0x10)
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000010
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    and     eax, 0xFFFFFFFC
    mov     [audio_base], rax
    mov     dword [audio_type], 1

    ; Reset e liga DAC/Mixer do AC97
    mov     dx, [audio_base]
    add     dx, AC97_RESET
    xor     ax, ax
    out     dx, ax

    mov     dx, [audio_base]
    add     dx, AC97_POWERDOWN
    xor     ax, ax
    out     dx, ax

    movzx   rdi, byte [audio_volume]
    call    audio_set_volume
    jmp     .fim

.init_hda:
    ; Habilitar Memory Space (bit 1) e Bus Master (bit 2) no PCI Command (offset 0x04)
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000004
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    or      eax, 0x06
    mov     ecx, eax

    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000004
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    mov     eax, ecx
    out     dx, eax

    ; Ler BAR0 (MMIO Base, offset 0x10)
    mov     eax, ebx
    shl     eax, 8
    or      eax, 0x80000010
    mov     dx, 0x0CF8
    out     dx, eax
    mov     dx, 0x0CFC
    in      eax, dx
    and     eax, 0xFFFFFFF0
    mov     [audio_base], rax
    mov     dword [audio_type], 2

    ; Tira o controlador Intel HDA do estado de Reset (CRST = 1)
    mov     rcx, [audio_base]
    test    rcx, rcx
    jz      .fim
    mov     dword [rcx + HDA_GCTL], 1

.fim:
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; --------------------------------------
; Status no Terminal
; --------------------------------------
audio_status:
    mov     rsi, msg_audio_ok
    call    print_string

    cmp     dword [audio_type], 1
    je      .tipo_ac97
    cmp     dword [audio_type], 2
    je      .tipo_hda
    mov     rsi, msg_audio_no
    jmp     .exibe
.tipo_ac97:
    mov     rsi, msg_ac97
    jmp     .exibe
.tipo_hda:
    mov     rsi, msg_hda
.exibe:
    call    print_string
    call    print_newline

    cmp     byte [audio_muted], 1
    je      .exibe_mudo
    mov     rsi, msg_vol_ok
    call    print_string
    movzx   rdi, byte [audio_volume]
    call    print_dec
    call    print_newline
    ret
.exibe_mudo:
    mov     rsi, msg_mute_on
    call    print_string
    call    print_newline
    ret

; --------------------------------------
; Volume (rdi = 0..31)
; --------------------------------------
audio_set_volume:
    push    rax
    push    rdx

    cmp     rdi, AUDIO_VOLUME_MAX
    jbe     .aplica
    mov     rdi, AUDIO_VOLUME_MAX
.aplica:
    mov     [audio_volume], dil
    mov     byte [audio_muted], 0

    ; Se AC97 ativo, aplica atenuacao (0 = max, 31 = min)
    cmp     dword [audio_type], 1
    jne     .fim

    mov     al, AUDIO_VOLUME_MAX
    sub     al, [audio_volume]
    mov     ah, al
    mov     dx, [audio_base]
    add     dx, AC97_MASTER_VOL
    out     dx, ax

    mov     dx, [audio_base]
    add     dx, AC97_PCM_OUT_VOL
    out     dx, ax

.fim:
    pop     rdx
    pop     rax
    ret

audio_mute_toggle:
    push    rax
    push    rdx

    xor     byte [audio_muted], 1
    cmp     dword [audio_type], 1
    jne     .fim

    mov     dx, [audio_base]
    add     dx, AC97_MASTER_VOL
    cmp     byte [audio_muted], 1
    je      .mutar_hw

    movzx   rdi, byte [audio_volume]
    call    audio_set_volume
    jmp     .fim

.mutar_hw:
    mov     ax, 0x8000              ; Bit 15 = Mute no AC97
    out     dx, ax

.fim:
    pop     rdx
    pop     rax
    ret

; --------------------------------------
; COMANDOS DO TERMINAL (FydelTerm)
; --------------------------------------
do_audio:
    call    audio_status
    ret

do_vol:
    mov     rax, [argc]
    cmp     rax, 2
    jl      .uso
    mov     rdi, [argv + 8]
    call    str_to_int
    mov     rdi, rax
    call    audio_set_volume
    mov     rsi, msg_vol_ok
    call    print_string
    movzx   rdi, byte [audio_volume]
    call    print_dec
    call    print_newline
    ret
.uso:
    mov     rsi, ajuda_vol
    call    print_string
    call    print_newline
    ret

do_mute:
    call    audio_mute_toggle
    cmp     byte [audio_muted], 1
    je      .sim
    mov     rsi, msg_mute_off
    jmp     .fim
.sim:
    mov     rsi, msg_mute_on
.fim:
    call    print_string
    call    print_newline
    ret

do_sound:
    mov     rsi, msg_playing
    call    print_string
    call    print_newline

    ; Emite bip curto via PC Speaker PIT Channel 2 (porta 0x42 / 0x61)
    mov     al, 0xB6
    out     0x43, al
    mov     ax, 1193                ; ~1000 Hz
    out     0x42, al
    mov     al, ah
    out     0x42, al

    in      al, 0x61
    or      al, 0x03
    out     0x61, al

    mov     rcx, 4000000
.atraso:
    pause
    dec     rcx
    jnz     .atraso

    in      al, 0x61
    and     al, 0xFC
    out     0x61, al

    mov     rsi, msg_tone_ok
    call    print_string
    call    print_newline
    ret

; ======================================
; AUXILIARES
; ======================================
str_to_int:
    xor     rax, rax
    xor     rcx, rcx
.loop:
    mov     cl, [rdi]
    cmp     cl, '0'
    jb      .fim
    cmp     cl, '9'
    ja      .fim
    sub     cl, '0'
    imul    rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .loop
.fim:
    ret

print_dec:
    push    rbx
    push    rdx
    push    rax
    mov     rax, rdi
    mov     rbx, 10
    push    10
.div:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    push    rdx
    test    rax, rax
    jnz     .div
.imp:
    pop     rdx
    cmp     rdx, 10
    je      .fim
    mov     al, dl
    call    print_char
    jmp     .imp
.fim:
    pop     rax
    pop     rdx
    pop     rbx
    ret
