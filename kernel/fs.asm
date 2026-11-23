; ============================================================================
; FS.ASM — DRIVER FAT32 REAL + DETECCAO NATIVA MBR & GPT + VFS EM ARVORE
; Leitura · Escrita · Diretorios · Arquivos · Sem Simulacao
; FydelisTech OS v4.2 · Salvador • Bahia
; ============================================================================
BITS 64
default rel

%include "fydelterm.inc"

; ========== CONSTANTES MBR / GPT ==========
MBR_SIG_OFFSET            equ 510
MBR_ASSINATURA            equ 0xAA55
MBR_PART_TABELA           equ 446
MBR_PART_TAMANHO          equ 16
MBR_PART_TIPO             equ 4
MBR_PART_LBA_INICIO       equ 8

MBR_TIPO_FAT32_CHS        equ 0x0B
MBR_TIPO_FAT32_LBA        equ 0x0C
MBR_TIPO_GPT_PROTETOR     equ 0xEE

GPT_HDR_ASSINATURA        equ 0         ; "EFI PART" (8 bytes)
GPT_HDR_PART_LBA          equ 72        ; QWORD: LBA inicial da tabela de particoes
GPT_HDR_NUM_ENTS          equ 80        ; DWORD: numero de entradas
GPT_HDR_TAM_ENT           equ 84        ; DWORD: tamanho de cada entrada (geralmente 128)
GPT_ENT_LBA_INICIO        equ 32        ; QWORD: Starting LBA da particao
GPT_ENT_LBA_FIM           equ 40        ; QWORD: Ending LBA da particao

; ========== CONSTANTES FAT32 (BPB) ==========
FAT_BPB_BYTES_SETOR       equ 11
FAT_BPB_SETORES_CLUSTER   equ 13
FAT_BPB_RESERVADOS        equ 14
FAT_BPB_NUM_FATS          equ 16
FAT32_BPB_SETORES_FAT     equ 36
FAT32_BPB_CLUSTER_RAIZ    equ 44
FAT32_BPB_ASSINATURA_FS   equ 82        ; "FAT32   "

; Entrada de Diretorio (32 bytes)
FAT_ENTRADA_NOME          equ 0
FAT_ENTRADA_EXT           equ 8
FAT_ENTRADA_ATRIB         equ 11
FAT_ENTRADA_CLUSTER_ALTO  equ 20
FAT_ENTRADA_CLUSTER_BAIXO equ 26
FAT_ENTRADA_TAMANHO       equ 28

; Atributos
FAT_ATRIB_LEITURA         equ 0x01
FAT_ATRIB_ESCONDIDO       equ 0x02
FAT_ATRIB_SISTEMA         equ 0x04
FAT_ATRIB_VOLUME          equ 0x08
FAT_ATRIB_DIRETORIO       equ 0x10
FAT_ATRIB_ARQUIVO         equ 0x20
FAT_ATRIB_LFN             equ 0x0F

; Marcadores
FAT_ENTRADA_LIVRE         equ 0xE5
FAT_ENTRADA_FIM           equ 0x00
FAT_CLUSTER_FIM           equ 0x0FFFFFF8
FAT_CLUSTER_INVALIDO      equ 0x0FFFFFF7

; ========== EXTERNAIS ==========
extern disco_ler_setor, disco_escrever_setor
extern print_string, print_newline, print_char

; ========== EXPORTACOES GLOBAIS ==========
global fs_inicializar
global fs_listar_dir
global fs_criar_pasta
global fs_gravar_arquivo
global salvar_arquivo
global fs_ler_arquivo
global carregar_arquivo
global fs_existe
global fs_remover
global fs_copiar
global fs_procurar
global fs_obter_caminho_atual
global fs_definir_caminho_atual
global fs_obter_particao_lba
global fs_obter_tipo_tabela

; ========== DADOS DO SISTEMA DE ARQUIVOS ==========
section .data
gpt_assinatura_magic:     db "EFI PART"
fat32_assinatura_magic:   db "FAT32"

; GUIDs validos de particao de dados/EFI no GPT (16 bytes cada, mixed-endian)
; EFI System Partition: C12A7328-F81F-11D2-BA4B-00A0C93EC93B
guid_esp:
    db 0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11
    db 0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B

; Microsoft Basic Data (FAT32/NTFS): EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
guid_basic_data:
    db 0xA2, 0xA0, 0xD0, 0xEB, 0xE5, 0xB9, 0x33, 0x44
    db 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7

section .bss
align 512
setor_buffer:             resb 512
gpt_buffer:               resb 512
fat_buffer:               resb 512
dir_buffer:               resb 4096
arq_setor_buf:            resb 512
zero_setor_buf:           resb 512
seg_token_buf:            resb 64
nome_83_tmp:              resb 12

fat_inicializado:         resb 1
tipo_tabela_particao:     resb 1      ; 0 = invalido, 1 = MBR, 2 = GPT, 3 = Superfloppy (LBA 0)
particao_lba_inicio:      resq 1      ; LBA inicial da particao FAT32 montada
bytes_setor:              resw 1
setores_cluster:          resb 1
num_fats:                 resb 1
setores_fat:              resd 1
cluster_raiz:             resd 1
setor_dados_relativo:     resd 1      ; relativo ao inicio da particao
proximo_cluster_livre:    resd 1

; Navegacao
caminho_atual:            resb 256
cluster_atual:            resd 1

section .text

; ============================================================================
; DETECCAO DE PARTICAO MBR / GPT (retorna rax = LBA inicial ou -1 em erro)
; ============================================================================
detectar_particao_fat32:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    ; 1. Ler LBA 0 (MBR ou VBR)
    xor rdi, rdi
    lea rsi, [rel setor_buffer]
    call disco_ler_setor
    test rax, rax
    jz .erro_part

    ; Verifica assinatura 0xAA55
    cmp word [rel setor_buffer + MBR_SIG_OFFSET], MBR_ASSINATURA
    jne .erro_part

    ; 2. Verificar se ha entrada GPT protetora (tipo 0xEE) nas 4 entradas MBR
    lea rbx, [rel setor_buffer + MBR_PART_TABELA]
    xor ecx, ecx
.checa_gpt_loop:
    cmp ecx, 4
    jae .checa_mbr
    mov al, [rbx + MBR_PART_TIPO]
    cmp al, MBR_TIPO_GPT_PROTETOR
    je .ler_gpt
    add rbx, MBR_PART_TAMANHO
    inc ecx
    jmp .checa_gpt_loop

    ; 3. Processar tabela GPT (LBA 1 = Header, LBA 2+ = Entradas)
