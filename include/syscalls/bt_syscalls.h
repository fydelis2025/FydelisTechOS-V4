// ==========================================
// FYDELIS TECH OS — Syscalls: Bluetooth
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef BT_SYSCALLS_H
#define BT_SYSCALLS_H

#stdint.h>
#include <glib.h>

#define BDADDR_TAMANHO   6
#define NOME_BT_TAMANHO  24
#define MAX_DEV_BT       16

// Estrutura do Dispositivo Bluetooth (Compatível com C puro)
typedef struct {
    uint8_t  bdaddr[BDADDR_TAMANHO];        // Endereço único
    char     nome[NOME_BT_TAMANHO + 1];    // Nome visível
    uint32_t classe;                        // Tipo de aparelho
    int8_t   sinal;                         // 0-100%
    int      conectado;                     // 1 = sim
    void*    proximo;
} BtDispositivo;

// --- Syscalls do kernel (bluetooth.asm) ---
int            sys_bt_detectar(void);
int            sys_bt_inicializar(void);
BtDispositivo* sys_bt_escanear(void);
int            sys_bt_conectar(const uint8_t* bdaddr);
int            sys_bt_desconectar(void);
int            sys_bt_enviar(const void* dados, uint32_t tam);
int            sys_bt_receber(void* buffer, uint32_t tamMax);

// --- Ponte Assembly → C / GTK 4 ---
int            bridge_bt_disponivel(void);
BtDispositivo* bridge_bt_listar(void);
int            bridge_bt_conectar_por_nome(const char* nome);
int            bridge_bt_enviar_texto(const char* mensagem);

#endif // BT_SYSCALLS_H
