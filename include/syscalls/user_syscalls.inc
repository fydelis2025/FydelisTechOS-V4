; ==================================================
; FydelisTechOS — Chamadas de Sistema: Usuário
; Interface estável entre núcleo e espaço de usuário
; ==================================================

; Grupo: Gerenciamento de Processos (faixa 0x30–0x3F)
SYS_PROCESS_EXIT       equ 0x30
SYS_PROCESS_SPAWN      equ 0x31
SYS_PROCESS_WAIT       equ 0x32
SYS_PROCESS_GETPID      equ 0x33
SYS_PROCESS_SETNAME     equ 0x34

; Grupo: Memória de Usuário (faixa 0x40–0x4F)
SYS_MEM_ALLOC           equ 0x40
SYS_MEM_FREE            equ 0x41
SYS_MEM_MAP             equ 0x42

; Grupo: E/S Básica (faixa 0x20–0x2F)
SYS_IO_WRITE            equ 0x20
SYS_IO_READ             equ 0x21
SYS_IO_SETCOLOR         equ 0x22

; Flags de memória
MEM_READ                equ (1 << 0)
MEM_WRITE               equ (1 << 1)
MEM_EXEC                equ (1 << 2)
MEM_USER                equ (1 << 3)

; Códigos de erro
SYS_OK                  equ 0
SYS_ERR_BADNO           equ -1
SYS_ERR_NOPERM          equ -2
SYS_ERR_NOEXEC          equ -3
SYS_ERR_NOMEM           equ -4

; Offsets — struct UsuarioInfo (x86_64)
USRINFO_NOME         equ 0     ; char[32]
USRINFO_SENHA_HASH    equ 32    ; uint8_t[32]
USRINFO_NIVEL        equ 64    ; int (0=admin,1=usuário,2=convidado)
USRINFO_ATIVO        equ 68    ; int
USRINFO_ULTIMO_ACESSO equ 72   ; uint64_t
USRINFO_TAMANHO      equ 80    ; Alinhado