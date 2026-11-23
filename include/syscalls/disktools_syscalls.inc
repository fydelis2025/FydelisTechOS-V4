; ==========================================
; 📞 SYSCALLS — Disk Tools ↔ particao.asm
; Modo Usuário → Modo Kernel → Hardware
; ==========================================
SYS_DISCO_LISTAR           equ 100   ; Listar discos
SYS_PARTICAO_LISTAR        equ 101   ; Listar partições
SYS_PARTICAO_CRIAR         equ 102   ; Criar partição
SYS_PARTICAO_EXCLUIR       equ 103   ; Excluir partição
SYS_PARTICAO_REDIMENSIONAR equ 104  ; Redimensionar
SYS_FORMATAR_FAT32         equ 105   ; Formatar FAT32
SYS_FORMATAR_EXFAT         equ 106   ; Formatar exFAT
SYS_DISCO_LER_SETOR        equ 107   ; Ler setor bruto
SYS_DISCO_ESCREVER_SETOR   equ 108   ; Escrever setor bruto
SYS_CLONAR_DISCO           equ 109   ; Clonagem
SYS_ESCANEAR_PERDIDOS      equ 110   ; Recuperação de partição
SYS_LIMPAR_DISCO           equ 111   ; Limpeza segura

; ── Operações de Arquivos e Particionamento ──
SYS_DISCO_MONTAR           equ 0x50
SYS_DISCO_DESMONTAR        equ 0x51
SYS_ARQUIVO_ABRIR          equ 0x52
SYS_ARQUIVO_FECHAR         equ 0x53
SYS_ARQUIVO_LER            equ 0x54
SYS_ARQUIVO_ESCREVER       equ 0x55
SYS_DIRETORIO_LISTAR       equ 0x56
SYS_DIRETORIO_CRIAR        equ 0x57
SYS_ARQUIVO_REMOVER        equ 0x58
