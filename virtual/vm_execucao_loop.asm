; ==================================================
; FydelisTechOS — Laço Principal da VM
; Repetir: Executar → Tratar saída → Voltar
; ==================================================
bits 64

; Funções externas
extern vmx_launch
extern vmx_handle_exit
extern svm_launch
extern svm_handle_exit
extern vmx_ativo
extern svm_ativo

section .text
global vm_executar

; ─────────────────────────────────────
; Laço principal: rodar até a VM sair
; Retorno: rax = código de encerramento
; ─────────────────────────────────────
vm_executar:
    .loop:
        ; ── Passo 1: Executar a VM ──
        cmp  byte [vmx_ativo], 1
        je   .executar_vmx
        cmp  byte [svm_ativo], 1
        je   .executar_svm
        jmp  .sem_plataforma

.executar_vmx:
        call vmx_launch
        jmp  .processar

.executar_svm:
        call svm_launch
        jmp  .processar

        ; ── Passo 2: Tratar saída ──
.processar:
        cmp  byte [vmx_ativo], 1
        je   .tratar_vmx
        cmp  byte [svm_ativo], 1
        je   .tratar_svm

.tratar_vmx:
        ; rdx = código de saída (passado por vmx_launch)
        call vmx_handle_exit
        jmp  .decisao

.tratar_svm:
        call svm_handle_exit
        jmp  .decisao

        ; ── Passo 3: Decidir voltar ou parar ──
.decisao:
        test rax, rax
        jnz  .loop              ; ✅ Voltar para a VM
        jmp  .fim               ; ❌ Encerrar

.sem_plataforma:
        xor  rax, rax

.fim:
    ret