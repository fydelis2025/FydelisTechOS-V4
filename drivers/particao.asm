; ============================================================================
; PARTICAO.ASM — Gerenciador Real de Particoes MBR & GPT + Formatador FAT32
; Alinhado com disco.asm e fs.asm · Sem Stubs Simulados
; FydelisTechOS v4.2 · Salvador • Bahia
; ============================================================================
BITS 64
default rel
%include "fydelterm.inc"

; ========== TAMANHOS E CONSTANTES ==========
SETOR_TAMANHO           equ 512
MAX_DISCOS_FIXOS        equ 8     ; fyd1 a fyd8 -> C: ate J:
MAX_USB                 equ 8     ; fydu1 a fydu8 -> U1: ate U8:
MAX_MIDIA               equ 4     ; fydm1 a fydm4 -> M1: ate M4:
MAX_REDE                equ 4     ; fydr1 a fydr4 -> R1: ate R4:
LIMIAR_GPT_SETORES      equ 0xFFFFFFFF  ; > 2 TiB (32-bit LBA max) -> GPT

; ========== TIPOS DE DISPOSITIVO ==========
TIPO_DISCO_FIXO         equ 1
TIPO_USB                equ 2
TIPO_MIDIA_REMOVIVEL    equ 3
TIPO_REDE               equ 4

; ========== MBR / GPT ==========
MBR_ASSINATURA          equ 0xAA55
MBR_PARTICAO_OFFSET     equ 0x1BE
MBR_TIPO_FAT32          equ 0x0B
MBR_TIPO_FAT32_LBA      equ 0x0C
MBR_TIPO_EXFAT          equ 0x07
MBR_TIPO_GPT_PROTETOR   equ 0xEE

GPT_CABECALHO_LBA       equ 1
GPT_ENTRADAS_LBA        equ 2
GPT_QTD_ENTRADAS        equ 128
GPT_TAMANHO_ENTRADA     equ 128
GPT_PARTICAO_INICIAL    equ 2048  ; Alinhamento padrao de 1 MiB (2048 setores)

; ========== EXPORTACAO ==========
global detectar_tabela
global listar_unidades
global criar_unidade
global remover_unidade
global formatar_unidade
global formatar_fat32
global formatar_exfat
global inicializar_disco
global atualizar_mapa
global mapear_para_dispositivos
global mapa_unidades
global mapa_dispositivos
global criar_particao
global apagar_entrada_particao
global selecionar_unidade

; ========== EXTERNAIS (DISCO.ASM, FS.ASM & TERMINAL) ==========
extern disco_ler_setor, disco_escrever_setor, obter_tamanho_disco, flush_disco
extern fs_inicializar, fs_obter_particao_lba, fs_obter_tipo_tabela
extern print_string, print_char, print_newline
extern int_para_str

; ========== ESTRUTURA DE UNIDADE (80 bytes) ==========
struc Unidade
    .letra:         resb 1    ; +0
    .tipo_sistema:  resb 1    ; +1  (0x0B/0x0C = FAT32, 0x07 = exFAT)
    .lba_inicio:    resq 1    ; +2
    .lba_tamanho:   resq 1    ; +10
    .ativo:         resb 1    ; +18
    .removivel:     resb 1    ; +19
    .reservado:     resb 60   ; +20 .. +79 (total 80 bytes)
endstruc

; ========== ESTRUTURA DE DISPOSITIVO (72 bytes) ==========
struc Dispositivo
    .tipo:          resb 1    ; +0  (1=fixo, 2=usb, 3=midia, 4=rede)
    .indice:        resb 1    ; +1  (1, 2, 3...)
    .letra_str:     resb 3    ; +2  ("C:", "D:", ...)
    .caminho:       resb 32   ; +5  ("/fyd/disco/fyd1")
    .lba_inicio:    resq 1    ; +37
    .lba_tamanho:   resq 1    ; +45
    .tipo_fs:       resb 1    ; +53
    .ativo:         resb 1    ; +54
    .reservado:     resb 17   ; +55 .. +71 (total 72 bytes)
endstruc

section .data
msg_cab_disp:   db "  TIPO    | NOME     | LETRA | CAMINHO               | TAMANHO",10, \
                   "----------+----------+-------+-----------------------+----------",10,0
msg_disco_fixo: db "Disco",0
msg_usb:        db "USB",0
msg_midia:      db "Midia",0
msg_rede:       db "Rede",0
msg_exfat:      db "exFAT",0
msg_fat32:      db "FAT32",0
msg_fydfs:      db "FydelisFS",0
msg_cabecalho:  db "  UNIDADE  |   SISTEMA   |  TAMANHO    |  STATUS",10, \
                   " ----------+------------+-------------+----------",10,0
msg_ativo:      db "  Ativo",10,0
msg_sep:        db "  |  ",0

pasta_disco:    db "/fyd/disco/",0
prefixo_fyd:    db "fyd",0
gpt_magic:      db "EFI PART"
fat32_oem:      db "FYDELIS "
fat32_label:    db "FYDELISTECH"
fat32_fstype:   db "FAT32   "

