; ==========================================
; PCB — Process Control Block
; Estrutura de Controle de Processo
; FydelisTech OS v2.0 · Salvador • Bahia 🇧🇷
; ==========================================
; Estados do processo
PCB_ESTADO_PRONTO    equ 0
PCB_ESTADO_EXECUTANDO equ 1
PCB_ESTADO_BLOQUEADO  equ 2
PCB_ESTADO_ZOMBIE     equ 3

; Tamanho da pilha por processo
PCB_PILHA_TAMANHO     equ 8192

; Offsets na estrutura PCB
PCB_RAX       equ 0
PCB_RBX       equ 8
PCB_RCX       equ 16
PCB_RDX       equ 24
PCB_RSI       equ 32
PCB_RDI       equ 40
PCB_RBP       equ 48
PCB_RSP       equ 56
PCB_RIP       equ 64
PCB_RFLAGS    equ 72
PCB_R8        equ 80
PCB_R9        equ 88
PCB_R10       equ 96
PCB_R11       equ 104
PCB_R12       equ 112
PCB_R13       equ 120
PCB_R14       equ 128
PCB_R15       equ 136
PCB_ID        equ 144
PCB_ESTADO    equ 152
PCB_PRIORIDADE equ 156
PCB_NOME      equ 160
PCB_TAMANHO   equ 256