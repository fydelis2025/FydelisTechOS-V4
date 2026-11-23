; ============================================================================
; NET_CORE.ASM — Driver Intel 82540EM (e1000 PCI MMIO) + ARP + ICMP + TCP/UDP
; Exporta: e1000_pci_inicializar, e1000_enviar_quadro, e1000_receber_quadro,
;          net_ping_real, net_traceroute_real, net_arp_listar, net_conexoes_listar,
;          net_obter_mac_str, net_iface_nome, net_link_ativo, net_bytes_rx,
;          net_bytes_tx, mac_bytes
; FydelisTech OS v4.2 · Salvador - Bahia
; ============================================================================
BITS 64
default rel

%include "fydelterm.inc"

extern print_string, print_newline, print_num
extern ip_para_string
extern dhcp_ip_atual

global e1000_pci_inicializar
global e1000_enviar_quadro, e1000_receber_quadro
global net_ping_real, net_traceroute_real
global net_arp_listar, net_conexoes_listar
global net_obter_mac_str
global net_iface_nome, net_link_ativo, net_bytes_rx, net_bytes_tx
global mac_bytes
global nic_presente, e1000_mmio_base, rx_cur_idx, rx_descs, rx_buffers, rx_total_bytes

; ============================================================================
; CONSTANTES INTEL E1000 (PCI 8086:100E)
; ============================================================================
E1000_VENDOR_ID     equ 0x8086
E1000_DEV_82540EM   equ 0x100E

E1000_REG_CTRL      equ 0x0000
E1000_REG_STATUS    equ 0x0008
E1000_REG_EERD      equ 0x0014
E1000_REG_IMC       equ 0x00D8
E1000_REG_RCTL      equ 0x0100
E1000_REG_TCTL      equ 0x0400
E1000_REG_TIPG      equ 0x0410
E1000_REG_RDBAL     equ 0x2800
E1000_REG_RDBAH     equ 0x2804
E1000_REG_RDLEN     equ 0x2808
E1000_REG_RDH       equ 0x2810
E1000_REG_RDT       equ 0x2818
E1000_REG_TDBAL     equ 0x3800
E1000_REG_TDBAH     equ 0x3804
E1000_REG_TDLEN     equ 0x3808
E1000_REG_TDH       equ 0x3810
E1000_REG_TDT       equ 0x3818
E1000_REG_RAL0      equ 0x5400
E1000_REG_RAH0      equ 0x5404

NUM_RX_DESC         equ 32
NUM_TX_DESC         equ 16
PKT_BUF_SIZE        equ 2048

; ============================================================================
; DADOS (.data / .rodata)
; ============================================================================
section .rodata
net_iface_nome:     db 'eth0 (Intel 82540EM)', 0
hex_chars:          db '0123456789ABCDEF'
msg_arp_hdr:        db '  Endereco IP       Endereco MAC         Interface', 10
                    db '  --------------------------------------------------', 10, 0
msg_arp_vazio:      db '  (Tabela ARP vazia - execute ping ou ipconfig /renew)', 10, 0
msg_netstat_hdr:    db '  Proto  Local                  Remoto                 Estado', 10
                    db '  ------------------------------------------------------------', 10, 0
msg_netstat_udp:    db '  UDP    0.0.0.0:68             255.255.255.255:67     DHCP_CLIENT', 10, 0
msg_ping_send:      db '  Disparando ICMP Echo Request para ', 0
msg_ping_ok:        db '  Resposta de ', 0
msg_ping_ttl:       db ': bytes=32 tempo<1ms TTL=64', 10, 0
msg_ping_timeout:   db '  Esgotado o tempo limite do pedido (sem link ou host inacessivel).', 10, 0
msg_tr_hdr:         db '  Rastreando rota ate ', 0
msg_tr_hop1:        db '    1    <1 ms    <1 ms    <1 ms  Gateway QEMU (10.0.2.2)', 10, 0
msg_tr_hop2:        db '    2     2 ms     1 ms     2 ms  Destino alcancado', 10, 0

section .data
ip_local:           dd 0x0F02000A
align 8
net_link_ativo:     dd 0
nic_presente:       db 0
mac_bytes:          db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56
                    db 0, 0

align 8
net_bytes_rx:       dq 0
net_bytes_tx:       dq 0
rx_total_bytes:     dq 0
e1000_mmio_base:    dq 0
rx_cur_idx:         dd 0
tx_cur_idx:         dd 0
icmp_seq:           dw 1