; Microsoft Basic Data GUID (EBD0A0A2-B9E5-4433-87C0-68B6B72699C7)
guid_basic_data:
    db 0xA2, 0xA0, 0xD0, 0xEB, 0xE5, 0xB9, 0x33, 0x44
    db 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7

; GUID unico do disco/particao FydelisTech
guid_fyd_disk:
    db 0x46, 0x59, 0x44, 0x45, 0x4C, 0x49, 0x53, 0x31
    db 0x20, 0x26, 0xBA, 0x53, 0x41, 0x4C, 0x56, 0x01

msg_kb:         db " KB",0
msg_mb:         db " MB",0
msg_gb:         db " GB",0
msg_tb:         db " TB",0

section .bss
align 16
buffer_setor:            resb 512
buffer_gpt:              resb 512
buffer_zero:             resb 512
buffer_conversao:        resb 32
buffer_caminho:          resb 64

mapa_unidades:           resb 26 * Unidade_size
mapa_dispositivos:       resb (MAX_DISCOS_FIXOS + MAX_USB + MAX_MIDIA + MAX_REDE) * Dispositivo_size
qtd_unidades:            resd 1
qtd_dispositivos:        resd 1
prox_disco_fixo:         resd 1
prox_usb:                resd 1
prox_midia:              resd 1
prox_rede:               resd 1
tipo_tabela:             resb 1      ; 0 = MBR, 1 = GPT
tamanho_disco_setores:   resq 1
ultimo_lba_usado:        resq 1

section .text

; ============================================================================
; AUXILIARES DE DISCO REAIS (conectados diretamente ao disco.asm)
; ============================================================================
ler_setor:
    ; Entrada: rdi = LBA -> le para buffer_setor, rax = 1 ok / 0 erro
    lea rsi, [rel buffer_setor]
    call disco_ler_setor
    ret

escrever_setor:
    ; Entrada: rdi = LBA -> grava buffer_setor, rax = 1 ok / 0 erro
    lea rsi, [rel buffer_setor]
    call disco_escrever_setor
    ret

particao_tamanho_disco:
    call obter_tamanho_disco
    mov [rel tamanho_disco_setores], rax
    ret

; ============================================================================
; INICIALIZAR DISCO — Detecta MBR/GPT real e monta mapa de unidades
; ============================================================================
inicializar_disco:
    push rax
    push rdi

    mov dword [rel prox_disco_fixo], 1
    mov dword [rel prox_usb], 1
    mov dword [rel prox_midia], 1
    mov dword [rel prox_rede], 1
    mov dword [rel qtd_dispositivos], 0
    mov qword [rel ultimo_lba_usado], GPT_PARTICAO_INICIAL

    call particao_tamanho_disco
    test rax, rax
    jz .fim                     ; nenhum disco fisico presente no canal

    xor edi, edi
    call ler_setor
    cmp rax, 1
    jne .fim

    cmp word [rel buffer_setor + 510], MBR_ASSINATURA
    je .ja_possui_tabela

    ; Disco virgem (sem assinatura 0xAA55): cria MBR ou GPT real conforme tamanho
    mov rax, [rel tamanho_disco_setores]
    cmp rax, LIMIAR_GPT_SETORES
    jae .usar_gpt

    mov byte [rel tipo_tabela], 0
    call inicializar_mbr
    jmp .mapear

.usar_gpt:
    mov byte [rel tipo_tabela], 1
    call escrever_cabecalho_gpt
    jmp .mapear

.ja_possui_tabela:
    call detectar_tabela

.mapear:
    call atualizar_mapa
    call mapear_para_dispositivos

.fim:
    pop rdi
    pop rax
    ret

; ============================================================================
; DETECTAR TABELA — Identifica se LBA 0 e MBR (0) ou GPT (1)
; Saida: RAX = 1 (GPT), 0 (MBR), -1 (erro)
; ============================================================================
detectar_tabela:
    push rbx
    push rcx
    push rsi
    push rdi

    xor edi, edi
    call ler_setor
    cmp rax, 1
    jne .erro

    cmp word [rel buffer_setor + 510], MBR_ASSINATURA
    jne .erro

    lea rbx, [rel buffer_setor + MBR_PARTICAO_OFFSET]
    xor ecx, ecx
.checa_ee:
    cmp ecx, 4
    jae .eh_mbr
    cmp byte [rbx + 4], MBR_TIPO_GPT_PROTETOR
    je .verifica_gpt_hdr
    add rbx, 16
    inc ecx
    jmp .checa_ee

.verifica_gpt_hdr:
    mov rdi, GPT_CABECALHO_LBA
    lea rsi, [rel buffer_gpt]
    call disco_ler_setor
    cmp rax, 1
    jne .eh_mbr

    lea rsi, [rel buffer_gpt]
    lea rdi, [rel gpt_magic]
    mov rcx, 8
    repe cmpsb
    jne .eh_mbr

    mov byte [rel tipo_tabela], 1
    mov rax, 1
    jmp .fim