.ler_gpt:
    mov rdi, 1
    lea rsi, [rel gpt_buffer]
    call disco_ler_setor
    test rax, rax
    jz .erro_part

    ; Confere assinatura "EFI PART"
    lea rsi, [rel gpt_buffer + GPT_HDR_ASSINATURA]
    lea rdi, [rel gpt_assinatura_magic]
    mov rcx, 8
    repe cmpsb
    jne .erro_part

    mov r12, [rel gpt_buffer + GPT_HDR_PART_LBA]   ; LBA da tabela de particoes GPT
    mov r13d, [rel gpt_buffer + GPT_HDR_NUM_ENTS]  ; total de entradas (geralmente 128)
    cmp r13d, 128
    jbe .gpt_ents_ok
    mov r13d, 128
.gpt_ents_ok:
    xor ebx, ebx                ; indice da entrada GPT atual

.gpt_varrer_entradas:
    cmp ebx, r13d
    jae .erro_part

    ; Cada setor de 512 bytes contem 4 entradas GPT de 128 bytes
    mov eax, ebx
    shr eax, 2                  ; setor relativo = entrada / 4
    mov rdi, r12
    add rdi, rax
    lea rsi, [rel gpt_buffer]
    call disco_ler_setor
    test rax, rax
    jz .erro_part

    mov eax, ebx
    and eax, 3
    shl eax, 7                  ; offset dentro do setor = (entrada % 4) * 128
    lea rdx, [rel gpt_buffer]
    add rdx, rax                ; rdx = ponteiro para entrada GPT atual

    ; Verifica se GUID nao e nulo (starting LBA > 0)
    mov rax, [rdx + GPT_ENT_LBA_INICIO]
    test rax, rax
    jz .gpt_prox_ent

    ; Compara GUID com EFI System Partition ou Microsoft Basic Data
    push rdx
    mov rsi, rdx
    lea rdi, [rel guid_esp]
    mov rcx, 16
    repe cmpsb
    pop rdx
    je .gpt_achou

    push rdx
    mov rsi, rdx
    lea rdi, [rel guid_basic_data]
    mov rcx, 16
    repe cmpsb
    pop rdx
    je .gpt_achou

.gpt_prox_ent:
    inc ebx
    jmp .gpt_varrer_entradas

.gpt_achou:
    mov rax, [rdx + GPT_ENT_LBA_INICIO]
    mov byte [rel tipo_tabela_particao], 2
    jmp .fim_part

    ; 4. Processar tabela MBR classica (4 entradas de 16 bytes)
.checa_mbr:
    lea rbx, [rel setor_buffer + MBR_PART_TABELA]
    xor ecx, ecx
.mbr_loop:
    cmp ecx, 4
    jae .checa_superfloppy
    mov al, [rbx + MBR_PART_TIPO]
    cmp al, MBR_TIPO_FAT32_LBA
    je .mbr_achou
    cmp al, MBR_TIPO_FAT32_CHS
    je .mbr_achou
    add rbx, MBR_PART_TAMANHO
    inc ecx
    jmp .mbr_loop

.mbr_achou:
    mov eax, [rbx + MBR_PART_LBA_INICIO]
    test eax, eax
    jz .checa_superfloppy
    mov byte [rel tipo_tabela_particao], 1
    jmp .fim_part

    ; 5. Fallback Superfloppy (volume FAT32 direto no LBA 0 sem MBR/GPT)
.checa_superfloppy:
    lea rsi, [rel setor_buffer + FAT32_BPB_ASSINATURA_FS]
    lea rdi, [rel fat32_assinatura_magic]
    mov rcx, 5
    repe cmpsb
    jne .erro_part

    xor eax, eax
    mov byte [rel tipo_tabela_particao], 3
    jmp .fim_part

.erro_part:
    mov byte [rel tipo_tabela_particao], 0
    mov rax, -1

.fim_part:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================================
; INICIALIZACAO DO SISTEMA DE ARQUIVOS FAT32 REAL
; ============================================================================
fs_inicializar:
    cmp byte [rel fat_inicializado], 1
    je .pronto

    call detectar_particao_fat32
    cmp rax, 0
    jl .erro
    mov [rel particao_lba_inicio], rax

    ; Ler Boot Sector (VBR) da particao FAT32 encontrada
    mov rdi, [rel particao_lba_inicio]
    lea rsi, [rel setor_buffer]
    call disco_ler_setor
    test rax, rax
    jz .erro

    ; Validar assinatura 0xAA55 e string "FAT32"
    cmp word [rel setor_buffer + MBR_SIG_OFFSET], MBR_ASSINATURA
    jne .erro

    lea rsi, [rel setor_buffer + FAT32_BPB_ASSINATURA_FS]
    lea rdi, [rel fat32_assinatura_magic]
    mov rcx, 5
    repe cmpsb
    jne .erro

    ; Extrair parametros do BPB
    mov ax, [rel setor_buffer + FAT_BPB_BYTES_SETOR]
    cmp ax, 512
    jne .erro
    mov [rel bytes_setor], ax

    mov al, [rel setor_buffer + FAT_BPB_SETORES_CLUSTER]
    test al, al
    jz .erro
    mov [rel setores_cluster], al

    mov al, [rel setor_buffer + FAT_BPB_NUM_FATS]
    test al, al
    jz .erro
    mov [rel num_fats], al

    mov eax, [rel setor_buffer + FAT32_BPB_SETORES_FAT]
    test eax, eax
    jz .erro
    mov [rel setores_fat], eax

    mov eax, [rel setor_buffer + FAT32_BPB_CLUSTER_RAIZ]
    cmp eax, 2
    jb .erro
    mov [rel cluster_raiz], eax
    mov [rel cluster_atual], eax

    ; Calcular inicio da area de dados (relativo ao inicio da particao):
    ; reservados + (num_fats * setores_fat)
    movzx eax, byte [rel num_fats]
    mul dword [rel setores_fat]
    movzx ecx, word [rel setor_buffer + FAT_BPB_RESERVADOS]
    add eax, ecx
    mov [rel setor_dados_relativo], eax

    ; Caminho inicial = raiz "/"
    mov byte [rel caminho_atual], '/'
    mov byte [rel caminho_atual + 1], 0
    mov dword [rel proximo_cluster_livre], 2

    call encontrar_proximo_cluster_livre

    mov byte [rel fat_inicializado], 1
