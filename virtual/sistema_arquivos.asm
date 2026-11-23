; ==================================================
; FydelisTechOS — Sistema de Arquivos Simples v2.2
; Tabela de diretório + alocação de blocos
; ==================================================
bits 64

; Layout do disco
BLOCO_TAMANHO       equ 4096    ; 4KB por bloco
BLOCO_POR_SETOR     equ 8       ; 4096 / 512 = 8 setores por bloco
MAX_ARQUIVOS        equ 512     ; Máximo de arquivos
INICIO_DADOS        equ 34      ; Primeiro setor de dados

; Entrada de diretório
struc DIRENT
    .nome       resb 32          ; Nome do arquivo
    .tamanho    resq 1           ; Tamanho em bytes
    .bloco_inic resd 1           ; Bloco inicial
    .reservado  resb 32          ; Espaço futuro
endstruc

section .bss
align 4096
global superbloco
global mapa_bits
global diretorio

superbloco:      resb 512
mapa_bits:       resb 512       ; 1 bit por bloco → 4096 blocos
diretorio:       resb MAX_ARQUIVOS * DIRENT_size

section .text
global fs_inicializar
global fs_criar_arquivo
global fs_ler_arquivo
global fs_escrever_arquivo
global fs_buscar_arquivo

; Funções externas de disco exigidas
extern disco_ler_setor
extern disco_escrever_setor

; ─────────────────────────────────────
; Inicializar sistema de arquivos
; ─────────────────────────────────────
fs_inicializar:
    ; Ler superbloco (setor 0)
    mov  rdi, 0
    lea  rsi, [rel superbloco]
    call disco_ler_setor
    test rax, rax
    jz   .erro

    ; Verificar se já formatado
    mov  rax, [rel superbloco]
    cmp  eax, 0x46594446  ; "FYDF"
    je   .carregar

    ; ── Formatar novo sistema ──
    mov  dword [rel superbloco], 0x46594446  ; Assinatura
    mov  dword [rel superbloco+4], 1         ; Versão

    ; Marcar primeiros blocos como ocupados (sistema)
    mov  byte [rel mapa_bits], 0xFF          ; Blocos 0–7 ocupados

    ; Zerar diretório
    lea  rdi, [rel diretorio]
    mov  rcx, MAX_ARQUIVOS * DIRENT_size / 8
    xor  rax, rax
    rep stosq

    ; Salvar no disco
    jmp  .salvar_tudo

.carregar:
    ; Carregar mapa de bits e diretório
    mov  rdi, 1
    lea  rsi, [rel mapa_bits]
    call disco_ler_setor

    mov  rdi, 2
    lea  rsi, [rel diretorio]
    mov  rcx, 32
.loop_dir:
    push rcx
    call disco_ler_setor
    inc  rdi
    add  rsi, 512
    pop  rcx
    dec  rcx
    jnz  .loop_dir

.salvar_tudo:
    ; Salvar superbloco
    mov  rdi, 0
    lea  rsi, [rel superbloco]
    call disco_escrever_setor

    ; Salvar mapa de bits
    mov  rdi, 1
    lea  rsi, [rel mapa_bits]
    call disco_escrever_setor

    ; Salvar diretório
    mov  rdi, 2
    lea  rsi, [rel diretorio]
    mov  rcx, 32
.loop_salvar:
    push rcx
    call disco_escrever_setor
    inc  rdi
    add  rsi, 512
    pop  rcx
    dec  rcx
    jnz  .loop_salvar

    mov  rax, 1
    ret

.erro:
    xor  rax, rax
    ret

; ─────────────────────────────────────
; Encontrar bloco livre
; Saída: rax = número do bloco ou -1 se cheio
; ─────────────────────────────────────
encontrar_bloco_livre:
    mov  rcx, 512                  ; 512 bytes no mapa
    xor  rdx, rdx                  ; Índice do bloco
.procurar_byte:
    lea  rbx, [rel mapa_bits]
    mov  al, [rbx + rdx]
    cmp  al, 0xFF                  ; Todos ocupados?
    jne  .encontrado
    inc  rdx
    cmp  rdx, 512
    jge  .cheio
    jmp  .procurar_byte

.encontrado:
    ; Encontrar bit livre neste byte
    mov  r8, rdx
    shl  r8, 3                     ; × 8 = bloco inicial deste byte
    mov  r9, 8
.procurar_bit:
    test al, 1
    jz   .bloco_livre
    shr  al, 1
    inc  r8
    dec  r9
    jnz  .procurar_bit

    inc  rdx
    jmp  .procurar_byte

