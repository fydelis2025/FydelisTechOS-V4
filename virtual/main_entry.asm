; ==================================================
; Ponto de entrada — integrar tudo
; ==================================================
bits 64

extern init_virtual_memory
extern load_page_tables
extern detect_vmx_support
extern vmx_enter

global _start

_start:
    ; Passo 1 — Inicializar memória virtual
    call init_virtual_memory
    call load_page_tables

    ; Passo 2 — Verificar suporte a VT-x
    call detect_vmx_support
    test rax, rax
    jz   .sem_virtualizacao

    ; Passo 3 — Ligar modo de virtualização
    call vmx_enter
    test rax, rax
    jz   .vmx_falhou

    ; ✅ Tudo pronto!
    ; Aqui você pode criar VMs nas próximas versões

.sem_virtualizacao:
    ; CPU não tem VT-x — continua sem virtualização
    hlt

.vmx_falhou:
    ; Falha ao ativar — verificar BIOS
    hlt