.pronto:
    mov rax, 1
    ret
.erro:
    xor rax, rax
    ret

fs_obter_particao_lba:
    mov rax, [rel particao_lba_inicio]
    ret

fs_obter_tipo_tabela:
    xor eax, eax
    mov al, [rel tipo_tabela_particao]
    ret

; ========== CONVERSAO CLUSTER -> SETOR LBA ABSOLUTO ==========
cluster_para_setor:
    ; rdi = cluster -> rax = LBA absoluto no disco
    sub rdi, 2
    movzx rax, byte [rel setores_cluster]
    mul rdi
    mov ecx, [rel setor_dados_relativo]
    add rax, rcx
    add rax, [rel particao_lba_inicio]
    ret

; ========== LER PROXIMO CLUSTER NA CADEIA FAT32 ==========
ler_proximo_cluster:
    ; rdi = cluster atual -> rax = proximo cluster (0 em erro)
    push rbx
    push rcx
    push rdx

    mov rax, rdi
    shl rax, 2                  ; offset em bytes na FAT = cluster * 4
    movzx rcx, word [rel bytes_setor]
    xor rdx, rdx
    div rcx                     ; rax = setor relativo da FAT, rdx = offset no setor

    movzx rcx, word [rel setor_buffer + FAT_BPB_RESERVADOS]
    add rax, rcx
    add rax, [rel particao_lba_inicio]
    mov rbx, rdx                ; salva offset dentro do setor

    mov rdi, rax
    lea rsi, [rel fat_buffer]
    call disco_ler_setor
    test rax, rax
    jz .erro_ler

    mov eax, [rel fat_buffer + rbx]
    and eax, 0x0FFFFFFF
    jmp .fim_ler
.erro_ler:
    xor eax, eax
.fim_ler:
    pop rdx
    pop rcx
    pop rbx
    ret

; ========== ESCREVER ENTRADA NA FAT (ATUALIZA TODAS AS COPIAS FAT) ==========
escrever_proximo_cluster:
    ; rdi = cluster, rsi = valor (ex: proximo cluster, FAT_CLUSTER_FIM ou 0)
    push rbx
    push rcx
    push rdx
    push r8
    push r9

    mov r8d, esi
    mov rax, rdi
    shl rax, 2
    movzx rcx, word [rel bytes_setor]
    xor rdx, rdx
    div rcx                     ; rax = setor relativo da FAT, rdx = offset no setor
    mov r9, rdx

    movzx rcx, word [rel setor_buffer + FAT_BPB_RESERVADOS]
    add rax, rcx
    add rax, [rel particao_lba_inicio]
    mov rbx, rax                ; rbx = LBA absoluto na FAT #0

    mov rdi, rbx
    lea rsi, [rel fat_buffer]
    call disco_ler_setor
    test rax, rax
    jz .fim_esc

    ; Preserva os 4 bits superiores reservados pela especificacao FAT32
    mov eax, [rel fat_buffer + r9]
    and eax, 0xF0000000
    and r8d, 0x0FFFFFFF
    or eax, r8d
    mov [rel fat_buffer + r9], eax

    ; Grava em todas as copias da FAT (FAT1, FAT2...)
    movzx rcx, byte [rel num_fats]
.loop_fats:
    push rcx
    mov rdi, rbx
    lea rsi, [rel fat_buffer]
    call disco_escrever_setor
    pop rcx
    mov eax, [rel setores_fat]
    add rbx, rax
    dec rcx
    jnz .loop_fats

.fim_esc:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ========== ENCONTRAR PROXIMO CLUSTER LIVRE ==========
encontrar_proximo_cluster_livre:
    push rbx
    mov ebx, [rel proximo_cluster_livre]
    cmp ebx, 2
    jae .buscar
    mov ebx, 2

.buscar:
    mov edi, ebx
    call ler_proximo_cluster
    test eax, eax
    jz .achou
    inc ebx
    cmp ebx, 0x0FFFFFF0
    jb .buscar

    mov ebx, 2
.buscar_inicio:
    cmp ebx, [rel proximo_cluster_livre]
    jae .cheio
    mov edi, ebx
    call ler_proximo_cluster
    test eax, eax
    jz .achou
    inc ebx
    jmp .buscar_inicio

.cheio:
    xor eax, eax
    jmp .fim
.achou:
    mov eax, ebx
    inc ebx
    mov [rel proximo_cluster_livre], ebx
.fim:
    pop rbx
    ret

; ========== LER DIRETORIO INTEIRO PARA DIR_BUFFER ==========
ler_diretorio:
    ; rdi = cluster inicial do diretorio -> rax = 1 ok, 0 erro
    push rbp
    push rbx
    push rcx
    push rdx
    push rsi

    mov rbp, rdi
    lea rbx, [rel dir_buffer]

    push rdi
    lea rdi, [rel dir_buffer]
    mov rcx, 4096 / 8
    xor eax, eax
    rep stosq
    pop rdi

    xor rdx, rdx

.loop_cluster:
    cmp rbp, 2
    jb .ok
    cmp rbp, FAT_CLUSTER_FIM
    jae .ok
    cmp rdx, 4096
    jae .ok

    mov rdi, rbp
    call cluster_para_setor
    mov rdi, rax
    movzx rcx, byte [rel setores_cluster]
    xor rsi, rsi

.loop_setor:
    cmp rsi, rcx
    jae .prox_cluster
    cmp rdx, 4096
    jae .ok

    push rdi
    push rsi
    push rcx
    push rdx
    add rdi, rsi
    lea rsi, [rbx + rdx]
    call disco_ler_setor
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    test rax, rax
    jz .erro

    add rdx, 512
    inc rsi
    jmp .loop_setor

.prox_cluster:
    mov rdi, rbp
    call ler_proximo_cluster
    mov rbp, rax
    jmp .loop_cluster

.ok:
    mov rax, 1
    jmp .sair
.erro:
    xor rax, rax
.sair:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ========== GRAVAR DIR_BUFFER DE VOLTA NO DISCO ==========
escrever_diretorio:
    ; rdi = cluster inicial do diretorio -> rax = 1 ok, 0 erro
    push rbp
    push rbx
    push rcx
    push rdx
    push rsi

    mov rbp, rdi
    lea rbx, [rel dir_buffer]
    xor rdx, rdx