.bloco_livre:
    ; Marcar como ocupado
    mov  rcx, r8
    shr  rcx, 3                    ; Índice do byte
    mov  rdx, r8
    and  rdx, 7                    ; Bit dentro do byte
    lea  rbx, [rel mapa_bits]
    bts  [rbx + rcx], rdx

    mov  rax, r8
    ret

.cheio:
    mov  rax, -1
    ret

; ─────────────────────────────────────
; Criar arquivo
; Entrada: rsi = nome, rdi = ponteiro para buffer, rdx = tamanho
; Saída: rax = descritor ou 0
; ─────────────────────────────────────
fs_criar_arquivo:
    ; Procurar entrada vazia no diretório
    mov  rcx, MAX_ARQUIVOS
    lea  r8, [rel diretorio]
.procurar:
    cmp  byte [r8], 0              ; Nome vazio = entrada livre
    je   .encontrado
    add  r8, DIRENT_size
    dec  rcx
    jnz  .procurar
    xor  rax, rax
    ret

.encontrado:
    ; Copiar nome
    mov  rdi, r8
    mov  rcx, 32
    rep movsb

    ; Alocar bloco
    call encontrar_bloco_livre
    cmp  rax, -1
    je   .sem_espaco
    mov  [r8 + DIRENT.bloco_inic], eax

    ; Definir tamanho
    mov  [r8 + DIRENT.tamanho], rdx

    ; Escrever dados no bloco
    mov  r9, rax
    shl  r9, 9                     ; bloco × 512 × 8 = offset no disco
    add  r9, INICIO_DADOS * 512    ; Início da área de dados

    ; Escrever em setores
    mov  rcx, rdx
    mov  r10, rdi                  ; Salvar fim do nome = dados
.escrever:
    push rcx
    push r9
    mov  rdi, r9
    shr  rdi, 9                    ; Converter offset → setor
    mov  rsi, r10
    call disco_escrever_setor
    pop  r9
    pop  rcx
    add  r9, 512
    add  r10, 512
    sub  rcx, 512
    jg   .escrever

    ; Salvar diretório
    mov  rax, r8
    lea  rbx, [rel diretorio]
    sub  rax, rbx
    shr  rax, 5                    ; ÷ 32 = índice × 512
    add  rax, 2                    ; Setor do diretório
    mov  rdi, rax
    mov  rsi, r8
    call disco_escrever_setor

    mov  rax, 1                    ; Sucesso
    ret

.sem_espaco:
    xor  rax, rax
    ret

; ─────────────────────────────────────
; Buscar arquivo pelo nome
; Entrada: rsi = nome
; Saída: rax = entrada ou 0 se não encontrado
; ─────────────────────────────────────
fs_buscar_arquivo:
    mov  rcx, MAX_ARQUIVOS
    lea  r8, [rel diretorio]
.procurar:
    cmp  byte [r8], 0
    je   .nao_encontrado

    ; Comparar nomes
    mov  rdi, r8
    mov  rdx, rsi
    mov  r9, 32
.comp:
    lodsb
    cmp  al, [rdi]
    jne  .proximo
    inc  rdi
    dec  r9
    jnz  .comp
    ; Nomes iguais
    mov  rax, r8
    ret

.proximo:
    add  r8, DIRENT_size
    dec  rcx
    jnz  .procurar

.nao_encontrado:
    xor  rax, rax
    ret

; ─────────────────────────────────────
; Ler arquivo
; Entrada: rsi = nome, rdi = buffer destino
; Saída: rax = tamanho lido, 0 se erro
; ─────────────────────────────────────
fs_ler_arquivo:
    push rdi
    call fs_buscar_arquivo
    test rax, rax
    jz   .nao_encontrado

    mov  r9, rax
    mov  rcx, [r9 + DIRENT.tamanho]
    mov  r8d, [r9 + DIRENT.bloco_inic]
    shl  r8, 9                     ; Bloco → offset
    add  r8, INICIO_DADOS * 512

    pop  rdi
    mov  rdx, rcx
.ler:
    mov  rsi, r8
    shr  rsi, 9
    push rdi
    push rdx
    push r8
    call disco_ler_setor
    pop  r8
    pop  rdx
    pop  rdi
    add  r8, 512
    add  rdi, 512
    sub  rdx, 512
    jg   .ler

    mov  rax, rcx
    ret

.nao_encontrado:
    pop  rdi
    xor  rax, rax
    ret
