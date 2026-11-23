; ==========================================
; ATA.ASM — Driver de Disco
; Leitura e Escrita de Setores
; FydelisTech OS v2.0 · Salvador • Bahia 🇧🇷
; ==========================================
bits 64

; Portas ATA Primárias
ATA_PRIM_DATA    equ 0x1F0
ATA_PRIM_ERR     equ 0x1F1
ATA_PRIM_SECTCNT equ 0x1F2
ATA_PRIM_LBA0    equ 0x1F3
ATA_PRIM_LBA1    equ 0x1F4
ATA_PRIM_LBA2    equ 0x1F5
ATA_PRIM_LBA3    equ 0x1F6
ATA_PRIM_CMD     equ 0x1F7
ATA_PRIM_STAT    equ 0x1F7

; Comandos ATA
ATA_CMD_READ     equ 0x20
ATA_CMD_WRITE    equ 0x30
ATA_CMD_IDENTIFY equ 0xEC

; Bits de Status
ATA_STAT_BSY     equ 0x80
ATA_STAT_RDY     equ 0x40
ATA_STAT_DRQ     equ 0x08
ATA_STAT_ERR     equ 0x01

section .bss
align 16
disco_identificado: resd 1
disco_tamanho_setores: resq 1

section .text
global ata_inicializar
global ata_ler_setor
global ata_ler_multiplo
global ata_escrever_setor
global disco_ler_setor_impl
global disco_ler_multiplo_impl

; ==========================================
; 📋 DETECTAR E IDENTIFICAR DISCO
; ==========================================
ata_inicializar:
    ; Selecionar disco mestre, LBA habilitado
    mov dx, ATA_PRIM_LBA3
    mov al, 0xE0
    out dx, al

    ; Enviar comando IDENTIFY
    mov dx, ATA_PRIM_CMD
    mov al, ATA_CMD_IDENTIFY
    out dx, al

    ; Aguardar pronto
    call ata_esperar_pronto
    test rax, rax
    jz .sem_disco

    ; Ler dados de identificação
    mov rcx, 256
    mov rdi, 0   ; Buffer — pode salvar
    mov dx, ATA_PRIM_DATA
.ler_id:
    in ax, dx
    add rdi, 2
    dec rcx
    jnz .ler_id

    mov dword [disco_identificado], 1
    mov rax, 1
    ret

.sem_disco:
    xor rax, rax
    ret

; ==========================================
; 📄 LER 1 SETOR (512 bytes)
; rdi = número do setor, rsi = buffer → rax = 1 sucesso
; ==========================================
ata_ler_setor:
    push rbx
    push rdi
    push rsi

    call ata_esperar_pronto
    jz .falha

    ; Programar endereço LBA 28 usando DX para as portas
    mov rax, rdi
    
    push rax
    and rax, 0xFF
    mov dx, ATA_PRIM_LBA0
    out dx, al
    pop rax

    push rax
    shr rax, 8
    and rax, 0xFF
    mov dx, ATA_PRIM_LBA1
    out dx, al
    pop rax

    push rax
    shr rax, 16
    and rax, 0xFF
    mov dx, ATA_PRIM_LBA2
    out dx, al
    pop rax

    shr rax, 24
    and rax, 0x0F
    or  al, 0xE0              ; Selecionar disco + LBA
    mov dx, ATA_PRIM_LBA3
    out dx, al

    ; 1 setor
    mov al, 1
    mov dx, ATA_PRIM_SECTCNT
    out dx, al

    ; Enviar comando de leitura
    mov al, ATA_CMD_READ
    mov dx, ATA_PRIM_CMD
    out dx, al

    call ata_esperar_dados
    jz .falha

    ; Ler 256 palavras = 512 bytes
    pop rsi
    mov rcx, 256
    mov dx, ATA_PRIM_DATA
.loop_ler:
    in ax, dx
    mov [rsi], ax
    add rsi, 2
    dec rcx
    jnz .loop_ler

    mov rax, 1
    jmp .fim

.falha:
    xor rax, rax
.fim:
    pop rdi
    pop rbx
    ret

; ==========================================
; 📄 LER MÚLTIPLOS SETORES
; rdi = setor inicial, rsi = buffer, rdx = quantidade
; ==========================================
ata_ler_multiplo:
    push rbp
    push rbx
    mov rbp, rdx              ; Contador
    mov rbx, rsi              ; Ponteiro

.loop:
    cmp rbp, 0
    jle .concluido

    mov rsi, rbx
    call ata_ler_setor
    test rax, rax
    jz .falha

    add rbx, 512
    inc rdi
    dec rbp
    jmp .loop

.concluido:
    mov rax, 1
    jmp .fim_mult
.falha:
    xor rax, rax
.fim_mult:
    pop rbx
    pop rbp
    ret

; ==========================================
; ✅ FUNÇÕES PÚBLICAS — Usadas pelo fs.asm
; ==========================================
disco_ler_setor_impl:
    ; rdi = setor, rsi = buffer
    jmp ata_ler_setor

disco_ler_multiplo_impl:
    ; rdi = setor, rsi = buffer, rdx = qtd
    jmp ata_ler_multiplo

; ==========================================
; ⏳ FUNÇÕES AUXILIARES
; ==========================================
ata_esperar_pronto:
    xor rcx, rcx
.loop:
    mov dx, ATA_PRIM_STAT
    in al, dx
    test al, ATA_STAT_BSY
    jz .pronto
    dec rcx
    jnz .loop
    xor rax, rax
    ret
.pronto:
    mov rax, 1
    ret

ata_esperar_dados:
    xor rcx, rcx
.loop:
    mov dx, ATA_PRIM_STAT
    in al, dx
    test al, ATA_STAT_ERR
    jnz .erro
    test al, ATA_STAT_DRQ
    jnz .pronto
    dec rcx
    jnz .loop
.erro:
    xor rax, rax
    ret
.pronto:
    mov rax, 1
    ret