.loop_cluster:
    cmp rbp, 2
    jb .ok
    cmp rbp, FAT_CLUSTER_FIM
    jae .ok
    cmp rdx, 4096
    jae .ok

    mov rdi, rbp
    call cluster_para_setor
    mov rdi, rax
    movzx rcx, byte [rel setores_cluster]
    xor rsi, rsi

.loop_setor:
    cmp rsi, rcx
    jae .prox_cluster
    cmp rdx, 4096
    jae .ok

    push rdi
    push rsi
    push rcx
    push rdx
    add rdi, rsi
    lea rsi, [rbx + rdx]
    call disco_escrever_setor
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    test rax, rax
    jz .erro

    add rdx, 512
    inc rsi
    jmp .loop_setor

.prox_cluster:
    mov rdi, rbp
    call ler_proximo_cluster
    mov rbp, rax
    jmp .loop_cluster

.ok:
    mov rax, 1
    jmp .sair
.erro:
    xor rax, rax
.sair:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ========== ZERAR SETORES DE UM CLUSTER NOVO ==========
zerar_cluster:
    ; rdi = cluster -> rax = 1 ok, 0 erro
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi
    lea rdi, [rel zero_setor_buf]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq

    mov rdi, rbx
    call cluster_para_setor
    mov rbx, rax
    movzx rcx, byte [rel setores_cluster]
    xor rsi, rsi

.loop:
    cmp rsi, rcx
    jae .ok
    push rcx
    push rsi
    mov rdi, rbx
    add rdi, rsi
    lea rsi, [rel zero_setor_buf]
    call disco_escrever_setor
    pop rsi
    pop rcx
    test rax, rax
    jz .erro
    inc rsi
    jmp .loop

.ok:
    mov rax, 1
    jmp .sair
.erro:
    xor rax, rax
.sair:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; ========== FORMATAR NOME PARA PADRAO FAT 8.3 (MAIUSCULO) ==========
formatar_nome_entrada:
    ; rdi = destino (11 bytes), rsi = nome ASCII (terminado em 0 ou '/')
    push rax
    push rcx
    push rdx
    push rsi
    push rdi

    mov rcx, 11
    mov al, ' '
    rep stosb
    pop rdi
    push rdi

    xor rdx, rdx
.base:
    mov al, [rsi]
    test al, al
    jz .fim
    cmp al, '/'
    je .fim
    cmp al, '.'
    je .ponto
    cmp rdx, 8
    jae .pula_restante_base

    cmp al, 'a'
    jb .store_base
    cmp al, 'z'
    ja .store_base
    sub al, 32
.store_base:
    mov [rdi + rdx], al
    inc rdx
    inc rsi
    jmp .base

.pula_restante_base:
    mov al, [rsi]
    test al, al
    jz .fim
    cmp al, '/'
    je .fim
    cmp al, '.'
    je .ponto
    inc rsi
    jmp .pula_restante_base

.ponto:
    inc rsi
    xor rdx, rdx
.ext:
    mov al, [rsi]
    test al, al
    jz .fim
    cmp al, '/'
    je .fim
    cmp rdx, 3
    jae .fim

    cmp al, 'a'
    jb .store_ext
    cmp al, 'z'
    ja .store_ext
    sub al, 32
.store_ext:
    mov [rdi + 8 + rdx], al
    inc rdx
    inc rsi
    jmp .ext

.fim:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; ========== PROCURAR ENTRADA 8.3 NO DIRETORIO ==========
procurar_entrada:
    ; rdi = cluster dir, rsi = nome 8.3 (11 bytes) -> rax = ponteiro em dir_buffer ou 0
    push rbx
    push rbp
    push rcx
    push rdx

    mov rbp, rsi
    call ler_diretorio
    test rax, rax
    jz .nao_achou

    xor rcx, rcx
.loop:
    cmp rcx, 4096
    jae .nao_achou

    lea rbx, [rel dir_buffer + rcx]
    cmp byte [rbx + FAT_ENTRADA_NOME], FAT_ENTRADA_FIM
    je .nao_achou
    cmp byte [rbx + FAT_ENTRADA_NOME], FAT_ENTRADA_LIVRE
    je .prox

    mov al, [rbx + FAT_ENTRADA_ATRIB]
    cmp al, FAT_ATRIB_LFN
    je .prox

    push rcx
    push rsi
    push rdi
    mov rdi, rbx
    mov rsi, rbp
    mov rcx, 11
    repe cmpsb
    pop rdi
    pop rsi
    pop rcx
    je .achou

.prox:
    add rcx, 32
    jmp .loop

.achou:
    mov rax, rbx
    jmp .sair
.nao_achou:
    xor rax, rax
.sair:
    pop rdx
    pop rcx
    pop rbp
    pop rbx
    ret

; ========== PROCURAR SLOT LIVRE NO DIRETORIO ==========
procurar_entrada_livre:
    ; rdi = cluster dir -> rax = ponteiro em dir_buffer ou 0
    push rcx
    call ler_diretorio
    test rax, rax
    jz .sem_slot

    xor rcx, rcx
.loop:
    cmp rcx, 4096
    jae .sem_slot
    lea rax, [rel dir_buffer + rcx]
    cmp byte [rax], FAT_ENTRADA_FIM
    je .ok
    cmp byte [rax], FAT_ENTRADA_LIVRE
    je .ok
    add rcx, 32
    jmp .loop

.sem_slot:
    xor rax, rax
.ok:
    pop rcx
    ret

; ========== RESOLVER CAMINHO EM ARVORE ==========
; rdi = caminho ("/fyd/config/sistema.fcfg" ou "relativo/arq")
; rsi = criar_pastas_intermediarias (1 = cria, 0 = somente leitura)
; Retorna: rax = cluster do diretorio pai (0 erro), rdx = ponteiro ultimo segmento
fs_resolver_caminho_pai:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi
    mov r13d, esi

    test r12, r12
    jz .erro

    call fs_inicializar
    test rax, rax
    jz .erro

    cmp byte [r12], '/'
    jne .usa_atual
    mov r14d, [rel cluster_raiz]
.pula_barras_ini:
    cmp byte [r12], '/'
    jne .inicio_pronto
    inc r12
    jmp .pula_barras_ini

.usa_atual:
    mov r14d, [rel cluster_atual]

.inicio_pronto:
    cmp byte [r12], 0
    jne .loop_seg
    mov eax, r14d
    mov rdx, r12
    jmp .ok

