; ==========================================
; PACOTE DE IDIOMA: PORTUGUÊS BRASILEIRO
; ==========================================
[BITS 64]
[DEFAULT REL]

%include "idioma.inc"

section .rodata
align 8

; Strings individuais
pt_br_nome:             db "Português (Brasil)", 0
pt_br_bem_vindo:        db "Bem-vindo ao FydelisTechOS", 0
pt_br_saudacao:         db "Sistema operacional desenvolvido em Salvador - Bahia", 0
pt_br_sistema:          db "Kernel + Drivers + Interface — 100% Nativo", 0
pt_br_pronto:           db "Sistema pronto para uso", 0
pt_br_erro:             db "Erro: ", 0
pt_br_carregando:       db "Carregando sistema...", 0
pt_br_login:            db "Usuário: ", 0
pt_br_senha:            db "Senha: ", 0
pt_br_bem_vindo_novamente: db "Bem-vindo de volta!", 0
pt_br_sair:             db "Sair do sistema", 0
pt_br_configuracoes:    db "Configurações", 0
pt_br_idioma:           db "Idioma", 0

; Tabela de ponteiros — índice = código da mensagem
pt_br_tabela:
    dq pt_br_bem_vindo         ; 0
    dq pt_br_saudacao          ; 1
    dq pt_br_sistema           ; 2
    dq pt_br_pronto            ; 3
    dq pt_br_erro              ; 4
    dq pt_br_carregando        ; 5
    dq pt_br_login             ; 6
    dq pt_br_senha             ; 7
    dq pt_br_bem_vindo_novamente ; 8
    dq pt_br_sair              ; 9
    dq pt_br_configuracoes     ; 10
    dq pt_br_idioma            ; 11

section .data
align 8

; Estrutura completa do pacote
global pacote_pt_br
pacote_pt_br:
    dq pt_br_nome             ; ponteiro para o nome
    dd IDIOMA_PT_BR           ; código do idioma (double word)
    times 4 db 0              ; padding de alinhamento para 64-bit
    dq pt_br_tabela           ; ponteiro para a tabela de strings
