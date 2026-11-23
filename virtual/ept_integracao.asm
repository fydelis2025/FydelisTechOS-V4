; ==================================================
; Integração: Carregar EPT/NPT ao ativar VM
; ==================================================
bits 64

extern ept_inicializar
extern ept_mapear_faixa
extern ept_flush_todas
extern eptp_value

extern npt_inicializar
extern npt_mapear_faixa
extern npt_flush_todas
extern nptp_value

extern vmx_ativo
extern svm_ativo

section .text
global mem_aninhada_inicializar
global mem_aninhada_mapear_convidado
global mem_aninhada_flush

; ── Detectar e inicializar ──
mem_aninhada_inicializar:
    cmp  byte [vmx_ativo], 1
    je   .intel
    cmp  byte [svm_ativo], 1
    je   .amd
    xor  rax, rax
    ret
.intel:
    call ept_inicializar
    ; Mapear toda a RAM física para a VM (1:1 inicialmente)
    mov  rdi, 0                  ; Convidado: 0 = Físico: 0
    mov  rsi, 0
    mov  rdx, 512*1024*1024      ; 512MB (ajuste conforme sua RAM)
    call ept_mapear_faixa
    mov  rax, 1
    ret
.amd:
    call npt_inicializar
    mov  rdi, 0
    mov  rsi, 0
    mov  rdx, 512*1024*1024
    call npt_mapear_faixa
    mov  rax, 1
    ret

; ── Mapear região específica ──
mem_aninhada_mapear_convidado:
    ; rdi = convidado, rsi = físico, rdx = tamanho
    cmp  byte [vmx_ativo], 1
    je   .intel
    cmp  byte [svm_ativo], 1
    je   .amd
    ret
.intel:
    jmp  ept_mapear_faixa
.amd:
    jmp  npt_mapear_faixa

; ── Invalidar TLB ──
mem_aninhada_flush:
    cmp  byte [vmx_ativo], 1
    je   .intel
    cmp  byte [svm_ativo], 1
    je   .amd
    ret
.intel:
    jmp  ept_flush_todas
.amd:
    jmp  npt_flush_todas