.loop_seg:
    mov rsi, r12
    xor ecx, ecx
.busca_barra:
    mov al, [rsi]
    test al, al
    jz .fim_busca_barra
    cmp al, '/'
    je .achou_barra
    inc rsi
    jmp .busca_barra
.achou_barra:
    mov ecx, 1

.fim_busca_barra:
    test ecx, ecx
    jz .ultimo_seg

    lea rdi, [rel seg_token_buf]
    xor ebx, ebx
.copia_seg:
    mov al, [r12 + rbx]
    cmp al, '/'
    je .fim_copia_seg
    test al, al
    jz .fim_copia_seg
    cmp ebx, 62
    jae .avanca_seg
    mov [rdi + rbx], al
    inc rbx
.avanca_seg:
    jmp .copia_seg

.fim_copia_seg:
    mov byte [rdi + rbx], 0
    add r12, rbx
.pula_barras_meio:
    cmp byte [r12], '/'
    jne .seg_ok
    inc r12
    jmp .pula_barras_meio

.seg_ok:
    cmp byte [rel seg_token_buf], 0
    je .loop_seg

    lea rdi, [rel nome_83_tmp]
    lea rsi, [rel seg_token_buf]
    call formatar_nome_entrada

    mov edi, r14d
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jnz .seg_existe

    test r13d, r13d
    jz .erro

    push r12
    mov edi, r14d
    lea rsi, [rel nome_83_tmp]
    call criar_subpasta_em_cluster
    pop r12
    test eax, eax
    jz .erro
    mov r14d, eax
    jmp .loop_seg

.seg_existe:
    mov r15, rax
    mov al, [r15 + FAT_ENTRADA_ATRIB]
    and al, FAT_ATRIB_DIRETORIO
    jz .erro

    mov ecx, [r15 + FAT_ENTRADA_CLUSTER_ALTO]
    shl ecx, 16
    mov cx, [r15 + FAT_ENTRADA_CLUSTER_BAIXO]
    cmp ecx, 2
    jae .set_dir
    mov ecx, [rel cluster_raiz]
.set_dir:
    mov r14d, ecx
    jmp .loop_seg

.ultimo_seg:
    mov eax, r14d
    mov rdx, r12
    jmp .ok

.erro:
    xor eax, eax
    xor edx, edx
.ok:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ========== AUXILIAR: CRIAR SUBPASTA REAL EM CLUSTER PAI ==========
criar_subpasta_em_cluster:
    ; edi = cluster pai, rsi = nome 8.3 (11 bytes) -> eax = novo cluster (0 erro)
    push rbx
    push rbp
    push r12
    push r13

    mov r12d, edi
    mov r13, rsi

    mov edi, r12d
    mov rsi, r13
    call procurar_entrada
    test rax, rax
    jz .nova

    mov ecx, [rax + FAT_ENTRADA_CLUSTER_ALTO]
    shl ecx, 16
    mov cx, [rax + FAT_ENTRADA_CLUSTER_BAIXO]
    mov eax, ecx
    jmp .sair

.nova:
    call encontrar_proximo_cluster_livre
    test eax, eax
    jz .erro
    mov ebx, eax

    mov edi, ebx
    mov esi, FAT_CLUSTER_FIM
    call escrever_proximo_cluster

    mov edi, ebx
    call zerar_cluster
    test rax, rax
    jz .erro

    ; Inicializa entradas padrao "." e ".." no novo diretorio FAT32
    lea rdi, [rel dir_buffer]
    mov rcx, 4096 / 8
    xor eax, eax
    rep stosq

    ; Entrada "."
    lea rdi, [rel dir_buffer]
    mov rcx, 11
    mov al, ' '
    rep stosb
    mov byte [rel dir_buffer + 0], '.'
    mov byte [rel dir_buffer + FAT_ENTRADA_ATRIB], FAT_ATRIB_DIRETORIO
    mov [rel dir_buffer + FAT_ENTRADA_CLUSTER_BAIXO], bx
    mov eax, ebx
    shr eax, 16
    mov [rel dir_buffer + FAT_ENTRADA_CLUSTER_ALTO], ax

    ; Entrada ".."
    lea rdi, [rel dir_buffer + 32]
    mov rcx, 11
    mov al, ' '
    rep stosb
    mov word [rel dir_buffer + 32], '..'
    mov byte [rel dir_buffer + 32 + FAT_ENTRADA_ATRIB], FAT_ATRIB_DIRETORIO
    xor eax, eax
    cmp r12d, [rel cluster_raiz]
    je .pai_raiz_zero
    mov eax, r12d
.pai_raiz_zero:
    mov [rel dir_buffer + 32 + FAT_ENTRADA_CLUSTER_BAIXO], ax
    shr eax, 16
    mov [rel dir_buffer + 32 + FAT_ENTRADA_CLUSTER_ALTO], ax

    mov edi, ebx
    call escrever_diretorio
    test rax, rax
    jz .erro

    ; Adiciona entrada no diretorio pai
    mov edi, r12d
    call procurar_entrada_livre
    test rax, rax
    jz .erro
    mov rbp, rax

    push rcx
    push rsi
    push rdi
    mov rdi, rbp
    mov rsi, r13
    mov rcx, 11
    rep movsb
    pop rdi
    pop rsi
    pop rcx

    mov byte [rbp + FAT_ENTRADA_ATRIB], FAT_ATRIB_DIRETORIO
    mov dword [rbp + FAT_ENTRADA_TAMANHO], 0
    mov [rbp + FAT_ENTRADA_CLUSTER_BAIXO], bx
    mov eax, ebx
    shr eax, 16
    mov [rbp + FAT_ENTRADA_CLUSTER_ALTO], ax

    mov edi, r12d
    call escrever_diretorio
    test rax, rax
    jz .erro

    mov eax, ebx
    jmp .sair

.erro:
    xor eax, eax
.sair:
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ========== CRIAR PASTA (CAMINHO COMPLETO OU RELATIVO) ==========
fs_criar_pasta:
    ; rdi = caminho/nome -> rax = 1 ok, 0 erro
    push rbx
    push rbp

    test rdi, rdi
    jz .erro
    cmp byte [rdi], 0
    je .erro

    mov rsi, 1
    call fs_resolver_caminho_pai
    test eax, eax
    jz .erro

    mov ebx, eax
    mov rbp, rdx
.trim:
    cmp byte [rbp], '/'
    jne .nome_ok
    inc rbp
    jmp .trim