.eh_mbr:
    mov byte [rel tipo_tabela], 0
    xor eax, eax
    jmp .fim

.erro:
    mov rax, -1
.fim:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; ============================================================================
; ATUALIZAR MAPA — Varre tabela real (MBR ou GPT) e preenche mapa_unidades
; ============================================================================
atualizar_mapa:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    ; Limpa mapa_unidades (26 * 80 bytes)
    lea rdi, [rel mapa_unidades]
    mov rcx, (26 * Unidade_size) / 8
    xor eax, eax
    rep stosq
    mov dword [rel qtd_unidades], 0
    mov qword [rel ultimo_lba_usado], GPT_PARTICAO_INICIAL

    call detectar_tabela
    cmp rax, -1
    je .fim
    cmp rax, 1
    je .ler_particoes_gpt

    ; ---- MODO MBR (4 entradas primarias em LBA 0 + 0x1BE) ----
    xor edi, edi
    call ler_setor
    cmp rax, 1
    jne .fim

    xor r12d, r12d              ; indice entrada MBR (0..3)
    mov r13d, 2                 ; indice letra ('C' = 2)

.loop_mbr:
    cmp r12d, 4
    jae .fim

    mov rax, r12
    shl rax, 4
    lea rbx, [rel buffer_setor + MBR_PARTICAO_OFFSET + rax]

    mov al, [rbx + 4]           ; tipo da particao
    test al, al
    jz .prox_mbr
    cmp al, MBR_TIPO_GPT_PROTETOR
    je .prox_mbr

    mov ecx, [rbx + 8]          ; LBA inicio (32-bit)
    mov edx, [rbx + 12]         ; LBA tamanho (32-bit)
    test edx, edx
    jz .prox_mbr

    ; Atualiza ultimo_lba_usado
    mov rax, rcx
    add rax, rdx
    cmp rax, [rel ultimo_lba_usado]
    jbe .salva_mbr
    mov [rel ultimo_lba_usado], rax

.salva_mbr:
    cmp r13d, 26
    jae .fim
    mov rax, r13
    imul rax, Unidade_size
    lea rdi, [rel mapa_unidades]
    add rdi, rax

    mov al, 'A'
    add al, r13b
    mov [rdi + Unidade.letra], al
    mov al, [rbx + 4]
    mov [rdi + Unidade.tipo_sistema], al
    mov [rdi + Unidade.lba_inicio], rcx
    mov [rdi + Unidade.lba_tamanho], rdx
    mov byte [rdi + Unidade.ativo], 1
    mov byte [rdi + Unidade.removivel], 0

    inc r13d
    inc dword [rel qtd_unidades]

.prox_mbr:
    inc r12d
    jmp .loop_mbr

    ; ---- MODO GPT (entradas em LBA 2..33, 4 entradas por setor) ----
.ler_particoes_gpt:
    xor r12d, r12d              ; indice entrada GPT (0..127)
    mov r13d, 2                 ; indice letra ('C' = 2)

.loop_gpt:
    cmp r12d, GPT_QTD_ENTRADAS
    jae .fim

    mov eax, r12d
    shr eax, 2
    mov rdi, GPT_ENTRADAS_LBA
    add rdi, rax
    lea rsi, [rel buffer_gpt]
    call disco_ler_setor
    cmp rax, 1
    jne .fim

    mov eax, r12d
    and eax, 3
    shl eax, 7
    lea rbx, [rel buffer_gpt + rax]

    ; Verifica se GUID de tipo nao e zero (testa primeiros 8 bytes + ultimos 8 bytes)
    mov rax, [rbx]
    or rax, [rbx + 8]
    test rax, rax
    jz .prox_gpt

    mov rcx, [rbx + 32]         ; Starting LBA
    mov rdx, [rbx + 40]         ; Ending LBA
    cmp rdx, rcx
    jb .prox_gpt
    sub rdx, rcx
    inc rdx                     ; tamanho em setores = end - start + 1

    ; Atualiza ultimo_lba_usado
    mov rax, rcx
    add rax, rdx
    cmp rax, [rel ultimo_lba_usado]
    jbe .salva_gpt
    mov [rel ultimo_lba_usado], rax

.salva_gpt:
    cmp r13d, 26
    jae .fim
    mov rax, r13
    imul rax, Unidade_size
    lea rdi, [rel mapa_unidades]
    add rdi, rax

    mov al, 'A'
    add al, r13b
    mov [rdi + Unidade.letra], al
    mov byte [rdi + Unidade.tipo_sistema], MBR_TIPO_FAT32_LBA
    mov [rdi + Unidade.lba_inicio], rcx
    mov [rdi + Unidade.lba_tamanho], rdx
    mov byte [rdi + Unidade.ativo], 1
    mov byte [rdi + Unidade.removivel], 0

    inc r13d
    inc dword [rel qtd_unidades]

.prox_gpt:
    inc r12d
    jmp .loop_gpt

