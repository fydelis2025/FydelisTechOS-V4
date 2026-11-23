; ==================================================
; FydelisTechOS — Kernel Final v2.2 COMPLETO
; Memória Virtual + VT-x/AMD-V + Tratamento #VMEXIT
; + Espaço de Usuário / FydelTerm
; ==================================================
bits 64

; === Funções Externas — Memória ===
extern init_virtual_memory
extern load_page_tables

; === Funções Externas — Plataforma ===
extern detectar_plataforma
extern inicializar_plataforma
extern desligar_plataforma

; === Funções Externas — Virtualização ===
extern vm_load_guest
extern vm_test_guest_code
extern vm_test_guest_len
extern vm_executar                  ; Laço com tratamento de saída

; === Funções Externas — Subsistemas ===
extern disco_inicializar
extern fs_inicializar

; === Funções Externas — Usuário ===
extern init_entry
extern pilha_usuario_top

global _start
_start:
    ; ══════════════════════════════════════════════════
    ; ETAPA 1: INICIALIZAR MEMÓRIA VIRTUAL
    ; ══════════════════════════════════════════════════
    call init_virtual_memory
    call load_page_tables

    ; ══════════════════════════════════════════════════
    ; ETAPA 2: DETECTAR SUPORTE A VIRTUALIZAÇÃO
    ; ══════════════════════════════════════════════════
    call detectar_plataforma
    cmp  rax, 0
    je   .sem_virtualizacao

    ; ══════════════════════════════════════════════════
    ; ETAPA 3: LIGAR HIPERVISOR (VT-x / AMD-V)
    ; ══════════════════════════════════════════════════
    call inicializar_plataforma
    test rax, rax
    jz   .falha_inicializar

    ; ══════════════════════════════════════════════════
    ; ETAPA 4: INICIALIZAR DISCO E SISTEMA DE ARQUIVOS
    ; ══════════════════════════════════════════════════
    call disco_inicializar
    call fs_inicializar

    ; ══════════════════════════════════════════════════
    ; ETAPA 5: CARREGAR CONVIDADO DE TESTE (opcional)
    ; ══════════════════════════════════════════════════
    mov  rsi, vm_test_guest_code       ; Origem do código
    mov  rdi, 0x200000                 ; Endereço de carga na VM
    mov  rcx, vm_test_guest_len        ; Tamanho
    call vm_load_guest

    ; ══════════════════════════════════════════════════
    ; ETAPA 6: LANÇAR ESPAÇO DE USUÁRIO — FydelTerm 🚀
    ; ══════════════════════════════════════════════════
    ; Troca de contexto: Núcleo (nível 0) → Usuário (nível 3)
    ; Usamos 'iretq' para trocar privilégios de forma segura
    mov  rsp, pilha_usuario_top        ; Pilha isolada do usuário
    mov  rax, init_entry               ; Ponto de entrada do terminal

    ; Empilhar estado para retorno simulado → CPU carrega com privilégio reduzido
    push 0x23                          ; SS  — Seletor de dados do usuário
    push rsp                           ; Nova pilha do usuário
    pushf                             ; Flags (interrupções ativadas)
    push 0x1B                          ; CS  — Seletor de código do usuário
    push rax                          ; Endereço de entrada

    iretq                              ; Salta para usuário — não volta aqui

    ; ══════════════════════════════════════════════════
    ; FLUXO ALTERNATIVO: Executar convidado direto (sem usuário)
    ; ══════════════════════════════════════════════════
    call vm_executar
    test rax, rax
    jnz  .sucesso_vm
    jmp  .fim

.sucesso_vm:
    call desligar_plataforma
    jmp  .fim

.sem_virtualizacao:
    ; CPU sem VT-x/SVM — sistema roda em modo protegido clássico
    mov  rsp, pilha_usuario_top
    mov  rax, init_entry
    push 0x23
    push rsp
    pushf
    push 0x1B
    push rax
    iretq
    hlt

.falha_inicializar:
    ; Ative VT-x/SVM na BIOS/UEFI
    hlt

.fim:
    hlt