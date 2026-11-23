// ==========================================
// FYDELIS TECH OS — Syscalls: Rede & Wi-Fi
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4 (fyd_nsi)
// ==========================================
#ifndef REDE_SYSCALLS_H
#define REDE_SYSCALLS_H

#include <stdint.h>
#include <stddef.h>

// === TIPOS E ESTRUTURAS ===
#define WIFI_SSID_MAX   33
#define WIFI_BSSID_LEN  6

typedef struct WifiRede {
    char     ssid[WIFI_SSID_MAX];
    uint8_t  bssid[WIFI_BSSID_LEN];
    int32_t  sinal;
    char     seguranca[16];
    void*    proximo;
} WifiRede;

// === REDE GERAL ===
int            rede_inicializar(void);
int            rede_status(void);
const char*    rede_ler_iface_nome(void);
const uint8_t* rede_ler_mac(void);
uint32_t       rede_ler_ip(void);
uint32_t       rede_ler_mascara(void);
uint32_t       rede_ler_gateway(void);
uint32_t       rede_ler_dns(void);
int            rede_ler_status_link(void);
uint64_t       rede_ler_bytes_rx(void);
uint64_t       rede_ler_bytes_tx(void);
int            rede_exec_ping(const char* ip);
int            rede_exec_traceroute(const char* ip);
void           rede_ler_tabela_arp(void);

// === WIFI ===
int            wifi_detectar_placa(void);
int            wifi_inicializar(void);
WifiRede*      sys_wifi_scan(void);
int            sys_wifi_conectar(const char* ssid);
int            sys_wifi_desconectar(void);
int            wifi_ler_status(void);

// === DHCP ===
int            dhcp_cliente_iniciar(void);
int            dhcp_exec(void);
uint32_t       dhcp_ler_ip(void);
int            dhcp_servidor_iniciar(void);
int            dhcp_servidor_parar(void);
int            dhcp_servidor_status(void);

// === PONTE UI → ASSEMBLY ===
int            bridge_wifi_scan(void);
int            bridge_wifi_conectar(const char* ssid);
int            bridge_wifi_desconectar(void);

#endif // REDE_SYSCALLS_H