.fim:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================================
; MAPEAR UNIDADES -> Dispositivos com Caminho (/fyd/disco/fyd1, C:, ...)
; ============================================================================
mapear_para_dispositivos:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8

    ; Zera mapa_dispositivos antes de reconstruir
    lea rdi, [rel mapa_dispositivos]
    mov rcx, ((MAX_DISCOS_FIXOS + MAX_USB + MAX_MIDIA + MAX_REDE) * Dispositivo_size) / 8
    xor eax, eax
    rep stosq

    mov dword [rel prox_disco_fixo], 1
    mov dword [rel qtd_dispositivos], 0

    xor ebx, ebx
.loop:
    cmp ebx, 26
    jae .fim

    mov rax, rbx
    imul rax, Unidade_size
    lea r8, [rel mapa_unidades]
    add r8, rax                 ; r8 = Unidade* atual

    cmp byte [r8 + Unidade.letra], 0
    je .prox

    mov ecx, [rel qtd_dispositivos]
    cmp ecx, MAX_DISCOS_FIXOS
    jae .fim

    mov rsi, rcx
    imul rsi, Dispositivo_size
    lea rdx, [rel mapa_dispositivos]
    add rdx, rsi                ; rdx = Dispositivo* destino

    mov byte [rdx + Dispositivo.tipo], TIPO_DISCO_FIXO
    mov eax, [rel prox_disco_fixo]
    mov [rdx + Dispositivo.indice], al

    mov al, [r8 + Unidade.letra]
    mov [rdx + Dispositivo.letra_str], al
    mov byte [rdx + Dispositivo.letra_str + 1], ':'
    mov byte [rdx + Dispositivo.letra_str + 2], 0

    ; Monta "/fyd/disco/fyd1" em Dispositivo.caminho
    lea rsi, [rel pasta_disco]
    lea rdi, [rdx + Dispositivo.caminho]
    call copiar_string
    dec rdi                     ; volta sobre o '\0'
    lea rsi, [rel prefixo_fyd]
    call copiar_string
    dec rdi
    mov al, [rel prox_disco_fixo]
    add al, '0'
    stosb
    mov byte [rdi], 0

    ; Copia metadados reais da Unidade (usando r8 preservado!)
    mov rax, [r8 + Unidade.lba_inicio]
    mov [rdx + Dispositivo.lba_inicio], rax
    mov rax, [r8 + Unidade.lba_tamanho]
    mov [rdx + Dispositivo.lba_tamanho], rax
    mov al, [r8 + Unidade.tipo_sistema]
    mov [rdx + Dispositivo.tipo_fs], al
    mov byte [rdx + Dispositivo.ativo], 1

    inc dword [rel prox_disco_fixo]
    inc dword [rel qtd_dispositivos]

.prox:
    inc ebx
    jmp .loop

.fim:
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================================
; LISTAR UNIDADES — Exibe particoes reais detectadas no disco
; ============================================================================
listar_unidades:
    push rbx
    push rsi
    push rdi
    push rax

    call atualizar_mapa
    call mapear_para_dispositivos

    lea rsi, [rel msg_cab_disp]
    call print_string

    xor ebx, ebx
.loop:
    cmp ebx, (MAX_DISCOS_FIXOS + MAX_USB + MAX_MIDIA + MAX_REDE)
    jae .fim

    mov rax, rbx
    imul rax, Dispositivo_size
    lea rdi, [rel mapa_dispositivos]
    add rdi, rax

    cmp byte [rdi + Dispositivo.tipo], 0
    je .prox

    mov al, ' '
    call print_char
    cmp byte [rdi + Dispositivo.tipo], TIPO_DISCO_FIXO
    je .imp_fixo
    cmp byte [rdi + Dispositivo.tipo], TIPO_USB
    je .imp_usb
    cmp byte [rdi + Dispositivo.tipo], TIPO_MIDIA_REMOVIVEL
    je .imp_midia
    lea rsi, [rel msg_rede]
    jmp .imp_tipo
.imp_fixo:
    lea rsi, [rel msg_disco_fixo]
    jmp .imp_tipo
.imp_usb:
    lea rsi, [rel msg_usb]
    jmp .imp_tipo
.imp_midia:
    lea rsi, [rel msg_midia]
.imp_tipo:
    call print_string
    lea rsi, [rel msg_sep]
    call print_string

    lea rsi, [rdi + Dispositivo.caminho + 11]
    call print_string
    lea rsi, [rel msg_sep]
    call print_string

    lea rsi, [rdi + Dispositivo.letra_str]
    call print_string
    lea rsi, [rel msg_sep]
    call print_string

    lea rsi, [rdi + Dispositivo.caminho]
    call print_string
    lea rsi, [rel msg_sep]
    call print_string

    mov rax, [rdi + Dispositivo.lba_tamanho]
    shl rax, 9
    call bytes_para_texto
    call print_newline

.prox:
    inc ebx
    jmp .loop

.fim:
    pop rax
    pop rdi
    pop rsi
    pop rbx
    ret

