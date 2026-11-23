; ======================================
; FYDELTERM OS · CONSTANTES GLOBAIS
; Arquitetura: x86_64 Long Mode
; Padrão: System V AMD64 / NASM
; Atualizado: APIC · PCI · IRQ · Syscalls
; Salvador • Bahia 🇧🇷
; ======================================
%ifndef FYDELTERM_INC
%define FYDELTERM_INC

; ======================================
; 📍 LOCALIZAÇÃO NA MEMÓRIA
; ======================================
KERNEL_BASE         equ 0x7E00          ; Kernel carregado aqui
KERNEL_VIRT_BASE    equ 0xFFFFFFFF80000000  ; Espaço virtual do kernel (mapeamento alto)
VIDEO_TEXT_BASE     equ 0xB8000         ; Memória vídeo texto (modo texto)
STACK_TOP           equ 0x7C000         ; Topo da pilha (alinhado 16B)
PAGE_SIZE           equ 4096            ; Tamanho de página

; ======================================
; ⌨️ BUFFER E ARGUMENTOS
; ======================================
BUFFER_SIZE         equ 128
MAX_ARGS            equ 8
MAX_CMD_LEN         equ 64

; ======================================
; 🔤 CÓDIGOS DE TECLAS ASCII
; ======================================
KEY_NULL            equ 0x00
KEY_BACKSPACE       equ 0x08
KEY_TAB             equ 0x09
KEY_NEWLINE         equ 0x0A
KEY_ENTER           equ 0x0D
KEY_SPACE           equ 0x20
KEY_ESC             equ 0x1B

; ======================================
; 🎨 CORES — Modo Texto VGA
; ======================================
COL_BLACK           equ 0x00
COL_BLUE            equ 0x01
COL_GREEN           equ 0x02
COL_CYAN            equ 0x03
COL_RED             equ 0x04
COL_MAGENTA         equ 0x05
COL_BROWN           equ 0x06
COL_LGRAY           equ 0x07
COL_DGRAY           equ 0x08
COL_LBLUE           equ 0x09
COL_LGREEN          equ 0x0A
COL_LCYAN           equ 0x0B
COL_LRED            equ 0x0C
COL_LMAGENTA        equ 0x0D
COL_YELLOW          equ 0x0E
COL_WHITE           equ 0x0F

; Fundo(4b) + Letra(4b)
DEF_ATTR            equ (COL_BLACK << 4) | COL_LGRAY    ; Preto + Verde Neon
ATTR_ERRO           equ (COL_BLACK << 4) | COL_LRED      ; Preto + Vermelho
ATTR_AVISO          equ (COL_BLACK << 4) | COL_YELLOW    ; Preto + Amarelo
ATTR_TITULO         equ (COL_BLUE  << 4) | COL_WHITE     ; Azul + Branco

; ======================================
; ⚡ APIC — Endereços e Registradores
; ======================================
APIC_BASE_PHYS      equ 0xFEE00000
IOAPIC_BASE_PHYS    equ 0xFEC00000

; Local APIC — Deslocamentos
APIC_ID             equ 0x020
APIC_EOI            equ 0x0B0
APIC_SVR            equ 0x0F0
APIC_LVT_TIMER      equ 0x320
APIC_TIMER_INIT     equ 0x380
APIC_TIMER_DIV      equ 0x3E0

; IOAPIC — Registradores
IOAPIC_REG_SEL      equ 0x00
IOAPIC_REG_DATA     equ 0x10

; Vetores de Interrupção (32 = início das IRQs)
IRQ_BASE_VECTOR     equ 32
IRQ_TIMER           equ IRQ_BASE_VECTOR + 0
IRQ_KEYBOARD        equ IRQ_BASE_VECTOR + 1
IRQ_PCI_SYS         equ IRQ_BASE_VECTOR + 10

; ======================================
; 🔍 PCI — Configuração
; ======================================
PCI_CONFIG_ADDR     equ 0xCF8
PCI_CONFIG_DATA     equ 0xCFC

; Campos do cabeçalho PCI
PCI_VENDOR_ID       equ 0x00
PCI_DEVICE_ID       equ 0x02
PCI_CLASS           equ 0x09
PCI_BAR0            equ 0x10

; Classe de Dispositivos
PCI_CLASS_NETWORK    equ 0x02
PCI_SUBCLASS_NET_ETH equ 0x00
PCI_SUBCLASS_NET_WIFI equ 0x80

; ======================================
; 📞 CHAMADAS DE SISTEMA
; ======================================
SYS_WRITE           equ 0
SYS_READ            equ 1
SYS_OPEN            equ 2
SYS_CLOSE           equ 3
SYS_EXIT            equ 60
SYS_GET_TIME        equ 96
SYS_PROCESS_SPAWN   equ 0x31



; ======================================
; 🔗 FUNÇÕES EXTERNAS — Compartilhadas
; ======================================
; Buffer e Terminal
extern argc, argv, cursor_pos
extern buf_head, buf_tail, buffer

; Apenas declara como extern se NÃO estivermos no driver de vídeo
%ifndef BUILDING_VIDEO_DRIVER
extern clear_screen, print_string, print_char, print_newline
%endif

; PCI
%ifndef BUILDING_PCI_DRIVER
extern pci_ler_dispositivo
extern pci_ler_classe
extern pci_ler_bar0
%endif

; APIC
extern apic_detect
extern apic_inicializar
extern ioapic_redirecionar_irq
extern apic_enviar_eoi
extern apic_get_ok

; Timer
extern timer_inicializar
extern timer_get_ticks

; Teclado
extern keyboard_inicializar
extern keyboard_ler_tecla

; ======================================
%endif ; FYDELTERM_INC