.nome_ok:
    cmp byte [rbp], 0
    je .ok

    lea rdi, [rel nome_83_tmp]
    mov rsi, rbp
    call formatar_nome_entrada

    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call criar_subpasta_em_cluster
    test eax, eax
    jz .erro

.ok:
    mov rax, 1
    jmp .sair
.erro:
    xor rax, rax
.sair:
    pop rbp
    pop rbx
    ret

; ========== VERIFICAR EXISTENCIA REAL NO FAT32 ==========
fs_existe:
    ; rdi = caminho -> rax = 1 existe, 0 nao
    push rbx
    push rbp

    test rdi, rdi
    jz .nao
    cmp byte [rdi], 0
    je .nao

    mov rsi, 0
    call fs_resolver_caminho_pai
    test eax, eax
    jz .nao

    mov ebx, eax
    mov rbp, rdx
    cmp byte [rbp], 0
    je .sim

    lea rdi, [rel nome_83_tmp]
    mov rsi, rbp
    call formatar_nome_entrada

    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jz .nao

.sim:
    mov rax, 1
    jmp .sair
.nao:
    xor rax, rax
.sair:
    pop rbp
    pop rbx
    ret

fs_procurar:
    call fs_existe
    ret

; ========== LER ARQUIVO REAL DO FAT32 ==========
; rdi = caminho, rsi = buffer, rdx = tamanho_max -> rax = bytes lidos (-1 erro)
fs_ler_arquivo:
carregar_arquivo:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi
    mov r13, rdx

    test rdi, rdi
    jz .erro
    test r12, r12
    jz .erro
    test r13, r13
    jz .erro

    mov rsi, 0
    call fs_resolver_caminho_pai
    test eax, eax
    jz .erro

    mov ebx, eax
    cmp byte [rdx], 0
    je .erro

    lea rdi, [rel nome_83_tmp]
    mov rsi, rdx
    call formatar_nome_entrada

    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jz .erro

    mov rbp, rax
    mov eax, [rbp + FAT_ENTRADA_TAMANHO]
    mov r14, rax
    cmp r14, r13
    jbe .tam_ok
    mov r14, r13
.tam_ok:

    mov ecx, [rbp + FAT_ENTRADA_CLUSTER_ALTO]
    shl rcx, 16
    mov cx, [rbp + FAT_ENTRADA_CLUSTER_BAIXO]
    mov rbx, rcx
    xor r15, r15

.loop_cluster:
    cmp r15, r14
    jae .ok
    cmp rbx, 2
    jb .ok
    cmp rbx, FAT_CLUSTER_FIM
    jae .ok

    mov rdi, rbx
    call cluster_para_setor
    mov r8, rax
    movzx r9, byte [rel setores_cluster]
    xor r10, r10

.loop_setor:
    cmp r10, r9
    jae .prox_cluster
    cmp r15, r14
    jae .ok

    push r8
    push r9
    push r10
    mov rdi, r8
    add rdi, r10
    lea rsi, [rel arq_setor_buf]
    call disco_ler_setor
    pop r10
    pop r9
    pop r8
    test rax, rax
    jz .erro

    xor rcx, rcx
.copia_bytes:
    cmp rcx, 512
    jae .prox_setor
    cmp r15, r14
    jae .ok
    mov al, [rel arq_setor_buf + rcx]
    mov [r12 + r15], al
    inc r15
    inc rcx
    jmp .copia_bytes

.prox_setor:
    inc r10
    jmp .loop_setor

.prox_cluster:
    mov rdi, rbx
    call ler_proximo_cluster
    mov rbx, rax
    jmp .loop_cluster

.ok:
    mov rax, r15
    jmp .sair
.erro:
    mov rax, -1
.sair:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ========== GRAVAR ARQUIVO REAL NO FAT32 ==========
; salvar_arquivo:    rdi = caminho, rsi = buf, rdx = len -> rax = 1 ok, 0 erro
; fs_gravar_arquivo: rdi = caminho, rsi = buf, rdx = len -> rax = bytes gravados (-1 erro)
salvar_arquivo:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi
    mov r13, rdx

    test rdi, rdi
    jz .erro
    cmp byte [rdi], 0
    je .erro
    test r13, r13
    jz .tam_ok
    test r12, r12
    jz .erro

.tam_ok:
    mov rsi, 1
    call fs_resolver_caminho_pai
    test eax, eax
    jz .erro

    mov ebx, eax
    cmp byte [rdx], 0
    je .erro

    lea rdi, [rel nome_83_tmp]
    mov rsi, rdx
    call formatar_nome_entrada

    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jnz .existente

    mov edi, ebx
    call procurar_entrada_livre
    test rax, rax
    jz .erro
    mov rbp, rax

    push rcx
    push rsi
    push rdi
    mov rdi, rbp
    lea rsi, [rel nome_83_tmp]
    mov rcx, 11
    rep movsb
    pop rdi
    pop rsi
    pop rcx
    mov byte [rbp + FAT_ENTRADA_ATRIB], FAT_ATRIB_ARQUIVO
    jmp .gravar_cadeia

.existente:
    mov rbp, rax
    mov ecx, [rbp + FAT_ENTRADA_CLUSTER_ALTO]
    shl rcx, 16
    mov cx, [rbp + FAT_ENTRADA_CLUSTER_BAIXO]
    cmp rcx, 2
    jb .gravar_cadeia
    cmp rcx, FAT_CLUSTER_FIM
    jae .gravar_cadeia

    push rbx
    mov rdi, rcx
    call liberar_cadeia
    pop rbx

    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jz .erro
    mov rbp, rax

.gravar_cadeia:
    mov [rbp + FAT_ENTRADA_TAMANHO], r13d
    mov word [rbp + FAT_ENTRADA_CLUSTER_BAIXO], 0
    mov word [rbp + FAT_ENTRADA_CLUSTER_ALTO], 0

    cmp r13, 0
    je .flush_dir

    xor r14, r14
    xor r15d, r15d

.loop_cluster:
    cmp r14, r13
    jae .fechar_cadeia

    push rbx
    push rbp
    call encontrar_proximo_cluster_livre
    pop rbp
    pop rbx
    test eax, eax
    jz .erro

    cmp r15d, 0
    jne .encadear

    mov [rbp + FAT_ENTRADA_CLUSTER_BAIXO], ax
    push rax
    shr eax, 16
    mov [rbp + FAT_ENTRADA_CLUSTER_ALTO], ax
    pop rax
    jmp .escrever_cluster

