; ============================================================================
; EXCEPTIONS.ASM — Aliases de Excecoes e Parada de Seguranca x86_64
; FydelisTech OS v4.2 — Integrado ao idt.asm & kernel/panic.c
; Salvador - Bahia
; ============================================================================
bits 64
default rel

section .text
global isr_pf_handler
global isr_gp_handler
global isr_de_handler
global isr_df_handler
global fydelis_panic_excecao
global qt_main_entry

; Stubs reais gerados no kernel/idt.asm
extern isr0
extern isr8
extern isr13
extern isr14

qt_main_entry:
    ret

; Ponto de parada absoluto (chamado pelo kernel/panic.c apos exibir a tela)
fydelis_panic_excecao:
    cli
.halt_loop:
    hlt
    jmp .halt_loop

; Redirecionamentos diretos para os vetores da IDT (sem duplicar isr_comum)
isr_de_handler:
    jmp isr0

isr_df_handler:
    jmp isr8

isr_gp_handler:
    jmp isr13

isr_pf_handler:
    jmp isr14
