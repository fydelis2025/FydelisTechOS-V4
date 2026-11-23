// ==========================================
// FYDELIS TECH OS — Syscalls: Teclado & Layout
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef KEYBOARD_SYSCALLS_H
#define KEYBOARD_SYSCALLS_H

#include <stdint.h>

// === CÓDIGOS ESPECIAIS ===
#define KEY_NONE        0
#define KEY_ENTER       10
#define KEY_BACKSPACE   8
#define KEY_TAB         9
#define KEY_SPACE       32
#define KEY_NEWLINE     10

#define KEY_CIMA        0x81
#define KEY_ESQUERDA    0x82
#define KEY_DIREITA     0x83
#define KEY_BAIXO       0x84

#define KEY_F1          0x91
#define KEY_F10         0x92

// === LAYOUT ===
#define LAYOUT_US       0
#define LAYOUT_PTBR     1

// === SYSCALLS (exportadas do keyboard.asm) ===

/**
 * @brief Lê uma tecla do buffer — bloqueia até haver tecla
 * @return Caractere ou código especial (0x81~0xFF)
 */
uint8_t get_key(void);

/**
 * @brief Define layout para Português-Brasil
 */
void set_layout_ptbr(void);

/**
 * @brief Define layout para US QWERTY
 */
void set_layout_us(void);

// === PONTE / UTILITÁRIAS ===

/**
 * @brief Lê tecla sem bloquear
 * @return 0 se nenhuma tecla disponível
 */
uint8_t kb_try_get_key(void);

/**
 * @brief Retorna layout atual (LAYOUT_US ou LAYOUT_PTBR)
 */
uint8_t kb_get_layout(void);

/**
 * @brief Converte código de tecla para string legível
 * @param buf Buffer de saída (mín. 16 bytes)
 */
const char* kb_nome_tecla(uint8_t codigo, char* buf);

#endif // KEYBOARD_SYSCALLS_H