.encadear:
    push rax
    push rbx
    push rbp
    mov edi, r15d
    mov esi, eax
    call escrever_proximo_cluster
    pop rbp
    pop rbx
    pop rax

.escrever_cluster:
    mov r15d, eax
    push rbx
    push rbp
    push rax

    mov edi, eax
    call cluster_para_setor
    mov r8, rax
    movzx r9, byte [rel setores_cluster]
    xor r10, r10

.loop_setor:
    cmp r10, r9
    jae .fim_cluster

    push rcx
    push rdi
    lea rdi, [rel arq_setor_buf]
    mov rcx, 512 / 8
    xor eax, eax
    rep stosq
    pop rdi
    pop rcx

    xor rcx, rcx
.copia_setor:
    cmp rcx, 512
    jae .flush_setor
    cmp r14, r13
    jae .flush_setor
    mov al, [r12 + r14]
    mov [rel arq_setor_buf + rcx], al
    inc r14
    inc rcx
    jmp .copia_setor

.flush_setor:
    push r8
    push r9
    push r10
    mov rdi, r8
    add rdi, r10
    lea rsi, [rel arq_setor_buf]
    call disco_escrever_setor
    pop r10
    pop r9
    pop r8
    test rax, rax
    jz .erro_pop

    inc r10
    jmp .loop_setor

.fim_cluster:
    pop rax
    pop rbp
    pop rbx
    jmp .loop_cluster

.erro_pop:
    pop rax
    pop rbp
    pop rbx
    jmp .erro

.fechar_cadeia:
    cmp r15d, 0
    je .flush_dir
    mov edi, r15d
    mov esi, FAT_CLUSTER_FIM
    call escrever_proximo_cluster

.flush_dir:
    mov edi, ebx
    call escrever_diretorio
    test rax, rax
    jz .erro

    mov rax, 1
    jmp .sair

.erro:
    xor rax, rax
.sair:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

fs_gravar_arquivo:
    push rdx
    call salvar_arquivo
    pop rdx
    cmp rax, 1
    je .ok
    mov rax, -1
    ret
.ok:
    mov rax, rdx
    ret

; ========== LISTAR CONTEUDO DO DIRETORIO ==========
fs_listar_dir:
    push rbx
    push rcx
    push rsi

    call fs_inicializar
    test rax, rax
    jz .erro

    mov edi, [rel cluster_atual]
    call ler_diretorio
    test rax, rax
    jz .erro

    xor rcx, rcx
.loop:
    cmp rcx, 4096
    jae .fim

    lea rbx, [rel dir_buffer + rcx]
    cmp byte [rbx + FAT_ENTRADA_NOME], FAT_ENTRADA_FIM
    je .fim
    cmp byte [rbx + FAT_ENTRADA_NOME], FAT_ENTRADA_LIVRE
    je .prox

    mov al, [rbx + FAT_ENTRADA_ATRIB]
    cmp al, FAT_ATRIB_LFN
    je .prox

    mov rsi, rbx
    call print_nome_entrada

    mov al, [rbx + FAT_ENTRADA_ATRIB]
    and al, FAT_ATRIB_DIRETORIO
    jz .arq
    mov al, ' '
    call print_char
    mov al, '<'
    call print_char
    mov al, '>'
    call print_char
.arq:
    call print_newline

.prox:
    add rcx, 32
    jmp .loop

.fim:
    mov rax, 1
    jmp .sair
.erro:
    xor rax, rax
.sair:
    pop rsi
    pop rcx
    pop rbx
    ret

print_nome_entrada:
    push rax
    push rcx
    push rsi

    mov rcx, 8
.nome:
    lodsb
    cmp al, ' '
    je .pula
    call print_char
.pula:
    dec rcx
    jnz .nome

    cmp byte [rsi], ' '
    je .fim
    mov al, '.'
    call print_char

    mov rcx, 3
.ext:
    lodsb
    cmp al, ' '
    je .fim
    call print_char
    dec rcx
    jnz .ext

.fim:
    pop rsi
    pop rcx
    pop rax
    ret

; ========== REMOVER ARQUIVO / PASTA REAL ==========
fs_remover:
    push rbx
    push rbp

    test rdi, rdi
    jz .erro
    mov rsi, 0
    call fs_resolver_caminho_pai
    test eax, eax
    jz .erro

    mov ebx, eax
    mov rbp, rdx
    cmp byte [rbp], 0
    je .erro

    lea rdi, [rel nome_83_tmp]
    mov rsi, rbp
    call formatar_nome_entrada

    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jz .erro

    mov byte [rax], FAT_ENTRADA_LIVRE
    mov ecx, [rax + FAT_ENTRADA_CLUSTER_ALTO]
    shl rcx, 16
    mov cx, [rax + FAT_ENTRADA_CLUSTER_BAIXO]

    push rbx
    mov rdi, rcx
    call liberar_cadeia
    pop rbx

    mov edi, ebx
    call escrever_diretorio
    test rax, rax
    jz .erro

    mov rax, 1
    jmp .sair
.erro:
    xor rax, rax
.sair:
    pop rbp
    pop rbx
    ret

liberar_cadeia:
    push rbx
.loop:
    cmp rdi, 2
    jb .fim
    cmp rdi, FAT_CLUSTER_FIM
    jae .fim
    cmp rdi, FAT_CLUSTER_INVALIDO
    je .fim

    mov rbx, rdi
    call ler_proximo_cluster
    push rax
    mov rdi, rbx
    xor esi, esi
    call escrever_proximo_cluster
    pop rdi
    jmp .loop
.fim:
    pop rbx
    ret