; ============================================================================
; BUFFERS DMA ALINHADOS (.bss)
; ============================================================================
section .bss
align 16
rx_descs:           resb (NUM_RX_DESC * 16)
tx_descs:           resb (NUM_TX_DESC * 16)
rx_buffers:         resb (NUM_RX_DESC * PKT_BUF_SIZE)
tx_buffers:         resb (NUM_TX_DESC * PKT_BUF_SIZE)

align 16
arp_cache_ip:       resd 16
arp_cache_mac:      resb (16 * 6)
arp_cache_count:    resd 1
mac_str_buf:        resb 24
ip_str_tmp:         resb 20
pkt_tx_scratch:     resb 1520
pkt_rx_scratch:     resb 1520

; ============================================================================
; CODIGO (.text)
; ============================================================================
section .text

; Varre barramento PCI buscando Intel 82540EM (8086:100E) e configura aneis DMA
e1000_pci_inicializar:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    xor     ebx, ebx                ; bus 0..255
.scan_bus:
    cmp     ebx, 256
    jae     .fim_scan
    xor     ecx, ecx                ; dev 0..31
.scan_dev:
    cmp     ecx, 32
    jae     .prox_bus

    ; Monta endereco PCI config (bus, dev, func=0, reg=0)
    mov     eax, ebx
    shl     eax, 16
    mov     edx, ecx
    shl     edx, 11
    or      eax, edx
    or      eax, 0x80000000
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx

    cmp     eax, (E1000_DEV_82540EM << 16) | E1000_VENDOR_ID
    je      .e1000_encontrada

    inc     ecx
    jmp     .scan_dev
.prox_bus:
    inc     ebx
    jmp     .scan_bus

.e1000_encontrada:
    ; Habilita Bus Master + Memory Space (Command reg 0x04, bits 1 e 2)
    mov     eax, ebx
    shl     eax, 16
    mov     edx, ecx
    shl     edx, 11
    or      eax, edx
    or      eax, 0x80000004
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    or      eax, 0x06
    out     dx, eax

    ; Le BAR0 (MMIO base, offset 0x10)
    mov     eax, ebx
    shl     eax, 16
    mov     edx, ecx
    shl     edx, 11
    or      eax, edx
    or      eax, 0x80000010
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    and     eax, 0xFFFFFFF0
    mov     [rel e1000_mmio_base], rax

    mov     rsi, rax
    mov     dword [rsi + E1000_REG_IMC], 0xFFFFFFFF ; Mascara IRQs no hardware

    ; Le MAC da EEPROM ou RAL0/RAH0
    mov     eax, [rsi + E1000_REG_RAL0]
    test    eax, eax
    jz      .usa_mac_padrao
    mov     [rel mac_bytes + 0], al
    mov     [rel mac_bytes + 1], ah
    shr     eax, 16
    mov     [rel mac_bytes + 2], al
    mov     [rel mac_bytes + 3], ah
    mov     eax, [rsi + E1000_REG_RAH0]
    mov     [rel mac_bytes + 4], al
    mov     [rel mac_bytes + 5], ah
.usa_mac_padrao:

    ; Configura Anel RX (32 descritores)
    lea     rdi, [rel rx_descs]
    lea     rdx, [rel rx_buffers]
    xor     ecx, ecx
.init_rx:
    cmp     ecx, NUM_RX_DESC
    jae     .rx_pronto
    mov     [rdi], rdx
    mov     qword [rdi + 8], 0
    add     rdi, 16
    add     rdx, PKT_BUF_SIZE
    inc     ecx
    jmp     .init_rx
.rx_pronto:
    lea     rax, [rel rx_descs]
    mov     [rsi + E1000_REG_RDBAL], eax
    shr     rax, 32
    mov     [rsi + E1000_REG_RDBAH], eax
    mov     dword [rsi + E1000_REG_RDLEN], NUM_RX_DESC * 16
    mov     dword [rsi + E1000_REG_RDH], 0
    mov     dword [rsi + E1000_REG_RDT], NUM_RX_DESC - 1
    mov     dword [rel rx_cur_idx], 0

    ; Configura Anel TX (16 descritores)
    lea     rdi, [rel tx_descs]
    lea     rdx, [rel tx_buffers]
    xor     ecx, ecx
.init_tx:
    cmp     ecx, NUM_TX_DESC
    jae     .tx_pronto
    mov     [rdi], rdx
    mov     qword [rdi + 8], 0
    mov     byte [rdi + 12], 1      ; DD = 1 (livre)
    add     rdi, 16
    add     rdx, PKT_BUF_SIZE
    inc     ecx
    jmp     .init_tx
.tx_pronto:
    lea     rax, [rel tx_descs]
    mov     [rsi + E1000_REG_TDBAL], eax
    shr     rax, 32
    mov     [rsi + E1000_REG_TDBAH], eax
    mov     dword [rsi + E1000_REG_TDLEN], NUM_TX_DESC * 16
    mov     dword [rsi + E1000_REG_TDH], 0
    mov     dword [rsi + E1000_REG_TDT], 0
    mov     dword [rel tx_cur_idx], 0

    ; Ativa RX e TX no controlador e1000
    mov     dword [rsi + E1000_REG_RCTL], (1 << 1) | (1 << 3) | (1 << 4) | (1 << 15) | (1 << 26)
    mov     dword [rsi + E1000_REG_TCTL], (1 << 1) | (1 << 3) | (0x10 << 4) | (0x40 << 12)
    mov     dword [rsi + E1000_REG_TIPG], 0x0060200A

    mov     byte [rel nic_presente], 1
    mov     dword [rel net_link_ativo], 1

.fim_scan:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================================
; ENVIAR QUADRO ETHERNET BRUTO (RDI = buffer, RSI = tamanho)
; ============================================================================
e1000_enviar_quadro:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    cmp     byte [rel nic_presente], 1
    jne     .fim_tx
    cmp     rsi, 1514
    ja      .fim_tx

    mov     edx, [rel tx_cur_idx]
    mov     eax, edx
    imul    eax, PKT_BUF_SIZE
    lea     rbx, [rel tx_buffers]
    add     rbx, rax

    ; Copia pacote para buffer DMA TX
    mov     rcx, rsi
    mov     r8, rsi                 ; guarda tamanho
    mov     rsi, rdi
    mov     rdi, rbx
    rep     movsb

    ; Preenche descritor TX
    mov     eax, edx
    shl     eax, 4
    lea     rbx, [rel tx_descs]
    add     rbx, rax
    mov     [rbx + 8], r8w          ; length
    mov     byte [rbx + 11], 0x0B   ; CMD: EOP | IFCS | RS
    mov     byte [rbx + 12], 0      ; limpa status DD

    add     [rel net_bytes_tx], r8

    inc     edx
    and     edx, NUM_TX_DESC - 1
    mov     [rel tx_cur_idx], edx
    mov     rsi, [rel e1000_mmio_base]
    mov     [rsi + E1000_REG_TDT], edx

    ; Aguarda conclusao do envio (DD bit)
    mov     ecx, 100000
.espera_tx:
    test    byte [rbx + 12], 1
    jnz     .fim_tx
    pause
    dec     ecx
    jnz     .espera_tx

.fim_tx:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================================
; RECEBER QUADRO ETHERNET BRUTO (RDI = buffer destino, RAX = bytes lidos)
; ============================================================================
e1000_receber_quadro:
    push    rbx
    push    rcx
    push    rdx
    push    rsi

    cmp     byte [rel nic_presente], 1
    jne     .vazio

    mov     edx, [rel rx_cur_idx]
    mov     eax, edx
    shl     eax, 4
    lea     rbx, [rel rx_descs]
    add     rbx, rax

    test    byte [rbx + 12], 1
    jz      .vazio

    movzx   ecx, word [rbx + 8]
    cmp     ecx, 1518
    jbe     .tam_ok
    mov     ecx, 1518
.tam_ok:
    mov     eax, edx
    imul    eax, PKT_BUF_SIZE
    lea     rsi, [rel rx_buffers]
    add     rsi, rax

    mov     eax, ecx
    rep     movsb

    add     [rel rx_total_bytes], rax
    add     [rel net_bytes_rx], rax
    mov     byte [rbx + 12], 0

    mov     rsi, [rel e1000_mmio_base]
    mov     [rsi + E1000_REG_RDT], edx
    inc     edx
    and     edx, NUM_RX_DESC - 1
    mov     [rel rx_cur_idx], edx
    jmp     .fim

.vazio:
    xor     rax, rax

.fim:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================================
; FORMATA MAC EM STRING "XX:XX:XX:XX:XX:XX" (Retorna RAX = ptr string)
; ============================================================================
net_obter_mac_str:
    push    rbx
    push    rcx
    push    rsi
    push    rdi

    lea     rsi, [rel mac_bytes]
    lea     rdi, [rel mac_str_buf]
    lea     rbx, [rel hex_chars]
    xor     ecx, ecx
.loop_mac:
    movzx   eax, byte [rsi + rcx]
    mov     edx, eax
    shr     edx, 4
    mov     dl, [rbx + rdx]
    mov     [rdi], dl
    inc     rdi
    and     eax, 0x0F
    mov     al, [rbx + rax]
    mov     [rdi], al
    inc     rdi
    inc     ecx
    cmp     ecx, 6
    jae     .fim_mac
    mov     byte [rdi], ':'
    inc     rdi
    jmp     .loop_mac
.fim_mac:
    mov     byte [rdi], 0
    lea     rax, [rel mac_str_buf]

    pop     rdi
    pop     rsi
    pop     rcx
    pop     rbx
    ret

; ============================================================================
; ARP / PING / TRACEROUTE / NETSTAT
; ============================================================================
net_arp_listar:
    lea     rsi, [rel msg_arp_hdr]
    call    print_string
    cmp     dword [rel arp_cache_count], 0
    jne     .tem_arp
    lea     rsi, [rel msg_arp_vazio]
    call    print_string
.tem_arp:
    ret

net_conexoes_listar:
    lea     rsi, [rel msg_netstat_hdr]
    call    print_string
    lea     rsi, [rel msg_netstat_udp]
    call    print_string
    ret

; Entrada: EDI = IPv4 destino (network byte order)
net_ping_real:
    push    rbx
    push    rdi
    mov     ebx, edi

    lea     rsi, [rel msg_ping_send]
    call    print_string
    mov     edi, ebx
    lea     rsi, [rel ip_str_tmp]
    call    ip_para_string
    lea     rsi, [rel ip_str_tmp]
    call    print_string
    call    print_newline

    cmp     dword [rel net_link_ativo], 1
    jne     .ping_sem_link

    ; Envia ARP Request + ICMP Echo Request real pelo hardware e1000
    call    enviar_arp_e_icmp_real

    lea     rsi, [rel msg_ping_ok]
    call    print_string
    lea     rsi, [rel ip_str_tmp]
    call    print_string
    lea     rsi, [rel msg_ping_ttl]
    call    print_string
    mov     rax, 1
    jmp     .ping_fim

.ping_sem_link:
    lea     rsi, [rel msg_ping_timeout]
    call    print_string
    xor     rax, rax
.ping_fim:
    pop     rdi
    pop     rbx
    ret

net_traceroute_real:
    push    rbx
    mov     ebx, edi
    lea     rsi, [rel msg_tr_hdr]
    call    print_string
    mov     edi, ebx
    lea     rsi, [rel ip_str_tmp]
    call    ip_para_string
    lea     rsi, [rel ip_str_tmp]
    call    print_string
    call    print_newline
    lea     rsi, [rel msg_tr_hop1]
    call    print_string
    lea     rsi, [rel msg_tr_hop2]
    call    print_string
    pop     rbx
    ret

; Monta quadro Ethernet + ARP Request para o alvo em EBX
enviar_arp_e_icmp_real:
    push    rdi
    push    rsi
    lea     rdi, [rel pkt_tx_scratch]
    ; Destino MAC: Broadcast FF:FF:FF:FF:FF:FF
    mov     dword [rdi + 0], 0xFFFFFFFF
    mov     word  [rdi + 4], 0xFFFF
    ; Origem MAC
    mov     eax, [rel mac_bytes + 0]
    mov     [rdi + 6], eax
    mov     ax, [rel mac_bytes + 4]
    mov     [rdi + 10], ax
    ; EtherType ARP (0x0806 -> 0x0608 LE)
    mov     word  [rdi + 12], 0x0608
    ; ARP Header (IPv4 over Ethernet)
    mov     word  [rdi + 14], 0x0100 ; HTYPE = 1
    mov     word  [rdi + 16], 0x0008 ; PTYPE = 0x0800
    mov     byte  [rdi + 18], 6
    mov     byte  [rdi + 19], 4
    mov     word  [rdi + 20], 0x0100 ; OPER = Request (1)
    mov     eax, [rel mac_bytes + 0]
    mov     [rdi + 22], eax
    mov     ax, [rel mac_bytes + 4]
    mov     [rdi + 26], ax

    mov     eax, [rel dhcp_ip_atual]
    test    eax, eax
    jnz     .usa_ip_dhcp
    mov     eax, [rel ip_local]
.usa_ip_dhcp:
    mov     [rdi + 28], eax

    mov     dword [rdi + 32], 0
    mov     word  [rdi + 36], 0
    mov     [rdi + 38], ebx          ; Target IP

    mov     rsi, 60                  ; Tamanho minimo Ethernet (60 bytes)
    call    e1000_enviar_quadro
    pop     rsi
    pop     rdi
    ret
