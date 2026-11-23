// ==========================================
// FYDELIS TECH OS — Syscalls: Barramento & Dispositivos USB
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef USB_SYSCALLS_H
#define USB_SYSCALLS_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// === TIPOS DE CONTROLADOR ===
#define USB_CTRL_UHCI        1
#define USB_CTRL_OHCI        2
#define USB_CTRL_EHCI        3
#define USB_CTRL_XHCI        4

// === VELOCIDADES ===
#define USB_VEL_BAIXA        0
#define USB_VEL_COMPLETA     1
#define USB_VEL_ALTA         2
#define USB_VEL_SUPER        3

// === CLASSES DE DISPOSITIVO ===
#define USB_CLASSE_DESCONHECIDA 0
#define USB_CLASSE_MASSA        1
#define USB_CLASSE_HID          3   // Teclado, Mouse
#define USB_CLASSE_SERIAL       10
#define USB_CLASSE_VIDEO        14
#define USB_CLASSE_AUDIO        1

#define USB_MAX_DISPOSITIVOS    16

// === ESTRUTURA ===
typedef struct {
    uint8_t  porta;
    uint8_t  velocidade;
    uint16_t vid;
    uint16_t pid;
    uint8_t  classe;
    uint8_t  subclasse;
    uint8_t  endereco;
    bool     conectado;
    char     nome[32];
} UsbDispositivo;

// === SYSCALLS (exportadas do usb.asm) ===

/**
 * @brief Escaneia barramento PCI procurando controladores USB
 * @return Número de controladores encontrados
 */
int usb_scan_controllers(void);

/**
 * @brief Inicializa uma porta USB — reseta e detecta dispositivo
 * @param porta Número da porta (1+)
 * @return 0 = sem dispositivo, >0 = velocidade detectada, -1 = erro
 */
int usb_init_port(uint8_t porta);

// === PONTE / GERENCIAMENTO ===

/**
 * @brief Retorna tipo do controlador principal detectado
 * @return USB_CTRL_XHCI / EHCI / ... ou 0 = nenhum
 */
uint8_t usb_ctrl_tipo(void);

/**
 * @brief Retorna se há controlador USB ativo
 */
bool usb_disponivel(void);

/**
 * @brief Lê lista de dispositivos conectados
 * @param out Buffer para preencher
 * @param max Quantidade máxima a ler
 * @return Número efetivo copiado
 */
int usb_listar(UsbDispositivo* out, int max);

/**
 * @brief Lê dados de dispositivo HID (teclado/mouse USB)
 * @param endereco Endereço USB atribuído
 * @param endpoint Ponto de leitura (geralmente 0x81)
 * @param buf Buffer de recebimento
 * @param tam Tamanho máximo
 * @return Bytes lidos ou -1 em erro
 */
int usb_ler_hid(uint8_t endereco, uint8_t endpoint, void* buf, size_t tam);

/**
 * @brief Escreve dados para dispositivo USB
 */
int usb_escrever(uint8_t endereco, uint8_t endpoint, const void* buf, size_t tam);

#endif // USB_SYSCALLS_H
