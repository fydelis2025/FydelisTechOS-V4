; ==========================================
; PACOTE: ENGLISH (US)
; ==========================================
[BITS 64]
[DEFAULT REL]

%include "idioma.inc"

section .rodata
align 8

en_us_nome:             db "English (US)", 0
en_us_bem_vindo:        db "Welcome to FydelisTechOS", 0
en_us_saudacao:         db "Operating system developed in Salvador - Bahia", 0
en_us_sistema:          db "Kernel + Drivers + UI — 100% Native", 0
en_us_pronto:           db "System ready", 0
en_us_erro:             db "Error: ", 0
en_us_carregando:       db "Loading system...", 0
en_us_login:            db "Username: ", 0
en_us_senha:            db "Password: ", 0
en_us_bem_vindo_novamente: db "Welcome back!", 0
en_us_sair:             db "Log out", 0
en_us_configuracoes:    db "Settings", 0
en_us_idioma:           db "Language", 0

en_us_tabela:
    dq en_us_bem_vindo
    dq en_us_saudacao
    dq en_us_sistema
    dq en_us_pronto
    dq en_us_erro
    dq en_us_carregando
    dq en_us_login
    dq en_us_senha
    dq en_us_bem_vindo_novamente
    dq en_us_sair
    dq en_us_configuracoes
    dq en_us_idioma

section .data
align 8

global pacote_en_us
pacote_en_us:
    dq en_us_nome             ; ponteiro para o nome
    dd IDIOMA_EN_US           ; código do idioma (double word)
    times 4 db 0              ; padding de alinhamento para 64-bit
    dq en_us_tabela           ; ponteiro para a tabela de strings
