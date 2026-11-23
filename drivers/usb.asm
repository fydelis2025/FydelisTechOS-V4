; ==========================================
; FYDELIS TECH OS — usb.asm
; Detecção e Varredura Real de Barramento USB (PCI)
; De Salvador • Bahia 🇧🇷
; ==========================================
bits 64

section .data
usb_controller_found    db 0
usb_ctrl_type           db 0    ; 0=Desconhecido, 1=UHCI, 2=OHCI, 3=EHCI, 4=xHCI
usb_bar0                dq 0    ; Endereço Base (MMIO ou IO)

; Constantes de Configuração PCI
PCI_CONFIG_ADDRESS      equ 0xCF8
PCI_CONFIG_DATA         equ 0xCFC

section .text
global usb_scan_controllers
global usb_init_port

; ==========================================
; 🔍 PROCURAR CONTROLADOR USB VIA PCI (Bus/Device/Function)
; ==========================================
usb_scan_controllers:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov byte [usb_controller_found], 0
    mov byte [usb_ctrl_type], 0

    ; Percorre os barramentos PCI (0 a 255)
    xor rcx, rcx                ; Bus = 0

.proximo_bus:
    xor rbx, rbx                ; Device = 0 (0 a 31)

.proximo_device:
    xor rdx, rdx                ; Function = 0 (0 a 7)

.proxima_func:
    ; Monta o endereço PCI Config: 
    ; Bit 31 = Enable, Bits 23-16 = Bus, Bits 15-11 = Device, Bits 10-8 = Function, Bits 7-2 = Register
    mov eax, 0x80000000
    shl ecx, 16                 ; Bus
    or  eax, ecx
    mov esi, ebx
    shl esi, 11                 ; Device
    or  eax, esi
    mov edi, edx
    shl edi, 8                  ; Function
    or  eax, edi
    or  eax, 0x08               ; Registro 0x08: Revision ID & Class Code
    
    mov dx, PCI_CONFIG_ADDRESS
    out dx, eax

    mov dx, PCI_CONFIG_DATA
    in  eax, dx

    ; Verifica se o dispositivo existe (Vendor ID != 0xFFFF)
    cmp ax, 0xFFFF
    je  .proxima_func_inc

    ; Verifica se a Classe é 0x0C (Serial Bus) e Subclasse é 0x03 (USB)
    ; O byte mais significativo (bits 24-31) é a Class Code
    shr eax, 8
    cmp al, 0x03                ; Subclasse USB
    jne .proxima_func_inc
    shr eax, 8
    cmp al, 0x0C                ; Classe Serial Bus
    jne .proxima_func_inc

    ; --- CONTROLADOR USB ENCONTRADO! ---
    mov byte [usb_controller_found], 1

    ; Lê o Prog IF (Registro 0x09 / Offset ajustado) para descobrir o tipo:
    ; 0x00 = UHCI, 0x10 = OHCI, 0x20 = EHCI, 0x30 = xHCI
    mov eax, 0x80000000
    shl ecx, 16
    or  eax, ecx
    shl ebx, 11
    or  eax, ebx
    shl edx, 8
    or  eax, edx
    or  eax, 0x08               ; Offset 0x08 contém Prog IF no byte 3 (bits 16-23)
    
    mov dx, PCI_CONFIG_ADDRESS
    out dx, eax
    mov dx, PCI_CONFIG_DATA
    in  eax, dx
    
    shr eax, 16                 ; Pega o Prog IF
    mov al, ah
    
    cmp al, 0x20
    je  .ehci
    cmp al, 0x30
    je  .xhci
    cmp al, 0x00
    je  .uhci
    jmp .desconhecido

.uhci:
    mov byte [usb_ctrl_type], 1
    jmp .ler_bar0
.ohci:
    mov byte [usb_ctrl_type], 2
    jmp .ler_bar0
.ehci:
    mov byte [usb_ctrl_type], 3
    jmp .ler_bar0
.xhci:
    mov byte [usb_ctrl_type], 4
    jmp .ler_bar0
.desconhecido:
    mov byte [usb_ctrl_type], 0

.ler_bar0:
    ; Lê o BAR0 (Registro 0x10) para obter o endereço de controle
    mov eax, 0x80000000
    shl ecx, 16
    or  eax, ecx
    shl ebx, 11
    or  eax, ebx
    shl edx, 8
    or  eax, edx
    or  eax, 0x10
    
    mov dx, PCI_CONFIG_ADDRESS
    out dx, eax
    mov dx, PCI_CONFIG_DATA
    in  eax, dx
    movsxd rax, eax
    mov [usb_bar0], rax

    ; Encontrou o primeiro controlador válido, pode encerrar a busca
    jmp .fim

.proxima_func_inc:
    inc rdx
    cmp rdx, 8
    jl  .proxima_func

    inc rbx
    cmp rbx, 32
    jl  .proximo_device

    inc rcx
    cmp rcx, 256
    jl  .proximo_bus

.fim:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ==========================================
; 🔌 INICIALIZAR PORTA USB
; ==========================================
usb_init_port:
    ; Valida se encontrou o controlador antes de inicializar
    mov al, [usb_controller_found]
    test al, al
    jz .erro_init

    ; Aqui você realiza o reset do controlador baseado no tipo (usb_ctrl_type)
    ; e inicializa os registradores do BAR0 correspondente.

.erro_init:
    ret
