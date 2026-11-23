; ==================================================
; FydelisTechOS — Chamadas de Sistema: Virtualização
; Compartilhado entre kernel e usuário
; ==================================================

; Grupo: Virtualização (faixa 0x50–0x5F)
SYS_VM_INICIAR        equ 0x50
SYS_VM_PARAR          equ 0x51
SYS_VM_STATUS         equ 0x52
SYS_VM_MEM_ALOCAR     equ 0x53
SYS_VM_DISCO_ANEXAR   equ 0x54
SYS_VM_LISTAR          equ 0x55

; Códigos de retorno
VM_STATUS_DESLIGADO    equ 0
VM_STATUS_EXECUTANDO   equ 1
VM_STATUS_PAUSADO      equ 2
VM_STATUS_ERRO         equ -1

; Tipos de disco para anexar
DISCO_TIPO_ARQUIVO     equ 1
DISCO_TIPO_PARTICAO    equ 2

; Offsets — struct VMInfo (alinhamento nativo x86_64)
VMINFO_ID          equ 0    ; int
VMINFO_NOME        equ 8    ; char[32] → 8 a 39
VMINFO_RAM_ALOCADA equ 40   ; uint64_t
VMINFO_CPU_NUCLEOS equ 48   ; int
VMINFO_ATIVO       equ 52   ; int
VMINFO_TEMPO_EXEC  equ 56   ; uint64_t
VMINFO_TAMANHO     equ 64   ; Tamanho total alinhado