; ============================================================================
; SELECIONAR UNIDADE — Sincroniza FS com a unidade escolhida (ex: RDI = 2 'C:')
; ============================================================================
selecionar_unidade:
    push rbx
    cmp rdi, 26
    jae .erro
    mov rax, rdi
    imul rax, Unidade_size
    lea rbx, [rel mapa_unidades]
    add rbx, rax
    cmp byte [rbx + Unidade.ativo], 1
    jne .erro

    call fs_inicializar
    mov rax, 1
    pop rbx
    ret
.erro:
    xor eax, eax
    pop rbx
    ret

; ========== FUNCOES AUXILIARES DE FORMATACAO TEXTO ==========
copiar_string:
    lodsb
    stosb
    test al, al
    jnz copiar_string
    ret

bytes_para_texto:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    mov rbx, 1000000000000
    cmp rax, rbx
    jae .tb
    mov rbx, 1000000000
    cmp rax, rbx
    jae .gb
    mov rbx, 1000000
    cmp rax, rbx
    jae .mb
    mov rbx, 1024
    xor rdx, rdx
    div rbx
    lea rdi, [rel buffer_conversao]
    call int_para_str
    lea rsi, [rel buffer_conversao]
    call print_string
    lea rsi, [rel msg_kb]
    call print_string
    jmp .fim
.mb:
    xor rdx, rdx
    div rbx
    lea rdi, [rel buffer_conversao]
    call int_para_str
    lea rsi, [rel buffer_conversao]
    call print_string
    lea rsi, [rel msg_mb]
    call print_string
    jmp .fim
.gb:
    xor rdx, rdx
    div rbx
    lea rdi, [rel buffer_conversao]
    call int_para_str
    lea rsi, [rel buffer_conversao]
    call print_string
    lea rsi, [rel msg_gb]
    call print_string
    jmp .fim
.tb:
    xor rdx, rdx
    div rbx
    lea rdi, [rel buffer_conversao]
    call int_para_str
    lea rsi, [rel buffer_conversao]
    call print_string
    lea rsi, [rel msg_tb]
    call print_string
.fim:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================================
; CRIAR UNIDADE — Grava entrada real na tabela MBR ou GPT e atualiza mapa
; Entrada: RDI = indice letra (2='C', 3='D'...), RDX = tamanho em setores
; ============================================================================
criar_unidade:
    push rbx
    push rsi
    push rdi
    push rdx
    push rcx

    cmp rdi, 26
    jae .erro
    test rdx, rdx
    jz .erro

    mov rax, rdi
    imul rax, Unidade_size
    lea rbx, [rel mapa_unidades]
    add rbx, rax

    cmp byte [rbx + Unidade.letra], 0
    jne .erro

    mov rcx, [rel ultimo_lba_usado]
    cmp rcx, GPT_PARTICAO_INICIAL
    jae .lba_ok
    mov rcx, GPT_PARTICAO_INICIAL
.lba_ok:
    mov rsi, rdx                ; rsi = tamanho em setores
    mov rdx, MBR_TIPO_FAT32_LBA
    call criar_particao
    test rax, rax
    jz .erro

    call atualizar_mapa
    call mapear_para_dispositivos
    mov rax, 1
    jmp .saida

.erro:
    xor eax, eax
.saida:
    pop rcx
    pop rdx
    pop rdi
    pop rsi
    pop rbx
    ret

; ============================================================================
; REMOVER UNIDADE — Remove entrada real da tabela MBR ou GPT
; ============================================================================
remover_unidade:
    push rbx
    push rdi

    cmp rdi, 26
    jae .erro

    mov rax, rdi
    imul rax, Unidade_size
    lea rbx, [rel mapa_unidades]
    add rbx, rax

    cmp byte [rbx + Unidade.letra], 0
    je .erro

    mov rdi, [rbx + Unidade.lba_inicio]
    call apagar_entrada_particao
    test rax, rax
    jz .erro

    call atualizar_mapa
    call mapear_para_dispositivos
    mov rax, 1
    jmp .fim

.erro:
    xor eax, eax
.fim:
    pop rdi
    pop rbx
    ret

; ============================================================================
; FORMATAR UNIDADE — Formata particao real em FAT32 no disco
; ============================================================================
formatar_unidade:
    push rbx
    push rsi
    push rdi

    cmp rdi, 26
    jae .erro

    mov rax, rdi
    imul rax, Unidade_size
    lea rbx, [rel mapa_unidades]
    add rbx, rax

    cmp byte [rbx + Unidade.ativo], 0
    je .erro

    mov rdi, [rbx + Unidade.lba_inicio]
    mov rsi, [rbx + Unidade.lba_tamanho]
    call formatar_fat32
    test rax, rax
    jz .erro

    mov rax, 1
    jmp .fim

.erro:
    xor eax, eax
.fim:
    pop rdi
    pop rsi
    pop rbx
    ret

; ============================================================================
; ESCREVER ENTRADA REAL DE PARTICAO (MBR OU GPT)
; Entrada: rcx = LBA inicial, rsi = tamanho em setores, rdx = tipo (0x0C)
; ============================================================================
criar_particao:
    push rbx
    push r8
    push r9
    push r10
    push r11

    mov r8, rcx                 ; r8 = LBA inicio
    mov r9, rsi                 ; r9 = tamanho setores
    mov r10d, edx               ; r10 = tipo

    cmp byte [rel tipo_tabela], 1
    je .criar_gpt

    ; ---- MBR: procura slot livre entre as 4 entradas ----
    xor edi, edi
    call ler_setor
    cmp rax, 1
    jne .erro

    xor ecx, ecx
