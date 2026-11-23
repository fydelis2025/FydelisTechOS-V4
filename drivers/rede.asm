; ============================================================================
; REDE.ASM — Comandos FydelTerm + Ponte Unificada (net_core.asm <-> dhcp.asm)
; Bare-Metal Real (Intel e1000 PCI + ARP + IPv4 + ICMP + DHCP RFC 2131)
; FydelisTech OS v4.2 · Salvador - Bahia
; ============================================================================
BITS 64
default rel
%include "fydelterm.inc"

; ============================================================================
; ROTINAS DO TERMINAL
; ============================================================================
extern print_string, print_newline, print_char, print_num
extern argc, argv

; ============================================================================
; PONTE COM DRIVER HARDWARE E1000 (net_core.asm)
; ============================================================================
extern e1000_pci_inicializar
extern net_iface_nome
extern net_obter_mac_str
extern net_link_ativo
extern net_bytes_rx
extern net_bytes_tx
extern net_ping_real
extern net_arp_listar
extern net_conexoes_listar
extern net_traceroute_real
extern e1000_enviar_quadro      ; rsi = buf, rcx = len
extern e1000_receber_quadro     ; rdi = buf -> rax = bytes lidos (0 se vazio)
extern mac_bytes                ; 6 bytes do MAC real lido da placa PCI

; ============================================================================
; PONTE COM CLIENTE/SERVIDOR DHCP REAL (dhcp.asm)
; ============================================================================
extern dhcp_cliente_iniciar
extern dhcp_cliente_processar
extern dhcp_ler_status
extern dhcp_ip_atual
extern dhcp_mascara
extern dhcp_gateway
extern dhcp_dns

; ============================================================================
; EXPORTACOES PARA KERNEL, TERMINAL, GUI (exec.c), TCP.C E DHCP.ASM
; ============================================================================
global do_ipconfig, do_wifi, do_ping, do_arp, do_netstat, do_traceroute
global tx_pacote, rx_processa
global inicializar_nic_mmio, mac_addr, meu_ip
global rede_definir_ip_estatico, ip_para_string
global net_obter_ip_str, net_obter_mascara_str
global net_obter_gateway_str, net_obter_dns_str
global net_dhcp_renovar

section .data
align 16
hdr_net:      db '=== Configuracao de Rede (FydelNet Real Hardware) ===', 0
lbl_if:       db 'Interface: ', 0
lbl_mac:      db 'MAC:       ', 0
lbl_ip:       db 'IPv4:      ', 0
lbl_mask:     db 'Mascara:   ', 0
lbl_gw:       db 'Gateway:   ', 0
lbl_dns:      db 'DNS:       ', 0
lbl_up:       db 'Status:    [CONECTADO - LINK UP]', 0
lbl_down:     db 'Status:    [DESCONECTADO - LINK DOWN]', 0
hdr_stats:    db '=== Estatisticas Reais da Placa (NIC) ===', 0
lbl_rx:       db 'RX Recebido: ', 0
lbl_tx:       db 'TX Enviado:  ', 0
lbl_arp:      db '=== Tabela ARP Real (Cache Kernel) ===', 0
lbl_conn:     db '=== Sockets / Conexoes Ativas ===', 0
msg_ping_uso: db 'Uso: ping <ip_ipv4>  (ex: ping 10.0.2.2)', 0
msg_tr_uso:   db 'Uso: traceroute <ip_ipv4>', 0
msg_dhcp_ok:  db '[OK] Configuracao IPv4 obtida via DHCP real.', 0
msg_dhcp_err: db '[ERRO] Timeout DHCP: mantendo configuracao atual.', 0
msg_wifi_hw:  db '[INFO] Modo Bare-Metal: operando via NIC PCI Ethernet (eth0).', 0
lbl_bytes:    db ' B', 0
lbl_kilo:     db ' KB', 0
lbl_mega:     db ' MB', 0
lbl_giga:     db ' GB', 0

; Strings dinamicas atualizadas automaticamente pelo DHCP ACK ou IP Fixo
str_ip_atual:   db '10.0.2.15', 0, 0, 0, 0, 0, 0, 0
str_mask_atual: db '255.255.255.0', 0, 0, 0
str_gw_atual:   db '10.0.2.2', 0, 0, 0, 0, 0, 0, 0, 0
str_dns_atual:  db '10.0.2.3', 0, 0, 0, 0, 0, 0, 0, 0

; IPv4 ativo em host-order (0x0A00020F = 10.0.2.15) consumido por tcp.c e rede.asm
align 4
meu_ip:         dd 0x0A00020F

section .bss
align 16
mac_addr:       resb 6
                resb 2
ipv4_atual_u32: resd 1
mask_atual_u32: resd 1
gw_atual_u32:   resd 1
dns_atual_u32:  resd 1

section .text

