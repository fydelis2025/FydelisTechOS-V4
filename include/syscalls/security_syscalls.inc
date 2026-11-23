; ==========================================
; 🔒 SECURITY_SYSCALLS.INC — Chamadas de Sistema: Segurança
; FydelisTech OS v2.2 · Salvador • Bahia 🇧🇷[cite: 14]
; Padrão: NASM · x86_64 · System V AMD64[cite: 14]
; ==========================================
%ifndef SECURITY_SYSCALLS_INC
%define SECURITY_SYSCALLS_INC

; ========== NÚMEROS DAS CHAMADAS ==========
SYS_SEGURANCA_INICIALIZAR   equ 100
SYS_AUTENTICAR_USUARIO       equ 101
SYS_VERIFICAR_PERMISSAO      equ 102
SYS_REGISTRAR_EVENTO         equ 103
SYS_CRIPTOGRAFAR_DADOS       equ 104
SYS_DESCRIPTOGRAFAR_DADOS    equ 105
SYS_GERAR_CHAVE_ALEATORIA     equ 106
SYS_VERIFICAR_INTEGRIDADE     equ 107
SYS_ISOLAR_PROCESSO           equ 108
SYS_AUDITAR_ACESSO            equ 109
SYS_OBTER_NIVEL_CONFIANCA     equ 110


; ==========================================
; FYDELIS TECH OS — Constantes de Segurança (Syscalls)[cite: 14]
; ==========================================
SYS_AV_VERIFICAR          equ 0x93
SYS_AV_VARRER             equ 0x94
SYS_AV_QUARENTENA         equ 0x95
SYS_CVE_VERIFICAR         equ 0x96
SYS_SEC_LISTAR_AMEACAS    equ 0x97
SYS_SEC_STATUS            equ 0x98
SYS_FW_HABILITAR          equ 0x90
SYS_FW_DESABILITAR        equ 0x91
SYS_FW_REGRA_ADICIONAR    equ 0x92


; ========== NÍVEIS DE PRIVILÉGIO ==========
PRIVILEGIO_NENHUM     equ 0
PRIVILEGIO_USUARIO    equ 1
PRIVILEGIO_ADMIN      equ 100
PRIVILEGIO_ROOT       equ 255

; ========== TIPOS DE EVENTO DE SEGURANÇA ==========
SEG_EVENTO_LOGIN       equ 0x01
SEG_EVENTO_LOGOUT      equ 0x02
SEG_EVENTO_ACESSO      equ 0x03
SEG_EVENTO_ALTERACAO   equ 0x04
SEG_EVENTO_AMACACA     equ 0x05
SEG_EVENTO_BLOQUEIO    equ 0x06
SEG_EVENTO_CRIPTO      equ 0x07

; ========== RESULTADOS ==========
SEG_OK                 equ 0
SEG_ERRO_NEGADO        equ -1
SEG_ERRO_INVALIDO      equ -2
SEG_ERRO_SESSAO        equ -3
SEG_ERRO_INTEGRIDADE   equ -4
SEG_ERRO_SISTEMA       equ -5

; ========== TAMANHOS ==========
SEG_MAX_NOME_USUARIO    equ 32
SEG_MAX_HASH_SENHA      equ 64
SEG_MAX_CHAVE_AES       equ 32
SEG_MAX_REGISTRO_LOG    equ 256

; ========== ESTRUTURAS ==========
; Dados de autenticação
struc SegAuth
    .nomeUsuario:   resb SEG_MAX_NOME_USUARIO
    .senhaHash:     resb SEG_MAX_HASH_SENHA
    .privilegio:    resd 1
    .sessaoAtiva:   resb 1
endstruc

; Evento para auditoria
struc SegEvento
    .tipo:          resd 1
    .pid:           resd 1
    .usuario:       resb SEG_MAX_NOME_USUARIO
    .alvo:          resb 64
    .resultado:     resd 1
    .timestamp:     resq 1
endstruc

; ========== PONTEIROS PARA IMPLEMENTAÇÃO ==========
extern sys_seguranca_inicializar
extern sys_autenticar_usuario
extern sys_verificar_permissao
extern sys_registrar_evento
extern sys_criptografar_dados
extern sys_descriptografar_dados
extern sys_gerar_chave_aleatoria
extern sys_verificar_integridade
extern sys_isolar_processo
extern sys_auditar_acesso
extern sys_obter_nivel_confianca

%endif ; SECURITY_SYSCALLS_INC