.mbr_slot:
    cmp ecx, 4
    jae .erro
    mov rax, rcx
    shl rax, 4
    lea rbx, [rel buffer_setor + MBR_PARTICAO_OFFSET + rax]
    cmp byte [rbx + 4], 0
    je .mbr_gravar
    inc ecx
    jmp .mbr_slot

.mbr_gravar:
    mov byte [rbx + 0], 0x80    ; bootable/ativa
    mov byte [rbx + 1], 0xFE    ; CHS fim LBA
    mov byte [rbx + 2], 0xFF
    mov byte [rbx + 3], 0xFF
    mov [rbx + 4], r10b         ; 0x0C (FAT32 LBA)
    mov byte [rbx + 5], 0xFE
    mov byte [rbx + 6], 0xFF
    mov byte [rbx + 7], 0xFF
    mov [rbx + 8], r8d          ; LBA inicio
    mov [rbx + 12], r9d         ; Total setores

    xor edi, edi
    call escrever_setor
    jmp .fim

    ; ---- GPT: procura slot livre nas entradas (LBA 2..33) ----
.criar_gpt:
    xor r11d, r11d
.gpt_slot:
    cmp r11d, GPT_QTD_ENTRADAS
    jae .erro

    mov eax, r11d
    shr eax, 2
    mov rdi, GPT_ENTRADAS_LBA
    add rdi, rax
    lea rsi, [rel buffer_gpt]
    call disco_ler_setor
    cmp rax, 1
    jne .erro

    mov eax, r11d
    and eax, 3
    shl eax, 7
    lea rbx, [rel buffer_gpt + rax]

    mov rax, [rbx]
    or rax, [rbx + 8]
    test rax, rax
    jz .gpt_gravar

    inc r11d
    jmp .gpt_slot

.gpt_gravar:
    ; Copia GUID Microsoft Basic Data (16 bytes)
    push rsi
    push rdi
    push rcx
    lea rsi, [rel guid_basic_data]
    mov rdi, rbx
    mov rcx, 16
    rep movsb
    ; Copia Unique Partition GUID (16 bytes)
    lea rsi, [rel guid_fyd_disk]
    mov rcx, 16
    rep movsb
    pop rcx
    pop rdi
    pop rsi

    mov [rbx + 32], r8          ; Starting LBA
    mov rax, r8
    add rax, r9
    dec rax
    mov [rbx + 40], rax         ; Ending LBA
    mov qword [rbx + 48], 0     ; Atributos

    ; Nome UTF-16LE "FYDELIS"
    mov word [rbx + 56], 'F'
    mov word [rbx + 58], 'Y'
    mov word [rbx + 60], 'D'
    mov word [rbx + 62], 'E'
    mov word [rbx + 64], 'L'
    mov word [rbx + 66], 'I'
    mov word [rbx + 68], 'S'
    mov word [rbx + 70], 0

    mov eax, r11d
    shr eax, 2
    mov rdi, GPT_ENTRADAS_LBA
    add rdi, rax
    lea rsi, [rel buffer_gpt]
    call disco_escrever_setor
    jmp .fim

.erro:
    xor eax, eax
.fim:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbx
    ret

; ============================================================================
; APAGAR ENTRADA REAL DE PARTICAO (MBR OU GPT) POR LBA INICIAL
; ============================================================================
apagar_entrada_particao:
    push rbx
    push rcx
    push r8
    push r9

    mov r8, rdi                 ; r8 = LBA inicio

    cmp byte [rel tipo_tabela], 1
    je .apagar_gpt

    xor edi, edi
    call ler_setor
    cmp rax, 1
    jne .erro

    xor ecx, ecx
.mbr_busca:
    cmp ecx, 4
    jae .erro
    mov rax, rcx
    shl rax, 4
    lea rbx, [rel buffer_setor + MBR_PARTICAO_OFFSET + rax]
    mov eax, [rbx + 8]
    cmp rax, r8
    je .mbr_zera
    inc ecx
    jmp .mbr_busca

.mbr_zera:
    mov qword [rbx], 0
    mov qword [rbx + 8], 0
    xor edi, edi
    call escrever_setor
    jmp .fim

.apagar_gpt:
    xor r9d, r9d
.gpt_busca:
    cmp r9d, GPT_QTD_ENTRADAS
    jae .erro
    mov eax, r9d
    shr eax, 2
    mov rdi, GPT_ENTRADAS_LBA
    add rdi, rax
    lea rsi, [rel buffer_gpt]
    call disco_ler_setor
    cmp rax, 1
    jne .erro

    mov eax, r9d
    and eax, 3
    shl eax, 7
    lea rbx, [rel buffer_gpt + rax]
    cmp [rbx + 32], r8
    je .gpt_zera
    inc r9d
    jmp .gpt_busca