; ============================================================================
; PONTE DE HARDWARE PARA O DHCP.ASM (tx_pacote / rx_processa / mac_addr)
; ============================================================================
inicializar_nic_mmio:
    call    e1000_pci_inicializar
    ; Sincroniza mac_addr (6 bytes) com mac_bytes do net_core.asm
    mov     eax, [rel mac_bytes]
    mov     [rel mac_addr], eax
    mov     ax, [rel mac_bytes + 4]
    mov     [rel mac_addr + 4], ax
    ret

; Entrada: rdi = ponteiro do quadro Ethernet, rsi = tamanho em bytes
tx_pacote:
    push    rsi
    push    rcx
    mov     rcx, rsi                ; e1000_enviar_quadro espera rcx = tamanho
    mov     rsi, rdi                ; e1000_enviar_quadro espera rsi = buffer
    call    e1000_enviar_quadro
    pop     rcx
    pop     rsi
    ret

; Entrada: rdi = buffer de destino (>= 1518 bytes)
; Saida:   rax = quantidade de bytes recebidos (0 se fila RX vazia)
rx_processa:
    call    e1000_receber_quadro
    ret

; ============================================================================
; ATUALIZAR IP, MASCARA E GATEWAY (Chamado pelo DHCP ACK ou UI IP Fixo)
; Entrada: edi = IPv4 (host order, ex: 0x0A00020F = 10.0.2.15)
;          esi = Mascara (host order, ex: 0xFFFFFF00)
;          edx = Gateway (host order, ex: 0x0A000202)
; ============================================================================
rede_definir_ip_estatico:
    push    rbx
    push    rsi
    push    rdi
    push    rdx

    mov     [rel meu_ip], edi
    mov     [rel ipv4_atual_u32], edi
    mov     [rel mask_atual_u32], esi
    mov     [rel gw_atual_u32], edx
    mov     [rel dns_atual_u32], edx

    ; Formata str_ip_atual
    push    rsi
    push    rdx
    lea     rsi, [rel str_ip_atual]
    call    ip_para_string
    pop     rdx
    pop     rsi

    ; Formata str_mask_atual
    push    rdx
    mov     edi, esi
    lea     rsi, [rel str_mask_atual]
    call    ip_para_string
    pop     rdx

    ; Formata str_gw_atual e str_dns_atual
    mov     edi, edx
    lea     rsi, [rel str_gw_atual]
    call    ip_para_string

    mov     edi, [rel gw_atual_u32]
    lea     rsi, [rel str_dns_atual]
    call    ip_para_string

    pop     rdx
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ============================================================================
; CONVERTER IPv4 (32-bit host order) PARA STRING ASCII ("A.B.C.D")
; Entrada: edi = IP (byte mais significativo = 1o octeto)
;          rsi = buffer de destino (minimo 16 bytes)
; ============================================================================
ip_para_string:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    rsi

    mov     ebx, edi
    mov     rdi, rsi                ; rdi = cursor de escrita
    mov     ecx, 4                  ; 4 octetos

.prox_octeto:
    rol     ebx, 8                  ; traz octeto mais significativo para BL
    movzx   eax, bl

    ; Converte byte (0..255) para decimal ASCII
    push    rcx
    mov     ecx, 10
    xor     edx, edx
    div     ecx                     ; eax = quociente, edx = unidade
    push    rdx                     ; empilha unidade
    test    eax, eax
    jz      .escreve_1dig

    xor     edx, edx
    div     ecx                     ; eax = centena, edx = dezena
    test    eax, eax
    jz      .escreve_2dig

    add     al, '0'
    stosb
.escreve_2dig:
    mov     al, dl
    add     al, '0'
    stosb
.escreve_1dig:
    pop     rdx
    mov     al, dl
    add     al, '0'
    stosb
    pop     rcx

    dec     ecx
    jz      .fim_ip_str
    mov     byte [rdi], '.'
    inc     rdi
    jmp     .prox_octeto

.fim_ip_str:
    mov     byte [rdi], 0

    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ============================================================================
; ACESSORES DE CONFIGURACAO ATIVA
; ============================================================================
net_obter_ip_str:
    lea     rax, [rel str_ip_atual]
    ret

net_obter_mascara_str:
    lea     rax, [rel str_mask_atual]
    ret

net_obter_gateway_str:
    lea     rax, [rel str_gw_atual]
    ret

net_obter_dns_str:
    lea     rax, [rel str_dns_atual]
    ret

; ============================================================================
; EXECUTAR HANDSHAKE DHCP COMPLETO (DISCOVER -> OFFER -> REQUEST -> ACK)
; Saida: rax = 1 sucesso (BOUND), 0 timeout
; ============================================================================
net_dhcp_renovar:
    push    rcx

    call    dhcp_cliente_iniciar
    mov     ecx, 3000000            ; janela de polling para resposta do roteador/QEMU

.aguardar_bound:
    call    dhcp_cliente_processar
    call    dhcp_ler_status
    cmp     eax, 3                  ; DHCP_ST_BOUND = 3
    je      .sucesso
    dec     ecx
    jnz     .aguardar_bound

    xor     rax, rax
    pop     rcx
    ret

