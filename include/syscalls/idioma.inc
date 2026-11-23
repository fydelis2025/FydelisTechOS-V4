; ==========================================
; FYDELIS — SISTEMA DE IDIOMAS
; v1.0 | Códigos de mensagens
; ==========================================
%ifndef IDIOMA_INC
%define IDIOMA_INC

; === CÓDIGOS DE IDIOMA ===
%define IDIOMA_PT_BR   0
%define IDIOMA_EN_US   1
%define IDIOMA_ES      2

; === CÓDIGOS DE MENSAGENS (chaves) ===
%define MSG_BEM_VINDO          0
%define MSG_SAUDACAO           1
%define MSG_SISTEMA            2
%define MSG_PRONTO             3
%define MSG_ERRO               4
%define MSG_CARREGANDO         5
%define MSG_LOGIN              6
%define MSG_SENHA              7
%define MSG_BEM_VINDO_NOVAMENTE 8
%define MSG_SAIR               9
%define MSG_CONFIGURACOES     10
%define MSG_IDIOMA            11
%define MSG_TOTAL_MENSAGENS   12

; === ESTRUTURA DE PACOTE DE IDIOMA ===
; Cada pacote fornece uma tabela com ponteiros para as strings
struc PacoteIdioma
    .nome:          resq 1   ; Ponteiro: "Português (Brasil)"
    .codigo:        resd 1   ; IDIOMA_PT_BR / IDIOMA_EN_US / ...
    .tabela:        resq MSG_TOTAL_MENSAGENS  ; Vetor de ponteiros
endstruc

; === VARIÁVEIS EXTERNAS ===
extern idioma_ativo          ; ID do idioma corrente
extern tabela_ativa          ; Ponteiro para a tabela ativa

; === MACRO PARA PEGAR MENSAGEM ===
; Uso: mov rdx, [tabela_ativa + MSG_BEM_VINDO * 8]
%macro mensagem 1
    mov rdx, [tabela_ativa + (%1) * 8]
%endmacro

; === ROTINAS PÚBLICAS ===
global idioma_iniciar        ; Detectar e carregar idioma padrão
global idioma_selecionar     ; Selecionar por ID
global idioma_por_indice     ; Pegar pacote N
global idioma_quantos        ; Devolver quantidade de pacotes disponíveis

%endif