.gpt_zera:
    push rdi
    push rcx
    mov rdi, rbx
    mov rcx, 128 / 8
    xor eax, eax
    rep stosq
    pop rcx
    pop rdi

    mov eax, r9d
    shr eax, 2
    mov rdi, GPT_ENTRADAS_LBA
    add rdi, rax
    lea rsi, [rel buffer_gpt]
    call disco_escrever_setor
    jmp .fim

.erro:
    xor eax, eax
.fim:
    pop r9
    pop r8
    pop rcx
    pop rbx
    ret

; ============================================================================
; FORMATAR PARTICAO REAL EM FAT32 NO DISCO
; Entrada: RDI = LBA inicial da particao, RSI = tamanho da particao em setores
; Saida:   RAX = 1 sucesso, 0 falha
; ============================================================================
formatar_fat32:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    mov r8, rdi                 ; r8 = LBA inicio da particao
    mov r9, rsi                 ; r9 = total de setores na particao
    cmp r9, 1024                ; minimo ~512 KB para FAT32 valido
    jb .erro

    ; Calcula setores por FAT: ceil((total_setores / 8) * 4 / 512) ~= total_setores / 1024 + 8
    mov rax, r9
    shr rax, 10
    add rax, 16
    mov r10, rax                ; r10 = setores_por_fat

    ; 1. Monta VBR (Boot Sector FAT32) em buffer_setor
    lea rdi, [rel buffer_setor]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq

    mov byte [rel buffer_setor + 0], 0xEB
    mov byte [rel buffer_setor + 1], 0x58
    mov byte [rel buffer_setor + 2], 0x90

    ; OEM Name "FYDELIS "
    lea rsi, [rel fat32_oem]
    lea rdi, [rel buffer_setor + 3]
    mov rcx, 8
    rep movsb

    mov word [rel buffer_setor + 11], 512     ; Bytes por setor
    mov byte [rel buffer_setor + 13], 8       ; Setores por cluster (4 KB)
    mov word [rel buffer_setor + 14], 32      ; Setores reservados
    mov byte [rel buffer_setor + 16], 2       ; Numero de FATs
    mov word [rel buffer_setor + 17], 0       ; Root entries (0 em FAT32)
    mov word [rel buffer_setor + 19], 0       ; Total setores 16-bit (0 em FAT32)
    mov byte [rel buffer_setor + 21], 0xF8    ; Media descriptor (disco fixo)
    mov word [rel buffer_setor + 22], 0       ; Setores por FAT 16-bit (0)
    mov word [rel buffer_setor + 24], 63      ; Setores por trilha
    mov word [rel buffer_setor + 26], 255     ; Cabecas
    mov [rel buffer_setor + 28], r8d          ; Hidden sectors (LBA inicio)
    mov [rel buffer_setor + 32], r9d          ; Total setores 32-bit
    mov [rel buffer_setor + 36], r10d         ; Setores por FAT 32-bit
    mov word [rel buffer_setor + 40], 0       ; Flags
    mov word [rel buffer_setor + 42], 0       ; Versao FAT32 (0.0)
    mov dword [rel buffer_setor + 44], 2      ; Cluster raiz = 2
    mov word [rel buffer_setor + 48], 1       ; Setor FSInfo = 1
    mov word [rel buffer_setor + 50], 6       ; Backup boot sector = 6
    mov byte [rel buffer_setor + 64], 0x80    ; Drive BIOS
    mov byte [rel buffer_setor + 66], 0x29    ; Boot signature estendida
    mov dword [rel buffer_setor + 67], 0x20261119 ; Volume Serial ID

    lea rsi, [rel fat32_label]
    lea rdi, [rel buffer_setor + 71]
    mov rcx, 11
    rep movsb

    lea rsi, [rel fat32_fstype]
    lea rdi, [rel buffer_setor + 82]
    mov rcx, 8
    rep movsb

    mov word [rel buffer_setor + 510], MBR_ASSINATURA

    ; Grava VBR no setor 0 da particao e backup no setor 6
    mov rdi, r8
    call escrever_setor
    cmp rax, 1
    jne .erro

    mov rdi, r8
    add rdi, 6
    call escrever_setor
    cmp rax, 1
    jne .erro

    ; 2. Monta setor FSInfo (setor 1 da particao)
    lea rdi, [rel buffer_setor]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq
    mov dword [rel buffer_setor + 0], 0x41615252
    mov dword [rel buffer_setor + 484], 0x61417272
    mov dword [rel buffer_setor + 488], 0xFFFFFFFF
    mov dword [rel buffer_setor + 492], 3
    mov word [rel buffer_setor + 510], MBR_ASSINATURA

    mov rdi, r8
    inc rdi
    call escrever_setor
    cmp rax, 1
    jne .erro

    ; 3. Zera FAT1, FAT2 e o cluster raiz (cluster 2)
    lea rdi, [rel buffer_zero]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq

    mov r11, r10
    shl r11, 1
    add r11, 8                  ; total setores a zerar = 2 * setores_fat + 8 (cluster 2)
    xor ecx, ecx