.sucesso:
    mov     rax, 1
    pop     rcx
    ret

; ============================================================================
; COMANDO: ipconfig  (ou "ipconfig /renew" para disparar DHCP real)
; ============================================================================
do_ipconfig:
    push    rbx
    push    rsi
    push    rdi
    push    rax

    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .exibir_info

    lea     rbx, [rel argv]
    mov     rdi, [rbx + 8]
    cmp     byte [rdi], '/'
    je      .renovar_dhcp
    cmp     byte [rdi], 'd'
    je      .renovar_dhcp
    jmp     .exibir_info

.renovar_dhcp:
    call    net_dhcp_renovar
    test    rax, rax
    jz      .dhcp_falhou
    lea     rsi, [rel msg_dhcp_ok]
    call    print_string
    call    print_newline
    jmp     .exibir_info

.dhcp_falhou:
    lea     rsi, [rel msg_dhcp_err]
    call    print_string
    call    print_newline

.exibir_info:
    lea     rsi, [rel hdr_net]
    call    print_string
    call    print_newline
    call    print_newline

    lea     rsi, [rel lbl_if]
    call    print_string
    call    net_iface_nome
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel lbl_mac]
    call    print_string
    call    net_obter_mac_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel lbl_ip]
    call    print_string
    call    net_obter_ip_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel lbl_mask]
    call    print_string
    call    net_obter_mascara_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel lbl_gw]
    call    print_string
    call    net_obter_gateway_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel lbl_dns]
    call    print_string
    call    net_obter_dns_str
    mov     rsi, rax
    test    rsi, rsi
    jz      .dns_fim
    call    print_string
.dns_fim:
    call    print_newline
    call    print_newline

    call    net_link_ativo
    cmp     rax, 1
    je      .conectado
    lea     rsi, [rel lbl_down]
    jmp     .status_prn
.conectado:
    lea     rsi, [rel lbl_up]
.status_prn:
    call    print_string
    call    print_newline
    call    print_newline

    lea     rsi, [rel hdr_stats]
    call    print_string
    call    print_newline

    lea     rsi, [rel lbl_rx]
    call    print_string
    call    net_bytes_rx
    call    print_tamanho
    call    print_newline

    lea     rsi, [rel lbl_tx]
    call    print_string
    call    net_bytes_tx
    call    print_tamanho
    call    print_newline

    pop     rax
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ============================================================================
; COMANDO: wifi
; ============================================================================
do_wifi:
    push    rsi
    lea     rsi, [rel msg_wifi_hw]
    call    print_string
    call    print_newline
    pop     rsi
    ret

; ============================================================================
; COMANDO: ping <ip>
; ============================================================================
do_ping:
    push    rbx
    push    rsi
    push    rdi
    push    rax

    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .uso

    lea     rbx, [rel argv]
    mov     rdi, [rbx + 8]
    call    net_ping_real
    jmp     .fim

.uso:
    lea     rsi, [rel msg_ping_uso]
    call    print_string
    call    print_newline

.fim:
    pop     rax
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ============================================================================
; COMANDO: arp
; ============================================================================
do_arp:
    push    rsi
    lea     rsi, [rel lbl_arp]
    call    print_string
    call    print_newline
    call    net_arp_listar
    pop     rsi
    ret

; ============================================================================
; COMANDO: netstat
; ============================================================================
do_netstat:
    push    rsi
    lea     rsi, [rel lbl_conn]
    call    print_string
    call    print_newline
    call    net_conexoes_listar
    pop     rsi
    ret

; ============================================================================
; COMANDO: traceroute <ip>
; ============================================================================
do_traceroute:
    push    rbx
    push    rsi
    push    rdi
    push    rax

    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .uso

    lea     rbx, [rel argv]
    mov     rdi, [rbx + 8]
    call    net_traceroute_real
    jmp     .fim

.uso:
    lea     rsi, [rel msg_tr_uso]
    call    print_string
    call    print_newline

.fim:
    pop     rax
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ============================================================================
; AUXILIAR: Formatar tamanho (B -> KB -> MB -> GB)
; ============================================================================
print_tamanho:
    push    rcx
    push    rdx
    push    rbx
    push    rsi

    mov     rcx, 1024
    lea     rbx, [rel lbl_bytes]

    cmp     rax, rcx
    jb      .imprimir
    xor     edx, edx
    div     rcx
    lea     rbx, [rel lbl_kilo]

    cmp     rax, rcx
    jb      .imprimir
    xor     edx, edx
    div     rcx
    lea     rbx, [rel lbl_mega]

    cmp     rax, rcx
    jb      .imprimir
    xor     edx, edx
    div     rcx
    lea     rbx, [rel lbl_giga]

.imprimir:
    call    print_num
    mov     rsi, rbx
    call    print_string

    pop     rsi
    pop     rbx
    pop     rdx
    pop     rcx
    ret
