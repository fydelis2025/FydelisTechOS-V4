; ============================================================================
; DISCO.ASM — Driver Fisico ATA/IDE Real (Master 0xE0 / Slave 0xF0)
; Alinhado com fs.asm (rdi = LBA, rsi = buffer) · Sem Simulacao
; FydelisTechOS v4.2 · Salvador • Bahia
; ============================================================================
BITS 64
default rel
%include "fydelterm.inc"

; ========== PORTAS ATA PRIMARIAS ==========
ATA_DATA               equ 0x1F0
ATA_ERROR              equ 0x1F1
ATA_SECTORS            equ 0x1F2
ATA_LBA_LO             equ 0x1F3
ATA_LBA_MID            equ 0x1F4
ATA_LBA_HI             equ 0x1F5
ATA_DRIVE_HEAD         equ 0x1F6
ATA_CMD                equ 0x1F7
ATA_STATUS             equ 0x1F7
ATA_ALT_STATUS         equ 0x3F6

; ========== COMANDOS & FLAGS ATA ==========
ATA_CMD_READ           equ 0x20
ATA_CMD_WRITE          equ 0x30
ATA_CMD_IDENTIFY       equ 0xEC
ATA_CMD_FLUSH          equ 0xE7

ATA_STATUS_BSY         equ 0x80
ATA_STATUS_RDY         equ 0x40
ATA_STATUS_DRQ         equ 0x08
ATA_STATUS_ERR         equ 0x01

ATA_SEL_MASTER         equ 0xE0      ; index=0 (fydelterm.img - boot)
ATA_SEL_SLAVE          equ 0xF0      ; index=1 (fyd_data.img - FAT32 dados)

; ========== TAMANHOS ==========
SETOR_TAMANHO          equ 512
BUFFER_TAMANHO         equ 4096

; ========== EXPORTACAO ==========
global disco_ler_setor
global disco_escrever_setor
global disco_selecionar
global disco_obter_selecionado
global obter_tamanho_disco
global detectar_disco
global identificar_disco
global flush_disco
global buffer_setor

global syscall_obter_tamanho
global syscall_ler_setor
global syscall_escrever_setor

section .data
; Padrao: 1 = Primary Slave (0xF0 -> fyd_data.img no QEMU index=1)
; Use disco_selecionar(0) se quiser apontar para o Master (0xE0)
drive_selecionado:     db 1

section .bss
align 16
buffer_leitura:        resb BUFFER_TAMANHO
buffer_escrita:        resb BUFFER_TAMANHO
info_disco:            resw 256      ; 512 bytes do IDENTIFY
tamanho_master:        resq 1        ; Total de setores do Master (index=0)
tamanho_slave:         resq 1        ; Total de setores do Slave (index=1)
disco_identificado:    resb 2        ; Flags [0]=master, [1]=slave
buffer_setor:          resb 512

section .text

; ============================================================================
; AUXILIAR INTERNO: atraso de 400ns apos troca de drive (leitura de 0x3F6 x4)
; ============================================================================
ata_delay_400ns:
    push rdx
    mov dx, ATA_ALT_STATUS
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    pop rdx
    ret

; ============================================================================
; AUXILIAR INTERNO: retorna byte de selecao (0xE0 ou 0xF0) para drive em RDI
; ============================================================================
ata_byte_drive:
    cmp rdi, 1
    je .slave
    mov al, ATA_SEL_MASTER
    ret
.slave:
    mov al, ATA_SEL_SLAVE
    ret

; ============================================================================
; SELECIONAR DISCO ATIVO PARA O FS
; Entrada: RDI = 0 (Primary Master / index=0) ou 1 (Primary Slave / index=1)
; Saida:   RAX = 1 se detectado, 0 se ausente
; ============================================================================
disco_selecionar:
    and rdi, 1
    mov [rel drive_selecionado], dil
    call detectar_disco
    ret

disco_obter_selecionado:
    xor eax, eax
    mov al, [rel drive_selecionado]
    ret

; ============================================================================
; DETECTAR DISCO — Verifica se existe no canal ATA
; Entrada: RDI = 0 (Master) ou 1 (Slave)
; Saida:   RAX = 1 encontrado, 0 ausente
; ============================================================================
detectar_disco:
    push rcx
    push rdx
    push rdi

    and rdi, 1
    call ata_byte_drive
    mov dx, ATA_DRIVE_HEAD
    out dx, al
    call ata_delay_400ns

    ; Status 0xFF ou 0x00 indica barramento flutuante (sem dispositivo)
    mov dx, ATA_STATUS
    in al, dx
    cmp al, 0xFF
    je .nao_encontrado
    test al, al
    jz .nao_encontrado

    mov rcx, 100000
.aguardar:
    in al, dx
    test al, ATA_STATUS_BSY
    jz .pronto
    dec rcx
    jnz .aguardar
    jmp .nao_encontrado

.pronto:
    test al, ATA_STATUS_ERR
    jnz .nao_encontrado
    mov rax, 1
    jmp .fim

.nao_encontrado:
    xor eax, eax
.fim:
    pop rdi
    pop rdx
    pop rcx
    ret

; ============================================================================
; IDENTIFICAR DISCO — Executa ATA IDENTIFY (0xEC) e extrai setores reais
; Entrada: RDI = 0 (Master) ou 1 (Slave), RSI = buffer 512B (ou 0 para ignorar)
; Saida:   RAX = 1 sucesso, 0 falha
; ============================================================================
identificar_disco:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9

    and rdi, 1
    mov r9, rdi                 ; r9 = indice do disco (0 ou 1)
    mov r8, rsi                 ; r8 = buffer opcional do chamador

    ; Seleciona drive
    mov rdi, r9
    call ata_byte_drive
    mov dx, ATA_DRIVE_HEAD
    out dx, al
    call ata_delay_400ns

    ; Zera registradores LBA antes do IDENTIFY (padrao ATA)
    mov dx, ATA_SECTORS
    xor al, al
    out dx, al
    mov dx, ATA_LBA_LO
    out dx, al
    mov dx, ATA_LBA_MID
    out dx, al
    mov dx, ATA_LBA_HI
    out dx, al

    ; Envia comando IDENTIFY
    mov dx, ATA_CMD
    mov al, ATA_CMD_IDENTIFY
    out dx, al
    call ata_delay_400ns

    ; Status 0x00 significa que o drive nao existe
    in al, dx
    test al, al
    jz .falha
    cmp al, 0xFF
    je .falha

    mov rcx, 100000
.aguardar_bsy:
    in al, dx
    test al, ATA_STATUS_BSY
    jz .bsy_liberado
    dec rcx
    jnz .aguardar_bsy
    jmp .falha

.bsy_liberado:
    ; Verifica se nao e dispositivo ATAPI (LBA_MID/HI != 0)
    mov dx, ATA_LBA_MID
    in al, dx
    test al, al
    jnz .falha
    mov dx, ATA_LBA_HI
    in al, dx
    test al, al
    jnz .falha

    mov dx, ATA_STATUS
    mov rcx, 100000
.aguardar_drq:
    in al, dx
    test al, ATA_STATUS_ERR
    jnz .falha
    test al, ATA_STATUS_DRQ
    jnz .ler_ident
    dec rcx
    jnz .aguardar_drq
    jmp .falha

.ler_ident:
    mov rcx, 256
    lea rdi, [rel info_disco]
    mov dx, ATA_DATA
    rep insw

    ; Extrai total de setores: tenta LBA48 (palavras 100-103 -> offset 200)
    ; e faz fallback para LBA28 (palavras 60-61 -> offset 120)
    mov rax, [rel info_disco + 200]
    test rax, rax
    jnz .salva_tam
    mov eax, [rel info_disco + 120]

.salva_tam:
    lea rbx, [rel tamanho_master]
    mov [rbx + r9 * 8], rax
    lea rbx, [rel disco_identificado]
    mov byte [rbx + r9], 1

    ; Copia para buffer do chamador apenas se RSI != 0
    test r8, r8
    jz .ok
    mov rdi, r8
    lea rsi, [rel info_disco]
    mov rcx, 512 / 8
    rep movsq

.ok:
    mov rax, 1
    jmp .fim

.falha:
    xor eax, eax
.fim:
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================================
; OBTER TAMANHO DO DISCO ATIVO (setores de 512 bytes)
; ============================================================================
obter_tamanho_disco:
    push rbx
    push rdi
    push rsi

    xor edi, edi
    mov dil, [rel drive_selecionado]
    and edi, 1

    lea rbx, [rel disco_identificado]
    cmp byte [rbx + rdi], 1
    je .ja_identificado

    xor esi, esi
    call identificar_disco

.ja_identificado:
    xor edi, edi
    mov dil, [rel drive_selecionado]
    and edi, 1
    lea rbx, [rel tamanho_master]
    mov rax, [rbx + rdi * 8]

    pop rsi
    pop rdi
    pop rbx
    ret

; ============================================================================
; LER SETOR (INTERFACE DIRETA PARA FS.ASM)
; Entrada: RDI = LBA (setor), RSI = ponteiro buffer (512 bytes)
; Saida:   RAX = 1 sucesso, 0 falha
; ============================================================================
disco_ler_setor:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9

    test rsi, rsi
    jz .falha

    mov r9, rdi                 ; r9 = LBA
    mov r8, rsi                 ; r8 = buffer destino

    ; Auto-identifica disco ativo se ainda nao foi identificado
    xor edi, edi
    mov dil, [rel drive_selecionado]
    and edi, 1
    lea rbx, [rel disco_identificado]
    cmp byte [rbx + rdi], 1
    je .checa_limite

    xor esi, esi
    call identificar_disco
    test rax, rax
    jz .falha

.checa_limite:
    xor edi, edi
    mov dil, [rel drive_selecionado]
    and edi, 1
    lea rbx, [rel tamanho_master]
    mov rax, [rbx + rdi * 8]
    test rax, rax
    jz .prepara_leitura         ; se hardware nao reportar tamanho, tenta ler LBA
    cmp r9, rax
    jae .falha

.prepara_leitura:
    ; Seleciona drive (0xE0 Master ou 0xF0 Slave) + bits 24-27 do LBA
    xor edi, edi
    mov dil, [rel drive_selecionado]
    call ata_byte_drive
    mov bl, al

    mov rax, r9
    shr rax, 24
    and al, 0x0F
    or al, bl
    mov dx, ATA_DRIVE_HEAD
    out dx, al
    call ata_delay_400ns

    mov dx, ATA_SECTORS
    mov al, 1
    out dx, al

    mov rax, r9
    mov dx, ATA_LBA_LO
    out dx, al

    shr rax, 8
    mov dx, ATA_LBA_MID
    out dx, al

    shr rax, 8
    mov dx, ATA_LBA_HI
    out dx, al

    mov dx, ATA_CMD
    mov al, ATA_CMD_READ
    out dx, al

    mov dx, ATA_STATUS
    mov rcx, 200000
.aguardar:
    in al, dx
    test al, ATA_STATUS_BSY
    jnz .espera
    test al, ATA_STATUS_ERR
    jnz .falha
    test al, ATA_STATUS_DRQ
    jnz .dados_prontos
.espera:
    dec rcx
    jnz .aguardar
    jmp .falha

.dados_prontos:
    mov rcx, 128                ; 128 dwords = 512 bytes
    mov rdi, r8
    mov dx, ATA_DATA
    rep insd

    mov rax, 1
    jmp .fim

.falha:
    xor eax, eax
.fim:
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================================
; ESCREVER SETOR (INTERFACE DIRETA PARA FS.ASM)
; Entrada: RDI = LBA (setor), RSI = ponteiro buffer (512 bytes)
; Saida:   RAX = 1 sucesso, 0 falha
; ============================================================================
disco_escrever_setor:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9

    test rsi, rsi
    jz .falha

    mov r9, rdi                 ; r9 = LBA
    mov r8, rsi                 ; r8 = buffer origem

    ; Auto-identifica disco ativo se ainda nao foi identificado
    xor edi, edi
    mov dil, [rel drive_selecionado]
    and edi, 1
    lea rbx, [rel disco_identificado]
    cmp byte [rbx + rdi], 1
    je .checa_limite

    xor esi, esi
    call identificar_disco
    test rax, rax
    jz .falha

.checa_limite:
    xor edi, edi
    mov dil, [rel drive_selecionado]
    and edi, 1
    lea rbx, [rel tamanho_master]
    mov rax, [rbx + rdi * 8]
    test rax, rax
    jz .prepara_escrita
    cmp r9, rax
    jae .falha

.prepara_escrita:
    xor edi, edi
    mov dil, [rel drive_selecionado]
    call ata_byte_drive
    mov bl, al

    mov rax, r9
    shr rax, 24
    and al, 0x0F
    or al, bl
    mov dx, ATA_DRIVE_HEAD
    out dx, al
    call ata_delay_400ns

    mov dx, ATA_SECTORS
    mov al, 1
    out dx, al

    mov rax, r9
    mov dx, ATA_LBA_LO
    out dx, al

    shr rax, 8
    mov dx, ATA_LBA_MID
    out dx, al

    shr rax, 8
    mov dx, ATA_LBA_HI
    out dx, al

    mov dx, ATA_CMD
    mov al, ATA_CMD_WRITE
    out dx, al

    mov dx, ATA_STATUS
    mov rcx, 200000
.aguardar:
    in al, dx
    test al, ATA_STATUS_BSY
    jnz .espera
    test al, ATA_STATUS_ERR
    jnz .falha
    test al, ATA_STATUS_DRQ
    jnz .dados_prontos
.espera:
    dec rcx
    jnz .aguardar
    jmp .falha

.dados_prontos:
    mov rcx, 128                ; 128 dwords = 512 bytes
    mov rsi, r8
    mov dx, ATA_DATA
    rep outsd

    mov dx, ATA_STATUS
    mov rcx, 1000000
.espera_fim:
    in al, dx
    test al, ATA_STATUS_BSY
    jz .gravado
    dec rcx
    jnz .espera_fim
    jmp .falha

.gravado:
    call flush_disco
    mov rax, 1
    jmp .fim

.falha:
    xor eax, eax
.fim:
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================================
; FLUSH — Esvazia cache de escrita do controlador ATA
; ============================================================================
flush_disco:
    push rcx
    push rdx
    mov dx, ATA_CMD
    mov al, ATA_CMD_FLUSH
    out dx, al
    mov dx, ATA_STATUS
    mov rcx, 1000000
.aguardar:
    in al, dx
    test al, ATA_STATUS_BSY
    jz .ok
    dec rcx
    jnz .aguardar
.ok:
    mov rax, 1
    pop rdx
    pop rcx
    ret

; ============================================================================
; PONTES DE SYSCALL (ABI System V: rdi=disco_id, rsi=LBA, rdx=buffer)
; ============================================================================
syscall_obter_tamanho:
    call obter_tamanho_disco
    ret

syscall_ler_setor:
    push rdi
    and rdi, 1
    mov [rel drive_selecionado], dil
    mov rdi, rsi                ; LBA
    mov rsi, rdx                ; buffer
    call disco_ler_setor
    pop rdi
    ret

syscall_escrever_setor:
    push rdi
    and rdi, 1
    mov [rel drive_selecionado], dil
    mov rdi, rsi                ; LBA
    mov rsi, rdx                ; buffer
    call disco_escrever_setor
    pop rdi
    ret