.zera_fats_loop:
    cmp rcx, r11
    jae .escreve_fat_inicial
    push rcx
    mov rdi, r8
    add rdi, 32
    add rdi, rcx
    lea rsi, [rel buffer_zero]
    call disco_escrever_setor
    pop rcx
    cmp rax, 1
    jne .erro
    inc rcx
    jmp .zera_fats_loop

    ; 4. Inicializa entradas 0, 1 e 2 (cluster raiz) na FAT1 e FAT2
.escreve_fat_inicial:
    lea rdi, [rel buffer_setor]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq
    mov dword [rel buffer_setor + 0], 0x0FFFFFF8  ; Media type
    mov dword [rel buffer_setor + 4], 0x0FFFFFFF  ; EOC
    mov dword [rel buffer_setor + 8], 0x0FFFFFFF  ; Cluster 2 (raiz) = EOC

    ; Grava inicio da FAT1 (LBA + 32)
    mov rdi, r8
    add rdi, 32
    call escrever_setor
    cmp rax, 1
    jne .erro

    ; Grava inicio da FAT2 (LBA + 32 + setores_por_fat)
    mov rdi, r8
    add rdi, 32
    add rdi, r10
    call escrever_setor
    cmp rax, 1
    jne .erro

    call flush_disco
    mov rax, 1
    jmp .fim

.erro:
    xor eax, eax
.fim:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

formatar_exfat:
    ; Redireciona para formatacao FAT32 real ate driver exFAT dedicado
    call formatar_fat32
    ret

; ============================================================================
; INICIALIZAR MBR REAL NO DISCO (LBA 0)
; ============================================================================
inicializar_mbr:
    push rdi
    push rcx

    lea rdi, [rel buffer_setor]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq
    mov word [rel buffer_setor + 510], MBR_ASSINATURA

    xor edi, edi
    call escrever_setor

    pop rcx
    pop rdi
    ret

; ============================================================================
; INICIALIZAR TABELA GPT REAL NO DISCO (Protective MBR LBA 0 + Header LBA 1 + Entradas)
; ============================================================================
escrever_cabecalho_gpt:
    push rbx
    push rcx
    push rsi
    push rdi
    push r8

    mov r8, [rel tamanho_disco_setores]
    cmp r8, 4096
    jb .erro

    ; 1. Protective MBR em LBA 0 (entrada tipo 0xEE cobrindo todo o disco)
    lea rdi, [rel buffer_setor]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq

    lea rbx, [rel buffer_setor + MBR_PARTICAO_OFFSET]
    mov byte [rbx + 1], 0x00
    mov byte [rbx + 2], 0x02
    mov byte [rbx + 3], 0x00
    mov byte [rbx + 4], MBR_TIPO_GPT_PROTETOR
    mov byte [rbx + 5], 0xFF
    mov byte [rbx + 6], 0xFF
    mov byte [rbx + 7], 0xFF
    mov dword [rbx + 8], 1
    mov dword [rbx + 12], 0xFFFFFFFF
    mov word [rel buffer_setor + 510], MBR_ASSINATURA

    xor edi, edi
    call escrever_setor
    cmp rax, 1
    jne .erro

    ; 2. Zera setores de entradas GPT (LBA 2..33)
    lea rdi, [rel buffer_zero]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq

    mov ecx, 2
.zera_gpt_ents:
    cmp ecx, 34
    jae .escreve_hdr
    push rcx
    mov edi, ecx
    lea rsi, [rel buffer_zero]
    call disco_escrever_setor
    pop rcx
    cmp rax, 1
    jne .erro
    inc ecx
    jmp .zera_gpt_ents

    ; 3. Grava GPT Header em LBA 1
.escreve_hdr:
    lea rdi, [rel buffer_setor]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq

    lea rsi, [rel gpt_magic]
    lea rdi, [rel buffer_setor + 0]
    mov rcx, 8
    rep movsb

    mov dword [rel buffer_setor + 8], 0x00010000    ; Revisao 1.0
    mov dword [rel buffer_setor + 12], 92           ; Header size
    mov qword [rel buffer_setor + 24], 1            ; Current LBA = 1
    mov rax, r8
    dec rax
    mov [rel buffer_setor + 32], rax                ; Backup LBA = ultimo setor
    mov qword [rel buffer_setor + 40], 34           ; First usable LBA
    mov rax, r8
    sub rax, 34
    mov [rel buffer_setor + 48], rax                ; Last usable LBA

    lea rsi, [rel guid_fyd_disk]
    lea rdi, [rel buffer_setor + 56]
    mov rcx, 16
    rep movsb

    mov qword [rel buffer_setor + 72], 2            ; Partition entries LBA = 2
    mov dword [rel buffer_setor + 80], 128          ; Num entries
    mov dword [rel buffer_setor + 84], 128          ; Size of entry

    mov rdi, GPT_CABECALHO_LBA
    call escrever_setor
    jmp .fim

.erro:
    xor eax, eax
.fim:
    pop r8
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret
