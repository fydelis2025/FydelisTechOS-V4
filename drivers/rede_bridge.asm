; ============================================================================
; REDE_BRIDGE.ASM — Acessores Legados para UI / Browser / Painel Gráfico
; Redireciona para a pilha unificada rede.asm + net_core.asm (sem duplicar símbolos)
; FydelisTech OS v4.2 · Salvador - Bahia
; ============================================================================
BITS 64
default rel

extern net_iface_nome, net_link_ativo, net_bytes_rx, net_bytes_tx
extern net_obter_ip_str, net_obter_mascara_str, net_obter_gateway_str, net_obter_dns_str
extern net_ping_real, net_arp_listar, net_conexoes_listar, net_traceroute_real
extern mac_addr

global rede_ler_iface_nome, rede_ler_mac
global rede_ler_ip, rede_ler_mascara, rede_ler_gateway, rede_ler_dns
global rede_ler_status_link, rede_ler_bytes_rx, rede_ler_bytes_tx
global rede_ler_wifi_disponiveis, rede_conectar_wifi, rede_desconectar_wifi
global rede_exec_ping, rede_ler_tabela_arp, rede_ler_conexoes, rede_exec_traceroute

section .text

rede_ler_iface_nome:
    lea     rax, [rel net_iface_nome]
    ret

rede_ler_mac:
    lea     rax, [rel mac_addr]
    ret

rede_ler_ip:
    call    net_obter_ip_str
    ret

rede_ler_mascara:
    call    net_obter_mascara_str
    ret

rede_ler_gateway:
    call    net_obter_gateway_str
    ret

rede_ler_dns:
    call    net_obter_dns_str
    ret

rede_ler_status_link:
    mov     eax, [rel net_link_ativo]
    ret

rede_ler_bytes_rx:
    mov     rax, [rel net_bytes_rx]
    ret

rede_ler_bytes_tx:
    mov     rax, [rel net_bytes_tx]
    ret

rede_ler_wifi_disponiveis:
    xor     rax, rax
    ret

rede_conectar_wifi:
    xor     rax, rax
    ret

rede_desconectar_wifi:
    xor     rax, rax
    ret

rede_exec_ping:
    call    net_ping_real
    ret

rede_ler_tabela_arp:
    call    net_arp_listar
    xor     rax, rax
    ret

rede_ler_conexoes:
    call    net_conexoes_listar
    xor     rax, rax
    ret

rede_exec_traceroute:
    call    net_traceroute_real
    ret