; ========== COPIAR ARQUIVO REAL (CLUSTER A CLUSTER, SEM LIMITE FIXO) ==========
fs_copiar:
    ; rdi = origem, rsi = destino -> rax = 1 ok, 0 erro
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                ; caminho origem
    mov r13, rsi                ; caminho destino

    ; Localiza entrada de origem
    mov rdi, r12
    mov rsi, 0
    call fs_resolver_caminho_pai
    test eax, eax
    jz .erro
    mov ebx, eax
    cmp byte [rdx], 0
    je .erro

    lea rdi, [rel nome_83_tmp]
    mov rsi, rdx
    call formatar_nome_entrada

    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jz .erro

    ; Extrai cluster inicial e tamanho da origem
    mov ecx, [rax + FAT_ENTRADA_CLUSTER_ALTO]
    shl rcx, 16
    mov cx, [rax + FAT_ENTRADA_CLUSTER_BAIXO]
    mov r14, rcx                ; r14 = cluster atual origem
    mov r15d, [rax + FAT_ENTRADA_TAMANHO] ; r15 = bytes restantes

    ; Cria arquivo vazio no destino
    mov rdi, r13
    xor rsi, rsi
    xor rdx, rdx
    call salvar_arquivo
    test rax, rax
    jz .erro

    ; Localiza entrada criada no destino para preencher cadeia de clusters
    mov rdi, r13
    mov rsi, 0
    call fs_resolver_caminho_pai
    test eax, eax
    jz .erro
    mov ebx, eax                ; ebx = cluster diretorio pai destino

    lea rdi, [rel nome_83_tmp]
    mov rsi, rdx
    call formatar_nome_entrada

    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jz .erro
    mov rbp, rax                ; rbp = entrada 32 bytes destino
    mov [rbp + FAT_ENTRADA_TAMANHO], r15d

    xor r12d, r12d              ; r12d = ultimo cluster destino alocado

.loop_copia_cluster:
    test r15d, r15d
    jz .fechar_copia
    cmp r14, 2
    jb .fechar_copia
    cmp r14, FAT_CLUSTER_FIM
    jae .fechar_copia

    push rbx
    push rbp
    call encontrar_proximo_cluster_livre
    pop rbp
    pop rbx
    test eax, eax
    jz .erro

    cmp r12d, 0
    jne .encadear_copia
    mov [rbp + FAT_ENTRADA_CLUSTER_BAIXO], ax
    push rax
    shr eax, 16
    mov [rbp + FAT_ENTRADA_CLUSTER_ALTO], ax
    pop rax
    jmp .copiar_setores

.encadear_copia:
    push rax
    push rbx
    push rbp
    mov edi, r12d
    mov esi, eax
    call escrever_proximo_cluster
    pop rbp
    pop rbx
    pop rax

.copiar_setores:
    mov r12d, eax

    mov rdi, r14
    call cluster_para_setor
    mov r8, rax                 ; LBA origem

    mov edi, r12d
    call cluster_para_setor
    mov r9, rax                 ; LBA destino

    movzx r10, byte [rel setores_cluster]
    xor r11, r11

.loop_copia_setor:
    cmp r11, r10
    jae .prox_cluster_copia

    push r8
    push r9
    push r10
    push r11
    mov rdi, r8
    add rdi, r11
    lea rsi, [rel arq_setor_buf]
    call disco_ler_setor
    pop r11
    pop r10
    pop r9
    pop r8
    test rax, rax
    jz .erro

    push r8
    push r9
    push r10
    push r11
    mov rdi, r9
    add rdi, r11
    lea rsi, [rel arq_setor_buf]
    call disco_escrever_setor
    pop r11
    pop r10
    pop r9
    pop r8
    test rax, rax
    jz .erro

    cmp r15d, 512
    jbe .zera_rest
    sub r15d, 512
    jmp .inc_setor
.zera_rest:
    xor r15d, r15d
.inc_setor:
    inc r11
    jmp .loop_copia_setor

.prox_cluster_copia:
    mov rdi, r14
    call ler_proximo_cluster
    mov r14, rax
    jmp .loop_copia_cluster

.fechar_copia:
    cmp r12d, 0
    je .salvar_dir_copia
    mov edi, r12d
    mov esi, FAT_CLUSTER_FIM
    call escrever_proximo_cluster

.salvar_dir_copia:
    mov edi, ebx
    call escrever_diretorio
    test rax, rax
    jz .erro

    mov rax, 1
    jmp .sair

.erro:
    xor rax, rax
.sair:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ========== NAVEGACAO REAL ==========
fs_obter_caminho_atual:
    lea rax, [rel caminho_atual]
    ret

fs_definir_caminho_atual:
    push rbx
    push rbp
    push rsi

    test rdi, rdi
    jz .erro
    cmp byte [rdi], 0
    je .erro

    call fs_inicializar
    test rax, rax
    jz .erro

    mov rbp, rdi
    cmp byte [rbp], '/'
    jne .relativo

    cmp byte [rbp + 1], 0
    jne .abs_sub
    mov eax, [rel cluster_raiz]
    mov [rel cluster_atual], eax
    mov byte [rel caminho_atual], '/'
    mov byte [rel caminho_atual + 1], 0
    mov rax, 1
    jmp .sair

.abs_sub:
    mov rsi, 0
    call fs_resolver_caminho_pai
    test eax, eax
    jz .erro
    mov ebx, eax
    mov rsi, rdx
    cmp byte [rsi], 0
    je .aplica_abs

    lea rdi, [rel nome_83_tmp]
    call formatar_nome_entrada
    mov edi, ebx
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jz .erro
    mov cl, [rax + FAT_ENTRADA_ATRIB]
    and cl, FAT_ATRIB_DIRETORIO
    jz .erro

    mov ecx, [rax + FAT_ENTRADA_CLUSTER_ALTO]
    shl ecx, 16
    mov cx, [rax + FAT_ENTRADA_CLUSTER_BAIXO]
    mov ebx, ecx

.aplica_abs:
    mov [rel cluster_atual], ebx
    mov rsi, rbp
    lea rdi, [rel caminho_atual]
    mov rcx, 255
.copia_abs:
    lodsb
    stosb
    test al, al
    jz .ok
    dec rcx
    jnz .copia_abs
    mov byte [rel caminho_atual + 255], 0
.ok:
    mov rax, 1
    jmp .sair

.relativo:
    lea rdi, [rel nome_83_tmp]
    mov rsi, rbp
    call formatar_nome_entrada

    mov edi, [rel cluster_atual]
    lea rsi, [rel nome_83_tmp]
    call procurar_entrada
    test rax, rax
    jz .erro

    mov cl, [rax + FAT_ENTRADA_ATRIB]
    and cl, FAT_ATRIB_DIRETORIO
    jz .erro

    mov ecx, [rax + FAT_ENTRADA_CLUSTER_ALTO]
    shl ecx, 16
    mov cx, [rax + FAT_ENTRADA_CLUSTER_BAIXO]
    mov [rel cluster_atual], ecx
    mov rax, 1
    jmp .sair

.erro:
    xor rax, rax
.sair:
    pop rsi
    pop rbp
    pop rbx
    ret
